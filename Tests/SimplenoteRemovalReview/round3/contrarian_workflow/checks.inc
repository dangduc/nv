- (void)nv_runTests {
    @try {
        NVApplicationController *coordinator = [NVApplicationController sharedController];
        NotationController *library = [coordinator library];
        GlobalPrefs *global = [GlobalPrefs defaultPrefs];
        NSString *expectationPath = [TestDirectory stringByAppendingPathComponent:@"workflow-expected.plist"];
        Check([NSApp delegate] == coordinator, @"actual application delegate owns command routing");
        Check(![global quitWhenClosingWindow], @"isolated launch disables quit after closing the last browser");

        if (atoi(getenv("NV_REVIEW_PHASE")) == 2) {
            NSDictionary *expected = [NSDictionary dictionaryWithContentsOfFile:expectationPath];
            Check([expected count] == 2 && [[library allNotes] count] == 2, @"fresh process reopens exactly the two expected local notes");
            for (NoteObject *note in [library allNotes]) {
                NSString *uuid = [NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]];
                NSDictionary *record = expected[uuid];
                Check(record != nil, @"reopened note retains its exact UUID");
                Check([titleOfNote(note) isEqual:record[@"title"]], @"reopened note retains its title");
                Check([[[note contentString] string] isEqual:record[@"source"]], @"pending source committed by browser closure survives normal quit and process restart");
                Check([labelsOfNote(note) isEqual:record[@"tags"]], @"reopened note retains its tags");
                Check([[note sourceSyntaxIdentifier] isEqual:record[@"syntax"]], @"reopened note retains locally stored syntax");
            }
            Check(![global highlightSearchTerms], @"preference set through retained initial-browser bridge survives restart");
            NSLog(@"WORKFLOW ROUND3 phase2: %lu checks passed", (unsigned long)Checks);
            [NSApp terminate:self]; return;
        }

        // This runner substitutes applicationDidFinishLaunching:, so reproduce
        // its Preferences controller construction without running real startup.
        PrefsWindowController *preferences = [[PrefsWindowController alloc] init];
        [self setValue:preferences forKey:@"prefsWindowController"];
        [preferences release];
        [global setQuitWhenClosingWindow:NO sender:self];
        NoteObject *alpha = MakeNote(library, @"Closure α # / 😀", @"alpha source");
        NoteObject *beta = MakeNote(library, @"Closure β ?", @"beta source");
        [alpha setLabelString:@"local,alpha"];
        [beta setLabelString:@"local,beta"];
        [alpha setSourceSyntaxIdentifier:@"json"];
        [beta setSourceSyntaxIdentifier:@"markdown"];
        [coordinator newWindow:self]; Pump();
        AppController *peer = [[coordinator browserControllers] lastObject];
        Check([[coordinator browserControllers] count] == 2 && peer != self &&
            [peer sharedNotationController] == library, @"two native browser controllers share the same library before closure");
        [self searchForString:@""]; [self revealNote:alpha options:0];
        [peer searchForString:@""]; [peer revealNote:beta options:0]; Pump();
        Check([library flushAllNoteChanges], @"checkpoint establishes original note bodies before pending source edits");

        for (AppController *browser in @[self, peer]) {
            LinkingEditor *editor = [browser valueForKey:@"textView"];
            [editor setMarkedText:@" pending-close" selectedRange:NSMakeRange(14, 0)
                replacementRange:NSMakeRange([[editor string] length], 0)];
            Check([editor hasMarkedText], @"native source editor has an unfinished composition before window closure");
        }
        Check([[[alpha contentString] string] isEqual:@"alpha source"] &&
            [[[beta contentString] string] isEqual:@"beta source"], @"both note models still hold their checkpoint bodies");
        [[peer window] performClose:self]; Pump();
        Check([[coordinator browserControllers] count] == 1 &&
            [[[beta contentString] string] isEqual:@"beta source pending-close"], @"closing an additional browser commits its pending source and unregisters it");
        [[self window] performClose:self]; Pump();
        Check([[coordinator browserControllers] count] == 0, @"closing the initial browser leaves no registered browser windows");
        Check([coordinator library] == library && [self sharedNotationController] == library &&
            [coordinator activeBrowser] == self, @"coordinator retains the shared library and initial application-services bridge without browser windows");
        Check([[[alpha contentString] string] isEqual:@"alpha source pending-close"], @"closing the last browser commits the initial editor's pending source");

        Check([NSApp sendAction:@selector(showPreferencesWindow:) to:coordinator from:self],
            @"Preferences action reaches the coordinator while no browser window exists");
        Pump();
        NSWindow *preferencesWindow = [preferences valueForKey:@"window"];
        Check([preferencesWindow isVisible] && [[coordinator browserControllers] count] == 0,
            @"retained initial-browser bridge opens Preferences without creating a browser");
        NSButton *highlight = [preferences valueForKey:@"highlightSearchTermsButton"];
        Check(highlight != nil, @"remaining native preference action has its connected control");
        [highlight setState:NSControlStateValueOff];
        [preferences changedHighlightSearchTerms:highlight];
        Check(![global highlightSearchTerms], @"native Preferences action updates its setting without browser windows");
        [preferencesWindow performClose:self]; Pump();

        // Sensitivity control still recreates a browser, but omits forwarding
        // the URL to its normal note-reveal path.
        if (getenv("NV_R3_OMIT_URL_REVEAL"))
            Swap([NVApplicationController class], @selector(handleGetURLEvent:withReplyEvent:),
                @selector(review_omitURLReveal:withReplyEvent:));
        NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass
            eventID:kAEGetURL targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
        [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:[[alpha uniqueNoteLink] absoluteString]]
            forKeyword:keyDirectObject];
        [(id)[NSApp delegate] handleGetURLEvent:event withReplyEvent:nil]; Pump();
        Check([[coordinator browserControllers] count] == 1, @"local UUID URL recreates exactly one browser after every browser closed");
        AppController *recreated = [coordinator activeBrowser];
        Check(recreated != self && [recreated sharedNotationController] == library && [[recreated window] isVisible],
            @"URL-created browser attaches to the existing shared library and becomes visible");
        Check([recreated selectedNoteObject] == alpha && [[library allNotes] count] == 2,
            @"local UUID URL selects the exact existing note without creating a duplicate");
        LinkingEditor *recreatedEditor = [recreated valueForKey:@"textView"];
        Check([[recreatedEditor string] isEqual:@"alpha source pending-close"], @"URL-created editor displays source committed at closure");
        [recreatedEditor setMarkedText:@" second-close" selectedRange:NSMakeRange(13, 0)
            replacementRange:NSMakeRange([[recreatedEditor string] length], 0)];
        Check([recreatedEditor hasMarkedText] &&
            [[[alpha contentString] string] isEqual:@"alpha source pending-close"], @"recreated browser holds a second uncommitted source composition");
        [[recreated window] performClose:self]; Pump();
        Check([[coordinator browserControllers] count] == 0 &&
            [[[alpha contentString] string] isEqual:@"alpha source pending-close second-close"], @"closing the URL-created browser also commits its pending source");

        Check([(id)[NSApp delegate] applicationShouldHandleReopen:NSApp hasVisibleWindows:NO],
            @"application reopen request reports it was handled");
        Pump(); recreated = [coordinator activeBrowser];
        Check([[coordinator browserControllers] count] == 1 && recreated != self &&
            [recreated sharedNotationController] == library && [[recreated window] isVisible],
            @"application reopen creates one visible browser using the retained library");
        [recreated searchForString:@""]; [recreated revealNote:alpha options:0]; Pump();
        Check([recreated selectedNoteObject] == alpha &&
            [[[recreated valueForKey:@"textView"] string] isEqual:@"alpha source pending-close second-close"],
            @"reopened browser can reach the existing note and both closure commits");
        [[recreated window] performClose:self]; Pump();
        Check([[coordinator browserControllers] count] == 0, @"application-reopened browser can close normally");

        Check([(id)[NSApp delegate] applicationOpenUntitledFile:NSApp], @"Open Untitled application command reports it was handled");
        Pump(); recreated = [coordinator activeBrowser];
        Check([[coordinator browserControllers] count] == 1 && [recreated sharedNotationController] == library &&
            [[library allNotes] count] == 2, @"Open Untitled recreates a browser without inventing an empty note");
        [recreated searchForString:@"Closure β"]; [recreated revealNote:beta options:0]; Pump();
        Check([recreated selectedNoteObject] == beta &&
            [[[recreated valueForKey:@"textView"] string] isEqual:@"beta source pending-close"],
            @"local search and selection remain usable after repeated zero-window intervals");
        [[recreated window] performClose:self]; Pump();
        Check([[coordinator browserControllers] count] == 0 && [coordinator library] == library,
            @"normal termination will start with no browser windows and the retained local library");

        NSMutableDictionary *expected = [NSMutableDictionary dictionary];
        for (NoteObject *note in @[alpha, beta]) {
            NSString *uuid = [NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]];
            expected[uuid] = @{@"title": titleOfNote(note), @"source": [[note contentString] string],
                @"tags": labelsOfNote(note), @"syntax": [note sourceSyntaxIdentifier]};
        }
        Check([expected writeToFile:expectationPath atomically:YES], @"independent expected identity and text manifest is written outside the notes library");
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"WORKFLOW ROUND3 phase1: %lu checks passed; normal quit from zero browser windows", (unsigned long)Checks);
        [NSApp terminate:self];
    } @catch (NSException *exception) {
        NSLog(@"FAIL: workflow closure review exception %@", exception); exit(1);
    }
}
