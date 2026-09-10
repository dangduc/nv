- (void)invalidateSearchHighlights {
    if (searchHighlightsInvalidated) return;
    searchHighlightsInvalidated = YES;
    // TextKit has not adjusted its glyph ranges during storage notifications.
    // Suppress stale backgrounds now and remove them after edit processing.
    [self performSelector:@selector(removeHighlightedTerms) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
}
- (void)removeHighlightedTerms {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];
    searchHighlightsInvalidated = NO;
    if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) {
        [self invalidateSearchHighlights];
        return;
    }
    [[self layoutManager] removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0, [[self string] length])];
}
- (void)setSearchHighlightRanges:(NSArray *)ranges {
    [self removeHighlightedTerms];
    if (searchHighlightsInvalidated) return;
    NSColor *color = [[self currentSearchHighlightAttributes] objectForKey:NSBackgroundColorAttributeName];
    if (!color) return;
    NSUInteger length = [[self string] length];
    NSUInteger displayed = 0;
    for (NSValue *value in ranges) {
        if (displayed++ == NVSearchMaximumDisplayedRanges) break;
        NSRange range = [value rangeValue];
        if (range.location <= length && range.length <= length - range.location && range.length)
            [[self layoutManager] addTemporaryAttribute:NSBackgroundColorAttributeName value:color forCharacterRange:range];
    }
}