- (void)nv_summaryContrarianAwait {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent] && ![[self browserSession] searchError],
        @"the real search worker publishes a current successful result");
}
- (NSArray *)nv_summaryContrarianAXTree {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
    NSMutableArray *seen = [NSMutableArray array];
    for (NSUInteger i = 0; i < [pending count] && [seen count] < 300; i++) {
        id item = [pending objectAtIndex:i];
        if ([seen indexOfObjectIdenticalTo:item] != NSNotFound) continue;
        [seen addObject:item];
        if ([item respondsToSelector:@selector(accessibilityAttributeValue:)]) {
            id children = [item accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
            if ([children isKindOfClass:[NSArray class]]) [pending addObjectsFromArray:children];
        }
    }
    Check([seen count] < 300, @"the exposed accessibility traversal remains within its bound");
    return seen;
}
- (void)nv_summaryContrarianCheckSurface {
    Check(NSEqualRects([notesScrollView frame], [notesSubview bounds]),
        @"normal search reserves no blank summary strip above the notes list");
    NSArray *tree = [self nv_summaryContrarianAXTree];
    Check([tree indexOfObjectIdenticalTo:searchStatusField] == NSNotFound &&
        [tree indexOfObjectIdenticalTo:[searchStatusField cell]] == NSNotFound,
        @"the removed summary has no residual element in the window accessibility tree");
    NSUInteger residualSummaryValues = 0;
    for (id item in tree) if ([item respondsToSelector:@selector(accessibilityAttributeValue:)]) {
        for (NSString *attribute in @[NSAccessibilityValueAttribute, NSAccessibilityTitleAttribute,
                                      NSAccessibilityDescriptionAttribute, NSAccessibilityHelpAttribute]) {
            id value = [item accessibilityAttributeValue:attribute];
            if ([value isKindOfClass:[NSString class]] &&
                ([value containsString:@"results in"] || [value containsString:@"title matches first"])) residualSummaryValues++;
        }
    }
    Check(residualSummaryValues == 0, @"no exposed accessibility value or help repeats the removed count or ranking summary");
    NSLog(@"SUMMARY_AX descendants=%lu statusHidden=%d listHeight=%.1f parentHeight=%.1f",
        (unsigned long)[tree count], [searchStatusField isHidden], NSHeight([notesScrollView frame]), NSHeight([notesSubview bounds]));
}
- (void)nv_summaryContrarianKey:(unichar)character modifiers:(NSEventModifierFlags)modifiers {
    NSString *characters = [NSString stringWithCharacters:&character length:1];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers
        timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:[window windowNumber] context:nil
        characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:0];
    [notesTableView keyDown:event]; Pump();
}
- (NSUInteger)nv_summaryContrarianCountTitle:(NSString *)title {
    NSUInteger matches = 0;
    for (NoteObject *note in [[[NVApplicationController sharedController] library] allNotes])
        if ([titleOfNote(note) isEqual:title]) matches++;
    return matches;
}
- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *road = [MakeNote(library, @"Road map", @"road planning source") retain];
        MakeNote(library, @"Unrelated", @"nothing matching here");
        [prefsController setAutoCompleteSearches:NO sender:self];
        [window setContentSize:NSMakeSize(600, 440)]; Pump();
        [self searchForString:@"road" mode:@"fuzzy"]; [self nv_summaryContrarianAwait];
        NVBrowserSession *session = [self browserSession];
        Check([session resultCount] == 2 && [session distinctResultNoteCount] == 1 &&
            [session noteObjectAtFilteredIndex:0] == road && [session noteObjectAtFilteredIndex:1] == road,
            @"the fixture retains title and fuzzy occurrences of one note");
        NSString *negative = getenv("NV_SUMMARY_CONTRARIAN_NEGATIVE") ?
            [NSString stringWithUTF8String:getenv("NV_SUMMARY_CONTRARIAN_NEGATIVE")] : @"";
        if ([negative isEqual:@"visible-summary"]) {
            [searchStatusField setStringValue:@"2 results in 1 notes — title matches first"];
            [searchStatusField setHidden:NO];
        } else if ([negative isEqual:@"reserved-gap"]) {
            NSRect frame = [notesScrollView frame]; frame.size.height -= 24; [notesScrollView setFrame:frame];
        }
        [self nv_summaryContrarianCheckSurface];

        [notesTableView selectRowAndScroll:0];
        [window makeFirstResponder:notesTableView]; Pump();
        id editing = [self valueForKey:@"editingSession"];
        NSTextStorage *storage = [textView textStorage];
        NSString *titleKey = [[session rowKeyAtIndex:0] copy];
        NSString *fuzzyKey = [[session rowKeyAtIndex:1] copy];
        Check(![titleKey isEqual:fuzzyKey] && [[session matchKindAtIndex:0] isEqual:@"title"] &&
            [[session matchKindAtIndex:1] isEqual:@"fuzzy"], @"duplicate result rows retain distinct occurrence keys and native grouping");
        [self nv_summaryContrarianKey:NSDownArrowFunctionKey modifiers:0];
        Check([notesTableView primarySelectedRow] == 1 && [[self selectedSearchResultRowKey] isEqual:fuzzyKey],
            @"Down selects the fuzzy occurrence after removal of the summary strip");
        Check([self selectedNoteObject] == road && [self valueForKey:@"editingSession"] == editing &&
            [textView textStorage] == storage, @"keyboard movement between duplicate rows retains one source session");
        [self nv_summaryContrarianKey:NSUpArrowFunctionKey modifiers:0];
        Check([notesTableView primarySelectedRow] == 0 && [[self selectedSearchResultRowKey] isEqual:titleKey],
            @"Up returns to the title occurrence");
        [self nv_summaryContrarianKey:NSDownArrowFunctionKey modifiers:NSEventModifierFlagShift];
        Check([notesTableView numberOfSelectedRows] == 2 &&
            [[session notesAtIndexes:[notesTableView selectedRowIndexes]] isEqual:@[road]],
            @"Shift-Down selects both visible occurrences while resolving one note for document actions");
        [self nv_summaryContrarianCheckSurface];
        [titleKey release]; [fuzzyKey release];

        NSUInteger originalCount = [library totalNoteCount];
        NSString *query = @"absent summary create button fixture";
        [self searchForString:query mode:@"fuzzy"]; [self nv_summaryContrarianAwait];
        Check([session resultCount] == 0 && ![createNoteButton isHidden] && [createNoteButton isEnabled],
            @"zero results retain a visible enabled Create control");
        [self nv_summaryContrarianCheckSurface];
        NSArray *emptyTree = [self nv_summaryContrarianAXTree];
        Check([emptyTree indexOfObjectIdenticalTo:createNoteButton] != NSNotFound ||
            [emptyTree indexOfObjectIdenticalTo:[createNoteButton cell]] != NSNotFound,
            @"the zero-result Create control remains in the exposed accessibility tree");
        NSPoint center = NSMakePoint(NSMidX([createNoteButton bounds]), NSMidY([createNoteButton bounds]));
        NSPoint hitPoint = [createNoteButton convertPoint:center toView:[notesSubview superview]];
        NSView *hit = [notesSubview hitTest:hitPoint];
        Check(hit == createNoteButton || [hit isDescendantOf:createNoteButton],
            @"the expanded scroll view does not intercept the visible Create button hit region");
        [createNoteButton performClick:self]; [self nv_summaryContrarianAwait];
        Check([library totalNoteCount] == originalCount + 1 && [self nv_summaryContrarianCountTitle:query] == 1,
            @"the visible Create button creates exactly one note with the unmatched query as title");

        query = @"different absent return creation fixture";
        [self searchForString:query mode:@"fuzzy"]; [self nv_summaryContrarianAwait];
        Check([session resultCount] == 0 && [field currentEditor] != nil,
            @"Return fixture has an unmatched query in the actual search editor");
        [(id)[field currentEditor] doCommandBySelector:@selector(insertNewline:)]; [self nv_summaryContrarianAwait];
        Check([library totalNoteCount] == originalCount + 2 && [self nv_summaryContrarianCountTitle:query] == 1,
            @"Return creates exactly one note without the removed result summary");
        [self searchForString:@"" mode:@"fuzzy"]; [self nv_summaryContrarianAwait];
        [self nv_summaryContrarianCheckSurface];
        Check([createNoteButton isHidden] && [[[road contentString] string] isEqual:@"road planning source"],
            @"clearing search hides Create and leaves the original note source unchanged");
        [road release];
        NSLog(@"SEARCH_SUMMARY_CONTRARIAN_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) { NSLog(@"SEARCH_SUMMARY_CONTRARIAN_EXCEPTION %@", exception); exit(2); }
}
