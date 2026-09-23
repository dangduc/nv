- (void)nv_checkSearchPlacementWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
    NSMenuItem *placement = [self nv_itemInMenu:viewMenu action:@selector(toggleSearchInTitleBar:)];
    Check(placement != nil, @"View contains Search in Title Bar");
    [viewMenu update];
    Check(![prefsController searchInTitleBar] && [placement state] == NSControlStateValueOff,
        @"a new defaults domain places Search below the title bar");
    if (@available(macOS 11.0, *)) {
        [self searchForString:@"al"]; [self revealNote:alpha options:0]; Pump();
        [self nv_focusSearch];
        NSRect originalFrame = [window frame];
        for (NSNumber *titleBar in @[@YES, @NO]) {
            BOOL inTitleBar = [titleBar boolValue];
            NSTextView *editor = (id)[field currentEditor];
            [editor setSelectedRange:NSMakeRange(1, 1)];
            [self nv_sendMenuItem:placement];
            [viewMenu update];
            Check([placement state] == (inTitleBar ? NSControlStateValueOn : NSControlStateValueOff),
                @"the placement checkmark follows the preference");
            Check([field currentEditor] == editor && NSEqualRanges([editor selectedRange], NSMakeRange(1, 1)),
                @"changing Search placement retains field focus and text selection");
            Check([[field stringValue] isEqual:@"al"] && [[[self browserSession] searchString] isEqual:@"al"] &&
                [self selectedNoteObject] == alpha, @"changing Search placement preserves the query and note selection");
            [self nv_checkPeer:peer note:beta];
            for (NSWindow *browserWindow in @[window, [peer window]]) {
                Check([browserWindow toolbarStyle] == (inTitleBar ? NSWindowToolbarStyleUnifiedCompact : NSWindowToolbarStyleExpanded) &&
                    [browserWindow titleVisibility] == (inTitleBar ? NSWindowTitleHidden : NSWindowTitleVisible),
                    @"the placement change updates both browser windows");
            }
            for (NSNumber *width in @[@480, @780, @1200]) {
                NSRect frame = originalFrame; frame.size.width = [width doubleValue];
                [window setFrame:frame display:YES]; Pump();
                NSRect search = [field convertRect:[field bounds] toView:nil];
                NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
                NSRect close = [closeButton convertRect:[closeButton bounds] toView:nil];
                NSRect list = [notesScrollView convertRect:[notesScrollView bounds] toView:nil];
                Check(NSWidth(search) >= NSWidth(frame) - 130 && NSMaxX(search) >= NSWidth(frame) - 30,
                    @"Search fills the available width in both positions");
                Check(inTitleBar ? (NSMidY(search) >= NSMinY(close) && NSMidY(search) <= NSMaxY(close)) :
                    (NSMaxY(search) <= NSMinY(close) && NSMinY(search) >= NSMaxY(list)),
                    @"Search occupies the selected row without overlapping the notes list");
            }
            [window setFrame:originalFrame display:YES]; Pump();
            [self nv_captureViewControls:inTitleBar ? @"search-in-title-bar.png" : @"search-below-title-bar.png"];
            editor = (id)[field currentEditor];
            [editor setMarkedText:@"lp" selectedRange:NSMakeRange(2, 0) replacementRange:NSMakeRange(1, 1)];
            [self nv_sendMenuItem:placement]; [self nv_sendMenuItem:placement];
            Check([field currentEditor] == editor && [editor hasMarkedText] && [[editor string] isEqual:@"alp"] &&
                [[[self browserSession] searchString] isEqual:@"al"],
                @"changing Search placement preserves uncommitted input composition");
            [editor insertText:@"al" replacementRange:NSMakeRange(0, [[editor string] length])]; Pump();
            [self setDualFieldIsVisible:NO];
            [self nv_focusSearch];
            Check([window toolbarStyle] == (inTitleBar ? NSWindowToolbarStyleUnifiedCompact : NSWindowToolbarStyleExpanded),
                @"Search restores a hidden toolbar in the selected position");
            [self focusNoteBody];
            [self nv_sendMenuItem:placement]; [self nv_sendMenuItem:placement];
            Check([window firstResponder] == textView, @"changing Search placement does not steal body focus");
            [self nv_focusSearch];
            if (inTitleBar) {
                NVApplicationController *app = [NVApplicationController sharedController];
                [app newWindow:self]; Pump();
                AppController *created = [[app browserControllers] lastObject];
                Check([[created window] toolbarStyle] == NSWindowToolbarStyleUnifiedCompact,
                    @"a new browser uses the saved Search placement");
                [[created window] close]; Pump();
                [self nv_focusSearch];
            }
        }
    } else {
        Check(![placement isEnabled], @"older macOS keeps Search in its separate toolbar row");
    }
}
