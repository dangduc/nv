- (NSMenuItem *)nv_menuItemForAction:(SEL)action {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
    for (NSUInteger i = 0; i < [pending count]; i++) {
        for (NSMenuItem *item in [[pending objectAtIndex:i] itemArray]) {
            if ([item action] == action) return item;
            if ([item submenu]) [pending addObject:[item submenu]];
        }
    }
    return nil;
}

- (void)nv_dispatchMenuAction:(SEL)action {
    NSMenuItem *item = [self nv_menuItemForAction:action];
    Check(item != nil, [NSString stringWithFormat:@"menu contains %@", NSStringFromSelector(action)]);
    [[item menu] update];
    Check([item isEnabled], [NSString stringWithFormat:@"menu enables %@", NSStringFromSelector(action)]);
    Check([NSApp sendAction:[item action] to:[item target] from:item],
        [NSString stringWithFormat:@"menu dispatches %@", NSStringFromSelector(action)]);
    Pump();
}

- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Toolbar Alpha", @"alpha body") retain];
        NoteObject *beta = [MakeNote(library, @"Toolbar Beta", @"beta body") retain];
        [self nv_activateBrowser];
        [self searchForString:@"" mode:@"exact"]; [self revealNote:alpha options:0]; Pump();

        Check([[toolbar items] count] == 1 && ![toolbar allowsUserCustomization], @"fixed toolbar has one item");
        Check([dualFieldItem class] == [NSToolbarItem class], @"search uses ordinary NSToolbarItem");
        [toolbar validateVisibleItems];
        Check([dualFieldItem isEnabled] && [field isEnabled] && [field isEditable],
            @"ordinary item validation keeps the search control enabled and editable");
        [self nv_dispatchMenuAction:@selector(bringFocusToControlField:)];
        Check([window firstResponder] == [field currentEditor] && [field currentEditor] != nil,
            @"Search menu makes the actual search editor first responder");
        [window makeFirstResponder:textView];
        for (NSUInteger i = 0; i < 8; i++) Pump();
        Check([window firstResponder] == textView, @"no deferred search activation steals subsequent body focus");

        for (NSString *selectorName in @[@"newNote:", @"togglePreview:", @"renameNote:", @"tagNote:",
                                          @"copyNoteLink:", @"exportNote:", @"deleteNote:"]) {
            NSMenuItem *item = [self nv_menuItemForAction:NSSelectorFromString(selectorName)];
            Check(item != nil && [NSApp targetForAction:[item action] to:[item target] from:item] != nil,
                [NSString stringWithFormat:@"removed icon command %@ retains a menu receiver", selectorName]);
            [[item menu] update];
            Check([item isEnabled], [NSString stringWithFormat:@"selected note enables %@", selectorName]);
        }
        [self nv_dispatchMenuAction:@selector(renameNote:)];
        Check([noteTitleField currentEditor] != nil, @"Rename menu focuses the selected note title");
        [window makeFirstResponder:textView];
        [self nv_dispatchMenuAction:@selector(tagNote:)];
        Check([noteTagsField currentEditor] != nil, @"Tags menu focuses the selected note tags");
        [window makeFirstResponder:textView];
        [self nv_dispatchMenuAction:@selector(togglePreview:)];
        Check(viewingNote, @"Preview menu enters the selected note viewer");
        [self nv_dispatchMenuAction:@selector(togglePreview:)];
        Check(!viewingNote, @"Preview menu returns to source");

        NSDictionary *legacy = @{ @"TB Item Identifiers": @[@"NewNote", @"Preview", @"More", @"Search"],
                                  @"TB Is Shown": @NO, @"TB Display Mode": @1, @"TB Size Mode": @1 };
        NSString *legacyKey = @"NSToolbar Configuration NVBrowserToolbar";
        [[NSUserDefaults standardUserDefaults] setObject:legacy forKey:legacyKey];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"saved-layout migration uses a newly created browser");
        [peer nv_activateBrowser];
        NSToolbar *peerToolbar = [[peer window] toolbar];
        Check([[peerToolbar identifier] isEqual:@"NVBrowserSearchToolbar"] && [peerToolbar isVisible] &&
            [[[peerToolbar items] valueForKey:@"itemIdentifier"] isEqual:@[@"Search"]],
            @"legacy saved icons and hidden toolbar do not migrate into a new browser");
        Check([[[NSUserDefaults standardUserDefaults] objectForKey:legacyKey] isEqual:legacy],
            @"migration leaves unrelated legacy preferences unchanged");
        [peer searchForString:@"" mode:@"exact"]; [peer revealNote:beta options:0]; Pump();
        [peer nv_dispatchMenuAction:@selector(bringFocusToControlField:)];
        DualField *peerField = [peer valueForKey:@"field"];
        Check([[peer window] firstResponder] == [peerField currentEditor] && [peerField currentEditor] != nil &&
            [field currentEditor] == nil, @"Search menu focuses only the active browser");
        NSUInteger before = [library totalNoteCount];
        [peer nv_dispatchMenuAction:@selector(newNote:)];
        Check([library totalNoteCount] == before + 1 && [peer selectedNoteObject] != beta &&
            [self selectedNoteObject] == alpha, @"New Note menu creates in the active browser and preserves peer selection");
        Check([[self nv_menuItemForAction:@selector(newNote:)] keyEquivalent] &&
            [[[[self nv_menuItemForAction:@selector(newNote:)] keyEquivalent] lowercaseString] isEqual:@"n"],
            @"New Note retains the keyboard shortcut");
        [alpha release]; [beta release];
        NSLog(@"TORVALDS_REVIEW_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) {
        NSLog(@"TORVALDS_REVIEW_EXCEPTION %@ %@", [exception name], [exception reason]);
        exit(2);
    }
}
