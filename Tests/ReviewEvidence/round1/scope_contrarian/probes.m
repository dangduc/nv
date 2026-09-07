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
        MakeNote(library, @"Temporary Alpha", @"body alpha");
        [[self browserSession] filterNotesFromString:@"Temporary"];
        if ([self horizontalLayout]) [self switchViewLayout:self];
        NotesTableView *table = [self valueForKey:@"notesTableView"];
        NSLog(@"INITIAL columns=%@", [[table tableColumns] valueForKey:@"identifier"]);
        if ([[table tableColumns] count] < 2) {
            NSTableColumn *date = [table noteAttributeColumnForIdentifier:NoteDateModifiedColumnString];
            [table addTableColumn:date];
        }
        NSTableColumn *first = [[table tableColumns] objectAtIndex:0];
        NSString *identifier = [[first identifier] copy];
        CGFloat originalWidth = [first width];
        [first setWidth:MAX([first minWidth], originalWidth - 65)];
        [table moveColumn:0 toColumn:[[table tableColumns] count] - 1];
        CGFloat savedWidth = [first width];
        NSArray *savedOrder = [[[table tableColumns] valueForKey:@"identifier"] copy];
        NSDictionary *state = [[self browserWindowState] copy];
        Check([state objectForKey:@"frame"] != nil && [state objectForKey:@"sort"] != nil, @"state captures existing frame and sort fields");
        [app newWindow:self]; Pump();
        AppController *restored = [[app browserControllers] lastObject];
        [restored restoreBrowserWindowState:state]; Pump();
        NotesTableView *other = [restored valueForKey:@"notesTableView"];
        CGFloat restoredWidth = [[other tableColumnWithIdentifier:identifier] width];
        NSArray *restoredOrder = [[other tableColumns] valueForKey:@"identifier"];
        NSLog(@"EVIDENCE column=%@ original-width=%.1f saved-width=%.1f restored-width=%.1f",identifier,originalWidth,savedWidth,restoredWidth);
        NSLog(@"EVIDENCE saved-order=%@ restored-order=%@ state-keys=%@",savedOrder,restoredOrder,[state allKeys]);
        Check(fabs(savedWidth - restoredWidth) > 1, @"BUG resized column width does not survive browser-state restoration");
        Check(![savedOrder isEqual:restoredOrder], @"BUG user column order does not survive browser-state restoration");
        Check([[state objectForKey:@"search"] isEqual:[[restored browserSession] searchString]], @"query survives the same round trip");
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"SCOPE CONTRARIAN ROUND 1 COMPLETED (%lu checks)",(unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
