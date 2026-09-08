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
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        [self nv_activateBrowser];
        [window setContentSize:NSMakeSize(480, 420)]; Pump();
        [prefsController setShowWordCount:YES];
        NoteObject *alpha = [MakeNote([app library], @"Alpha", @"alpha body") retain];
        NoteObject *beta = [MakeNote([app library], @"Beta", @"beta body") retain];
        NSMenuItem *search = [self linusFind:@selector(bringFocusToControlField:)];
        Check(search != nil, @"existing Search menu command is available");
        NSLog(@"CONTROL preferred localization %@", [[NSBundle mainBundle] preferredLocalizations]);
        NSUInteger observations = 0, searchMisses = 0, delayedBodyMisses = 0;
        for (NSNumber *width in @[@480, @780]) {
            [window setContentSize:NSMakeSize([width doubleValue], 420)]; Pump();
            for (NSUInteger repetition = 0; repetition < 2; repetition++) {
                for (NSUInteger history = 0; history < 3; history++) {
                    [self setViewingNote:NO];
                    [self searchForString:@""]; [self revealNote:alpha options:0]; Pump();
                    if (history == 1) {
                        NSUInteger index = [[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
                        Check(index != NSNotFound, @"Search item is present before removal");
                        [toolbar removeItemAtIndex:index]; Pump();
                    } else if (history == 2) [self setDualFieldIsVisible:NO];
                    [[search menu] update];
                    Check([search isEnabled] && [NSApp sendAction:[search action] to:[search target] from:search],
                        @"existing native Search command dispatches");
                    for (NSUInteger tick = 0; tick < 7; tick++) Pump();
                    BOOL focused = [toolbar isVisible] && [field currentEditor] && ![field isHiddenOrHasHiddenAncestor];
                    if (!focused) searchMisses++;
                    NSLog(@"OBSERVE width=%@ repetition=%lu history=%lu Search350ms=%d fieldWidth=%.1f key=%d fieldEditor=%@ responder=%@",
                        width, repetition, history, focused, NSWidth([field bounds]), [window isKeyWindow],
                        [field currentEditor], [window firstResponder]);
                    [self focusNoteBody];
                    BOOL immediate = [window firstResponder] == textView;
                    for (NSUInteger tick = 0; tick < 10; tick++) Pump();
                    BOOL retained = [window firstResponder] == textView;
                    if (!retained) delayedBodyMisses++;
                    NSLog(@"OBSERVE width=%@ repetition=%lu history=%lu bodyImmediate=%d body500ms=%d responder=%@",
                        width, repetition, history, immediate, retained, [window firstResponder]);
                    observations++;
                    NSUInteger count = 0;
                    for (NSToolbarItem *item in [toolbar items]) if ([[item itemIdentifier] isEqual:@"Search"]) count++;
                    Check(count == 1, @"restoring Search leaves exactly one Search toolbar item");
                    Check([self selectedNoteObject] == alpha && [[[self browserSession] searchString] isEqual:@""],
                        @"Search histories preserve note selection and query");
                }
            }
        }
        Check([[[alpha contentString] string] isEqual:@"alpha body"] && [[[beta contentString] string] isEqual:@"beta body"],
            @"all common-action histories preserve exact source contents");
        NSLog(@"LINUS CONTROL FINISHED: %lu checks; %lu histories; %lu Search misses; %lu delayed body misses",
            Checks, observations, searchMisses, delayedBodyMisses);
        [alpha release]; [beta release];
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception %@", exception); exit(1); }
}
