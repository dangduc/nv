- (void)nv_sendFocusKey:(unichar)character keyCode:(unsigned short)keyCode modifiers:(NSEventModifierFlags)modifiers {
    NSString *characters = [NSString stringWithCharacters:&character length:1];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:modifiers timestamp:[[NSProcessInfo processInfo] systemUptime] windowNumber:[window windowNumber]
        context:nil characters:characters charactersIgnoringModifiers:characters
        isARepeat:NO keyCode:keyCode];
    // Dequeue through AppKit so handlers that forward window.currentEvent see this key.
    [NSApp postEvent:event atStart:YES];
    NSEvent *queued = [NSApp nextEventMatchingMask:NSEventMaskKeyDown untilDate:[NSDate dateWithTimeIntervalSinceNow:1]
        inMode:NSDefaultRunLoopMode dequeue:YES];
    Check(queued && [queued keyCode] == keyCode && [queued windowNumber] == [window windowNumber] &&
        [[queued characters] isEqual:characters], @"AppKit dequeues the posted navigation key");
    [NSApp sendEvent:queued]; Pump();
}

- (void)nv_pressShiftTab {
    [self nv_sendFocusKey:NSBackTabCharacter keyCode:kVK_Tab modifiers:NSEventModifierFlagShift];
}

- (void)nv_checkShiftTabWithNote:(NoteObject *)note {
    [self revealNote:note options:0]; [self nv_focusSearch];
    NSString *query = [[[self browserSession] searchString] copy];
    NSAttributedString *source = [[note contentString] copy];
    [textView setSelectedRange:NSMakeRange(2, 3)];
    for (NSUInteger cycle = 0; cycle < 3; cycle++) {
        [self nv_pressShiftTab];
        Check([window firstResponder] == textView, @"Shift-Tab moves from Search to the open note body");
        Check(NSEqualRanges([textView selectedRange], NSMakeRange(2, 3)), @"Shift-Tab preserves the body text selection");
        [self nv_pressShiftTab];
        Check([self searchFieldHasFocus], @"Shift-Tab returns from the body to Search without visiting the list or metadata");
    }
    [window makeFirstResponder:notesTableView];
    Check([window firstResponder] == notesTableView, @"Shift-Tab fixture starts in the notes list");
    [self nv_pressShiftTab];
    Check([window firstResponder] == textView, @"Shift-Tab moves from the notes list to the open body");
    [self nv_pressShiftTab];
    Check([self searchFieldHasFocus], @"the list entry path joins the body and Search cycle");
    [self nv_pressShiftTab];
    Check([window firstResponder] == textView, @"subsequent Shift-Tab skips the notes list");
    Check([self selectedNoteObject] == note && [[[self browserSession] searchString] isEqual:query] &&
        [[field stringValue] isEqual:query] && [[note contentString] isEqual:source],
        @"Shift-Tab preserves the note, query, and source contents");
    [self setViewingNote:YES]; [self nv_focusSearch];
    [self nv_pressShiftTab];
    NSView *responder = (id)[window firstResponder];
    Check([responder isKindOfClass:[NSView class]] && [responder isDescendantOf:[previewController webView]],
        @"Search Shift-Tab focuses the displayed Preview body");
    [self nv_pressShiftTab];
    for (NSUInteger attempt = 0; attempt < 4 && ![self searchFieldHasFocus]; attempt++) Pump();
    Check([self searchFieldHasFocus], @"Preview Shift-Tab returns to Search");
    [self setViewingNote:NO];
    [query release]; [source release];
}

- (void)nv_checkSearchArrows {
    Check([notesTableView numberOfRows] == 2, @"arrow fixture has two matching rows");
    [notesTableView selectRowAndScroll:0]; [self nv_focusSearch];
    NSString *query = [[[self browserSession] searchString] copy];
    NSText *editor = [field currentEditor];
    for (NSArray *step in @[@[@(NSDownArrowFunctionKey), @(kVK_DownArrow), @1],
                            @[@(NSUpArrowFunctionKey), @(kVK_UpArrow), @0],
                            @[@(NSUpArrowFunctionKey), @(kVK_UpArrow), @0],
                            @[@(NSDownArrowFunctionKey), @(kVK_DownArrow), @1],
                            @[@(NSDownArrowFunctionKey), @(kVK_DownArrow), @1]]) {
        [self nv_sendFocusKey:[step[0] unsignedShortValue] keyCode:[step[1] unsignedShortValue]
            modifiers:NSEventModifierFlagFunction | NSEventModifierFlagNumericPad];
        NSInteger row = [step[2] integerValue];
        Check([notesTableView primarySelectedRow] == row && [notesTableView numberOfSelectedRows] == 1 &&
            [self selectedNoteObject] == [[self browserSession] noteObjectAtFilteredIndex:row],
            @"Search arrow keys select the adjacent row and stop at list boundaries");
        Check([self searchFieldHasFocus] && [field currentEditor] == editor,
            @"Search arrow keys preserve the focused Search editor");
        Check([[[self browserSession] searchString] isEqual:query] && [[field stringValue] isEqual:query],
            @"Search arrow keys preserve the query");
    }
    [query release];
}

