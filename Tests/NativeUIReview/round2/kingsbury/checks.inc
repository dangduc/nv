- (void)nv_activate {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ((![NSApp isActive] || [NSApp keyWindow] != window || [NSApp mainWindow] != window) &&
        [deadline timeIntervalSinceNow] > 0) Pump();
    Check([NSApp isActive] && [NSApp keyWindow] == window && [NSApp mainWindow] == window &&
        [[NVApplicationController sharedController] activeBrowser] == self,
        @"intended browser owns native key window, main window, and command routing");
}
- (NSTextView *)nv_pendingTitle:(NSString *)value {
    [self nv_activate];
    [self renameNote:self];
    NSTextView *editor = (id)[noteTitleField currentEditor];
    Check(editor != nil && [window firstResponder] == editor, @"title uses the focused AppKit field editor");
    [editor insertText:value replacementRange:NSMakeRange(0, [[editor string] length])];
    return editor;
}
- (void)nv_history:(SEL)action {
    [self nv_activate];
    [window makeFirstResponder:textView];
    Check([window firstResponder] == textView, @"history command starts from the intended note body");
    NSMenuItem *command = nil;
    NSMutableArray *menus = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
    for (NSUInteger i = 0; i < [menus count]; i++) {
        for (NSMenuItem *item in [menus[i] itemArray]) {
            if ([item action] == action) command = item;
            if ([item submenu]) [menus addObject:[item submenu]];
        }
    }
    [[command menu] update];
    Check(command != nil && [command isEnabled], @"actual Undo or Redo menu item is enabled");
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:[command keyEquivalentModifierMask]
        timestamp:0 windowNumber:[window windowNumber] context:nil characters:[command keyEquivalent]
        charactersIgnoringModifiers:[command keyEquivalent] isARepeat:NO keyCode:0];
    Check([[NSApp mainMenu] performKeyEquivalent:event], @"AppKit dispatches the actual history key equivalent");
    Pump();
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = MakeNote(library, @"Alpha", @"body");
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [self revealNote:alpha options:0]; [peer revealNote:alpha options:0]; Pump();
        LinkingEditor *peerBody = [peer valueForKey:@"textView"];
        [[alpha undoManager] removeAllActions];

        NSLog(@"HISTORY same-note pending field, peer commit, peer undo, new branch");
        NSTextView *pending = [self nv_pendingTitle:@"From origin"];
        Check([titleOfNote(alpha) isEqual:@"Alpha"], @"origin title remains pending before peer activation");
        NSTextView *peerTitle = [peer nv_pendingTitle:@"From peer"];
        [peerTitle doCommandBySelector:@selector(insertNewline:)]; Pump();
        NSLog(@"STATE peerCommit title=%@ originField=%@ originBound=%@", titleOfNote(alpha), [pending string], [self valueForKey:@"metadataNote"]);
        Check([titleOfNote(alpha) isEqual:@"From peer"] && [[pending string] isEqual:@"From origin"] &&
            [self valueForKey:@"metadataNote"] == alpha, @"peer commit keeps the origin pending title bound to the same note");
        [peerBody insertText:@" peer suffix" replacementRange:NSMakeRange([[peerBody string] length], 0)]; Pump();
        Check([[[alpha contentString] string] isEqual:@"body peer suffix"], @"peer body edit commits after the peer rename");
        [peer nv_history:@selector(undo:)];
        Check([titleOfNote(alpha) isEqual:@"From peer"] && [[[alpha contentString] string] isEqual:@"body"],
            @"peer Undo first removes its later body edit");
        [peer nv_history:@selector(undo:)];
        Check([titleOfNote(alpha) isEqual:@"Alpha"] && [[pending string] isEqual:@"From origin"],
            @"peer Undo restores committed title while origin pending text survives");
        [self nv_activate];
        Check([noteTitleField currentEditor] == pending, @"returning to origin retains its pending AppKit field editor");
        [pending doCommandBySelector:@selector(insertNewline:)]; Pump();
        Check([titleOfNote(alpha) isEqual:@"From origin"] && ![[alpha undoManager] canRedo],
            @"origin commit replaces the abandoned redo branch with its own title");
        [peer nv_history:@selector(undo:)];
        Check([titleOfNote(alpha) isEqual:@"Alpha"] && ![[alpha undoManager] canUndo] &&
            [[[alpha contentString] string] isEqual:@"body"], @"peer can undo origin commit back to the initial complete note state");
        [self nv_history:@selector(redo:)];
        Check([titleOfNote(alpha) isEqual:@"From origin"] && [[noteTitleField stringValue] isEqual:@"From origin"] &&
            [[[peer valueForKey:@"noteTitleField"] stringValue] isEqual:@"From origin"],
            @"origin Redo updates both headers without restoring the abandoned peer branch");

        NSLog(@"HISTORY filtered rename, pinned row, external body, cross-browser undo");
        NoteObject *filtered = MakeNote(library, @"needle target", @"shared content");
        [self nv_activate]; [self searchForString:@"needle"]; Pump();
        [peer nv_activate]; [peer searchForString:@"shared"]; Pump();
        NSLog(@"QUERY_SETUP origin=%@ originNote=%@ peer=%@ peerNote=%@ peerMatches=%lu", [[self browserSession] searchString],
            [self selectedNoteObject], [[peer browserSession] searchString], [peer selectedNoteObject],
            (unsigned long)[[[peer browserSession] valueForKey:@"matchingNotes"] count]);
        [self revealNote:filtered options:0]; [peer revealNote:filtered options:0]; Pump();
        Check([self selectedNoteObject] == filtered && [peer selectedNoteObject] == filtered,
            @"independent queries select the same starting note");
        [[filtered undoManager] removeAllActions];
        NSTextView *rename = [self nv_pendingTitle:@"renamed target"];
        [rename doCommandBySelector:@selector(insertNewline:)]; Pump();
        Check([self selectedNoteObject] == filtered && [[[self browserSession] valueForKey:@"matchingNotes"] count] == 0 &&
            [notesTableView numberOfRows] == 1, @"rename leaves exactly one pinned row outside the origin query matches");
        Check([[[peer browserSession] searchString] isEqual:@"shared"] && [peer selectedNoteObject] == filtered,
            @"origin rename preserves the peer query and selection");
        [filtered setContentString:[[[NSAttributedString alloc] initWithString:@"shared remote"] autorelease]]; Pump();
        [peer nv_history:@selector(undo:)];
        Check([titleOfNote(filtered) isEqual:@"needle target"] && [[[filtered contentString] string] isEqual:@"shared remote"] &&
            [[textView string] isEqual:@"shared remote"] && [[peerBody string] isEqual:@"shared remote"],
            @"peer metadata Undo retains external body text in model and both editors");
        Check([[[self browserSession] searchString] isEqual:@"needle"] && [[[self browserSession] valueForKey:@"matchingNotes"] count] == 1 &&
            [notesTableView numberOfRows] == 1, @"metadata Undo returns the pinned note to the actual query matches without duplication");
        [peer nv_history:@selector(redo:)];
        Check([titleOfNote(filtered) isEqual:@"renamed target"] && [[[self browserSession] valueForKey:@"matchingNotes"] count] == 0 &&
            [notesTableView numberOfRows] == 1 && [[[filtered contentString] string] isEqual:@"shared remote"],
            @"peer Redo recreates only the pinned row and preserves external text");
        [self nv_activate]; [self searchForString:@"needle more"]; Pump();
        Check([notesTableView numberOfRows] == 0 && [self selectedNoteObject] == nil &&
            [[[self browserSession] valueForKey:@"matchingNotes"] count] == 0,
            @"refining the query drops the pinned row instead of using it as a candidate");
        [peer nv_history:@selector(undo:)];
        Check([titleOfNote(filtered) isEqual:@"needle target"] && [notesTableView numberOfRows] == 0 && [self selectedNoteObject] == nil &&
            [[[self browserSession] searchString] isEqual:@"needle more"] && [[[peer browserSession] searchString] isEqual:@"shared"] &&
            [peer selectedNoteObject] == filtered && [[[filtered contentString] string] isEqual:@"shared remote"],
            @"Undo after origin deselection preserves both query histories and the peer selected note");
        NSLog(@"FINAL title=%@ body=%@ originQuery=%@ originRows=%ld peerQuery=%@ peerSelected=%@", titleOfNote(filtered),
            [[filtered contentString] string], [[self browserSession] searchString], (long)[notesTableView numberOfRows],
            [[peer browserSession] searchString], titleOfNote([peer selectedNoteObject]));
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"KINGSBURY ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
