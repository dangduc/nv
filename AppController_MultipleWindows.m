#import "AppController.h"
#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "NoteAttributeColumn.h"
#import "LinkingEditor.h"
#import "DualField.h"
#import "GlobalPrefs.h"
#import "NotationPrefs.h"
#import "BookmarksController.h"
#import "NSString_NV.h"
#import "RBSplitView.h"
#import "RBSplitSubview.h"
#import "TitlebarButton.h"
#import "SyncSessionController.h"
#import "SecureTextEntryManager.h"

@implementation AppController (MultipleWindows)
- (NVBrowserSession *)browserSession { return (NVBrowserSession *)notationController; }
- (NotationController *)sharedNotationController { return [[self browserSession] library]; }
- (NSString *)browserIdentifier { return browserIdentifier; }
- (void)retainWindowObjects:(NSArray *)objects { windowObjects = [objects retain]; }
- (void)attachLibrary:(NotationController *)library {
    [self setupViewsAfterAppAwakened];
    NSString *oldQuery = [[[self browserSession] searchString] copy];
    NoteAttributeColumn *oldSort = [[[self browserSession] sortColumn] retain];
    BOOL oldReverse = [[self browserSession] reverseSorted];
    [notesTableView abortEditing];
    [notesTableView deselectAll:self];
    [self _setCurrentNote:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SyncSessionsChangedVisibleStatusNotification object:nil];
    [[self browserSession] setDelegate:nil];
    [notationController release];
    notationController = (id)[[NVBrowserSession alloc] initWithLibrary:library];
    [[self browserSession] setDelegate:self];
    [notesTableView setDataSource:[[self browserSession] notesListDataSource]];
    [notesTableView setLabelsListSource:[library labelsListDataSource]];
    [[self browserSession] setSortColumn:[notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]]];
    [notesTableView reloadData];
    [self setEmptyViewState:YES];
    [noteSelections removeAllObjects];
    [windowUndoManager removeAllActions];
    if (oldQuery) {
        [typedString release]; typedString = [oldQuery copy]; typedStringIsCached = YES;
        [field setStringValue:oldQuery];
        [[self browserSession] filterNotesFromString:oldQuery];
        if (oldSort) [[self browserSession] setSortColumn:oldSort reversed:oldReverse];
    }
    if (applicationOwner) {
        [[prefsController bookmarksController] setDataSource:library];
        if ([library aliasNeedsUpdating]) [prefsController setAliasDataForDefaultDirectory:[library aliasDataForNoteDirectory] sender:self];
        if (!oldQuery) [self restoreListStateUsingPreferences];
    }
    [titleBarButton setMenu:[[library syncSessionController] syncStatusMenu]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncSessionsChangedVisibleStatus:)
        name:SyncSessionsChangedVisibleStatusNotification object:[library syncSessionController]];
    if ([[library notationPrefs] secureTextEntry]) [[SecureTextEntryManager sharedInstance] enableSecureTextEntry];
    else [[SecureTextEntryManager sharedInstance] disableSecureTextEntry];
    [textView setAllowsUndo:NO];
    [oldQuery release];
    [oldSort release];
}
- (void)prepareAdditionalWindow {
    hasLaunched = YES;
    [field setTrackingRect];
    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    [window makeFirstResponder:field];
    // Visual preferences are global; changing libraries and starting services remain application-owned.
    for (NSString *selector in @[@"setForegroundTextColor:sender:", @"setBackgroundTextColor:sender:",
        @"setTableFontSize:sender:", @"setTableColumnsShowPreview:sender:", @"addTableColumn:sender:", @"removeTableColumn:sender:"]) {
        [prefsController registerForSettingChange:NSSelectorFromString(selector) withTarget:self];
    }
}
- (void)finishEditing {
    if ([textView hasMarkedText]) [textView unmarkText];
    [editingSession commitPendingTextChanges];
}
- (void)refreshEditorForNote:(NoteObject *)note {
    if (note == currentNote) {
        [textView setNeedsDisplay:YES];
        [self postTextUpdate];
        [self updateWordCount:![prefsController showWordCount]];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldUpdate" object:self];
    }
}
- (id)tablePreviewForNote:(NoteObject *)note { return [[self browserSession] previewForNote:note inTable:notesTableView]; }
- (void)unregisterBrowserObservers {
    [prefsController unregisterTarget:self];
    NSMutableArray *views = [NSMutableArray arrayWithObjects:[window contentView], nil];
    for (id object in windowObjects) if ([object isKindOfClass:[NSView class]]) [views addObject:object];
    for (NSUInteger i = 0; i < [views count]; i++) {
        NSView *view = [views objectAtIndex:i];
        [views addObjectsFromArray:[view subviews]];
        [prefsController unregisterTarget:view];
    }
    [modifierTimer invalidate];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}
