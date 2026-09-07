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

static NSMenuItem *ColumnMenuItem(NotesTableView *table, NSString *identifier) {
    for (NSMenuItem *item in [[table menuForColumnConfiguration:nil] itemArray])
        if ([[[item representedObject] identifier] isEqualToString:identifier]) return item;
    return nil;
}
static void VerifyVisibleColumns(NSArray *browsers) {
    NSArray *visible = [[GlobalPrefs defaultPrefs] visibleTableColumns];
    for (AppController *browser in browsers) {
        NotesTableView *table = [browser valueForKey:@"notesTableView"];
        NSArray *identifiers = [[table tableColumns] valueForKey:@"identifier"];
        NSSet *expected = [NSSet setWithArray:[browser horizontalLayout] ? @[NoteTitleColumnString] : visible];
        Check([[NSSet setWithArray:identifiers] isEqual:expected] && [identifiers count] == [expected count], @"visible column set matches global preference and has no duplicates");
        for (NSString *identifier in @[NoteLabelsColumnString, NoteDateModifiedColumnString, NoteDateCreatedColumnString])
            Check([ColumnMenuItem(table, identifier) state] == ([visible containsObject:identifier] ? NSOnState : NSOffState), @"generated menu agrees with shared visibility");
    }
}
static void DispatchColumnCommand(NVApplicationController *app, AppController *target, NSMenuItem *item) {
    // The isolated executable remains inactive when launched directly by the runner.
    // Deliver the production window delegate event to test coordinator routing.
    [target windowDidBecomeMain:[NSNotification notificationWithName:NSWindowDidBecomeMainNotification object:[target window]]];
    Check([app activeBrowser] == target, @"coordinator identifies the intended active browser");
    Check([NSApp sendAction:[item action] to:app from:item], @"coordinator routes the column menu action");
    Pump();
}

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
        MakeNote(library, @"Alpha", @"alpha body"); MakeNote(library, @"Beta", @"beta body");
        if ([self horizontalLayout]) [self switchViewLayout:self];
        [app newWindow:self]; Pump();
        AppController *second = [[app browserControllers] lastObject];
        if ([second horizontalLayout]) [second switchViewLayout:self];
        [app newWindow:self]; Pump();
        AppController *third = [[app browserControllers] lastObject];
        if (![third horizontalLayout]) [third switchViewLayout:self];
        NSArray *browsers = @[self, second, third];
        [[self browserSession] filterNotesFromString:@"Alpha"];
        [[second browserSession] filterNotesFromString:@"Beta"];
        NotesTableView *firstTable = [self valueForKey:@"notesTableView"];
        NotesTableView *secondTable = [second valueForKey:@"notesTableView"];
        [[firstTable tableColumnWithIdentifier:NoteTitleColumnString] setWidth:188];
        [[secondTable tableColumnWithIdentifier:NoteTitleColumnString] setWidth:218];
        VerifyVisibleColumns(browsers);
        for (NSString *identifier in @[NoteDateModifiedColumnString, NoteLabelsColumnString, NoteDateCreatedColumnString]) {
            // Dispatch an item after changing the active browser from the one that generated it.
            // The coordinator must resolve the action using the active browser's column.
            NSMenuItem *item = [ColumnMenuItem(firstTable, identifier) retain];
            if (![[[GlobalPrefs defaultPrefs] visibleTableColumns] containsObject:identifier]) DispatchColumnCommand(app, second, item);
            for (AppController *browser in browsers) {
                NotesTableView *table = [browser valueForKey:@"notesTableView"];
                [[browser browserSession] setSortColumn:[table noteAttributeColumnForIdentifier:identifier] reversed:(browser != self)];
            }
            DispatchColumnCommand(app, second, item);
            VerifyVisibleColumns(browsers);
            for (AppController *browser in browsers)
                Check(![[[[browser browserSession] sortColumn] identifier] isEqualToString:identifier], @"hiding the selected sort updates every browser sort");
            DispatchColumnCommand(app, third, item);
            VerifyVisibleColumns(browsers);
            Check([[[self browserSession] searchString] isEqualToString:@"Alpha"] && [[[second browserSession] searchString] isEqualToString:@"Beta"], @"menu commands preserve independent queries");
            Check(fabs([[firstTable tableColumnWithIdentifier:NoteTitleColumnString] width]-188) < 1
                && fabs([[secondTable tableColumnWithIdentifier:NoteTitleColumnString] width]-218) < 1, @"menu commands preserve independent title widths");
            [item release];
        }
        // Restore old browser state with a removed/unknown sort identifier and no columns field.
        NSMutableDictionary *oldState = [[[self browserWindowState] mutableCopy] autorelease];
        [oldState removeObjectForKey:@"columns"];
        [oldState setObject:@"obsolete-column" forKey:@"sort"];
        [second restoreBrowserWindowState:oldState]; Pump();
        Check([[[[second browserSession] sortColumn] identifier] isEqualToString:NoteTitleColumnString], @"unknown legacy sort identifier falls back to Title");
        VerifyVisibleColumns(browsers);
        Check([[[second browserSession] searchString] isEqualToString:@"Alpha"], @"old state restores its query without a columns field");
        NSDictionary *currentState = [[second browserWindowState] retain];
        [third restoreBrowserWindowState:currentState]; Pump();
        Check(![third horizontalLayout], @"current saved state restores its vertical layout over a horizontal browser");
        VerifyVisibleColumns(browsers);
        [currentState release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"SCOPE CONTRARIAN ROUND 3 COMPLETED (%lu checks)",(unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
