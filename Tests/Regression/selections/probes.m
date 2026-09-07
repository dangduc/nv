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
static NSArray *CocoaSelectionAfter(NSString *text, NSArray *ranges, NSRange edited, NSString *replacement) {
    NSTextView *reference = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,500,500)];
    [reference setString:text];
    [reference setSelectedRanges:ranges];
    [[reference textStorage] replaceCharactersInRange:edited withString:replacement];
    NSArray *result = [[[reference selectedRanges] copy] autorelease];
    [reference release];
    return result;
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
        NoteObject *note = MakeNote(library, @"Selection transformations", @"abcdefghij");
        [a revealNote:note options:0]; Pump();
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        [b revealNote:note options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"], *eb = [b valueForKey:@"textView"];
        [[a window] makeKeyAndOrderFront:self]; [[a window] makeFirstResponder:ea];
        [eb setSelectedRange:NSMakeRange(1,3)];
        [ea insertText:@"X" replacementRange:NSMakeRange(10,0)]; Pump();
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(1,3)), @"ordinary suffix edit preserves peer selection");
        [ea undo:self]; Pump();
        Check([[ea string] isEqualToString:@"abcdefghij"] && NSEqualRanges([eb selectedRange],NSMakeRange(1,3)), @"undo preserves peer selection before the edited suffix");
        [ea redo:self]; Pump();
        Check([[ea string] isEqualToString:@"abcdefghijX"] && NSEqualRanges([eb selectedRange],NSMakeRange(1,3)), @"redo preserves peer selection before the edited suffix");
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"abcdefghijXY"] autorelease]]; Pump();
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(1,3)), @"external suffix insertion preserves peer selection");

        [eb setSelectedRange:NSMakeRange(5,3)];
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"PQabcdefghijXY"] autorelease]]; Pump();
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(7,3)), @"external prefix insertion shifts peer selection by inserted length");
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"abcdefghijXY"] autorelease]]; Pump();
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(5,3)), @"external prefix deletion shifts peer selection back");

        NSArray *overlapRanges = @[[NSValue valueWithRange:NSMakeRange(3,5)]];
        NSArray *expectedOverlap = CocoaSelectionAfter(@"abcdefghijXY", overlapRanges, NSMakeRange(5,2), @"Z");
        [eb setSelectedRanges:overlapRanges];
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"abcdeZhijXY"] autorelease]]; Pump();
        Check([[eb selectedRanges] isEqualToArray:expectedOverlap], @"overlapping replacement uses Cocoa selection adjustment");

        [note setContentString:[[[NSAttributedString alloc] initWithString:@"abcdefghij"] autorelease]]; Pump();
        NSArray *multiple = @[[NSValue valueWithRange:NSMakeRange(1,2)], [NSValue valueWithRange:NSMakeRange(6,2)]];
        [eb setSelectedRanges:multiple];
        Check([[eb selectedRanges] count] == 2, @"peer editor supports multiple selected ranges");
        NSArray *expectedMultiple = CocoaSelectionAfter(@"abcdefghij", multiple, NSMakeRange(0,0), @"PRE");
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"PREabcdefghij"] autorelease]]; Pump();
        Check([[eb selectedRanges] isEqualToArray:expectedMultiple], @"prefix insertion transforms every selected range");
        NSMutableAttributedString *restyled = [[note contentString] mutableCopy];
        [restyled addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:26.0] range:NSMakeRange(0,[restyled length])];
        [restyled addAttribute:NSUnderlineStyleAttributeName value:@1 range:NSMakeRange(0,3)];
        [note setContentString:restyled]; Pump();
        Check([[eb selectedRanges] isEqualToArray:expectedMultiple], @"attribute-only reload preserves every selected range");
        NSFont *font = [[ea textStorage] attribute:NSFontAttributeName atIndex:4 effectiveRange:NULL];
        Check([font pointSize] == 26.0 && [[[ea textStorage] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] intValue] == 1, @"snapshot applies font and style runs beyond changed characters");
        [restyled release];

        NoteObject *merged = MakeNote(library, @"Merge selection transformations", @"abcdefghij");
        [a revealNote:merged options:0]; [b revealNote:merged options:0]; Pump();
        [eb setSelectedRange:NSMakeRange(1,3)];
        [ea setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(10,0)];
        [merged setContentString:[[[NSAttributedString alloc] initWithString:@"REMOTEabcdefghij"] autorelease]];
        [ea unmarkText]; [a finishEditing]; Pump();
        Check([[[merged contentString] string] isEqualToString:@"REMOTEabcdefghijLOCAL"], @"pending external prefix merges with local suffix");
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(7,3)), @"merge transforms unrelated peer selection for external prefix");
        [ea undo:self]; Pump();
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(7,3)), @"undo of merged local suffix preserves shifted peer selection");
        [ea redo:self]; Pump();
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(7,3)), @"redo of merged local suffix preserves shifted peer selection");
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"SELECTION REGRESSION TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
