- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSInteger phase = atoi(getenv("NV_REVIEW_PHASE"));
        if (phase == 2) {
            NSDictionary *expected = @{@"Workflow α / 😀": @"alpha source before-quit committed-on-quit",
                @"Workflow β ? #": @"beta source before-quit committed-on-quit"};
            Check([[library allNotes] count] == [expected count], @"relaunch has exactly the two local notes");
            for (NoteObject *note in [library allNotes]) {
                Check([[[note contentString] string] isEqual:expected[titleOfNote(note)]],
                    [NSString stringWithFormat:@"normal termination preserved both composition commits: %@", titleOfNote(note)]);
            }
            Check(![[GlobalPrefs defaultPrefs] highlightSearchTerms], @"preference changed in native window survives termination and relaunch");
            NSLog(@"WORKFLOW ROUND1 phase2: %lu checks passed", (unsigned long)Checks);
            [NSApp terminate:self]; return;
        }
        NoteObject *alpha = MakeNote(library, @"Workflow α / 😀", @"alpha source");
        NoteObject *beta = MakeNote(library, @"Workflow β ? #", @"beta source");
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self && [peer sharedNotationController] == library, @"two native windows share one local library");
        [self searchForString:@"alpha"]; [self revealNote:alpha options:0];
        [peer searchForString:@"beta"]; [peer revealNote:beta options:0]; Pump();

        NSArray *configurations = @[@[@"Sync"], @[@"Sync", @"NewNote"], @[@"NewNote", @"Sync", @"Search"],
            @[@"Sync", NSToolbarFlexibleSpaceItemIdentifier], @[@"More", @"Preview"], @[]];
        NSLog(@"Observed native toolbar configuration keys: %@", [[toolbar configurationDictionary] allKeys]);
        for (NSUInteger index = 0; index < [configurations count]; index++) {
            NSMutableDictionary *configuration = [[toolbar configurationDictionary] mutableCopy];
            configuration[@"TB Item Identifiers"] = configurations[index];
            [toolbar setConfigurationFromDictionary:configuration]; [configuration release]; Pump();
            NSArray *identifiers = [[toolbar items] valueForKey:@"itemIdentifier"];
            NSLog(@"Legacy toolbar history %lu requested=%@ restored=%@", (unsigned long)index, configurations[index], identifiers);
            Check(![identifiers containsObject:@"Sync"], @"native restoration discards the removed Sync identifier");
            [toolbar setVisible:NO];
            [self nv_activateBrowser]; [self bringFocusToControlField:self];
            for (NSUInteger i = 0; i < 5; i++) Pump();
            Check([toolbar isVisible] && [field currentEditor] && [field window] == window &&
                ![field isHiddenOrHasHiddenAncestor], @"Search restores a usable toolbar from an obsolete or empty saved configuration");
            NSPredicate *isSearch = [NSPredicate predicateWithFormat:@"itemIdentifier == %@", @"Search"];
            Check([[[toolbar items] filteredArrayUsingPredicate:isSearch] count] == 1, @"restoration leaves exactly one Search item");
            Check([self selectedNoteObject] == alpha && [[[self browserSession] searchString] isEqual:@"alpha"] &&
                [peer selectedNoteObject] == beta && [[[peer browserSession] searchString] isEqual:@"beta"],
                @"toolbar migration preserves both window queries and note selections");
        }

        // Use the actual unique-note URL and the application Apple event router.
        // UUID routing must remain valid after the old sync-ID alternative disappears.
        for (NSUInteger index = 0; index < 2; index++) {
            AppController *active = index == 0 ? self : peer;
            AppController *inactive = index == 0 ? peer : self;
            NoteObject *target = index == 0 ? beta : alpha;
            NoteObject *inactiveNote = [inactive selectedNoteObject];
            NSString *inactiveQuery = [[[inactive browserSession] searchString] copy];
            [active nv_activateBrowser];
            NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass
                eventID:kAEGetURL targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
            [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:[[target uniqueNoteLink] absoluteString]]
                forKeyword:keyDirectObject];
            [app handleGetURLEvent:event withReplyEvent:nil]; Pump();
            Check([active selectedNoteObject] == target, @"local UUID note URL reaches the active browser with Unicode and URL punctuation");
            Check([inactive selectedNoteObject] == inactiveNote && [[[inactive browserSession] searchString] isEqual:inactiveQuery],
                @"local URL navigation leaves the inactive browser unchanged");
            [inactiveQuery release];
        }

        // Exercise remaining preference panes through their native toolbar actions.
        // The copied-app harness bypasses applicationDidFinishLaunching:, which owns this construction.
        prefsWindowController = [[PrefsWindowController alloc] init];
        [self showPreferencesWindow:self]; Pump();
        PrefsWindowController *preferences = [self valueForKey:@"prefsWindowController"];
        NSWindow *preferencesWindow = [preferences valueForKey:@"window"];
        Check([preferencesWindow isVisible], @"remaining Preferences window opens");
        NSToolbar *preferencesToolbar = [preferences valueForKey:@"toolbar"];
        for (NSToolbarItem *item in [preferencesToolbar items]) {
            [preferences switchViews:item]; Pump();
            Check([[preferencesWindow contentView] subviews].count > 0 && [preferencesWindow isVisible],
                [NSString stringWithFormat:@"native preference pane remains usable: %@", [item itemIdentifier]]);
        }
        NSButton *highlight = [preferences valueForKey:@"highlightSearchTermsButton"];
        [highlight setState:NSControlStateValueOff]; [preferences changedHighlightSearchTerms:highlight];
        Check(![[GlobalPrefs defaultPrefs] highlightSearchTerms], @"remaining preference action updates the shared setting");
        [preferencesWindow performClose:self]; Pump();
        Check(![preferencesWindow isVisible] && [[app browserControllers] count] == 2,
            @"closing Preferences keeps both browser windows alive");
        [self showPreferencesWindow:self]; Pump();
        Check([highlight state] == NSControlStateValueOff && [preferencesWindow isVisible], @"reopening Preferences retains the changed local setting");
        [preferencesWindow performClose:self]; Pump();

        [self searchForString:@""]; [peer searchForString:@""];
        [self revealNote:alpha options:0]; [peer revealNote:beta options:0]; Pump();
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        [textView setMarkedText:@" before-quit" selectedRange:NSMakeRange(12, 0) replacementRange:NSMakeRange([[textView string] length], 0)];
        [peerEditor setMarkedText:@" before-quit" selectedRange:NSMakeRange(12, 0) replacementRange:NSMakeRange([[peerEditor string] length], 0)];
        Check([textView hasMarkedText] && [peerEditor hasMarkedText], @"two different note editors hold pending native compositions before termination");
        Check([[[alpha contentString] string] isEqual:@"alpha source"] && [[[beta contentString] string] isEqual:@"beta source"],
            @"composition fixtures are still uncommitted in both note models");
        if (getenv("NV_WORKFLOW_SKIP_FINISH_EDITING")) {
            Swap([NVApplicationController class], @selector(applicationShouldTerminate:), @selector(nv_workflowPrematureTermination:));
        }
        NSDate *start = [NSDate date];
        NSApplicationTerminateReply reply = [(id<NSApplicationDelegate>)app applicationShouldTerminate:NSApp];
        NSLog(@"Termination decision duration: %.6f seconds", -[start timeIntervalSinceNow]);
        Check(reply == NSTerminateNow && ![textView hasMarkedText] && ![peerEditor hasMarkedText],
            @"termination completes all window compositions and returns immediately without remote wait");
        Check([[[alpha contentString] string] isEqual:@"alpha source before-quit"] &&
            [[[beta contentString] string] isEqual:@"beta source before-quit"], @"termination decision commits pending source in both note models");
        // Re-stage input to ensure the real NSApplication termination repeats the path.
        for (LinkingEditor *editor in @[textView, peerEditor]) {
            [editor setMarkedText:@" committed-on-quit" selectedRange:NSMakeRange(18, 0)
                replacementRange:NSMakeRange([[editor string] length], 0)];
            Check([editor hasMarkedText], @"normal application quit starts with a pending source composition");
        }
        NSLog(@"WORKFLOW ROUND1 phase1: %lu checks passed; invoking normal termination with unflushed pending input", (unsigned long)Checks);
        [NSApp terminate:self];
    } @catch (NSException *exception) { NSLog(@"FAIL: workflow exception %@", exception); exit(1); }
}
