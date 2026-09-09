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
#import "SecureTextEntryManager.h"
#import "PreviewController.h"

static NSDictionary *ValidatedBodyState(id value) {
    if (![value isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    id scroll = [value objectForKey:@"sourceScroll"];
    if ([scroll isKindOfClass:[NSString class]]) {
        NSPoint point = NSPointFromString(scroll);
        if (isfinite(point.x) && isfinite(point.y) && point.x >= 0 && point.y >= 0) [state setObject:scroll forKey:@"sourceScroll"];
    }
    id viewers = [value objectForKey:@"viewers"];
    if ([viewers isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *validViewers = [NSMutableDictionary dictionary];
        for (NSString *identifier in @[@"markdown", @"textile", @"html"]) {
            id viewerState = [viewers objectForKey:identifier];
            if ([viewerState isKindOfClass:[NSDictionary class]]) [validViewers setObject:viewerState forKey:identifier];
        }
        [state setObject:validViewers forKey:@"viewers"];
    }
    return state;
}

@implementation AppController (MultipleWindows)
- (NVBrowserSession *)browserSession { return (NVBrowserSession *)notationController; }
- (NotationController *)sharedNotationController { return [[self browserSession] library]; }
- (NSString *)browserIdentifier { return browserIdentifier; }
- (void)retainWindowObjects:(NSArray *)objects { windowObjects = [objects retain]; }
- (void)attachLibrary:(NotationController *)library {
    [self attachLibrary:library finishingOldLibrary:YES];
}
- (void)attachLibrary:(NotationController *)library finishingOldLibrary:(BOOL)finishOldLibrary {
    [self cancelMultiTagEditing];
    [self setupViewsAfterAppAwakened];
    NSString *oldQuery = [[[self browserSession] searchString] copy];
    NSString *oldMode = [[[self browserSession] searchMode] copy];
    NoteAttributeColumn *oldSort = [[[self browserSession] sortColumn] retain];
    BOOL oldReverse = [[self browserSession] reverseSorted];
    // Detach before deselection callbacks can finish editing the old note.
    [self _setCurrentNote:nil finishingEditing:finishOldLibrary];
    [notesTableView abortEditing];
    [notesTableView deselectAll:self];
    [self discardViewer];
    [[self browserSession] setDelegate:nil];
    [self cancelSearchIntents];
    [[self browserSession] invalidateSearch];
    [notationController release];
    notationController = (id)[[NVBrowserSession alloc] initWithLibrary:library];
    [[self browserSession] setDelegate:self];
    [[self browserSession] setSearchService:[[NVApplicationController sharedController] searchService]];
    [[self browserSession] setSearchMode:oldMode ?: @"fuzzy"];
    [self setupSearchControls];
    [notesTableView setDataSource:[[self browserSession] notesListDataSource]];
    [notesTableView setLabelsListSource:[library labelsListDataSource]];
    [[self browserSession] setSortColumn:[notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]]];
    [notesTableView reloadData];
    [self setEmptyViewState:YES];
    [noteSelections removeAllObjects];
    [noteBodyStates removeAllObjects];
    presentationStateGeneration++;
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
    if ([[library notationPrefs] secureTextEntry]) [[SecureTextEntryManager sharedInstance] enableSecureTextEntry];
    else [[SecureTextEntryManager sharedInstance] disableSecureTextEntry];
    [textView setAllowsUndo:NO];
    [oldQuery release];
    [oldMode release];
    [oldSort release];
}
- (void)prepareAdditionalWindow {
    hasLaunched = YES;
    [window makeFirstResponder:field];
    // Visual preferences are global; changing libraries remains application-owned.
    for (NSString *selector in @[@"setForegroundTextColor:sender:", @"setBackgroundTextColor:sender:",
        @"setTableFontSize:sender:", @"setTableColumnsShowPreview:sender:", @"addTableColumn:sender:", @"removeTableColumn:sender:"]) {
        [prefsController registerForSettingChange:NSSelectorFromString(selector) withTarget:self];
    }
}
- (void)finishEditing {
    [self commitNoteMetadata];
    if ([textView hasMarkedText]) [textView unmarkText];
    [editingSession commitPendingTextChanges];
}
- (void)refreshEditorForNote:(NoteObject *)note {
    if (note == currentNote) {
        [self updateNoteHeader];
        [textView setNeedsDisplay:YES];
        [self postTextUpdate];
        [self updateWordCount:![prefsController showWordCount]];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldUpdate" object:self];
    }
}
- (id)tablePreviewForNote:(NoteObject *)note { return [[self browserSession] previewForNote:note inTable:notesTableView]; }
- (id)tablePreviewForRow:(NSInteger)row { return row < 0 ? nil : [[self browserSession] previewForRow:row inTable:notesTableView]; }
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
    [self captureBodyPresentation];
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    [state setObject:[window stringWithSavedFrame] ?: @"" forKey:@"frame"];
    [state setObject:@2 forKey:@"layoutVersion"];
    [state setObject:@NO forKey:@"horizontalLayout"];
    [state setObject:@1 forKey:@"presentationVersion"];
    [state setObject:@(viewingNote) forKey:@"viewingNote"];
    [state setObject:selectedViewerIdentifier forKey:@"viewerIdentifier"];
    [state setObject:[[self browserSession] searchString] ?: @"" forKey:@"search"];
    [state setObject:[self searchMode] forKey:@"searchMode"];
    if (selectedSearchRowKey) [state setObject:selectedSearchRowKey forKey:@"searchRowKey"];
    [state setObject:[[[self browserSession] sortColumn] identifier] ?: NoteTitleColumnString forKey:@"sort"];
    [state setObject:@([[self browserSession] reverseSorted]) forKey:@"reverse"];
    [state setObject:@([self notesListHeight]) forKey:@"divider"];
    [state setObject:[notesTableView columnLayoutState] forKey:@"columns"];
    [state setObject:NSStringFromPoint([[notesScrollView contentView] bounds].origin) forKey:@"listScroll"];
    if (currentNote) {
        [state setObject:[NSString uuidStringWithBytes:*[currentNote uniqueNoteIDBytes]] forKey:@"note"];
        [state setObject:NSStringFromRange([textView selectedRange]) forKey:@"selection"];
        NSString *key = [NSString uuidStringWithBytes:*[currentNote uniqueNoteIDBytes]];
        NSString *sourceScroll = [[noteBodyStates objectForKey:key] objectForKey:@"sourceScroll"];
        [state setObject:viewingNote && sourceScroll ? sourceScroll : NSStringFromPoint([[textScrollView contentView] bounds].origin) forKey:@"editorScroll"];
        if ([noteBodyStates objectForKey:key]) [state setObject:[noteBodyStates objectForKey:key] forKey:@"bodyState"];
    }
    if (pendingSearchRestoration) {
        NSMutableDictionary *pending = [[pendingSearchRestoration mutableCopy] autorelease];
        [pending setObject:[state objectForKey:@"frame"] forKey:@"frame"];
        return pending;
    }
    return state;
}
- (void)restoreBrowserWindowState:(NSDictionary *)state {
    [self cancelSearchIntents];
    searchApplyingResult = YES;
    [self setViewingNote:NO];
    presentationStateGeneration++;
    [self discardViewer];
    if ([[state objectForKey:@"frame"] isKindOfClass:[NSString class]]) [window setFrameFromString:state[@"frame"]];
    browserHorizontalLayout = NO;
    NSString *query = [state[@"search"] isKindOfClass:[NSString class]] ? state[@"search"] : @"";
    [typedString release]; typedString = [query copy]; typedStringIsCached = YES;
    [field setStringValue:query];
    NSString *sort = [state[@"sort"] isKindOfClass:[NSString class]] ? state[@"sort"] : NoteTitleColumnString;
    NoteAttributeColumn *column = [notesTableView noteAttributeColumnForIdentifier:sort] ?:
        [notesTableView noteAttributeColumnForIdentifier:NoteTitleColumnString];
    [[self browserSession] setSortColumn:column reversed:[state[@"reverse"] boolValue]];
    [notesTableView setSortDirection:[[self browserSession] reverseSorted] inTableColumn:column];
    [[self browserSession] setSearchMode:[state[@"searchMode"] isEqual:@"fuzzy"] ? @"fuzzy" : @"exact"];
    [self setupSearchControls];
    [[self browserSession] filterNotesFromString:query];
    id divider = state[@"divider"];
    if ([state[@"horizontalLayout"] boolValue]) [self setNotesListHeight:NSHeight([splitView bounds]) / 3.0];
    else if ([divider isKindOfClass:[NSNumber class]]) [self setNotesListHeight:[divider doubleValue]];
    [notesTableView restoreColumnLayoutState:state[@"columns"]];
    searchApplyingResult = NO;
    if ([[self browserSession] searchResultsAreCurrent]) {
        searchApplyingResult = YES;
        [self applyRestoredSearchNoteState:state];
        searchApplyingResult = NO;
    } else pendingSearchRestoration = [state copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(restoreNotesListHeight) object:nil];
    if (![state[@"horizontalLayout"] boolValue] && [divider isKindOfClass:[NSNumber class]]) {
        pendingListHeight = [divider doubleValue];
        [self performSelector:@selector(restoreNotesListHeight) withObject:nil afterDelay:0];
    }
    [self updateSearchAffordance];
}
- (void)applyRestoredSearchNoteState:(NSDictionary *)state {
    NSString *uuid = state[@"note"];
    NSUInteger row = NSNotFound;
    for (NoteObject *note in [[self sharedNotationController] allNotes]) {
        if ([[NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]] isEqual:uuid]) {
            NSString *key = state[@"searchRowKey"];
            if ([key isKindOfClass:[NSString class]]) row = [[self browserSession] indexForRowKey:key];
            if (row == NSNotFound || [[self browserSession] noteObjectAtFilteredIndex:row] != note)
                row = [[self browserSession] indexInFilteredListForNoteIdenticalTo:note];
            break;
        }
    }
    if (row != NSNotFound) {
        [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [self displayContentsForNoteAtIndex:row];
    } else {
        [notesTableView deselectAll:nil];
        [self _setCurrentNote:nil];
        [self setEmptyViewState:YES];
    }
    if (currentNote && [state[@"selection"] isKindOfClass:[NSString class]]) {
        NSRange range = NSRangeFromString(state[@"selection"]);
        NSUInteger length = [[textView string] length];
        if (range.location <= length && range.length <= length - range.location) [textView setSelectedRange:range];
    }
    if ([state[@"listScroll"] isKindOfClass:[NSString class]]) [notesTableView scrollPoint:NSPointFromString(state[@"listScroll"])];
    if (currentNote && [state[@"editorScroll"] isKindOfClass:[NSString class]]) [textView scrollPoint:NSPointFromString(state[@"editorScroll"])];
    NSString *viewer = state[@"viewerIdentifier"];
    if ([@[@"markdown", @"textile", @"html"] containsObject:viewer]) {
        [selectedViewerIdentifier release]; selectedViewerIdentifier = [viewer copy];
    }
    if (currentNote) [noteBodyStates setObject:ValidatedBodyState(state[@"bodyState"])
        forKey:[NSString uuidStringWithBytes:*[currentNote uniqueNoteIDBytes]]];
    id version = state[@"presentationVersion"], mode = state[@"viewingNote"];
    [self setViewingNote:[version isKindOfClass:[NSNumber class]] && [version integerValue] == 1 &&
        [mode isKindOfClass:[NSNumber class]] && [mode boolValue]];
    [self updateBodyPresentation];
    [self refreshSearchHighlights];
}
@end
