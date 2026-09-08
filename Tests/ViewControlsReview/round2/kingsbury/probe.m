- (id)nv_k2JavaScript:(NSString *)script preview:(PreviewController *)preview {
    __block BOOL done = NO;
    __block id result = nil;
    [[preview webView] evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
        Check(error == nil, @"WebKit completes the bounded DOM observation");
        result = [value retain]; done = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (!done && [deadline timeIntervalSinceNow] > 0) Pump();
    Check(done, @"DOM observation completes before its deadline");
    return [result autorelease];
}
- (void)nv_k2Wait:(PreviewController *)preview {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
    while ([preview loading] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check(preview && ![preview loading] && ![preview renderError], @"the mixed-mode browser completes its native preview");
}
- (void)nv_k2Hidden:(NSArray *)browsers {
    for (AppController *browser in browsers) {
        Check([[[browser valueForKey:@"browserSplitController"] splitViewItems][0] isCollapsed] &&
            [[browser valueForKey:@"noteTitleField"] isHidden] && [[browser valueForKey:@"noteTagsField"] isHidden] &&
            [[browser valueForKey:@"bodyModeControl"] isHidden], @"Source and Preview windows both keep the actual list and header controls hidden");
    }
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSUInteger phase = strtoul(getenv("NV_REVIEW_PHASE") ?: "1", NULL, 10);
        NSString *markerPath = [TestDirectory stringByAppendingPathComponent:@"mixed-mode.plist"];
        if (phase == 1) {
            NSMutableString *body = [NSMutableString string];
            for (NSUInteger i = 0; i < 350; i++) [body appendFormat:@"Paragraph %lu: source remains intact across layout and mode transitions.\n\n", (unsigned long)i];
            NoteObject *alpha = MakeNote(library, @"Mixed Alpha", body);
            NoteObject *beta = MakeNote(library, @"Mixed Beta", [@"# Beta preview\n\n" stringByAppendingString:body]);
            [app newWindow:self]; Pump();
            AppController *peer = [[app browserControllers] lastObject];
            [self revealNote:alpha options:0]; [peer revealNote:beta options:0];
            for (AppController *browser in [app browserControllers]) {
                NSRect frame = [[browser window] frame]; frame.size = NSMakeSize(780, 700);
                [[browser window] setFrame:frame display:YES];
            }
            for (NSUInteger i = 0; i < 6; i++) Pump();
            [self setNotesListHeight:125]; [peer setNotesListHeight:175];
            [textView setSelectedRange:NSMakeRange(240, 7)];
            [[textView layoutManager] ensureLayoutForTextContainer:[textView textContainer]];
            [textView scrollPoint:NSMakePoint(0, 500)];
            LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
            [peerEditor setSelectedRange:NSMakeRange(350, 9)];
            [[peerEditor layoutManager] ensureLayoutForTextContainer:[peerEditor textContainer]];
            [peerEditor scrollPoint:NSMakePoint(0, 650)];
            [peer setViewingNote:YES];
            PreviewController *preview = [peer valueForKey:@"previewController"];
            [self nv_k2Wait:preview];
            [self nv_k2JavaScript:@"window.scrollTo(0,700); window.scrollY" preview:preview];
            [prefsController setShowWordCount:YES];
            [prefsController setShowTitleInTopSection:NO sender:nil];
            [prefsController setShowTagsInTopSection:NO sender:nil];
            [prefsController setShowBodyControlsInTopSection:NO sender:nil];
            [prefsController setShowNotesList:NO sender:nil]; Pump();
            [self nv_k2Hidden:[app browserControllers]];
            [peer nv_activateBrowser];
            NSMenuItem *syntax = [[[NSMenuItem alloc] initWithTitle:@"JSON" action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
            [syntax setRepresentedObject:@"json"];
            Check([NSApp sendAction:[syntax action] to:app from:syntax], @"Syntax dispatch reaches the active Preview browser while controls are hidden");
            for (NSUInteger i = 0; i < 5; i++) Pump();
            [self nv_k2Wait:preview];
            Check([[beta sourceSyntaxIdentifier] isEqual:@"json"] && [[alpha sourceSyntaxIdentifier] isEqual:@"plain"],
                @"hidden Syntax command changes only the active note's local syntax");
            Check([[preview viewerIdentifier] isEqual:@"markdown"], @"local JSON syntax leaves the peer Markdown viewer selected");
            Check(NSEqualRanges([textView selectedRange], NSMakeRange(240,7)) && NSEqualRanges([peerEditor selectedRange], NSMakeRange(350,9)),
                @"visibility and syntax transitions preserve both independent source selections");
            Check([[textView string] isEqual:body] && [[peerEditor string] isEqual:[[beta contentString] string]],
                @"visibility and local syntax transitions preserve both source bodies");
            Check(fabs([[textScrollView contentView] bounds].origin.y - 500) < 1,
                @"collapsing the list and header preserves the visible source viewport");
            [self nv_k2JavaScript:@"window.scrollTo(0,700); window.scrollY" preview:preview];
            __block BOOL captured = NO;
            [preview captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) { captured = YES; }];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while (!captured && [deadline timeIntervalSinceNow] > 0) Pump();
            Check(captured, @"the persistence checkpoint includes a completed DOM capture");
            Check([@{@"alpha": [[alpha contentString] string], @"beta": [[beta contentString] string]}
                writeToFile:markerPath atomically:YES], @"independent expected source bodies are saved outside application state");
            [app saveWindowStates]; [prefsController synchronize];
            [library flushAllNoteChanges]; [library closeJournal];
            NSLog(@"KINGSBURY ROUND 2 PHASE 1 PASSED: %lu checks", (unsigned long)Checks); exit(0);
        }
        NSArray *browsers = [app browserControllers];
        Check([browsers count] == 2, @"a second app process restores both mixed-mode browsers");
        AppController *sourceBrowser = browsers[0], *peer = browsers[1];
        Check(![[sourceBrowser valueForKey:@"viewingNote"] boolValue] && [[peer valueForKey:@"viewingNote"] boolValue],
            @"normal relaunch restores independent Source and Preview modes");
        [self nv_k2Hidden:browsers];
        NoteObject *alpha = [sourceBrowser selectedNoteObject], *beta = [[peer selectedNoteObject] retain];
        NSDictionary *marker = [NSDictionary dictionaryWithContentsOfFile:markerPath];
        Check([titleOfNote(alpha) isEqual:@"Mixed Alpha"] && [titleOfNote(beta) isEqual:@"Mixed Beta"],
            @"hidden-list restoration selects the original note in each mixed-mode window");
        Check([[[alpha contentString] string] isEqual:marker[@"alpha"]] && [[[beta contentString] string] isEqual:marker[@"beta"]],
            @"both exact source bodies survive the process boundary");
        Check([[alpha sourceSyntaxIdentifier] isEqual:@"plain"] && [[beta sourceSyntaxIdentifier] isEqual:@"json"],
            @"relaunch retains the independent local syntax metadata");
        LinkingEditor *sourceEditor = [sourceBrowser valueForKey:@"textView"], *peerEditor = [peer valueForKey:@"textView"];
        Check(NSEqualRanges([sourceEditor selectedRange], NSMakeRange(240,7)) && NSEqualRanges([peerEditor selectedRange], NSMakeRange(350,9)),
            @"normal relaunch retains both visible and hidden source selections");
        PreviewController *preview = [peer valueForKey:@"previewController"];
        [self nv_k2Wait:preview];
        Check([[preview renderedHTML] containsString:@"Beta preview"] && [[preview viewerIdentifier] isEqual:@"markdown"],
            @"the restored hidden-control viewer renders the correct note and format");
        CGFloat restoredY = [[self nv_k2JavaScript:@"window.scrollY" preview:preview] doubleValue];
        NSLog(@"OBSERVED restored preview scroll=%g", restoredY);
        Check(fabs(restoredY - 700) < 2, @"the completed preview viewport capture survives normal relaunch");
        [peer setViewingNote:NO]; Pump();
        CGFloat sourceY = [[(NSScrollView *)[peer valueForKey:@"textScrollView"] contentView] bounds].origin.y;
        NSLog(@"OBSERVED restored hidden source scroll=%g", sourceY);
        // Record independently of the PR oracle: the legacy restoration path
        // may clamp this before any newly added visibility callback runs.
        NSLog(@"OBSERVATION: source viewport after restored Preview expected=650 actual=%g", sourceY);
        [peer setViewingNote:YES]; [self nv_k2Wait:[peer valueForKey:@"previewController"]];
        preview = [peer valueForKey:@"previewController"];
        [peer captureBodyPresentation];
        Check([preview hasPendingViewerStateCaptureForSnapshot:[preview snapshot] viewerIdentifier:[preview viewerIdentifier]],
            @"deletion history begins with an outstanding exact viewport capture");
        [[library undoManager] removeAllActions];
        [library removeNote:beta];
        [prefsController setShowTitleInTopSection:YES sender:nil];
        [prefsController setShowNotesList:YES sender:nil];
        [prefsController setShowTitleInTopSection:NO sender:nil];
        [prefsController setShowNotesList:NO sender:nil];
        Pump();
        Check(![[library allNotes] containsObject:beta], @"the preview note is deleted while view preferences change");
        [[library undoManager] undo]; Pump();
        [peer revealNote:beta options:0]; [peer setViewingNote:YES];
        [self nv_k2Wait:[peer valueForKey:@"previewController"]];
        for (NSUInteger i = 0; i < 10; i++) Pump();
        [self nv_k2Hidden:browsers];
        Check([[library allNotes] containsObject:beta] && [[beta sourceSyntaxIdentifier] isEqual:@"json"] &&
            [[[beta contentString] string] isEqual:marker[@"beta"]], @"deletion Undo restores the exact note body and local syntax after pending capture completion");
        Check([sourceBrowser selectedNoteObject] == alpha && [[sourceEditor string] isEqual:marker[@"alpha"]] &&
            NSEqualRanges([sourceEditor selectedRange], NSMakeRange(240,7)), @"the peer deletion history leaves the Source browser's selection and body intact");
        [prefsController setShowNotesList:YES sender:nil]; Pump();
        Check(fabs([sourceBrowser notesListHeight]-125)<1 && fabs([peer notesListHeight]-175)<1,
            @"mixed-mode relaunch and deletion Undo retain both expanded list heights");
        [beta release]; [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"KINGSBURY ROUND 2 PHASE 2 PASSED: %lu checks", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
