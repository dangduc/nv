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
static NSMenuItem *DateMenuItem(NotesTableView *table) {
    for (NSMenuItem *item in [[table menuForColumnConfiguration:nil] itemArray]) {
        if ([[[item representedObject] identifier] isEqualToString:NoteDateModifiedColumnString]) return item;
    }
    return nil;
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
        if ([self horizontalLayout]) [self switchViewLayout:self];
        NotesTableView *first = [self valueForKey:@"notesTableView"];
        [app newWindow:self]; Pump();
        AppController *secondBrowser = [[app browserControllers] lastObject];
        if ([secondBrowser horizontalLayout]) [secondBrowser switchViewLayout:self];
        NotesTableView *second = [secondBrowser valueForKey:@"notesTableView"];
        Check([first tableColumnWithIdentifier:NoteDateModifiedColumnString] != nil && [second tableColumnWithIdentifier:NoteDateModifiedColumnString] != nil,
            @"both browsers initially show Date Modified");
        [[first tableColumnWithIdentifier:NoteTitleColumnString] setWidth:188];
        NSDictionary *state = [[self browserWindowState] retain];
        [secondBrowser restoreBrowserWindowState:state]; Pump();
        Check(fabs([[second tableColumnWithIdentifier:NoteTitleColumnString] width] - 188) < 1, @"round1 width restoration remains fixed");
        NSMenuItem *firstItem = DateMenuItem(first);
        [first actionHideShowColumn:firstItem]; Pump();
        NSLog(@"EVIDENCE after-hide global=%@ first=%@ second=%@", [[GlobalPrefs defaultPrefs] visibleTableColumns],
            [[first tableColumns] valueForKey:@"identifier"], [[second tableColumns] valueForKey:@"identifier"]);
        Check(![[[GlobalPrefs defaultPrefs] visibleTableColumns] containsObject:NoteDateModifiedColumnString], @"menu action hides Date Modified in global preferences");
        Check([first tableColumnWithIdentifier:NoteDateModifiedColumnString] == nil, @"initiating browser hides Date Modified");
        Check([second tableColumnWithIdentifier:NoteDateModifiedColumnString] != nil, @"BUG other browser still shows globally hidden Date Modified");
        NSMenuItem *secondItem = DateMenuItem(second);
        Check([secondItem state] == NSOffState, @"other browser menu reports Date Modified hidden despite visible column");
        [second actionHideShowColumn:secondItem]; Pump();
        NSArray *secondColumns = [[second tableColumns] valueForKey:@"identifier"];
        NSLog(@"EVIDENCE second-toggle global=%@ first=%@ second=%@", [[GlobalPrefs defaultPrefs] visibleTableColumns],
            [[first tableColumns] valueForKey:@"identifier"], secondColumns);
        NSUInteger dates = 0;
        for (NSString *identifier in secondColumns) if ([identifier isEqualToString:NoteDateModifiedColumnString]) dates++;
        Check(dates == 2, @"BUG toggling through the other browser creates duplicate Date Modified columns");
        [state release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"SCOPE CONTRARIAN ROUND 2 COMPLETED (%lu checks)",(unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
