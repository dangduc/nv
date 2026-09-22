- (void)nv_waitForCurrentSearch {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent], @"the New Note fixture has current search results");
}

- (void)nv_pressNewNoteWithTitle:(NSString *)title keyCode:(unsigned short)keyCode {
    NotationController *library = [[NVApplicationController sharedController] library];
    NSUInteger count = [library totalNoteCount];
    NoteObject *oldNote = [self selectedNoteObject];
    NSString *characters = keyCode == kVK_ANSI_N ? @"n" : (keyCode == kVK_Return ? @"\r" : @"\003");
    NSUInteger modifiers = NSEventModifierFlagCommand | (keyCode == kVK_ANSI_KeypadEnter ? NSEventModifierFlagNumericPad : 0);
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:modifiers timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:keyCode];
    if (keyCode == kVK_ANSI_N) {
        NSMenu *menu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
        NSMenuItem *item = [self nv_itemInMenu:menu action:@selector(newNote:)];
        [menu update];
        Check([item isEnabled] && [[item keyEquivalent] isEqual:@"n"] &&
            [item keyEquivalentModifierMask] == NSEventModifierFlagCommand,
            @"New Note is enabled with the Command-N key equivalent");
        Check([[NSApp mainMenu] performKeyEquivalent:event], @"the application menu handles Command-N");
    } else {
        // Exercise AppKit routing from the application through the focused search control.
        [NSApp sendEvent:event];
    }
    Pump();
    NoteObject *created = [[self selectedNoteObject] retain];
    Check(created && created != oldNote && [library totalNoteCount] == count + 1 &&
        [titleOfNote(created) isEqual:title],
        [NSString stringWithFormat:@"New Note creates exactly one new note titled “%@”", title]);
    Check([[created contentString] length] == 0 && [[created sourceSyntaxIdentifier] isEqual:@"plain"] &&
        ![self isViewingNote], @"New Note creates empty Plain Text source");
    Check([[field stringValue] length] == 0 && [[[self browserSession] searchString] length] == 0 &&
        [[self browserSession] searchResultsAreCurrent], @"New Note clears the query and leaves current results");
    Check([prefsController showTitleInTopSection] ? [noteTitleField currentEditor] != nil : [window firstResponder] == textView,
        @"New Note retains the configured title or source editing focus");
    NSInteger createdRow = [notesTableView primarySelectedRow];
    Check(createdRow >= 0 && NSContainsRect([notesTableView visibleRect], [notesTableView rectOfRow:createdRow]),
        @"New Note scrolls the created note fully into the notes list viewport");
    for (NSUInteger attempt = 0; attempt < 4; attempt++) Pump();
    Check([self selectedNoteObject] == created && [library totalNoteCount] == count + 1,
        @"late search callbacks preserve the new note and create no extra note");
    createdRow = [notesTableView primarySelectedRow];
    Check(createdRow >= 0 && NSContainsRect([notesTableView visibleRect], [notesTableView rectOfRow:createdRow]),
        @"post-creation list refreshes keep the created note in view");
    [library removeNote:created]; [created release]; Pump();
}

- (void)nv_pressNewNoteWithTitle:(NSString *)title {
    [self nv_pressNewNoteWithTitle:title keyCode:kVK_ANSI_N];
}

- (void)nv_sendReturnWithModifiers:(NSUInteger)modifiers {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:modifiers timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:kVK_Return];
    [NSApp sendEvent:event]; Pump();
}

