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
        LinkingEditor *ea = [a valueForKey:@"textView"], *eb = [b valueForKey:@"textView"];
        NSArray *histories = @[@"identity", @"changed-reverted", @"repeated-identity", @"real", @"reverted-then-real", @"style-reverted", @"style-real"];
        for (NSString *history in histories) {
            for (NSNumber *atEnd in @[@NO, @YES]) {
                BOOL suffix = [atEnd boolValue];
                NSString *label = [NSString stringWithFormat:@"%@ %@", history, suffix ? @"suffix" : @"prefix"];
                NSLog(@"CASE %@", label);
                NoteObject *note = MakeNote(library, label, @"body");
                [a revealNote:note options:0]; [b revealNote:note options:0]; Pump();
                [eb insertText:@"!" replacementRange:NSMakeRange(4,0)]; Pump();
                NSAttributedString *baseline = [[note contentString] copy];
                NSMutableAttributedString *changed = [baseline mutableCopy];
                [changed insertAttributedString:[[[NSAttributedString alloc] initWithString:@"REMOTE"] autorelease]
                    atIndex:suffix ? 0 : [changed length]];
                NSMutableAttributedString *style = [baseline mutableCopy];
                [style addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:29.0] range:NSMakeRange(0,[style length])];
                NSString *local = suffix ? @"body!LOCAL" : @"LOCALbody!";
                [eb setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(suffix ? 5 : 0,0)];
                Check([eb hasMarkedText], @"matrix begins with native composition");
                NSUInteger before = [[library allNotes] count];
                BOOL real = [history isEqualToString:@"real"] || [history isEqualToString:@"reverted-then-real"] || [history isEqualToString:@"style-real"];
                BOOL styleOnly = [history isEqualToString:@"style-real"];
                if ([history isEqualToString:@"identity"]) [note setContentString:baseline];
                else if ([history isEqualToString:@"repeated-identity"]) { for (NSUInteger i=0; i<3; i++) [note setContentString:baseline]; }
                else if ([history isEqualToString:@"changed-reverted"]) { [note setContentString:changed]; [note setContentString:baseline]; }
                else if ([history isEqualToString:@"real"]) [note setContentString:changed];
                else if ([history isEqualToString:@"reverted-then-real"]) { [note setContentString:changed]; [note setContentString:baseline]; [note setContentString:changed]; }
                else if ([history isEqualToString:@"style-reverted"]) { [note setContentString:style]; [note setContentString:baseline]; }
                else [note setContentString:style];
                Check([[eb string] isEqualToString:local], @"external snapshot sequence leaves active composition intact");
                [ea undo:self]; Pump();
                NSString *checkpoint = real && !styleOnly ? [changed string] : @"body!";
                Check(![eb hasMarkedText], @"other browser finalizes the composing view");
                Check([[[note contentString] string] isEqualToString:checkpoint], @"first undo removes only local composition");
                [ea undo:self]; Pump();
                Check([[[note contentString] string] isEqualToString:real ? checkpoint : @"body"], @"second undo distinguishes real external checkpoints from net no-ops");
                [ea redo:self]; [ea redo:self]; Pump();
                NSString *merged = real && !styleOnly ? (suffix ? @"REMOTEbody!LOCAL" : @"LOCALbody!REMOTE") : local;
                Check([[[note contentString] string] isEqualToString:merged], @"redo restores the expected combined contents");
                for (NSUInteger cycle=0; cycle<3; cycle++) {
                    [ea undo:self]; Pump();
                    Check([[[note contentString] string] isEqualToString:checkpoint], @"repeated undo retains the correct checkpoint");
                    [eb redo:self]; Pump();
                    Check([[[note contentString] string] isEqualToString:merged], @"repeated redo retains both sides of the merge");
                }
                Check([[library allNotes] count] == before, @"net no-op and disjoint revisions create no conflict notes");
                Check([[ea string] isEqualToString:[eb string]], @"both views agree after history cycles");
                if (styleOnly) {
                    NSUInteger originalIndex = suffix ? 0 : 5;
                    NSFont *font = [[note contentString] attribute:NSFontAttributeName atIndex:originalIndex effectiveRange:NULL];
                    Check([font pointSize] == 29.0, @"style checkpoint survives repeated history operations");
                }
                [style release]; [changed release]; [baseline release];
            }
        }
        NoteObject *conflict = MakeNote(library, @"Real same-position insertions", @"base");
        [a revealNote:conflict options:0]; [b revealNote:conflict options:0]; Pump();
        [eb setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(4,0)];
        NSUInteger beforeConflict = [[library allNotes] count];
        [conflict setContentString:[[[NSAttributedString alloc] initWithString:@"baseREMOTE"] autorelease]];
        for (NSUInteger cycle=0; cycle<3; cycle++) {
            [ea undo:self]; Pump();
            Check([[[conflict contentString] string] isEqualToString:@"base"], @"same-position conflict undo removes local insertion");
            [eb redo:self]; Pump();
            Check([[[conflict contentString] string] isEqualToString:@"baseLOCAL"], @"same-position conflict redo restores local insertion");
        }
        NSUInteger copies = 0;
        for (NoteObject *candidate in [library allNotes]) if ([[[candidate contentString] string] isEqualToString:@"baseREMOTE"]) copies++;
        Check(copies == 1 && [[library allNotes] count] == beforeConflict + 1, @"real insertion conflict retains exactly one remote copy after history cycles");

        NoteObject *closing = MakeNote(library, @"Closing composition owner", @"base");
        [a revealNote:closing options:0]; [b revealNote:closing options:0]; Pump();
        [eb setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(0,0)];
        [closing setContentString:[[[NSAttributedString alloc] initWithString:@"baseREMOTE"] autorelease]];
        [[b window] close]; Pump();
        Check([[[closing contentString] string] isEqualToString:@"LOCALbaseREMOTE"], @"closing composing browser preserves local and deferred remote text");
        [ea undo:self]; Pump();
        Check([[[closing contentString] string] isEqualToString:@"baseREMOTE"], @"remaining browser can undo local composition after its owner closes");
        [ea redo:self]; Pump();
        Check([[[closing contentString] string] isEqualToString:@"LOCALbaseREMOTE"], @"remaining browser can redo composition after its owner closes");
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"KINGSBURY ROUND 3 PROBES COMPLETED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
