- (void)nv_waitForSearch {
    NVBrowserSession *session = [self browserSession];
    Check(CaptureAwait(^BOOL { return [session searchResultsAreCurrent] && ![session searchPending]; }, 10),
        @"the fuzzy query completes before capture");
    Check(CaptureAwait(^BOOL {
        for (NSUInteger row = 0; row < [session resultCount]; row++) {
            NSAttributedString *preview = [session previewForRow:row inTable:notesTableView];
            __block BOOL highlighted = NO;
            [preview enumerateAttribute:NSBackgroundColorAttributeName inRange:NSMakeRange(0, [preview length]) options:0
                usingBlock:^(id color, NSRange range, BOOL *stop) { if (color) highlighted = YES; }];
            if (!highlighted) return NO;
        }
        return [session resultCount] > 0;
    }, 5), @"every result preview has its fuzzy match highlights");
}

- (void)nv_selectNote:(NoteObject *)note matchingLine:(NSString *)line {
    NVBrowserSession *session = [self browserSession];
    NSUInteger found = NSNotFound;
    for (NSUInteger row = 0; row < [session resultCount]; row++) {
        NVSearchMatch *match = [[session searchResult] matchForRowKey:[session rowKeyAtIndex:row]];
        if ([session noteObjectAtFilteredIndex:row] == note && [[[match line] field] isEqual:@"source"] &&
            [[[match line] text] isEqual:line]) { found = row; break; }
    }
    Check(found != NSNotFound, @"the selected body line has its own fuzzy result");
    [notesTableView selectRowAndScroll:found];
    [self displayContentsForNoteAtIndex:found];
    [self focusNoteBody];
    Check(CaptureAwait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]); }, 5),
        @"Org syntax highlighting is current");
    for (NSUInteger i = 0; i < 12; i++) Pump();
    Check([self selectedNoteObject] == note && [[note sourceSyntaxIdentifier] isEqual:@"org"],
        @"the browser selects the intended Org note");
    NSColor *background = [[textView backgroundColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    Check(fabs([background redComponent] - 253 / 255.0) < .005 &&
        fabs([background greenComponent] - 233 / 255.0) < .005 && fabs([background blueComponent] - 217 / 255.0) < .005,
        @"the editor uses the light User Scheme background");
    NSRange todo = [[textView string] rangeOfString:@"TODO"];
    Check([[[textView layoutManager] temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:todo.location
        effectiveRange:NULL] isEqual:@"keyword.todo"], @"Org TODO syntax is active");
    __block BOOL highlighted = NO;
    NSRange selectedLine = [[textView string] rangeOfString:line];
    for (NSUInteger index = selectedLine.location; index < NSMaxRange(selectedLine); index++) {
        NSColor *color = [[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName
            atCharacterIndex:index effectiveRange:NULL];
        if (color) { highlighted = YES; break; }
    }
    Check(highlighted, @"the selected fuzzy match is highlighted in the Org source");
}