- (void)nv_checkCommandReturnWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    NotationController *library = [[NVApplicationController sharedController] library];
    BOOL showTitle = [prefsController showTitleInTopSection];
    BOOL showTags = [prefsController showTagsInTopSection];
    [prefsController setShowTitleInTopSection:NO sender:nil];
    [self nv_activateBrowser];
    for (NSString *mode in @[@"exact", @"fuzzy"]) {
        [self searchForString:@"Alpha" mode:mode]; [self nv_waitForCurrentSearch];
        [self revealNote:alpha options:0];
        NSUInteger count = [library totalNoteCount];
        [self nv_sendReturnWithModifiers:0];
        Check([self selectedNoteObject] == alpha && [library totalNoteCount] == count &&
            [window firstResponder] == textView, @"plain Return opens the matching note without creating another note");
        [self nv_focusSearch];
        [self nv_pressNewNoteWithTitle:@"Alpha" keyCode:kVK_Return];
    }

    [self searchForString:@"Pending Command Return" mode:@"fuzzy"];
    Check([[self browserSession] searchPending] && [self searchFieldHasFocus],
        @"Command-Return starts with a pending fuzzy request");
    [self fieldAction:self];
    [self nv_pressNewNoteWithTitle:@"Pending Command Return" keyCode:kVK_Return];

    [self searchForString:@"previous query" mode:@"exact"];
    [(NSTextView *)[field currentEditor] setString:@"Live search text 📝"];
    [self nv_pressNewNoteWithTitle:@"Live search text 📝" keyCode:kVK_Return];
    [self searchForString:@"Keypad Enter" mode:@"fuzzy"]; [self nv_waitForCurrentSearch];
    [self nv_pressNewNoteWithTitle:@"Keypad Enter" keyCode:kVK_ANSI_KeypadEnter];
    [self searchForString:@"" mode:@"exact"];
    [self nv_pressNewNoteWithTitle:NSLocalizedString(@"Untitled Note", @"Title of a nameless note") keyCode:kVK_Return];

    [prefsController setShowTitleInTopSection:YES sender:nil];
    [prefsController setShowTagsInTopSection:YES sender:nil];
    for (NSString *focus in @[@"body", @"title", @"tags", @"list"]) {
        [self searchForString:@"Alpha" mode:@"exact"]; [self revealNote:alpha options:0];
        if ([focus isEqual:@"title"]) [self renameNote:self];
        else if ([focus isEqual:@"tags"]) [self tagNote:self];
        else [window makeFirstResponder:[focus isEqual:@"body"] ? (NSResponder *)textView : notesTableView];
        Check(![self searchFieldHasFocus], @"Command-Return scope fixture has focus outside Search");
        NSUInteger count = [library totalNoteCount];
        [self nv_sendReturnWithModifiers:NSEventModifierFlagCommand];
        Check([library totalNoteCount] == count,
            [NSString stringWithFormat:@"Command-Return in %@ does not create a note", focus]);
    }

    [self searchForString:@"Alpha" mode:@"exact"]; [self revealNote:alpha options:0];
    [peer nv_activateBrowser];
    [peer searchForString:@"Beta" mode:@"exact"]; [peer revealNote:beta options:0];
    [peer nv_pressNewNoteWithTitle:@"Beta" keyCode:kVK_Return];
    Check([self selectedNoteObject] == alpha && [[field stringValue] isEqual:@"Alpha"],
        @"Command-Return uses the focused browser and preserves the other browser");
    [peer searchForString:@"Beta" mode:@"exact"]; [peer revealNote:beta options:0];
    [self nv_activateBrowser];
    [prefsController setShowTitleInTopSection:showTitle sender:nil];
    [prefsController setShowTagsInTopSection:showTags sender:nil];
}