- (void)nv_checkKeyboardFocusWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta probe:(NSString *)probe {
    BOOL shiftTab = ![probe isEqual:@"arrows"], arrows = ![probe isEqual:@"shift-tab"];
    BOOL oldPlacement = [prefsController searchInTitleBar];
    BOOL oldTitle = [prefsController showTitleInTopSection], oldTags = [prefsController showTagsInTopSection];
    BOOL oldControls = [prefsController showBodyControlsInTopSection];
    BOOL oldEmpty = [notesTableView allowsEmptySelection];
    [notesTableView setAllowsEmptySelection:YES];
    [prefsController setShowTitleInTopSection:YES sender:nil];
    [prefsController setShowTagsInTopSection:YES sender:nil];
    [prefsController setShowBodyControlsInTopSection:YES sender:nil];
    [self setViewingNote:NO]; [self nv_activateBrowser];
    for (NSNumber *placement in @[@NO, @YES]) {
        [prefsController setSearchInTitleBar:[placement boolValue] sender:nil];
        for (NSNumber *side in @[@NO, @YES]) {
            [self setHorizontalLayout:[side boolValue]];
            for (NSString *mode in @[@"exact", @"fuzzy"]) {
                NSLog(@"FOCUS_MATRIX titleBar=%@ side=%@ mode=%@", placement, side, mode);
                [self searchForString:@"body" mode:mode]; [self nv_waitForCurrentSearch];
                if (arrows) [self nv_checkSearchArrows];
                if (shiftTab) {
                    [self nv_checkShiftTabWithNote:alpha];
                    for (NSString *query in @[@"body", @"", @"No matching note"]) {
                        [self searchForString:query mode:mode]; [self nv_waitForCurrentSearch];
                        [notesTableView deselectAll:self]; [self nv_focusSearch];
                        Check([self selectedNoteObject] == nil, @"Shift-Tab fixture has no open note");
                        for (NSUInteger cycle = 0; cycle < 2; cycle++) {
                            [self nv_pressShiftTab];
                            Check([self searchFieldHasFocus] && ![self selectedNoteObject],
                                @"Shift-Tab stays in Search when no note is selected");
                            Check([[field stringValue] isEqual:query] && [[[self browserSession] searchString] isEqual:query],
                                @"Shift-Tab without an open note preserves the query");
                        }
                        [window makeFirstResponder:notesTableView]; [self nv_pressShiftTab];
                        Check([self searchFieldHasFocus] && ![self selectedNoteObject],
                            @"Shift-Tab from an unselected list skips the empty body");
                    }
                }
                [self nv_checkPeer:peer note:beta];
            }
        }
    }
    [self setHorizontalLayout:NO];
    if (shiftTab) {
        [peer nv_activateBrowser]; [peer nv_checkShiftTabWithNote:beta];
        [self nv_activateBrowser];
        [self searchForString:@"Alpha" mode:@"exact"]; [self revealNote:alpha options:0];
        [self focusNoteBody]; [self setDualFieldIsVisible:NO];
        [self nv_pressShiftTab];
        Check([self searchFieldHasFocus] && [self dualFieldIsVisible], @"body Shift-Tab restores a hidden Search bar");
    }
    [prefsController setSearchInTitleBar:oldPlacement sender:nil];
    [prefsController setShowTitleInTopSection:oldTitle sender:nil];
    [prefsController setShowTagsInTopSection:oldTags sender:nil];
    [prefsController setShowBodyControlsInTopSection:oldControls sender:nil];
    [notesTableView setAllowsEmptySelection:oldEmpty];
    [self searchForString:@"al" mode:@"exact"]; [self revealNote:alpha options:0];
}
