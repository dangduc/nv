- (void)nv_kWaitSearch {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent], @"the browser's current query has a complete result");
}
- (void)nv_kStateQuery:(NSString *)query mode:(NSString *)mode title:(NSString *)title {
    Check([[field stringValue] isEqual:query], @"visible query matches the independent history model");
    Check([[[self browserSession] searchString] isEqual:query], @"session query matches the independent history model");
    Check([[self searchMode] isEqual:mode], @"search mode remains local to its browser");
    Check([titleOfNote([self selectedNoteObject]) isEqual:title], @"selected note matches the independent history model");
    Check([[window title] isEqual:title] && [window titleVisibility] == NSWindowTitleHidden,
        @"window title updates for the selected note while staying hidden");
    Check([[[toolbar items] valueForKey:@"itemIdentifier"] isEqual:@[@"Search"]],
        @"the browser has exactly one Search item after its history");
    Check([self sharedNotationController] == [[NVApplicationController sharedController] library],
        @"the browser still belongs to the application's shared library");
}
- (void)nv_kFocus {
    [self nv_activateBrowser];
    [self bringFocusToControlField:self];
    [[[window contentView] superview] layoutSubtreeIfNeeded];
    Check([toolbar isVisible] && [field window] == window && ![field isHiddenOrHasHiddenAncestor] &&
        [field currentEditor] != nil && [window firstResponder] == [field currentEditor],
        @"Search immediately restores and focuses this browser's own field");
    NSRect frame = [field convertRect:[field bounds] toView:nil];
    Check(NSWidth(frame) >= NSWidth([window frame]) - 130 && NSMaxX(frame) >= NSWidth([window frame]) - 30,
        @"Search fills the available title-bar width after a transition");
    [window makeFirstResponder:textView];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    Check([window firstResponder] == textView, @"later body focus survives delayed toolbar work");
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSUInteger phase = strtoul(getenv("NV_REVIEW_PHASE") ?: "1", NULL, 10);
        if (phase == 2) {
            NSArray *browsers = [app browserControllers];
            Check([browsers count] == 2, @"a fresh process restores both browser histories");
            AppController *first = browsers[0], *second = browsers[1];
            [first nv_kWaitSearch]; [second nv_kWaitSearch];
            [first nv_kStateQuery:@"alpha corpus" mode:@"exact" title:@"Alpha renamed 3"];
            [second nv_kStateQuery:@"beta corpus" mode:@"fuzzy" title:@"Beta"];
            [first nv_kFocus]; [second nv_kFocus];
            Check([library totalNoteCount] == 2, @"relaunch preserves exactly the two fixture notes");
            [library flushAllNoteChanges]; [library closeJournal];
            NSLog(@"KINGSBURY_PHASE_2_PASS checks=%lu", (unsigned long)Checks); exit(0);
        }
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha corpus source") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"beta corpus source") retain];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"two independent browser controllers exist");
        [self searchForString:@"alpha corpus" mode:@"exact"];
        [peer searchForString:@"beta corpus" mode:@"fuzzy"];
        [self nv_kWaitSearch]; [peer nv_kWaitSearch];
        [self revealNote:alpha options:0]; [peer revealNote:beta options:0]; Pump();
        Check([self valueForKey:@"field"] != [peer valueForKey:@"field"] &&
            [self valueForKey:@"dualFieldItem"] != [peer valueForKey:@"dualFieldItem"],
            @"the same toolbar identifier does not share fields or item objects");
        if (getenv("NV_TITLEBAR_QUERY_CLOBBER")) {
            // Fault injection models the removed title/query coupling. The
            // invariant must fail even though normal AppKit focus succeeds.
            Method method = class_getInstanceMethod([AppController class], @selector(selectSearchField));
            IMP original = method_getImplementation(method);
            IMP mutated = imp_implementationWithBlock(^(AppController *browser) {
                ((void (*)(id, SEL))original)(browser, @selector(selectSearchField));
                [[browser valueForKey:@"field"] setStringValue:[[browser window] title]];
            });
            method_setImplementation(method, mutated);
            [self nv_kFocus];
            [self nv_kStateQuery:@"alpha corpus" mode:@"exact" title:@"Alpha"];
            Check(NO, @"the injected query clobber must be detected");
        }
        for (NSUInteger history = 0; history < 4; history++) {
            NSLog(@"HISTORY %lu: hide/show, independent resize, mode, title, config, closure", (unsigned long)history);
            [self nv_kStateQuery:@"alpha corpus" mode:@"exact" title:history ? [NSString stringWithFormat:@"Alpha renamed %lu", (unsigned long)history-1] : @"Alpha"];
            [peer nv_kStateQuery:@"beta corpus" mode:@"fuzzy" title:@"Beta"];
            NSRect left = [window frame], right = [[peer window] frame];
            left.size.width = history % 2 ? 1200 : 480;
            right.size.width = history % 2 ? 480 : 900;
            [self setDualFieldIsVisible:NO]; [peer setDualFieldIsVisible:NO];
            [window setFrame:left display:YES]; [[peer window] setFrame:right display:YES]; Pump();
            [self nv_kFocus];
            Check(![[[peer window] toolbar] isVisible], @"showing one browser's toolbar leaves the peer hidden");
            [peer nv_kFocus];
            [self nv_activateBrowser]; [self bringFocusToControlField:self];
            NSTextView *queryEditor = (id)[field currentEditor];
            [queryEditor insertText:@"alpha corpus" replacementRange:NSMakeRange(0, [[queryEditor string] length])];
            [self nv_kWaitSearch]; [self revealNote:alpha options:0];
            [window makeFirstResponder:textView];
            NSString *title = [NSString stringWithFormat:@"Alpha renamed %lu", (unsigned long)history];
            [[app editingSessionForNote:alpha] setMetadataValue:title isTitle:YES];
            [self nv_kWaitSearch]; [peer nv_kWaitSearch]; Pump();
            [self nv_kStateQuery:@"alpha corpus" mode:@"exact" title:title];
            [peer nv_kStateQuery:@"beta corpus" mode:@"fuzzy" title:@"Beta"];
            NSMutableDictionary *configuration = [[[toolbar configurationDictionary] mutableCopy] autorelease];
            [configuration setObject:@[@"NewNote", @"Preview", @"More", @"Search"] forKey:@"TB Item Identifiers"];
            [toolbar setConfigurationFromDictionary:configuration];
            [self nv_kFocus];
            [self nv_kStateQuery:@"alpha corpus" mode:@"exact" title:title];
            [peer nv_kStateQuery:@"beta corpus" mode:@"fuzzy" title:@"Beta"];
            NSDictionary *state = [[peer browserWindowState] copy];
            [[peer window] close]; Pump();
            Check([[app browserControllers] count] == 1, @"closing the secondary browser releases its registration");
            [app newWindow:self]; Pump();
            peer = [[app browserControllers] lastObject];
            [peer restoreBrowserWindowState:state]; [state release];
            [peer nv_kWaitSearch]; Pump();
            [peer nv_kFocus];
            [self nv_kStateQuery:@"alpha corpus" mode:@"exact" title:title];
            [peer nv_kStateQuery:@"beta corpus" mode:@"fuzzy" title:@"Beta"];
            Check([library totalNoteCount] == 2, @"the transition history creates no extra notes");
        }
        [app saveWindowStates]; [prefsController synchronize];
        [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"KINGSBURY_PHASE_1_PASS checks=%lu", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
