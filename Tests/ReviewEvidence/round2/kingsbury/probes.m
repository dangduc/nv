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
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        LinkingEditor *ea = [a valueForKey:@"textView"];
        LinkingEditor *eb = [b valueForKey:@"textView"];
        NSArray *cases = @[
            @[@"front insertion and remote suffix", @"abcdefghij", @"LOCAL", @0, @0, @"abcdefghijREMOTE", @"LOCALabcdefghijREMOTE"],
            @[@"remote growth before local replacement", @"abcdefghij", @"LOCAL", @7, @2, @"REMOTEcdefghij", @"REMOTEcdefgLOCALj"],
            @[@"remote shrink before local replacement", @"abcdefghij", @"LOCAL", @7, @2, @"cdefghij", @"cdefgLOCALj"],
            @[@"adjacent replacements", @"abcdefghij", @"LOCAL", @2, @2, @"abcdREMOTEghij", @"abLOCALREMOTEghij"],
            @[@"unicode prefix and local suffix", @"🐈abcdefghij", @"LOCAL", @10, @2, @"🐈REMOTEabcdefghij", @"🐈REMOTEabcdefghLOCAL"],
        ];
        for (NSArray *test in cases) {
            NoteObject *note = MakeNote(library, [test objectAtIndex:0], [test objectAtIndex:1]);
            [a revealNote:note options:0]; [b revealNote:note options:0]; Pump();
            [eb setMarkedText:[test objectAtIndex:2] selectedRange:NSMakeRange([[test objectAtIndex:2] length],0)
                replacementRange:NSMakeRange([[test objectAtIndex:3] unsignedIntegerValue], [[test objectAtIndex:4] unsignedIntegerValue])];
            Check([eb hasMarkedText], @"matrix case uses native marked text");
            NSUInteger countBefore = [[library allNotes] count];
            [note setContentString:[[[NSAttributedString alloc] initWithString:[test objectAtIndex:5]] autorelease]];
            [ea undo:self]; Pump();
            Check([[[note contentString] string] isEqualToString:[test objectAtIndex:5]], [@"undo preserves remote: " stringByAppendingString:[test objectAtIndex:0]]);
            [ea undo:self]; Pump();
            Check([[[note contentString] string] isEqualToString:[test objectAtIndex:5]], @"second undo cannot remove remote checkpoint");
            [eb redo:self]; Pump();
            Check([[[note contentString] string] isEqualToString:[test objectAtIndex:6]], [@"redo restores expected merge: " stringByAppendingString:[test objectAtIndex:0]]);
            Check([[library allNotes] count] == countBefore, @"disjoint merge creates no conflict copy");
            Check([[ea string] isEqualToString:[eb string]], @"browser copies agree after undo and redo");
        }
        NoteObject *latest = MakeNote(library, @"Latest external snapshot", @"base");
        [a revealNote:latest options:0]; [b revealNote:latest options:0]; Pump();
        [eb setMarkedText:@"LOCAL " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        [latest setContentString:[[[NSAttributedString alloc] initWithString:@"base REMOTE1"] autorelease]];
        [latest setContentString:[[[NSAttributedString alloc] initWithString:@"base REMOTE2"] autorelease]];
        [ea undo:self]; Pump();
        Check([[[latest contentString] string] isEqualToString:@"base REMOTE2"], @"undo preserves the latest of two external snapshots");
        [eb redo:self]; Pump();
        Check([[[latest contentString] string] isEqualToString:@"LOCAL base REMOTE2"], @"redo merges with the latest external snapshot");

        NoteObject *noop = MakeNote(library, @"Unchanged external snapshot", @"base");
        [a revealNote:noop options:0]; [b revealNote:noop options:0]; Pump();
        [eb insertText:@"!" replacementRange:NSMakeRange(4,0)]; Pump();
        Check([[noop undoManager] canUndo], @"no-op case starts with a committed local undo action");
        NSAttributedString *baseline = [[noop contentString] copy];
        [eb setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(5,0)];
        NSUInteger beforeNoop = [[library allNotes] count];
        [noop setContentString:baseline];
        Check([[noop contentString] isEqualToAttributedString:baseline], @"no-op external notification has exactly the original attributed contents");
        [eb unmarkText]; [b finishEditing]; Pump();
        NSLog(@"EVIDENCE unchanged-external before=%lu after=%lu text=%@", (unsigned long)beforeNoop, (unsigned long)[[library allNotes] count], [[noop contentString] string]);
        Check([[[noop contentString] string] isEqualToString:@"base!LOCAL"], @"no-op external notification preserves the local append");
        Check([[library allNotes] count] == beforeNoop + 1, @"BUG no-op external notification creates a spurious conflict copy");
        [ea undo:self]; Pump();
        Check([[[noop contentString] string] isEqualToString:@"base!"], @"first undo removes the local composition");
        [ea undo:self]; Pump();
        Check([[[noop contentString] string] isEqualToString:@"base!"], @"BUG no-op external notification erased the preceding committed edit's undo action");
        [baseline release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"KINGSBURY ROUND 2 PROBES COMPLETED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