- (void)nv_checkNewNoteWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    BOOL showTitle = [prefsController showTitleInTopSection];
    BOOL showTags = [prefsController showTagsInTopSection];
    BOOL showList = [prefsController showNotesList];
    NoteAttributeColumn *oldSort = [[[self browserSession] sortColumn] retain];
    BOOL oldReverse = [[self browserSession] reverseSorted];
    NSMutableArray *fillerNotes = [NSMutableArray array];
    for (NSUInteger index = 0; index < 40; index++) {
        NoteObject *filler = MakeNote([[NVApplicationController sharedController] library],
            [NSString stringWithFormat:@"Scroll fixture %02lu", (unsigned long)index], @"filler");
        [fillerNotes addObject:filler];
    }
    [[self browserSession] setSortColumn:[notesTableView noteAttributeColumnForIdentifier:NoteDateModifiedColumnString]
        reversed:YES];
    [self searchForString:@"" mode:@"exact"]; Pump();
    Check([notesTableView numberOfRows] > (NSInteger)[notesTableView rowsInRect:[notesTableView visibleRect]].length,
        @"the New Note visibility fixture spans multiple list viewports");
    [prefsController setShowTitleInTopSection:NO sender:nil];
    [self nv_activateBrowser];
    for (NSString *mode in @[@"exact", @"fuzzy"]) {
        [self searchForString:@"Alpha" mode:mode]; [self nv_waitForCurrentSearch];
        [self revealNote:alpha options:0];
        Check([self searchFieldHasFocus] && [self selectedNoteObject] == alpha,
            @"a focused query can already match the selected note");
        [self nv_pressNewNoteWithTitle:@"Alpha"];
    }
    [self searchForString:@"" mode:@"exact"];
    Check([self searchFieldHasFocus], @"the empty search field has keyboard focus");
    [self nv_pressNewNoteWithTitle:NSLocalizedString(@"Untitled Note", @"Title of a nameless note")];

    [self searchForString:@"previous query" mode:@"exact"];
    NSTextView *editor = (id)[field currentEditor];
    [editor setString:@"Live search text 📝"];
    Check([self searchFieldHasFocus] && ![[[self browserSession] searchString] isEqual:[editor string]],
        @"the field editor contains newer text than the submitted search");
    [self nv_pressNewNoteWithTitle:@"Live search text 📝"];

    [self searchForString:@"Pending new note" mode:@"fuzzy"];
    Check([[self browserSession] searchPending] && [self searchFieldHasFocus],
        @"Command-N starts while the fuzzy request is pending");
    [self fieldAction:self];
    [self nv_pressNewNoteWithTitle:@"Pending new note"];

    // Keep an existing selection while marked input suspends search publication.
    [self searchForString:@"Alpha" mode:@"fuzzy"]; [self nv_waitForCurrentSearch];
    [self revealNote:alpha options:0];
    editor = (id)[field currentEditor];
    [editor setMarkedText:@"日本語の新しいノート" selectedRange:NSMakeRange(10, 0)
        replacementRange:NSMakeRange(0, [[editor string] length])];
    // Programmatic marking does not send the control notification from native input.
    [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification
        object:field userInfo:@{@"NSFieldEditor": editor}]];
    Check([editor hasMarkedText] && [self selectedNoteObject] == alpha &&
        ![[self browserSession] searchResultsAreCurrent], @"marked search input suspends results with an existing selection");
    [self nv_pressNewNoteWithTitle:@"日本語の新しいノート"];

    [prefsController setShowTitleInTopSection:YES sender:nil];
    [prefsController setShowTagsInTopSection:YES sender:nil];
    [prefsController setShowNotesList:YES sender:nil];
    for (NSString *focus in @[@"body", @"title", @"tags", @"list"]) {
        [self searchForString:@"Alpha" mode:@"exact"]; [self revealNote:alpha options:0];
        if ([focus isEqual:@"title"]) [self renameNote:self];
        else if ([focus isEqual:@"tags"]) [self tagNote:self];
        else [window makeFirstResponder:[focus isEqual:@"body"] ? (NSResponder *)textView : notesTableView];
        Check(![self searchFieldHasFocus] && [[field stringValue] isEqual:@"Alpha"],
            [NSString stringWithFormat:@"the %@ has focus while Search retains text", focus]);
        [self nv_pressNewNoteWithTitle:NSLocalizedString(@"Untitled Note", @"Title of a nameless note")];
    }

    [self searchForString:@"Alpha" mode:@"exact"]; [self revealNote:alpha options:0];
    [peer nv_activateBrowser];
    [peer searchForString:@"Beta" mode:@"exact"]; [peer revealNote:beta options:0];
    Check(![self searchFieldHasFocus] && [peer searchFieldHasFocus],
        @"only the key browser owns focused search input");
    [peer nv_pressNewNoteWithTitle:@"Beta"];
    Check([self selectedNoteObject] == alpha && [[field stringValue] isEqual:@"Alpha"] &&
        [titleOfNote(alpha) isEqual:@"Alpha"] && [titleOfNote(beta) isEqual:@"Beta"],
        @"peer Command-N preserves the other browser and both existing notes");
    [peer searchForString:@"Beta" mode:@"exact"]; [peer revealNote:beta options:0];
    [self nv_activateBrowser];
    [self searchForString:@"" mode:@"exact"]; [self revealNote:alpha options:0];
    [prefsController setShowTitleInTopSection:showTitle sender:nil];
    [prefsController setShowTagsInTopSection:showTags sender:nil];
    [prefsController setShowNotesList:showList sender:nil];
    [[[NVApplicationController sharedController] library] removeNotes:fillerNotes]; Pump();
    [[self browserSession] setSortColumn:oldSort reversed:oldReverse];
    [oldSort release];
}
