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
    for (NSUInteger i = 0; i < 4; i++) Pump();
}

- (BOOL)nv_hasSearchItem {
    return [[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"];
}

- (void)nv_removeAndHideSearch {
    [window makeFirstResponder:notesTableView];
    NSUInteger index = [[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
    if (index != NSNotFound) [toolbar removeItemAtIndex:index];
    [toolbar setVisible:NO];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    Check(![self nv_hasSearchItem] && ![toolbar isVisible], @"Search is removed and the toolbar is hidden");
}

- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NSString *phase = [NSString stringWithUTF8String:getenv("NV_REVIEW_PHASE") ?: ""];
        [self nv_activate];
        if ([phase isEqual:@"1"]) {
            Check([library totalNoteCount] == 0, @"first launch starts with an empty temporary library");
            NoteObject *note = [MakeNote(library, @"Alpha", @"anchor body survives relaunch") retain];
            [self searchForString:@"anchor"]; [self revealNote:note options:0]; Pump();
            [window setContentSize:[window contentMinSize]];
            for (NSUInteger i = 0; i < 4; i++) Pump();
            NSLog(@"MINIMUM_SIZE actual=%@ minimum=%@", NSStringFromSize([[window contentView] frame].size), NSStringFromSize([window contentMinSize]));
            Check(fabs(NSWidth([[window contentView] frame]) - [window contentMinSize].width) < 1,
                @"pending edit fixture uses the minimum window content width");
            [self nv_removeAndHideSearch];
            [[note undoManager] removeAllActions];
            [self nv_activate];
            [noteTitleField selectText:self];
            NSTextView *editor = (id)[noteTitleField currentEditor];
            Check(editor != nil, @"pending title edit uses the real field editor");
            [editor insertText:@"Recovered Alpha" replacementRange:NSMakeRange(0, [[editor string] length])];
            Check([titleOfNote(note) isEqual:@"Alpha"] && [[editor string] isEqual:@"Recovered Alpha"],
                @"title edit remains uncommitted before the Search key command");
            [self nv_keyCommand:@selector(bringFocusToControlField:)];
            Check([self nv_hasSearchItem] && [toolbar isVisible] && [field currentEditor] != nil,
                @"Search restores and focuses its hidden removed item at minimum width");
            Check([titleOfNote(note) isEqual:@"Recovered Alpha"] && [noteTitleField currentEditor] == nil,
                @"Search commits the pending title to its original note");
            Check([self selectedNoteObject] == note && [[[self browserSession] searchString] isEqual:@"anchor"] &&
                [[field stringValue] isEqual:@"anchor"] && [library totalNoteCount] == 1,
                @"Search recovery preserves the query and selection without creating a note");
            [window makeFirstResponder:textView];
            [self nv_keyCommand:@selector(undo:)];
            Check([titleOfNote(note) isEqual:@"Alpha"] && ![[note undoManager] canUndo],
                @"one Undo reverses the single metadata commit from Search recovery");
            [self nv_removeAndHideSearch];
            NSLog(@"SAVED_TOOLBAR configuration=%@", [toolbar configurationDictionary]);
            [note release];
        } else {
            Check([phase isEqual:@"2"], @"second launch uses the same isolated preferences and notes");
            NSLog(@"RESTORED_TOOLBAR visible=%d searchPresent=%d configuration=%@", [toolbar isVisible], [self nv_hasSearchItem], [toolbar configurationDictionary]);
            Check(![toolbar isVisible] && ![self nv_hasSearchItem],
                @"fresh process restores both hidden toolbar and removed Search customization");
            Check([library totalNoteCount] == 1, @"fresh process reads exactly one saved note");
            NoteObject *note = [[library allNotes] lastObject];
            Check([titleOfNote(note) isEqual:@"Alpha"], @"fresh process reads the title restored by Undo");
            [self searchForString:@"anchor"]; [self revealNote:note options:0]; Pump();
            [self nv_keyCommand:@selector(bringFocusToControlField:)];
            Check([toolbar isVisible] && [self nv_hasSearchItem] && [field currentEditor] != nil && [field window] == window,
                @"Search key command recovers the persisted hidden and removed control after relaunch");
            NSTextView *editor = (id)[field currentEditor];
            [editor insertText:@"survives" replacementRange:NSMakeRange(0, [[editor string] length])];
            for (NSUInteger i = 0; i < 4; i++) Pump();
            Check([[[self browserSession] searchString] isEqual:@"survives"] && [notesTableView numberOfRows] == 1 &&
                [library totalNoteCount] == 1, @"the recovered search editor filters saved note text without creating notes");
        }
        Check([library flushAllNoteChanges], @"temporary note changes flush to disk");
        [library closeJournal];
        Check([[NSUserDefaults standardUserDefaults] synchronize], @"isolated preferences flush before controlled process exit");
        NSLog(@"ROUND 3 TORVALDS PHASE %@ PASSED (%lu checks)", phase, (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
