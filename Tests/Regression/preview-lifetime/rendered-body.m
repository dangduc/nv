    // The loaded harness must not be injected into external markup helpers.
    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        // NV_LIFETIME_INSTRUMENTATION
        NSAutoreleasePool *observationPool = [NSAutoreleasePool new];
        NSAutoreleasePool *batchPool = [NSAutoreleasePool new];
        NotationController *library = [app library];
        NoteObject *alpha = MakeNote(library, @"Preview Alpha", @"# Alpha readonly marker");
        NoteObject *beta = MakeNote(library, @"Preview Beta", @"# Beta readonly marker");
        [self revealNote:alpha options:0]; Pump();
        Check([self valueForKey:@"previewController"] == nil, @"initial provider remains lazy until Preview is selected");
        [self setViewingNote:YES];
        PreviewController *pa = [self valueForKey:@"previewController"];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
        while ([pa loading] && [deadline timeIntervalSinceNow] > 0) Pump();
        Check(![pa loading] && ![pa renderError] && [[pa renderedHTML] containsString:@"Alpha readonly marker"], @"initial viewer renders its owning browser note");
        Check([[pa view] window] == [self window], @"initial viewer is embedded in its browser window");
        [app newWindow:self]; Pump();
        AppController *second = [[app browserControllers] lastObject];
        [second revealNote:beta options:0]; Pump();
        Check([second valueForKey:@"previewController"] == nil, @"second source browser has no viewer before mode selection");
        [second setViewingNote:YES];
        PreviewController *pb = [second valueForKey:@"previewController"];
        deadline = [NSDate dateWithTimeIntervalSinceNow:12];
        while ([pb loading] && [deadline timeIntervalSinceNow] > 0) Pump();
        Check(![pb loading] && ![pb renderError] && [[pb renderedHTML] containsString:@"Beta readonly marker"], @"second viewer renders its owning browser note");
        Check([[pb view] window] == [second window] && [pa webView] != [pb webView], @"browsers own separate inline WK views");
        __block BOOL inspected = NO;
        [[pb webView] evaluateJavaScript:@"typeof Cocoa" completionHandler:^(id value, NSError *error) {
            Check(error == nil && [value isEqual:@"undefined"], @"rendered documents have no application script bridge"); inspected = YES;
        }];
        deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!inspected && [deadline timeIntervalSinceNow] > 0) Pump();
        Check(inspected, @"WebKit confirms the removed bridge without test repairs");
        for (AppController *browser in [app browserControllers]) [[browser window] close];
        Pump(); [batchPool drain]; Pump();
        Check([[app browserControllers] count] == 0, @"all browsers close without closing the shared library");
        Check([self valueForKey:@"previewController"] == nil, @"closing the initial service window releases its inline provider");
        for (int cycle = 0; cycle < 4; cycle++) {
            NSAutoreleasePool *pool = [NSAutoreleasePool new];
            [(id)app applicationShouldHandleReopen:NSApp hasVisibleWindows:NO]; Pump();
            AppController *browser = [[app browserControllers] lastObject];
            Check([[app browserControllers] count] == 1 && [browser sharedNotationController] == library, @"reopen keeps one browser on the same shared library");
            [browser revealNote:cycle % 2 ? beta : alpha options:0]; Pump();
            [browser setViewingNote:YES];
            PreviewController *preview = [browser valueForKey:@"previewController"];
            deadline = [NSDate dateWithTimeIntervalSinceNow:12];
            while ([preview loading] && [deadline timeIntervalSinceNow] > 0) Pump();
            NSString *marker = cycle % 2 ? @"Beta readonly marker" : @"Alpha readonly marker";
            Check(![preview loading] && ![preview renderError] && [[preview renderedHTML] containsString:marker], @"reopened browser viewer renders its current note");
            [[browser window] close]; Pump();
            [pool drain]; Pump();
            Check([[app browserControllers] count] == 0, @"closing a reopened browser leaves no tracked browser");
        }
        [observationPool drain];
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ((editorDeaths < 5 || webDeaths < 6 || previewDeaths < 6) && [deadline timeIntervalSinceNow] > 0) {
            NSAutoreleasePool *pool = [NSAutoreleasePool new]; Pump(); [pool drain];
        }
        NSLog(@"RENDERED LIFETIME browsers=%lu editors=%lu viewerBirths=%lu viewerDeaths=%lu WKBirths=%lu WKDeaths=%lu", (unsigned long)browserDeaths, (unsigned long)editorDeaths, (unsigned long)previewBirths, (unsigned long)previewDeaths, (unsigned long)webBirths, (unsigned long)webDeaths);
        Check(browserDeaths == 5 && editorDeaths == 5, @"all five additional rendered browsers and editors deallocate");
        Check(previewBirths == 6 && previewDeaths == 6, @"all six inline providers deallocate, including the initial window provider");
        Check(webBirths == 6 && webDeaths == 6, @"all six rendered WKWebViews deallocate without ownership repairs");
        Check([[GlobalPrefs defaultPrefs] noteBodyFont] != nil && [[library allNotes] count] == 2, @"initial service owner and shared library remain usable after all windows close");
        Check([[[alpha contentString] string] isEqual:@"# Alpha readonly marker"] && [[[beta contentString] string] isEqual:@"# Beta readonly marker"], @"rendering and browser teardown preserve both source notes");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"RENDERED PREVIEW CHECKS PASSED (%lu)", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
@end
