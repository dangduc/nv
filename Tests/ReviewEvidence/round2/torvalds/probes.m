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
        NoteObject *alpha = [MakeNote(library, @"Round Two Alpha", @"abcdefghij") retain];
        NoteObject *beta = [MakeNote(library, @"Round Two Beta", @"second note") retain];
        [a revealNote:alpha options:0]; Pump();
        NVNoteEditingSession *session = [app editingSessionForNote:alpha];
        [a revealNote:beta options:0]; Pump();
        NSFont *oldFont = [[GlobalPrefs defaultPrefs] noteBodyFont];
        NSFont *newFont = [NSFont fontWithName:[oldFont fontName] size:[oldFont pointSize] + 5.0];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:newFont sender:self];
        [a settingChangedForSelectorString:@"setNoteBodyFont:sender:"]; Pump();
        NSFont *hiddenFont = [[session textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([hiddenFont pointSize] == [newFont pointSize], @"round two independently validates hidden cached-note font refresh");
        [a revealNote:alpha options:0]; Pump();
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        [b revealNote:alpha options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"], *eb = [b valueForKey:@"textView"];
        [[a window] makeKeyAndOrderFront:self]; [[a window] makeFirstResponder:ea];
        [ea setSelectedRange:NSMakeRange(10,0)];
        [eb setSelectedRange:NSMakeRange(1,3)];
        [ea insertText:@"X" replacementRange:[ea selectedRange]]; Pump();
        NSRange peerAfterInsert = [eb selectedRange];
        NSLog(@"EVIDENCE B range after A appends X: %@", NSStringFromRange(peerAfterInsert));
        Check(NSEqualRanges(peerAfterInsert,NSMakeRange(1,3)), @"append outside B selection preserves its selected characters");
        [ea undo:self]; Pump();
        NSLog(@"EVIDENCE B range after A undo: %@; A range: %@; string=%@", NSStringFromRange([eb selectedRange]), NSStringFromRange([ea selectedRange]), [ea string]);
        Check([[ea string] isEqualToString:@"abcdefghij"], @"undo restores shared text");
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(10,0)), @"BUG undo collapses peer selection to document end");
        [ea redo:self]; Pump();
        NSLog(@"EVIDENCE B range after A redo: %@; A range: %@; string=%@", NSStringFromRange([eb selectedRange]), NSStringFromRange([ea selectedRange]), [ea string]);
        Check([[ea string] isEqualToString:@"abcdefghijX"], @"redo restores shared text");
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(11,0)), @"BUG redo moves peer cursor again");
        // A direct model update changes only the suffix. Observe the unrelated peer range.
        [eb setSelectedRange:NSMakeRange(1,3)];
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"abcdefghijXY"] autorelease]]; Pump();
        NSLog(@"EVIDENCE B range after suffix-only external update: %@", NSStringFromRange([eb selectedRange]));
        Check(NSEqualRanges([eb selectedRange], NSMakeRange(12,0)), @"BUG suffix-only external update collapses unrelated peer selection");
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [alpha release]; [beta release];
        NSLog(@"TORVALDS ROUND 2 PROBES COMPLETED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
