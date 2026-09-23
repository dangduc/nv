- (void)nv_checkSideLayoutWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    [self nv_activateBrowser];
    NSRect originalFrame = [window frame];
    NSRect frame = originalFrame; frame.size = NSMakeSize(900, 650);
    [window setFrame:frame display:YES]; Pump();
    [self searchForString:@"alpha"]; [self revealNote:alpha options:0]; Pump();
    [self setNotesListHeight:150];
    CGFloat stackedHeight = [self notesListHeight];
    CGFloat peerHeight = [peer notesListHeight];
    NSArray *columns = [[[notesTableView tableColumns] valueForKey:@"identifier"] copy];
    NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
    NSMenuItem *layout = [self nv_itemInMenu:viewMenu action:@selector(switchViewLayout:)];
    Check(layout && [[layout title] isEqual:@"Notes List on Side"], @"View exposes the restored side layout command");
    Check([[layout keyEquivalent] isEqual:@"l"] && [layout keyEquivalentModifierMask] ==
        (NSEventModifierFlagCommand | NSEventModifierFlagOption), @"side layout retains Command-Option-L");
    [self nv_focusSearch];
    NSTextView *searchEditor = (id)[field currentEditor];
    [searchEditor setSelectedRange:NSMakeRange(1, 2)];
    [self nv_sendMenuItem:layout]; [viewMenu update];
    Check([self horizontalLayout] && [splitView isVertical] && [layout state] == NSControlStateValueOn,
        @"the native View command enables and checks side layout");
    Check([field currentEditor] == searchEditor && NSEqualRanges([searchEditor selectedRange], NSMakeRange(1, 2)),
        @"layout changes preserve Search focus and text selection");
    Check([self selectedNoteObject] == alpha && [[[self browserSession] searchString] isEqual:@"alpha"],
        @"layout changes preserve the selected note and search query");
    Check(![peer horizontalLayout] && fabs([peer notesListHeight] - peerHeight) < 1,
        @"the side layout belongs only to the active browser");
    [self nv_checkPeer:peer note:beta];
    Check([[notesTableView tableColumns] count] == 1 && ![notesTableView headerView] && [notesTableView rowHeight] > 30,
        @"side view uses multiline note rows without column headers");
    [self setNotesListHeight:280]; Pump();
    NSRect list = [notesSubview convertRect:[notesSubview bounds] toView:nil];
    NSRect body = [splitSubview convertRect:[splitSubview bounds] toView:nil];
    Check(NSMaxX(list) <= NSMinX(body) && fabs(NSHeight(list) - NSHeight(body)) < 2 && NSWidth(body) >= 360,
        @"the list occupies the left pane beside a usable editor");
    NVApplicationController *app = [NVApplicationController sharedController];
    [app newWindow:self]; Pump();
    AppController *created = [[app browserControllers] lastObject];
    [created revealNote:alpha options:0]; [[created window] display]; Pump();
    NotesTableView *createdTable = [created valueForKey:@"notesTableView"];
    Check(![created horizontalLayout] && [createdTable rowHeight] < 30 && [createdTable headerView] != nil,
        @"a new window starts stacked even when the active browser has a side list");
    [[created window] close]; [self nv_activateBrowser];

    [self searchForString:@"alpha" mode:@"fuzzy"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    NVBrowserSession *session = [self browserSession];
    Check([session resultCount] == 2, @"side fuzzy search retains separate title and body results");
    for (NSUInteger row = 0; row < [session resultCount]; row++) {
        __block BOOL highlighted = NO;
        deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        do {
            NSAttributedString *preview = [session previewForRow:row inTable:notesTableView];
            [preview enumerateAttribute:NSBackgroundColorAttributeName inRange:NSMakeRange(0, [preview length])
                options:0 usingBlock:^(id color, NSRange range, BOOL *stop) { if (color) highlighted = YES; }];
            if (!highlighted) Pump();
        } while (!highlighted && [deadline timeIntervalSinceNow] > 0);
        Check(highlighted, @"each side-view fuzzy result contains its match highlight");
        [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; Pump();
        Check([self selectedNoteObject] == alpha, @"each fuzzy occurrence selects its owning note in side view");
    }
    [self nv_captureViewControls:@"notes-list-side.png"];
    [prefsController setSearchInTitleBar:YES sender:nil]; Pump();
    [self nv_captureViewControls:@"notes-list-side-title-bar.png"];
    [prefsController setSearchInTitleBar:NO sender:nil];

    [self nv_focusSearch];
    searchEditor = (id)[field currentEditor];
    [searchEditor setMarkedText:@"alphabet" selectedRange:NSMakeRange(8, 0) replacementRange:NSMakeRange(0, 5)];
    [self nv_sendMenuItem:layout]; [self nv_sendMenuItem:layout];
    Check([field currentEditor] == searchEditor && [searchEditor hasMarkedText] &&
        [[searchEditor string] isEqual:@"alphabet"] && [[session searchString] isEqual:@"alpha"],
        @"layout changes preserve uncommitted Search composition");
    [searchEditor insertText:@"alpha" replacementRange:NSMakeRange(0, 8)]; Pump();

    for (NSNumber *width in @[@640, @1200, @900]) {
        frame.size.width = [width doubleValue]; [window setFrame:frame display:YES]; Pump();
        body = [splitSubview convertRect:[splitSubview bounds] toView:nil];
        list = [notesSubview convertRect:[notesSubview bounds] toView:nil];
        Check(NSWidth(list) >= 179 && NSWidth(body) >= 359 && NSMaxX(list) <= NSMinX(body),
            @"resizing the side layout leaves both panes usable");
    }
    [self setNotesListHeight:280];

    [self focusNoteBody];
    [textView setSelectedRange:NSMakeRange(2, 3)];
    [self nv_sendMenuItem:layout]; [self nv_sendMenuItem:layout];
    Check([window firstResponder] == textView && NSEqualRanges([textView selectedRange], NSMakeRange(2, 3)),
        @"layout changes preserve body focus and selection");
    [self setViewingNote:YES]; Pump();
    [self nv_sendMenuItem:layout]; [self nv_sendMenuItem:layout];
    Check([self isViewingNote] && [self selectedNoteObject] == alpha,
        @"layout changes preserve the selected read-only preview");
    [self setViewingNote:NO];

    [prefsController setShowNotesList:NO sender:nil]; Pump();
    NSSplitViewItem *listItem = [[browserSplitController splitViewItems] firstObject];
    NSRect hiddenFrame = [window frame];
    [self nv_sendMenuItem:layout]; [self nv_sendMenuItem:layout];
    Check([listItem isCollapsed] && NSEqualRects([window frame], hiddenFrame),
        @"switching layout keeps a hidden list collapsed within the window");
    [prefsController setShowNotesList:YES sender:nil]; Pump();
    Check(fabs([self notesListHeight] - 280) < 2, @"showing the side list restores its previous width");
    [self nv_sendMenuItem:layout]; [viewMenu update];
    Check(![self horizontalLayout] && [layout state] == NSControlStateValueOff && fabs([self notesListHeight] - stackedHeight) < 2,
        @"returning to stacked view restores its independent divider height");
    Check([[[notesTableView tableColumns] valueForKey:@"identifier"] isEqual:columns],
        @"returning to stacked view restores the visible table columns");
    [columns release];
    [window setFrame:originalFrame display:YES];
    [self searchForString:@"al" mode:@"exact"]; [self revealNote:alpha options:0]; Pump();
}
