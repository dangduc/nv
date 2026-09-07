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


static NSArray *ColumnOrder(NotesTableView *table) { return [[table tableColumns] valueForKey:@"identifier"]; }
static NSMenuItem *ColumnMenuItem(NotesTableView *table, NSString *identifier) {
    for (NSMenuItem *item in [[table menuForColumnConfiguration:nil] itemArray])
        if ([[[item representedObject] identifier] isEqualToString:identifier]) return item;
    return nil;
}
static BOOL HasUniqueColumns(NotesTableView *table) {
    return [[NSSet setWithArray:ColumnOrder(table)] count] == [[table tableColumns] count];
}
static CGFloat TitleWidth(NotesTableView *table) { return [[table tableColumnWithIdentifier:NoteTitleColumnString] width]; }
static NSDictionary *RoundTripState(AppController *browser) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:[browser browserWindowState]
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    Check(data != nil, @"browser state serializes as a property list");
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
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
        MakeNote(library, @"Temporary Alpha", @"body alpha");
        [[self browserSession] filterNotesFromString:@"Temporary"];
        if ([self horizontalLayout]) [self switchViewLayout:self];
        NotesTableView *first = [self valueForKey:@"notesTableView"];
        Check([[first tableColumns] count] >= 2, @"isolated defaults provide two columns");
        [[first tableColumnWithIdentifier:NoteTitleColumnString] setWidth:188];
        [first moveColumn:[first columnWithIdentifier:NoteTitleColumnString] toColumn:[[first tableColumns] count]-1];
        NSArray *firstOrder = [[ColumnOrder(first) copy] autorelease];
        CGFloat firstWidth = TitleWidth(first);
        NSDictionary *firstState = [RoundTripState(self) retain];
        [app newWindow:self]; Pump();
        AppController *secondBrowser = [[app browserControllers] lastObject];
        if ([secondBrowser horizontalLayout]) [secondBrowser switchViewLayout:self];
        NotesTableView *second = [secondBrowser valueForKey:@"notesTableView"];
        [[second tableColumnWithIdentifier:NoteTitleColumnString] setWidth:218];
        NSArray *secondOrder = [[ColumnOrder(second) copy] autorelease];
        CGFloat secondWidth = TitleWidth(second);
        NSDictionary *secondState = [RoundTripState(secondBrowser) retain];
        Check(fabs(firstWidth - secondWidth) > 1 && ![firstOrder isEqual:secondOrder], @"two browsers have different column configurations");
        Check(fabs(TitleWidth(first)-firstWidth) < 1 && [ColumnOrder(first) isEqual:firstOrder], @"second browser changes preserve first browser columns");
        [app newWindow:self]; Pump();
        AppController *restoredFirst = [[app browserControllers] lastObject];
        [restoredFirst restoreBrowserWindowState:firstState]; Pump();
        NotesTableView *restoredFirstTable = [restoredFirst valueForKey:@"notesTableView"];
        Check(fabs(TitleWidth(restoredFirstTable)-firstWidth) < 1, @"first browser width survives property-list round trip");
        Check([ColumnOrder(restoredFirstTable) isEqual:firstOrder], @"first browser order survives property-list round trip");
        Check([[[restoredFirst browserSession] searchString] isEqual:@"Temporary"], @"query survives column restoration");
        [app newWindow:self]; Pump();
        AppController *restoredSecond = [[app browserControllers] lastObject];
        [restoredSecond restoreBrowserWindowState:secondState]; Pump();
        NotesTableView *restoredSecondTable = [restoredSecond valueForKey:@"notesTableView"];
        Check(fabs(TitleWidth(restoredSecondTable)-secondWidth) < 1 && [ColumnOrder(restoredSecondTable) isEqual:secondOrder], @"second browser restores its independent width and order");
        [restoredFirst switchViewLayout:self]; Pump();
        Check([[restoredFirstTable tableColumns] count] == 1, @"horizontal layout uses one column");
        [restoredFirst switchViewLayout:self]; Pump();
        Check(fabs(TitleWidth(restoredFirstTable)-firstWidth) < 1 && [ColumnOrder(restoredFirstTable) isEqual:firstOrder], @"vertical columns survive a layout round trip");
        Check(fabs(TitleWidth(restoredSecondTable)-secondWidth) < 1, @"layout switching leaves another browser width unchanged");
        [restoredFirst switchViewLayout:self]; Pump();
        NSDictionary *horizontalState = [RoundTripState(restoredFirst) retain];
        [restoredSecond restoreBrowserWindowState:horizontalState]; Pump();
        [restoredSecond switchViewLayout:self]; Pump();
        Check(fabs(TitleWidth(restoredSecondTable)-firstWidth) < 1 && [ColumnOrder(restoredSecondTable) isEqual:firstOrder], @"saved horizontal state also preserves its dormant vertical columns");
        // Exercise the actual shared preference callbacks through generated menu items.
        [[first tableColumnWithIdentifier:NoteDateModifiedColumnString] setWidth:120];
        [[second tableColumnWithIdentifier:NoteDateModifiedColumnString] setWidth:150];
        [first columnLayoutState]; [second columnLayoutState];
        NSArray *beforeVisibilityOrder = [[ColumnOrder(first) copy] autorelease];
        [[self browserSession] setSortColumn:[first noteAttributeColumnForIdentifier:NoteDateModifiedColumnString] reversed:NO];
        [[secondBrowser browserSession] setSortColumn:[second noteAttributeColumnForIdentifier:NoteDateModifiedColumnString] reversed:YES];
        [first actionHideShowColumn:ColumnMenuItem(first, NoteDateModifiedColumnString)]; Pump();
        Check([first tableColumnWithIdentifier:NoteDateModifiedColumnString] == nil && [second tableColumnWithIdentifier:NoteDateModifiedColumnString] == nil,
            @"hiding a column in one browser hides it in the other browser");
        Check([ColumnMenuItem(second, NoteDateModifiedColumnString) state] == NSOffState, @"other browser menu agrees with hidden column");
        Check([[[[self browserSession] sortColumn] identifier] isEqualToString:NoteTitleColumnString]
            && [[[[secondBrowser browserSession] sortColumn] identifier] isEqualToString:NoteTitleColumnString],
            @"all browsers replace a removed sort column with a visible column");
        Check(![[self browserSession] reverseSorted] && [[secondBrowser browserSession] reverseSorted], @"sort fallback preserves each browser direction");
        [second actionHideShowColumn:ColumnMenuItem(second, NoteDateModifiedColumnString)]; Pump();
        Check([first tableColumnWithIdentifier:NoteDateModifiedColumnString] != nil && [second tableColumnWithIdentifier:NoteDateModifiedColumnString] != nil,
            @"showing the column in the other browser updates both browsers");
        Check(HasUniqueColumns(first) && HasUniqueColumns(second), @"cross-browser toggles never duplicate table columns");
        Check(fabs([[first tableColumnWithIdentifier:NoteDateModifiedColumnString] width]-120) < 1
            && fabs([[second tableColumnWithIdentifier:NoteDateModifiedColumnString] width]-150) < 1,
            @"hidden and restored columns retain independent browser widths");
        Check([ColumnOrder(first) isEqual:beforeVisibilityOrder], @"another browser's visibility toggle preserves this browser's column order");
        [second addPermanentTableColumn:[second noteAttributeColumnForIdentifier:NoteDateModifiedColumnString]];
        Check(HasUniqueColumns(second), @"adding an already-visible column is idempotent");
        [app newWindow:self]; Pump();
        AppController *mixedBrowser = [[app browserControllers] lastObject];
        if (![mixedBrowser horizontalLayout]) [mixedBrowser switchViewLayout:self];
        NotesTableView *mixedTable = [mixedBrowser valueForKey:@"notesTableView"];
        [[mixedBrowser browserSession] setSortColumn:[mixedTable noteAttributeColumnForIdentifier:NoteDateModifiedColumnString] reversed:YES];
        [first actionHideShowColumn:ColumnMenuItem(first, NoteDateModifiedColumnString)]; Pump();
        Check([[mixedTable tableColumns] count] == 1 && [mixedTable tableColumnWithIdentifier:NoteTitleColumnString] != nil,
            @"global visibility changes keep horizontal layout's single title column");
        Check([[[[mixedBrowser browserSession] sortColumn] identifier] isEqualToString:NoteTitleColumnString], @"horizontal browser also replaces a globally hidden sort column");
        [mixedTable actionHideShowColumn:ColumnMenuItem(mixedTable, NoteDateModifiedColumnString)]; Pump();
        Check([[mixedTable tableColumns] count] == 1 && [first tableColumnWithIdentifier:NoteDateModifiedColumnString] != nil,
            @"showing a column from horizontal layout updates vertical browsers only");
        [mixedBrowser switchViewLayout:self]; Pump();
        Check([mixedTable tableColumnWithIdentifier:NoteDateModifiedColumnString] != nil && HasUniqueColumns(mixedTable),
            @"switching back to vertical uses the current global visible columns");
        NSMutableDictionary *oldState = [[firstState mutableCopy] autorelease];
        [oldState removeObjectForKey:@"columns"];
        [restoredFirst restoreBrowserWindowState:oldState]; Pump();
        Check([[restoredFirstTable tableColumns] count] >= 2, @"older state without columns remains readable");
        [restoredFirstTable restoreColumnLayoutState:@[@"wrong type"]];
        [restoredFirstTable restoreColumnLayoutState:@{@"vertical": @{@"order": @[@42, @"Unknown", NoteTitleColumnString, NoteTitleColumnString],
            @"widths": @{NoteTitleColumnString: @(-1), NoteDateModifiedColumnString: @"bad"}}}];
        Check(isfinite(TitleWidth(restoredFirstTable)) && TitleWidth(restoredFirstTable) > 0, @"malformed entries do not set invalid widths or duplicate columns");
        Check([[NSSet setWithArray:ColumnOrder(restoredFirstTable)] count] == [[restoredFirstTable tableColumns] count], @"duplicate saved identifiers do not duplicate visible columns");
        NSTableColumn *title = [restoredFirstTable tableColumnWithIdentifier:NoteTitleColumnString];
        [restoredFirstTable restoreColumnLayoutState:@{@"vertical": @{@"widths": @{NoteTitleColumnString: @(DBL_MAX)}}}];
        Check(TitleWidth(restoredFirstTable) <= [title maxWidth], @"oversized width is clamped to the column maximum");
        [restoredFirstTable restoreColumnLayoutState:@{@"vertical": @{@"widths": @{NoteTitleColumnString: @(NAN)}}}];
        Check(isfinite(TitleWidth(restoredFirstTable)), @"nonfinite saved width is ignored");
        // A saved identifier cannot re-enable a column hidden by current preferences.
        NSTableColumn *date = [restoredFirstTable tableColumnWithIdentifier:NoteDateModifiedColumnString];
        [restoredFirstTable removeTableColumn:date];
        [restoredFirstTable restoreColumnLayoutState:[firstState objectForKey:@"columns"]];
        Check([restoredFirstTable tableColumnWithIdentifier:NoteDateModifiedColumnString] == nil, @"saved layout does not re-add hidden columns");
        [firstState release]; [secondState release]; [horizontalState release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"COLUMN REGRESSIONS COMPLETED (%lu checks)",(unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