- (NSDictionary *)browserWindowState {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    [state setObject:[window stringWithSavedFrame] ?: @"" forKey:@"frame"];
    [state setObject:@(browserHorizontalLayout) forKey:@"horizontalLayout"];
    [state setObject:[[self browserSession] searchString] ?: @"" forKey:@"search"];
    [state setObject:[[[self browserSession] sortColumn] identifier] ?: NoteTitleColumnString forKey:@"sort"];
    [state setObject:@([[self browserSession] reverseSorted]) forKey:@"reverse"];
    [state setObject:@([notesSubview dimension]) forKey:@"divider"];
    [state setObject:NSStringFromPoint([[notesScrollView contentView] bounds].origin) forKey:@"listScroll"];
    if (currentNote) {
        [state setObject:[NSString uuidStringWithBytes:*[currentNote uniqueNoteIDBytes]] forKey:@"note"];
        [state setObject:NSStringFromRange([textView selectedRange]) forKey:@"selection"];
        [state setObject:NSStringFromPoint([[textScrollView contentView] bounds].origin) forKey:@"editorScroll"];
    }
    return state;
}
- (void)restoreBrowserWindowState:(NSDictionary *)state {
    if ([[state objectForKey:@"frame"] isKindOfClass:[NSString class]]) [window setFrameFromString:[state objectForKey:@"frame"]];
    if ([state objectForKey:@"horizontalLayout"] && [[state objectForKey:@"horizontalLayout"] boolValue] != browserHorizontalLayout) [self switchViewLayout:self];
    NSString *query = [state objectForKey:@"search"];
    if (![query isKindOfClass:[NSString class]]) query = @"";
    [typedString release];
    typedString = [query copy];
    typedStringIsCached = YES;
    [field setStringValue:query];
    [[self browserSession] filterNotesFromString:query];
    NSString *sort = [state objectForKey:@"sort"];
    if (![sort isKindOfClass:[NSString class]]) sort = NoteTitleColumnString;
    NoteAttributeColumn *column = [notesTableView noteAttributeColumnForIdentifier:sort];
    if (!column) column = [notesTableView noteAttributeColumnForIdentifier:NoteTitleColumnString];
    [[self browserSession] setSortColumn:column reversed:[[state objectForKey:@"reverse"] boolValue]];
    [notesTableView setSortDirection:[[self browserSession] reverseSorted] inTableColumn:column];
    NSString *uuid = [state objectForKey:@"note"];
    for (NoteObject *note in [[self sharedNotationController] allNotes]) {
        if ([[NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]] isEqual:uuid]) {
            NSUInteger index = [[self browserSession] indexInFilteredListForNoteIdenticalTo:note];
            if (index != NSNotFound) [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
            break;
        }
    }
    if (currentNote && [[state objectForKey:@"selection"] isKindOfClass:[NSString class]]) {
        NSRange range = NSRangeFromString([state objectForKey:@"selection"]);
        if (range.location <= [[textView string] length] && range.length <= [[textView string] length] - range.location) [textView setSelectedRange:range];
    }
    id divider = [state objectForKey:@"divider"];
    if ([divider isKindOfClass:[NSNumber class]]) { [notesSubview setDimension:MAX(80, [divider doubleValue])]; [splitView adjustSubviews]; }
    if ([[state objectForKey:@"listScroll"] isKindOfClass:[NSString class]]) [notesTableView scrollPoint:NSPointFromString([state objectForKey:@"listScroll"])];
    if (currentNote && [[state objectForKey:@"editorScroll"] isKindOfClass:[NSString class]]) [textView scrollPoint:NSPointFromString([state objectForKey:@"editorScroll"])];
}
@end
