// Loaded only by run-multiple-windows-tests.py into a disposable app copy.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "NoteAttributeColumn.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"
#import "NSFileManager_NV.h"
#import "ODBEditor.h"

static NSString *TestDirectory;
static NSUInteger Checks;
static void Check(BOOL result, NSString *description) {
    if (!result) { NSLog(@"FAIL: %@", description); exit(1); }
    NSLog(@"PASS: %@", description); Checks++;
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static NoteObject *MakeNote(NotationController *library, NSString *title, NSString *text) {
    NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:text] autorelease]
        title:title delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
    [library addNewNote:note]; Pump(); return note;
}
static void Swap(Class cls, SEL original, SEL replacement) {
    method_exchangeImplementations(class_getInstanceMethod(cls, original), class_getInstanceMethod(cls, replacement));
}
@interface NSFileManager (NVTestPaths)
- (NSString *)nv_testSupportDirectory;
@end
@implementation NSFileManager (NVTestPaths)
- (NSString *)nv_testSupportDirectory { return [TestDirectory stringByAppendingPathComponent:@"Support"]; }
@end

@interface ODBEditor (NVTestIsolation)
- (void)nv_skipExternalEditorInitialization:(id)prefs;
@end
@implementation ODBEditor (NVTestIsolation)
- (void)nv_skipExternalEditorInitialization:(id)prefs { }
@end

@interface AppController (NVWindowTests)
- (void)nv_testLaunch:(NSNotification *)notification;
- (void)nv_testDelayed;
- (void)nv_runTests;
@end
@implementation AppController (NVWindowTests)
+ (void)load {
    const char *directory = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!directory) return;
    TestDirectory = [[NSString stringWithUTF8String:directory] copy];
    Swap(self, @selector(applicationDidFinishLaunching:), @selector(nv_testLaunch:));
    Swap(self, @selector(runDelayedUIActionsAfterLaunch), @selector(nv_testDelayed));
    Swap([NSFileManager class], @selector(applicationSupportDirectory), @selector(nv_testSupportDirectory));
    Swap([ODBEditor class], @selector(initializeDatabase:), @selector(nv_skipExternalEditorInitialization:));
}
- (void)nv_testDelayed { }
- (void)nv_finishTests { [NSApp terminate:self]; }
- (void)nv_testLaunch:(NSNotification *)notification {
    [self setupViewsAfterAppAwakened];
    FSRef directory; OSStatus err = FSPathMakeRef((const UInt8 *)[[TestDirectory stringByAppendingPathComponent:@"Notes"] fileSystemRepresentation], &directory, NULL);
    Check(err == noErr, @"temporary library directory exists");
    NotationController *library = [[[NotationController alloc] initWithDirectoryRef:&directory error:&err] autorelease];
    Check(library != nil && err == noErr, @"temporary library opens");
    [self setNotationController:library];
    [self prepareAdditionalWindow];
    [[self window] makeKeyAndOrderFront:self];
    [self performSelector:@selector(nv_runTests) withObject:nil afterDelay:0.3];
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *a = self;
        NoteObject *note = [MakeNote(library, @"Round Three Selections", @"abcdefghij") retain];
        [a revealNote:note options:0]; Pump();
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        [b revealNote:note options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"], *eb = [b valueForKey:@"textView"];
        [[a window] makeKeyAndOrderFront:self]; [[a window] makeFirstResponder:ea];
        [eb setSelectedRange:NSMakeRange(1,3)];
        [ea insertText:@"X" replacementRange:NSMakeRange(10,0)]; Pump();
        [ea undo:self]; Pump();
        Check([[ea string] isEqualToString:@"abcdefghij"] && NSEqualRanges([eb selectedRange],NSMakeRange(1,3)), @"round-three undo validates the peer selection fix");
        [ea redo:self]; Pump();
        Check([[ea string] isEqualToString:@"abcdefghijX"] && NSEqualRanges([eb selectedRange],NSMakeRange(1,3)), @"round-three redo validates the peer selection fix");
        NSString *unicode = @"😀e\u0301 target 👩‍💻 tail";
        [note setContentString:[[[NSAttributedString alloc] initWithString:unicode] autorelease]]; Pump();
        NSRange target = [unicode rangeOfString:@"target"];
        [eb setSelectedRange:target];
        NSString *prefixed = [@"🎉" stringByAppendingString:unicode];
        [note setContentString:[[[NSAttributedString alloc] initWithString:prefixed] autorelease]]; Pump();
        NSRange prefixedTarget = [prefixed rangeOfString:@"target"];
        Check([[ea string] isEqualToString:prefixed] && NSEqualRanges([eb selectedRange],prefixedTarget), @"surrogate-pair prefix insertion shifts the peer range by UTF-16 length");
        NSString *emojiChanged = [prefixed stringByReplacingOccurrencesOfString:@"😀" withString:@"😁"];
        [note setContentString:[[[NSAttributedString alloc] initWithString:emojiChanged] autorelease]]; Pump();
        Check([[ea string] isEqualToString:emojiChanged] && NSEqualRanges([eb selectedRange],prefixedTarget), @"replacement of one surrogate code unit preserves the complete string and peer range");
        NSRange tail = [emojiChanged rangeOfString:@"tail"];
        NSArray *multiple = @[[NSValue valueWithRange:prefixedTarget], [NSValue valueWithRange:tail]];
        [eb setSelectedRanges:multiple];
        NSMutableAttributedString *styled = [[[NSAttributedString alloc] initWithString:emojiChanged] autorelease].mutableCopy;
        [styled addAttribute:NSUnderlineStyleAttributeName value:@1 range:prefixedTarget];
        [styled addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:25] range:tail];
        [note setContentString:styled]; Pump();
        Check([[eb selectedRanges] isEqualToArray:multiple], @"style-only changes preserve two independent selections");
        Check([[[ea textStorage] attribute:NSUnderlineStyleAttributeName atIndex:prefixedTarget.location effectiveRange:NULL] intValue] == 1 &&
              [[[ea textStorage] attribute:NSFontAttributeName atIndex:tail.location effectiveRange:NULL] pointSize] == 25,
              @"style-only snapshot applies both attribute runs");
        [styled release];
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"AAcoreZZ"] autorelease]]; Pump();
        [eb setSelectedRange:NSMakeRange(2,4)];
        NSTextView *reference = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,300,300)];
        [reference setString:@"AAcoreZZ"]; [reference setSelectedRange:NSMakeRange(2,4)];
        [[reference textStorage] replaceCharactersInRange:NSMakeRange(6,2) withString:@"YY"];
        [[reference textStorage] replaceCharactersInRange:NSMakeRange(0,2) withString:@"BB"];
        Check(NSEqualRanges([reference selectedRange],NSMakeRange(2,4)), @"native disjoint replacements preserve the unchanged middle selection");
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"BBcoreYY"] autorelease]]; Pump();
        NSLog(@"EVIDENCE disjoint external update: expected B %@, actual B %@; body=%@", NSStringFromRange([reference selectedRange]), NSStringFromRange([eb selectedRange]), [ea string]);
        Check([[ea string] isEqualToString:@"BBcoreYY"], @"disjoint external update preserves text");
        Check(NSEqualRanges([eb selectedRange],NSMakeRange(8,0)), @"BUG snapshot treats the unchanged middle as replaced and collapses its selection");
        [reference release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [note release];
        NSLog(@"TORVALDS ROUND 3 PROBES COMPLETED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
