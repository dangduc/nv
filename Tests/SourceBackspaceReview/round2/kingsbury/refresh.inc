- (void)refreshSearchHighlights {
    NSUInteger generation = ++searchHighlightGeneration;
    [textView removeHighlightedTerms];
    NVBrowserSession *session = [self browserSession];
    NVSearchService *service = [[NVApplicationController sharedController] searchService];
    [service cancelLiteralRangesForOwner:session];
    if (!currentNote || ![prefsController highlightSearchTerms] || ![session searchResultsAreCurrent] || searchHasPendingComposition) return;
    NSInteger row = [notesTableView primarySelectedRow];
    if (row < 0) return;
    NSString *kind = [session matchKindAtIndex:row];
    if ([kind isEqual:@"retained"]) return;
    NSString *key = [[session rowKeyAtIndex:row] copy];
    NSString *displayedSource = [[textView string] copy];
    BOOL (^isCurrent)(void) = ^BOOL {
        return generation == searchHighlightGeneration && [session searchResultsAreCurrent] &&
            [[session rowKeyAtIndex:[notesTableView primarySelectedRow]] isEqual:key];
    };
    NVSearchLiteralRangesCompletion apply = ^(NSArray *ranges, NSString *source, NSError *error) {
        // Shared character notifications advance this generation immediately.
        // The worker compared immutable source copies before returning ranges.
        if (!error && isCurrent()) [textView setSearchHighlightRanges:ranges];
    };
    if ([kind isEqual:@"fuzzy"]) [session requestSourceHighlightsForRow:row completion:^(NSArray *ranges, NSString *source) {
        if (isCurrent()) [service validateSourceRanges:ranges source:source matchingSource:displayedSource owner:session completion:apply];
    }];
    else [service requestLiteralRangesInSource:[[currentNote contentString] string] matchingSource:displayedSource query:[session searchString] owner:session completion:apply];
    [displayedSource release]; [key release];
}
