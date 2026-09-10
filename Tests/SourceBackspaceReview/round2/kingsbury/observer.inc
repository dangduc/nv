- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification {
    NSTextStorage *storage = [notification object];
    if (storage != [textView textStorage] || !([storage editedMask] & NSTextStorageEditedCharacters)) return;
    // Every attached editor observes shared characters, including uncommitted composition.
    ++searchHighlightGeneration;
    [textView invalidateSearchHighlights];
}
