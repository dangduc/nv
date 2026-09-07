- (void)nv_activate {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ((![NSApp isActive] || [NSApp keyWindow] != window || [NSApp mainWindow] != window) &&
        [deadline timeIntervalSinceNow] > 0) Pump();
    Check([NSApp isActive] && [NSApp keyWindow] == window && [NSApp mainWindow] == window &&
        [[NVApplicationController sharedController] activeBrowser] == self,
        @"native activation supplies the intended key window, main window, and command target");
}

- (NSMenuItem *)nv_menuItem:(SEL)action {
    NSMutableArray *menus = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
    for (NSUInteger i = 0; i < [menus count]; i++) {
        for (NSMenuItem *item in [menus[i] itemArray]) {
            if ([item action] == action) return item;
            if ([item submenu]) [menus addObject:[item submenu]];
        }
    }
    Check(NO, [NSString stringWithFormat:@"main menu contains %@", NSStringFromSelector(action)]);
    return nil;
}

- (void)nv_keyCommand:(SEL)action {
    [self nv_activate];
    NSMenuItem *item = [self nv_menuItem:action];
    [[item menu] update];
    Check([item isEnabled] && [[item keyEquivalent] length] > 0,
        [NSString stringWithFormat:@"%@ has an enabled key equivalent", NSStringFromSelector(action)]);
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:[item keyEquivalentModifierMask]
        timestamp:0 windowNumber:[window windowNumber] context:nil characters:[item keyEquivalent]
        charactersIgnoringModifiers:[item keyEquivalent] isARepeat:NO keyCode:0];
    Check([[NSApp mainMenu] performKeyEquivalent:event],
        [NSString stringWithFormat:@"AppKit dispatches key equivalent for %@", NSStringFromSelector(action)]);
    Pump();
}

- (void)nv_statesForSelectionCount:(NSUInteger)count {
    [self nv_activate];
    [self searchForString:@""];
    [notesTableView setAllowsMultipleSelection:YES];
    if (count) [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)] byExtendingSelection:NO];
    else [notesTableView deselectAll:self];
    [window makeFirstResponder:notesTableView]; Pump();
    Check([notesTableView numberOfSelectedRows] == count, @"selection fixture contains the requested number of rows");
    for (NSString *name in @[@"renameNote:", @"tagNote:", @"copyNoteLink:", @"exportNote:", @"deleteNote:", @"togglePreview:", @"newNote:"]) {
        NSMenuItem *item = [self nv_menuItem:NSSelectorFromString(name)];
        [[item menu] update];
        BOOL expected = [name isEqual:@"newNote:"] ||
            (([name isEqual:@"renameNote:"] || [name isEqual:@"copyNoteLink:"] || [name isEqual:@"togglePreview:"]) ? count == 1 : count > 0);
        NSLog(@"MENU_STATE selected=%lu action=%@ actual=%d expected=%d target=%@", (unsigned long)count, name, [item isEnabled], expected, [item target]);
        Check([item isEnabled] == expected, [NSString stringWithFormat:@"%@ state matches %lu selected rows", name, (unsigned long)count]);
    }
    [toolbar validateVisibleItems];
    for (NSToolbarItem *item in [toolbar items]) {
        if (![@[@"NewNote", @"Preview", @"More"] containsObject:[item itemIdentifier]]) continue;
        BOOL expected = [[item itemIdentifier] isEqual:@"NewNote"] ||
            ([[item itemIdentifier] isEqual:@"Preview"] ? count == 1 : count > 0);
        NSLog(@"TOOLBAR_STATE selected=%lu id=%@ actual=%d expected=%d", (unsigned long)count, [item itemIdentifier], [item isEnabled], expected);
        Check([item isEnabled] == expected, @"actual toolbar enabled state matches the selection");
    }
    Check([noteTitleField isEnabled] == (count == 1) && [noteTagsField isEnabled] == (count == 1),
        @"metadata fields enable only for a single note");
}

- (void)nv_editMetadata:(NSTextField *)control value:(NSString *)value command:(SEL)command {
    [self nv_activate];
    [control selectText:self];
    NSTextView *editor = (id)[control currentEditor];
    Check(editor != nil, @"metadata edit uses the native field editor");
    [editor insertText:value replacementRange:NSMakeRange(0, [[editor string] length])];
    [editor doCommandBySelector:command]; Pump();
    NSLog(@"METADATA value=%@ command=%@ title=%@ tags=%@ selected=%@ first=%@ body=%@ titleEditor=%@ tagsEditor=%@ key=%d main=%d",
        value, NSStringFromSelector(command), titleOfNote(currentNote), labelsOfNote(currentNote), currentNote,
        [window firstResponder], textView, [noteTitleField currentEditor], [noteTagsField currentEditor], [window isKeyWindow], [window isMainWindow]);
    Check([window firstResponder] == textView, @"metadata command returns focus to the note body");
}

- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha body") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"beta body") retain];
        [alpha setLabelString:@"original"]; Pump();
        for (NSUInteger count = 0; count <= 2; count++) [self nv_statesForSelectionCount:count];

        [self revealNote:alpha options:0]; Pump();
        [[alpha undoManager] removeAllActions];
        [self nv_editMetadata:noteTitleField value:@"Discard title" command:@selector(cancelOperation:)];
        [self nv_editMetadata:noteTagsField value:@"discarded, tags" command:@selector(cancelOperation:)];
        Check([titleOfNote(alpha) isEqual:@"Alpha"] && [labelsOfNote(alpha) isEqual:@"original"] && ![[alpha undoManager] canUndo],
            @"Escape preserves metadata and creates no note undo entry");
        [self nv_editMetadata:noteTitleField value:@"  \t  " command:@selector(insertNewline:)];
        Check([titleOfNote(alpha) isEqual:@"Alpha"] && ![[alpha undoManager] canUndo],
            @"Return on whitespace title preserves the title and creates no undo entry");
        [self nv_editMetadata:noteTagsField value:@"   " command:@selector(insertNewline:)];
        Check([labelsOfNote(alpha) isEqual:@""], @"Return on whitespace tags clears existing tags");
        [self nv_keyCommand:@selector(undo:)];
        Check([labelsOfNote(alpha) isEqual:@"original"], @"actual Undo key equivalent restores cleared tags");

        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"routing fixture contains two distinct browsers");
        [peer nv_activate];
        [peer searchForString:@"Beta"]; [peer revealNote:beta options:0]; Pump();
        [self nv_activate];
        [self searchForString:@"Alpha"]; [self revealNote:alpha options:0]; Pump();
        NSUInteger index = [[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
        Check(index != NSNotFound, @"origin initially contains Search");
        [window makeFirstResponder:textView];
        [toolbar removeItemAtIndex:index]; Pump();
        [peer nv_keyCommand:@selector(bringFocusToControlField:)];
        Check([[(NSSearchField *)[peer valueForKey:@"field"] currentEditor] window] == [peer window],
            @"Search key equivalent focuses the current browser");
        NSLog(@"PEER_SEARCH originPresent=%d originEditor=%@ originFirst=%@ peerFirst=%@ key=%@ main=%@",
            [[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"], [field currentEditor],
            [window firstResponder], [[peer window] firstResponder], [NSApp keyWindow], [NSApp mainWindow]);
        Check(![field currentEditor] && [NSApp keyWindow] == [peer window] && [NSApp mainWindow] == [peer window],
            @"Search in the peer preserves peer key and main windows without editing the origin query");
        // AppKit shares configuration among toolbars with the same identifier.
        // Remove the item again so the next command must restore it itself.
        index = [[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
        if (index != NSNotFound) [toolbar removeItemAtIndex:index];
        Pump();
        Check(![[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"],
            @"origin Search is absent immediately before its own key command");
        [self nv_keyCommand:@selector(bringFocusToControlField:)];
        Check([field currentEditor] != nil && [field window] == window &&
            [[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"],
            @"Search key equivalent restores the removed item after returning to the origin");
        Check([peer selectedNoteObject] == beta && [[[peer browserSession] searchString] isEqual:@"Beta"] &&
            [self selectedNoteObject] == alpha && [[[self browserSession] searchString] isEqual:@"Alpha"],
            @"both Search key commands preserve each browser query and selection");

        [peer nv_keyCommand:@selector(newNote:)];
        Check([library totalNoteCount] == 3 && [peer selectedNoteObject] != alpha && [peer selectedNoteObject] != beta &&
            [peer selectedNoteObject] != nil, @"New Note key equivalent creates one note in the active peer");
        Check([[peer valueForKey:@"noteTitleField"] currentEditor] != nil &&
            [[[peer browserSession] searchString] isEqual:@""], @"New Note clears the peer query and focuses its title");
        Check([self selectedNoteObject] == alpha && [[[self browserSession] searchString] isEqual:@"Alpha"],
            @"New Note preserves the inactive origin query and selection");
        [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"ROUND 2 TORVALDS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
