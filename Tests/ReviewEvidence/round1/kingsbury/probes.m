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
        NoteObject *note = [MakeNote(library, @"Undo composition ordering", @"base") retain];
        [a revealNote:note options:0]; [b revealNote:note options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"];
        LinkingEditor *eb = [b valueForKey:@"textView"];
        [[b window] makeFirstResponder:eb];
        [eb insertText:@" committed" replacementRange:NSMakeRange(4,0)]; Pump();
        Check([[ea string] isEqualToString:@"base committed"] && [[eb string] isEqualToString:[ea string]], @"ordinary edit reaches both browser editors");
        [eb undo:self]; Pump();
        Check([[[note contentString] string] isEqualToString:@"base"], @"control: ordinary undo updates the note model");
        [eb redo:self]; Pump();
        Check([[[note contentString] string] isEqualToString:@"base committed"], @"control: ordinary redo updates the note model");

        [eb setMarkedText:@"draft " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        Check([eb hasMarkedText] && [[eb string] isEqualToString:@"draft base committed"], @"native editor has an active composition");
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"base committed REMOTE"] autorelease]];
        Check([[eb string] isEqualToString:@"draft base committed"], @"external update is initially deferred while text is marked");
        Check([[[note contentString] string] isEqualToString:@"base committed REMOTE"], @"external text is initially present in model");

        [eb undo:self]; Pump();
        NSLog(@"EVIDENCE after-undo marked=%d editor=%@ model=%@", [eb hasMarkedText], [eb string], [[note contentString] string]);
        Check([[eb string] isEqualToString:@"base"], @"BUG undo replaces active composition with older snapshot");
        Check([[[note contentString] string] isEqualToString:@"base"], @"BUG undo overwrites the pending external model update");
        [eb unmarkText];
        [[app editingSessionForNote:note] commitPendingTextChanges]; Pump();
        NSLog(@"EVIDENCE after-unmark editor=%@ model=%@ notes=%lu", [eb string], [[note contentString] string], (unsigned long)[[library allNotes] count]);
        Check([[[note contentString] string] isEqualToString:@"base"], @"BUG committing composition does not restore external text");
        Check([[library allNotes] count] == 1, @"BUG overwritten external text receives no conflict copy");
        Check([[ea string] isEqualToString:[eb string]], @"both browsers agree after this interleaving");
        [note release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"KINGSBURY ROUND 1 PROBES COMPLETED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
