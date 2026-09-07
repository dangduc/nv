- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha body") retain];
        [self searchForString:@""]; [self revealNote:alpha options:0]; Pump();
        [[library undoManager] removeAllActions];
        [[alpha undoManager] removeAllActions];

        // Commit a rename exactly as the metadata delegate handles Return.
        [self renameNote:self];
        NSTextView *titleEditor = (id)[noteTitleField currentEditor];
        Check(titleEditor != nil, @"rename focuses title editor");
        [titleEditor insertText:@"Renamed Alpha" replacementRange:NSMakeRange(0, [[titleEditor string] length])];
        [titleEditor doCommandBySelector:@selector(insertNewline:)]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Renamed Alpha"] && [window firstResponder] == textView,
            @"Return commits title and focuses body");
        NSMenuItem *undoItem = [[[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"] autorelease];
        BOOL bodyCanUndo = [textView validateMenuItem:undoItem];
        NSLog(@"OBSERVATION metadata: libraryCanUndo=%d bodyCanUndo=%d bodyIsFirstResponder=%d", [[library undoManager] canUndo], bodyCanUndo, [window firstResponder] == textView);
        [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
        BOOL metadataUndone = [titleOfNote(alpha) isEqual:@"Alpha"];
        NSLog(@"OBSERVATION metadata after responder-chain Undo: title=%@ expected=Alpha", titleOfNote(alpha));
        // Control: the registered model undo actually exists and can restore it.
        [[library undoManager] undo]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Alpha"], @"library undo can restore the committed title");

        // Users can remove any allowed toolbar item in Customize Toolbar.
        [self searchForString:@"al"]; Pump();
        [window makeFirstResponder:textView]; Pump();
        NSArray *items = [toolbar items];
        NSUInteger searchIndex = NSNotFound;
        for (NSUInteger i = 0; i < [items count]; i++) if ([[items[i] itemIdentifier] isEqual:@"Search"]) searchIndex = i;
        Check(searchIndex != NSNotFound, @"toolbar initially contains Search");
        [toolbar removeItemAtIndex:searchIndex]; Pump();
        Check([toolbar isVisible], @"toolbar remains visible after removing Search");
        [self bringFocusToControlField:self];
        for (NSUInteger i = 0; i < 10; i++) Pump();
        BOOL searchRestored = NO;
        for (NSToolbarItem *item in [toolbar items]) if ([[item itemIdentifier] isEqual:@"Search"]) searchRestored = YES;
        BOOL searchFocused = [field currentEditor] != nil;
        NSLog(@"OBSERVATION search after Search command: present=%d focused=%d window=%@ query=%@", searchRestored, searchFocused, [field window], [[self browserSession] searchString]);
        // Control: the explicit visibility helper restores the missing item.
        [self setDualFieldIsVisible:YES]; [self bringFocusToControlField:self];
        for (NSUInteger i = 0; i < 10; i++) Pump();
        Check([field currentEditor] != nil && [field window] == window, @"visibility helper can restore and focus Search");

        [alpha release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"REVIEW RESULT metadataUndo=%d restoredSearch=%d focusedSearch=%d", metadataUndone, searchRestored, searchFocused);
        exit(metadataUndone && searchRestored && searchFocused ? 0 : 1);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
