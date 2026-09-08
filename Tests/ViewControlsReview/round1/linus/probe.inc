- (NSMenuItem *)reviewItem:(NSMenu *)menu action:(SEL)action {
    for (NSMenuItem *item in [menu itemArray]) if ([item action] == action) return item;
    return nil;
}
- (void)reviewSend:(NSMenuItem *)item {
    Check(item && [NSApp sendAction:[item action] to:[item target] from:item], @"native menu action dispatches");
    Pump();
}
- (BOOL)reviewWait:(BOOL (^)(void))condition seconds:(NSTimeInterval)seconds {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) Pump();
    return condition();
}
- (void)nv_runTests {
    @try {
        unsetenv("DYLD_INSERT_LIBRARIES");
        NVApplicationController *app = [NVApplicationController sharedController];
        [self nv_activateBrowser];
        NSRect frame = [window frame]; frame.size.width = 780; [window setFrame:frame display:YES];
        NSMenu *view = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
        NSArray *actions = @[@"toggleTitleInTopSection:", @"toggleTagsInTopSection:",
            @"toggleBodyControlsInTopSection:", @"toggleNotesList:", @"toggleSourcePreview:"];
        NSMenuItem *anchor = [self reviewItem:view action:@selector(toggleNoteBodyPreviews:)];
        Check(anchor != nil, @"the loaded menu has the existing View anchor");
        NSInteger anchorIndex = [view indexOfItem:anchor];
        Check([view numberOfItems] > anchorIndex + 6, @"the initial menu contains six new entries");
        // Rebuild from a translated anchor to test selector-based insertion.
        for (NSUInteger count = 0; count < 6; count++) [view removeItemAtIndex:anchorIndex + 1];
        [anchor setTitle:@"Aperçus des notes dans le titre — ノート"];
        NSInteger rebuiltCount = -1;
        for (NSUInteger round = 0; round < 4; round++) {
            [app performSelector:@selector(configureMenus)];
            NSInteger currentCount = [view numberOfItems];
            if (round == 0) rebuiltCount = currentCount;
            Check(currentCount == rebuiltCount, @"repeated menu setup adds no duplicate items");
            NSUInteger offset = 0;
            for (NSString *name in actions) {
                SEL action = NSSelectorFromString(name);
                NSUInteger matches = 0;
                for (NSMenuItem *item in [view itemArray]) if ([item action] == action) matches++;
                NSMenuItem *item = [view itemAtIndex:anchorIndex + 1 + offset++];
                Check(matches == 1 && [item action] == action && [item target] == app,
                    @"each new action occurs once, in order, and targets the coordinator");
            }
            NSMenu *syntax = [[view itemAtIndex:anchorIndex + 6] submenu];
            Check([[[syntax itemArray] valueForKey:@"representedObject"] isEqual:@[@"plain", @"markdown", @"textile", @"html", @"json"]],
                @"repeated setup preserves all five source syntax identities");
            Check([[self reviewItem:view action:@selector(toggleWordCount:)] infoForBinding:NSValueBinding] == nil,
                @"repeated setup leaves Word Count without the obsolete double-toggle binding");
        }

        NoteObject *note = [MakeNote([app library], @"Review focus", @"# Review\n\nNative focus source.") retain];
        [self searchForString:@""]; [self revealNote:note options:0];
        [self bringFocusToControlField:self];
        Check([self reviewWait:^BOOL { return [field currentEditor] != nil && NSWidth([field bounds]) >= 140; } seconds:3],
            @"native Search settles before the focus scenarios");
        [self focusNoteBody];
        [self setViewingNote:YES];
        Check([self reviewWait:^BOOL { return previewController && ![previewController loading]; } seconds:10],
            @"the native Preview finishes loading");
        Check([previewController renderError] == nil, @"the Preview fixture has a valid rendered note");
        for (NSString *key in @[@"noteTitleField", @"noteTagsField"]) {
            NSTextField *control = [self valueForKey:key];
            SEL action = [key isEqual:@"noteTitleField"] ? @selector(toggleTitleInTopSection:) : @selector(toggleTagsInTopSection:);
            [control selectText:self]; Pump();
            Check([control currentEditor] != nil, @"untouched metadata has native keyboard focus in Preview");
            [self reviewSend:[self reviewItem:view action:action]];
            NSResponder *responder = [window firstResponder];
            Check(![control currentEditor] && [responder isKindOfClass:[NSView class]] &&
                [(NSView *)responder isDescendantOf:[previewController view]],
                @"hiding untouched metadata transfers keyboard focus into Preview");
            [self reviewSend:[self reviewItem:view action:action]];
        }
        [window makeFirstResponder:viewerTypeControl];
        Check([window firstResponder] == viewerTypeControl, @"the Preview format popup has keyboard focus");
        [self reviewSend:[self reviewItem:view action:@selector(toggleBodyControlsInTopSection:)]];
        Check([[window firstResponder] isKindOfClass:[NSView class]] &&
            [(NSView *)[window firstResponder] isDescendantOf:[previewController view]],
            @"hiding the focused format popup transfers focus into Preview");
        [self reviewSend:[self reviewItem:view action:@selector(toggleBodyControlsInTopSection:)]];
        [self setViewingNote:NO];

        // Run the customization history that previously exposed fixture timing.
        for (NSUInteger history = 0; history < 3; history++) {
            NSUInteger searchIndex = [[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
            Check(searchIndex != NSNotFound, @"the Search customization fixture has its toolbar item");
            [toolbar removeItemAtIndex:searchIndex]; Pump();
            [self bringFocusToControlField:self];
            Check([self reviewWait:^BOOL { return [field currentEditor] != nil && ![field isHiddenOrHasHiddenAncestor] && NSWidth([field bounds]) >= 140; } seconds:3],
                @"Search returns after toolbar customization and receives a visible field editor");
            [self focusNoteBody];
            [self reviewSend:[self reviewItem:view action:@selector(toggleTitleInTopSection:)]];
            for (NSUInteger tick = 0; tick < 10; tick++) Pump();
            Check([window firstResponder] == textView, @"header layout retains body focus after a completed Search restoration");
            [self reviewSend:[self reviewItem:view action:@selector(toggleTitleInTopSection:)]];
        }
        [note release];
        NSLog(@"LINUS REVIEW CHECKS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
