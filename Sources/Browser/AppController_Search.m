#import "AppController.h"
#import "NVBrowserSession.h"
#import "NVSearchService.h"
#import "NVApplicationController.h"
#import "NoteObject.h"
#import "DualField.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"
#import "NSString_NV.h"

@implementation AppController (Search)
- (NSString *)searchMode { return [[self browserSession] searchMode] ?: @"exact"; }
- (NSString *)selectedSearchResultRowKey { return selectedSearchRowKey; }
- (BOOL)searchFieldHasFocus {
    return [field currentEditor] && [window firstResponder] == [field currentEditor];
}
- (void)setupSearchControls {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:NSLocalizedString(@"Search Mode", nil)] autorelease];
    for (NSArray *entry in @[@[@"Fuzzy", @"fuzzy"], @[@"Exact", @"exact"]]) {
        NSMenuItem *item = [menu addItemWithTitle:NSLocalizedString(entry[0], nil) action:@selector(selectSearchMode:) keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:entry[1]];
        [item setState:[[self searchMode] isEqual:entry[1]] ? NSControlStateValueOn : NSControlStateValueOff];
    }
    [(NSSearchFieldCell *)[field cell] setSearchMenuTemplate:menu];
    [field setPlaceholderString:[[self searchMode] isEqual:@"fuzzy"] ? NSLocalizedString(@"Fuzzy Search or Create", nil) : NSLocalizedString(@"Exact Search or Create", nil)];
    [field setAccessibilityLabel:[field placeholderString]];
}
- (void)cancelSearchIntents {
    searchAutocompletePending = NO;
    [pendingSearchReturnQuery release]; pendingSearchReturnQuery = nil;
    [pendingSearchRestoration release]; pendingSearchRestoration = nil;
    [pendingSearchReveal release]; pendingSearchReveal = nil;
}
- (void)searchForString:(NSString *)string mode:(NSString *)mode {
    if (!string) return;
    [self cancelSearchIntents];
    searchApplyingResult = YES;
    [[self browserSession] setSearchMode:mode];
    searchApplyingResult = NO;
    [self setupSearchControls];
    [self setDualFieldIsVisible:YES];
    [field setStringValue:string];
    [self selectSearchField];
    [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
}
- (IBAction)selectSearchMode:(id)sender {
    [self searchForString:[field stringValue] mode:[sender representedObject]];
}
- (IBAction)retrySearch:(id)sender {
    [self cancelSearchIntents];
    [[self browserSession] refilterNotes];
    [self updateSearchAffordance];
}
- (void)showSearchProgress {
    searchStatusDelayElapsed = YES;
    [self updateSearchAffordance];
}
- (void)browserSessionSearchStateDidChange:(NVBrowserSession *)session {
    if (session != [self browserSession]) return;
    if (![session searchResultsAreCurrent]) {
        searchHighlightGeneration++;
        [textView removeHighlightedTerms];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showSearchProgress) object:nil];
    searchStatusDelayElapsed = NO;
    if ([session searchPending]) {
        if (!searchSubmitting) {
            searchAutocompletePending = NO;
            [pendingSearchReturnQuery release]; pendingSearchReturnQuery = nil;
        }
        [self performSelector:@selector(showSearchProgress) withObject:nil afterDelay:0.1];
    }
    [self updateSearchAffordance];
    if ([session searchResultsAreCurrent]) [self refreshSearchHighlights];
}
- (void)browserSessionSearchDidComplete:(NVBrowserSession *)session {
    if (session != [self browserSession] || searchApplyingResult || searchHasPendingComposition) return;
    [self updateSearchAffordance];
    if (![session searchResultsAreCurrent]) return;
    searchApplyingResult = YES;
    if (pendingSearchRestoration) {
        NSDictionary *state = [[pendingSearchRestoration retain] autorelease];
        [pendingSearchRestoration release]; pendingSearchRestoration = nil;
        [self applyRestoredSearchNoteState:state];
    } else if (pendingSearchReveal) {
        NSDictionary *intent = [[pendingSearchReveal retain] autorelease];
        [pendingSearchReveal release]; pendingSearchReveal = nil;
        if ([intent objectForKey:@"notes"]) [self notation:(id)session revealNotes:[intent objectForKey:@"notes"]];
        else {
            NoteObject *note = [intent objectForKey:@"note"];
            [self revealNote:note options:[[intent objectForKey:@"options"] unsignedIntegerValue]];
            NSString *key = [intent objectForKey:@"rowKey"];
            NSUInteger row = key ? [session indexForRowKey:key] : NSNotFound;
            if (row != NSNotFound && [session noteObjectAtFilteredIndex:row] == note) {
                [notesTableView selectRowAndScroll:row];
                [self displayContentsForNoteAtIndex:row];
            }
            if ([intent objectForKey:@"scrollOffset"] && [notesTableView primarySelectedRow] >= 0)
                [notesTableView scrollRowToVisible:[notesTableView primarySelectedRow] withVerticalOffset:[[intent objectForKey:@"scrollOffset"] floatValue]];
        }
    } else if (searchAutocompletePending && searchIntentGeneration == [session searchGeneration] && [self searchFieldHasFocus]) {
        NSUInteger preferred = [session preferredSelectedNoteIndex];
        if ([prefsController autoCompleteSearches] && preferred != NSNotFound) {
            [notesTableView selectRowAndScroll:preferred];
            [self displayContentsForNoteAtIndex:preferred];
        } else {
            [notesTableView deselectAll:nil];
            [self _setCurrentNote:nil];
            [self setEmptyViewState:YES];
        }
    }
    searchAutocompletePending = NO;
    BOOL finishReturn = pendingSearchReturnQuery && [pendingSearchReturnQuery isEqual:[session searchString]] &&
        searchIntentGeneration == [session searchGeneration] && [self searchFieldHasFocus];
    [pendingSearchReturnQuery release]; pendingSearchReturnQuery = nil;
    searchApplyingResult = NO;
    [self refreshSearchHighlights];
    if (finishReturn) [self performSearchReturn];
}
- (void)performSearchReturn {
    NVBrowserSession *session = [self browserSession];
    if (searchHasPendingComposition || [(NSTextView *)[field currentEditor] hasMarkedText]) return;
    if (![session searchResultsAreCurrent]) {
        if ([session searchPending] && [self searchFieldHasFocus]) {
            [pendingSearchReturnQuery release]; pendingSearchReturnQuery = [[session searchString] copy];
            searchIntentGeneration = [session searchGeneration];
        }
        return;
    }
    if ([[session searchMode] isEqual:@"fuzzy"] && [session hasSearchTerms]) {
        if ([session resultCount]) {
            NSInteger row = [notesTableView primarySelectedRow];
            if (row < 0 || [[session matchKindAtIndex:row] isEqual:@"retained"]) row = 0;
            [notesTableView selectRowAndScroll:row];
            [self displayContentsForNoteAtIndex:row];
        } else {
            [notesTableView deselectAll:nil];
            [self _setCurrentNote:nil];
            [self setEmptyViewState:YES];
            [self createNoteIfNecessary];
        }
    } else {
        [self createNoteIfNecessary];
    }
    [self focusNoteBody];
}
- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification {
    NSTextStorage *storage = [notification object];
    if (storage != [textView textStorage] || !([storage editedMask] & NSTextStorageEditedCharacters)) return;
    // Every attached editor observes shared characters, including uncommitted composition.
    ++searchHighlightGeneration;
    [textView removeHighlightedTerms];
}
- (void)refreshSearchHighlights {
    NSUInteger generation = ++searchHighlightGeneration;
    [textView removeHighlightedTerms];
    NVBrowserSession *session = [self browserSession];
    if (!currentNote || ![prefsController highlightSearchTerms] || ![session searchResultsAreCurrent] || searchHasPendingComposition) return;
    NSString *committed = [[currentNote contentString] string];
    if (![[textView string] isEqual:committed]) return;
    NSInteger row = [notesTableView primarySelectedRow];
    if (row < 0) return;
    NSString *kind = [session matchKindAtIndex:row];
    if (![kind isEqual:@"fuzzy"]) {
        if (![kind isEqual:@"retained"]) {
            NVSearchQuery *query = [[[NVSearchQuery alloc] initWithString:[session searchString]] autorelease];
            [textView setSearchHighlightRanges:[query literalRangesInString:committed]];
        }
        return;
    }
    NSString *key = [[session rowKeyAtIndex:row] copy];
    [session requestSourceHighlightsForRow:row completion:^(NSArray *ranges, NSString *source) {
        if (generation == searchHighlightGeneration && [session searchResultsAreCurrent] &&
            [[session rowKeyAtIndex:[notesTableView primarySelectedRow]] isEqual:key] && [[textView string] isEqual:source])
            [textView setSearchHighlightRanges:ranges];
    }];
    [key release];
}
@end
