- (void)nv_waitForCurrentSearch {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent], @"the New Note fixture has current search results");
}

- (void)nv_pressNewNoteWithTitle:(NSString *)title {
    NotationController *library = [[NVApplicationController sharedController] library];
    NSUInteger count = [library totalNoteCount];
    NoteObject *oldNote = [self selectedNoteObject];
    NSMenu *menu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
    NSMenuItem *item = [self nv_itemInMenu:menu action:@selector(newNote:)];
    [menu update];
    Check([item isEnabled] && [[item keyEquivalent] isEqual:@"n"] &&
        [item keyEquivalentModifierMask] == NSEventModifierFlagCommand,
        @"New Note is enabled with the Command-N key equivalent");
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
    Check([[NSApp mainMenu] performKeyEquivalent:event], @"the application menu handles Command-N");
    Pump();
    NoteObject *created = [[self selectedNoteObject] retain];
    Check(created && created != oldNote && [library totalNoteCount] == count + 1 &&
        [titleOfNote(created) isEqual:title],
        [NSString stringWithFormat:@"Command-N creates exactly one new note titled “%@”", title]);
    Check([[created contentString] length] == 0 && [[created sourceSyntaxIdentifier] isEqual:@"plain"] &&
        ![self isViewingNote], @"Command-N creates empty Plain Text source");
    Check([[field stringValue] length] == 0 && [[[self browserSession] searchString] length] == 0 &&
        [[self browserSession] searchResultsAreCurrent], @"Command-N clears the query and leaves current results");
    Check([prefsController showTitleInTopSection] ? [noteTitleField currentEditor] != nil : [window firstResponder] == textView,
        @"Command-N retains the configured title or source editing focus");
    for (NSUInteger attempt = 0; attempt < 4; attempt++) Pump();
    Check([self selectedNoteObject] == created && [library totalNoteCount] == count + 1,
        @"late search callbacks preserve the new note and create no extra note");
    [library removeNote:created]; [created release]; Pump();
}

- (void)nv_checkNewNoteWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    BOOL showTitle = [prefsController showTitleInTopSection];
    BOOL showTags = [prefsController showTagsInTopSection];
    BOOL showList = [prefsController showNotesList];
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
}
