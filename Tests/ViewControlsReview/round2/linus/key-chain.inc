- (NSMenuItem *)linusFind:(SEL)action {
    NSMutableArray *menus = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
    for (NSUInteger i = 0; i < [menus count]; i++) {
        for (NSMenuItem *item in [[menus objectAtIndex:i] itemArray]) {
            if ([item action] == action) return item;
            if ([item submenu]) [menus addObject:[item submenu]];
        }
    }
    return nil;
}
- (void)linusSend:(SEL)action {
    NSMenuItem *item = [self linusFind:action];
    [[item menu] update];
    Check(item && [item isEnabled] && [NSApp sendAction:action to:[item target] from:item],
        @"requested native View command exists, is enabled, and dispatches");
    Pump();
}
- (BOOL)linusBodyHasFocus {
    if (!viewingNote) return [window firstResponder] == textView;
    return [[window firstResponder] isKindOfClass:[NSView class]] &&
        [(NSView *)[window firstResponder] isDescendantOf:[previewController view]];
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        [self nv_activateBrowser];
        [window setContentSize:NSMakeSize(780, 520)]; Pump();
        [prefsController setShowWordCount:YES];
        NoteObject *note = [MakeNote([app library], @"Navigation", @"# Navigation\n\nExact source remains unchanged.") retain];
        [self searchForString:@""]; [self revealNote:note options:0]; Pump();
        // Let native Search settle once before testing unrelated header navigation.
        [self bringFocusToControlField:self];
        for (NSUInteger tick = 0; tick < 20; tick++) Pump();
        [self focusNoteBody]; Pump();
        Check([self linusBodyHasFocus], @"header fixture starts with stable native Source focus");
        NSUInteger scenarios = 0;
        for (NSUInteger mode = 0; mode < 2; mode++) {
            if ([self isViewingNote] != (mode != 0)) [self linusSend:@selector(toggleSourcePreview:)];
            if (mode) {
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
                while ((!previewController || [previewController loading]) && [deadline timeIntervalSinceNow] > 0) Pump();
                Check(previewController && ![previewController loading] && ![previewController renderError],
                    @"Preview has finished rendering before native navigation");
            }
            for (NSUInteger mask = 0; mask < 8; mask++) {
                BOOL title = (mask & 1) != 0, tags = (mask & 2) != 0, controls = (mask & 4) != 0;
                if ([prefsController showTitleInTopSection] != title) [self linusSend:@selector(toggleTitleInTopSection:)];
                if ([prefsController showTagsInTopSection] != tags) [self linusSend:@selector(toggleTagsInTopSection:)];
                if ([prefsController showBodyControlsInTopSection] != controls) [self linusSend:@selector(toggleBodyControlsInTopSection:)];
                NSLog(@"KEY CHAIN mode=%lu mask=%lu", mode, mask);
                Check([noteTitleField isHidden] == !title && [noteTagsField isHidden] == !tags && [bodyModeControl isHidden] == !controls,
                    @"native visibility commands establish the requested header combination");
                if (title) {
                    [noteTitleField selectText:self]; Pump();
                    Check([noteTitleField currentEditor] != nil, @"visible title receives native field editing focus");
                    [(NSTextView *)[noteTitleField currentEditor] doCommandBySelector:@selector(insertTab:)]; Pump();
                    Check(tags ? [noteTagsField currentEditor] != nil : [self linusBodyHasFocus],
                        @"native Tab from title reaches visible tags or the current body");
                }
                if (tags) {
                    [noteTagsField selectText:self]; Pump();
                    Check([noteTagsField currentEditor] != nil, @"visible tags receive native field editing focus");
                    [(NSTextView *)[noteTagsField currentEditor] doCommandBySelector:@selector(insertTab:)]; Pump();
                    Check([self linusBodyHasFocus], @"native Tab from tags reaches the current body");
                }
                [self focusNoteBody];
                [self linusSend:@selector(toggleSourcePreview:)];
                Check([self isViewingNote] != (mode != 0) && [self linusBodyHasFocus],
                    @"Source/Preview command focuses the destination across every header combination");
                [self linusSend:@selector(toggleSourcePreview:)];
                Check([self isViewingNote] == (mode != 0) && [self linusBodyHasFocus],
                    @"Source/Preview return restores body focus across every header combination");
                scenarios++;
            }
        }
        Check([titleOfNote(note) isEqual:@"Navigation"] && [[[note contentString] string] isEqual:@"# Navigation\n\nExact source remains unchanged."],
            @"native navigation and mode commands preserve exact title and source");
        NSLog(@"LINUS KEY CHAIN PASSED: %lu checks; %lu scenarios", Checks, scenarios);
        [note release]; exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception %@", exception); exit(1); }
}
