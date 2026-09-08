// Native, disposable-library probe for access through empty and closed-window states.
- (NSMenuItem *)nv_c2Command:(SEL)action {
    NSMutableArray *menus = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
    for (NSUInteger i = 0; i < [menus count]; i++) {
        for (NSMenuItem *item in [menus[i] itemArray]) {
            if ([item action] == action) return item;
            if ([item submenu]) [menus addObject:[item submenu]];
        }
    }
    return nil;
}
- (void)nv_c2Enabled:(SEL)action expected:(BOOL)enabled {
    NSMenuItem *item = [self nv_c2Command:action];
    Check(item != nil, [NSString stringWithFormat:@"native menu contains %@", NSStringFromSelector(action)]);
    [[item menu] update];
    Check([item isEnabled] == enabled, [NSString stringWithFormat:@"native validation %@ %@",
        enabled ? @"enables" : @"disables", NSStringFromSelector(action)]);
}
- (void)nv_c2Dispatch:(SEL)action {
    [self nv_c2Enabled:action expected:YES];
    NSMenuItem *item = [self nv_c2Command:action];
    Check([NSApp sendAction:action to:[item target] from:item],
        [NSString stringWithFormat:@"application dispatch accepts %@", NSStringFromSelector(action)]);
    Pump();
}
- (void)nv_c2EmptyCommands {
    Check(currentNote == nil && [notesTableView numberOfSelectedRows] == 0,
        @"empty-state menu validation starts without a selected note");
    for (NSString *name in @[@"renameNote:", @"tagNote:", @"deleteNote:", @"toggleSourcePreview:", @"selectSourceSyntax:"])
        [self nv_c2Enabled:NSSelectorFromString(name) expected:NO];
    for (NSString *name in @[@"newNote:", @"newWindow:", @"bringFocusToControlField:", @"toggleNotesList:",
            @"toggleTitleInTopSection:", @"toggleTagsInTopSection:", @"toggleBodyControlsInTopSection:"])
        [self nv_c2Enabled:NSSelectorFromString(name) expected:YES];
}
- (void)nv_c2CheckHidden {
    Check([[[browserSplitController splitViewItems] firstObject] isCollapsed] &&
        [noteTitleField isHidden] && [noteTagsField isHidden] && [bodyModeControl isHidden] && [wordCounter isHidden],
        @"actual notes list and every header row remain hidden");
}
- (void)nv_c2Search:(NSString *)query {
    [self nv_c2Dispatch:@selector(bringFocusToControlField:)];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    Check([toolbar isVisible] && [field currentEditor] && ![field isHiddenOrHasHiddenAncestor],
        @"Search opens a visible native field editor from the empty hidden interface");
    NSTextView *editor = (id)[field currentEditor];
    [editor insertText:query replacementRange:NSMakeRange(0, [[editor string] length])]; Pump();
    Check([[[self browserSession] searchString] isEqual:query] && [[field stringValue] isEqual:query],
        @"native field editing sets the exact browser query");
}
- (void)nv_c2TypeBody:(NSString *)body {
    Check(currentNote && !viewingNote && [window firstResponder] == textView && ![textScrollView isHidden],
        @"note creation gives the visible editable Source the actual first responder");
    Check([NSApp sendAction:@selector(insertText:) to:nil from:body], @"nil-target body input resolves through the native responder chain");
    [self finishEditing]; Pump();
    Check([[[currentNote contentString] string] isEqual:body], @"responder-chain input commits the exact source characters");
}
- (void)nv_c2ForceLegacyNewNoteFocus:(id)sender {
    [self nv_c2ForceLegacyNewNoteFocus:sender];
    // Mutation control: force the old unconditional title focus after New Note.
    [noteTitleField selectText:self];
}
- (void)nv_runTests {
    @try {
        if (getenv("NV_C2_LEGACY_NEW_NOTE_FOCUS")) {
            Swap([AppController class], @selector(newNote:), @selector(nv_c2ForceLegacyNewNoteFocus:));
            NSLog(@"MUTATION: New Note unconditionally focuses Title, including its hidden control");
        }
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        [self nv_activateBrowser];
        [window setContentSize:NSMakeSize(780, 560)]; Pump();
        [prefsController setConfirmNoteDeletion:NO sender:nil];
        [prefsController setShowWordCount:YES];
        Check([[library allNotes] count] == 0, @"fixture starts with an actually empty shared library");
        NSLog(@"HISTORY 1: empty library, hidden toolbar, collapse the focused empty list");
        [self setDualFieldIsVisible:NO];
        Check([window makeFirstResponder:notesTableView] && [window firstResponder] == notesTableView,
            @"the empty notes list owns native focus before it is hidden");
        for (NSString *name in @[@"toggleTitleInTopSection:", @"toggleTagsInTopSection:",
                @"toggleBodyControlsInTopSection:", @"toggleNotesList:"])
            [self nv_c2Dispatch:NSSelectorFromString(name)];
        [self nv_c2CheckHidden];
        NSLog(@"OBSERVATION empty collapse toolbarVisible=%d firstResponder=%@ fieldEditor=%@ listHidden=%d",
            [toolbar isVisible], [window firstResponder], [field currentEditor], [notesTableView isHiddenOrHasHiddenAncestor]);
        [self nv_c2EmptyCommands];
        Check(![editorStatusView isHidden] && NSEqualRects([editorStatusView frame], [splitSubview bounds]),
            @"the empty-library status view occupies the released header space");
        [self nv_c2Search:@"Created by Return with no rows"];
        [self nv_c2EmptyCommands];
        NSTextView *searchEditor = (id)[field currentEditor];
        [searchEditor doCommandBySelector:@selector(insertTab:)]; Pump();
        Check([field currentEditor] == searchEditor && [[library allNotes] count] == 0,
            @"Tab keeps empty-result Search focused and creates no accidental note");
        [searchEditor doCommandBySelector:@selector(insertNewline:)]; Pump();
        Check([[library allNotes] count] == 1 && [titleOfNote(currentNote) isEqual:@"Created by Return with no rows"],
            @"Return creates exactly one note with the native Search query as title");
        [self nv_c2CheckHidden];
        [self nv_c2TypeBody:@"Body created from the empty hidden interface."];
        [self nv_c2Dispatch:@selector(deleteNote:)];
        Check([[library allNotes] count] == 0 && currentNote == nil, @"native Delete removes the last note with list and header hidden");
        [self nv_c2EmptyCommands];

        NSLog(@"HISTORY 2: close every browser, use View menus, then New Window");
        [window performClose:self]; Pump();
        Check([[app browserControllers] count] == 0 && [app library] == library,
            @"closing the last native window leaves the shared empty library open");
        [self nv_c2Dispatch:@selector(toggleTitleInTopSection:)];
        Check([prefsController showTitleInTopSection], @"a no-window View command reaches the retained application owner");
        [self nv_c2Dispatch:@selector(toggleTitleInTopSection:)];
        [self nv_c2Dispatch:@selector(newWindow:)];
        Check([[app browserControllers] count] == 1, @"the native New Window menu opens exactly one browser after all windows close");
        AppController *second = [[app browserControllers] lastObject];
        [second nv_activateBrowser];
        [[second window] setContentSize:NSMakeSize(780, 560)]; Pump();
        Check(second != self && [second sharedNotationController] == library,
            @"the reopened browser attaches to the original shared library");
        [second nv_c2CheckHidden];
        [second nv_c2EmptyCommands];
        [second nv_c2Dispatch:@selector(newNote:)];
        Check([[library allNotes] count] == 1, @"New Note creates exactly one note in the reopened empty library");
        [second nv_c2TypeBody:@"Body survives closing its only browser."];
        NoteObject *saved = [[second selectedNoteObject] retain];
        [[second window] performClose:self]; Pump();
        Check([[app browserControllers] count] == 0 && [app library] == library &&
            [[[saved contentString] string] isEqual:@"Body survives closing its only browser."],
            @"closing the secondary browser retains its note and the same open library");

        NSLog(@"HISTORY 3: Dock reopen, no-match filter, and New Note with hidden title");
        Check([(id<NSApplicationDelegate>)[NSApp delegate] applicationShouldHandleReopen:NSApp hasVisibleWindows:NO],
            @"the native application reopen callback accepts the zero-window state"); Pump();
        Check([[app browserControllers] count] == 1, @"Dock reopen creates exactly one browser");
        AppController *third = [[app browserControllers] lastObject];
        [third nv_activateBrowser];
        [[third window] setContentSize:NSMakeSize(780, 560)]; Pump();
        [third nv_c2CheckHidden];
        Check([third sharedNotationController] == library && [[library allNotes] containsObject:saved],
            @"Dock reopen reuses the shared library and keeps the previously created note");
        [third setDualFieldIsVisible:NO];
        [third nv_c2Search:@"No matching title or body 938472"];
        Check([[third valueForKey:@"notesTableView"] numberOfRows] == 0 && [third selectedNoteObject] == nil,
            @"the reopened browser reaches an actual zero-result query over a nonempty library");
        [third nv_c2EmptyCommands];
        [third nv_c2Dispatch:@selector(newNote:)];
        Check([[library allNotes] count] == 2 && [third selectedNoteObject] != saved &&
            [[[third browserSession] searchString] isEqual:@""] && [[third valueForKey:@"field"] stringValue] &&
            ![[[third valueForKey:@"field"] stringValue] length],
            @"New Note clears the unmatched query and creates a distinct note after reopen");
        [third nv_c2CheckHidden];
        [third nv_c2TypeBody:@"New Note after an unmatched query."];
        Check([[[saved contentString] string] isEqual:@"Body survives closing its only browser."],
            @"the second creation leaves the original note's exact source intact");
        [third nv_c2Dispatch:@selector(toggleNotesList:)];
        Check(![[[[third valueForKey:@"browserSplitController"] splitViewItems] firstObject] isCollapsed] &&
            [[third valueForKey:@"notesTableView"] numberOfRows] == 2 &&
            [[third valueForKey:@"notesTableView"] numberOfSelectedRows] == 1,
            @"Show Notes List restores both notes and the new note selection after both reopen paths");
        [saved release]; [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"CONTRARIAN ROUND 2 PASSED: %lu checks", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception %@", exception); exit(1); }
}
