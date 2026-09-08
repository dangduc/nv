- (void)nv_r2CheckObservers:(NSUInteger)expected {
    NSDictionary *observers = [prefsController valueForKey:@"selectorObservers"];
    for (NSString *selector in ViewSettingSelectors()) {
        NSArray *targets = [observers objectForKey:selector];
        Check([targets count] == expected, [NSString stringWithFormat:@"%@ has exactly %lu browser observers", selector, expected]);
        Check([[NSSet setWithArray:targets ?: @[]] count] == [targets count], @"preference observer list contains no duplicate target");
    }
}

- (void)nv_r2EditNote:(NoteObject *)note expected:(NSMutableString *)expected windows:(NSUInteger)windows label:(NSString *)label {
    NVApplicationController *app = [NVApplicationController sharedController];
    [self nv_activateBrowser]; [self setViewingNote:NO]; [window makeFirstResponder:textView];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    ResetCounters();
    double total = 0, minimum = DBL_MAX, maximum = 0;
    for (NSUInteger i = 0; i < 8; i++) {
        @autoreleasepool {
            double start = [NSDate timeIntervalSinceReferenceDate];
            [textView insertText:@"beta " replacementRange:NSMakeRange([[textView string] length], 0)];
            double elapsed = ([NSDate timeIntervalSinceReferenceDate] - start) * 1000;
            total += elapsed; minimum = MIN(minimum, elapsed); maximum = MAX(maximum, elapsed);
            [expected appendString:@"beta "];
            // Check before draining the event pool: the count must release temporary observers itself.
            Check([[[[app editingSessionForNote:note] textStorage] layoutManagers] count] == windows,
                @"native edit leaves exactly one source layout per attached window before pool drain");
        }
        Pump();
    }
    NSLog(@"MEASURE edit phase=%@ windows=%lu edits=8 count_calls=%lu count_ms=%.3f layout_calls=%lu pref_calls=%lu display_calls=%lu js_calls=%lu sync_total_ms=%.3f sync_min_ms=%.3f sync_max_ms=%.3f",
        label, windows, CountCalls, CountMilliseconds, LayoutCalls, PreferenceCalls, DisplayCalls, JSCalls, total, minimum, maximum);
    Check([[[note contentString] string] isEqual:expected], @"native edits commit the exact expected shared source");
    // The fixture starts with 20,000 words. Each five-character insertion adds one word.
    NSString *count = [NSString stringWithFormat:@"%lu words", 20000 + ([expected length] - 120000) / 5];
    for (AppController *browser in [app browserControllers])
        Check([[[browser valueForKey:@"wordCounter"] stringValue] isEqual:count], @"every attached window displays the current word count");
    Check(PreferenceCalls == 0 && DisplayCalls == 0 && JSCalls == 0, @"source edits cause no preference callbacks or viewer work");
}

- (void)nv_runTests {
    @try {
        Check(HasViewControls, @"fixture includes production View controls");
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        [prefsController setShowWordCount:YES]; // The legacy preference is inverted: YES hides the counter.
        NSMutableString *expected = [NSMutableString string];
        for (NSUInteger i = 0; i < 20000; i++) [expected appendString:@"alpha "];
        NoteObject *note = [MakeNote(library, @"Round 2 lifecycle measurement", expected) retain];
        [self revealNote:note options:0]; Pump();
        [prefsController setShowWordCount:NO];
        [self nv_r2CheckObservers:1];
        [self nv_r2EditNote:note expected:expected windows:1 label:@"before_churn"];

        NSUInteger deallocStart = BrowserDeallocs;
        for (NSUInteger cycle = 0; cycle < 12; cycle++) {
            @autoreleasepool {
                [app newWindow:self]; Pump();
                AppController *peer = [[app browserControllers] lastObject];
                [ClosedBrowserAddresses removeObject:[NSValue valueWithPointer:peer]];
                [peer revealNote:note options:0]; Pump();
                Check([[app browserControllers] count] == 2, @"open cycle adds exactly one browser");
                [self nv_r2CheckObservers:2];
                Check([[[[app editingSessionForNote:note] textStorage] layoutManagers] count] == 2,
                    @"open cycle attaches exactly one additional source layout");
                [prefsController setShowTitleInTopSection:cycle % 2 sender:nil];
                [prefsController setShowTagsInTopSection:cycle % 2 sender:nil];
                [prefsController setShowBodyControlsInTopSection:cycle % 2 sender:nil];
                [[peer window] performClose:self];
                [ClosedBrowserAddresses addObject:[NSValue valueWithPointer:peer]];
                Pump();
            }
            for (NSUInteger i = 0; i < 3; i++) Pump();
            Check([[app browserControllers] count] == 1, @"close cycle removes the additional browser");
            [self nv_r2CheckObservers:1];
            Check([[[[app editingSessionForNote:note] textStorage] layoutManagers] count] == 1,
                @"close cycle detaches the additional source layout");
            ResetCounters();
            [prefsController setShowTitleInTopSection:YES sender:nil];
            [prefsController setShowTagsInTopSection:YES sender:nil];
            [prefsController setShowBodyControlsInTopSection:YES sender:nil];
            [prefsController setShowNotesList:NO sender:nil];
            [prefsController setShowNotesList:YES sender:nil];
            [prefsController setShowWordCount:NO];
            NSLog(@"MEASURE lifecycle cycle=%lu open_browsers=%lu preference_callbacks=%lu closed_callbacks=%lu count_calls=%lu header_layouts=%lu shared_layouts=%lu browser_deallocs=%lu",
                cycle + 1, [[app browserControllers] count], PreferenceCalls, ClosedPreferenceCalls, CountCalls, LayoutCalls,
                [[[[app editingSessionForNote:note] textStorage] layoutManagers] count], BrowserDeallocs - deallocStart);
            Check(PreferenceCalls == 6 && ClosedPreferenceCalls == 0 && CountCalls == 1,
                @"six post-close settings reach only the surviving browser and perform one word count");
        }
        [self nv_r2EditNote:note expected:expected windows:1 label:@"after_churn"];
        while ([[app browserControllers] count] < 4) {
            [app newWindow:self]; Pump();
            AppController *peer = [[app browserControllers] lastObject];
            [ClosedBrowserAddresses removeObject:[NSValue valueWithPointer:peer]];
            [peer revealNote:note options:0]; Pump();
        }
        [self nv_r2CheckObservers:4];
        [self nv_r2EditNote:note expected:expected windows:4 label:@"four_windows"];

        [prefsController setShowTitleInTopSection:NO sender:nil];
        [prefsController setShowTagsInTopSection:NO sender:nil];
        [prefsController setShowBodyControlsInTopSection:NO sender:nil];
        for (NSUInteger i = 0; i < 4; i++) Pump();
        ResetCounters();
        double resizeTotal = 0;
        for (NSUInteger cycle = 0; cycle < 12; cycle++) {
            NSRect frame = [window frame];
            frame.size.width += cycle % 2 ? -80 : 80;
            frame.size.height += cycle % 2 ? -40 : 40;
            double start = [NSDate timeIntervalSinceReferenceDate];
            [window setFrame:frame display:YES]; [[window contentView] layoutSubtreeIfNeeded];
            resizeTotal += ([NSDate timeIntervalSinceReferenceDate] - start) * 1000;
            Pump();
            Check(![wordCounter isHidden] && NSContainsRect([splitSubview bounds], [wordCounter frame]),
                @"resize keeps the independently visible word counter inside the body header");
            Check([[[[app editingSessionForNote:note] textStorage] layoutManagers] count] == 4,
                @"resize preserves exactly four source layouts");
        }
        NSLog(@"MEASURE resize windows=4 resized_windows=1 commands=12 count_calls=%lu layout_calls=%lu pref_calls=%lu display_calls=%lu js_calls=%lu sync_total_ms=%.3f",
            CountCalls, LayoutCalls, PreferenceCalls, DisplayCalls, JSCalls, resizeTotal);
        Check(CountCalls == 0 && PreferenceCalls == 0 && DisplayCalls == 0 && JSCalls == 0,
            @"source resizing does not count words, dispatch preferences, or contact a viewer");

        NoteObject *html = [MakeNote(library, @"Mode cycles", @"<p>alpha beta gamma</p>") retain];
        [self revealNote:html options:0]; Pump();
        NSMenuItem *choice = [[[NSMenuItem alloc] init] autorelease]; [choice setRepresentedObject:@"html"];
        [self selectPreviewMode:choice];
        PreviewController *provider = [self valueForKey:@"previewController"];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (([provider loading] || [[provider webView] isLoading] || ![provider renderedHTML]) && [deadline timeIntervalSinceNow] > 0) Pump();
        Check(![provider loading] && ![[provider webView] isLoading] && [provider renderedHTML] != nil, @"mode fixture loads a real HTML viewer");
        for (NSUInteger i = 0; i < 8; i++) Pump();
        TraceJS = YES;
        for (NSUInteger cycle = 0; cycle < 4; cycle++) {
            ResetCounters();
            for (NSUInteger repeat = 0; repeat < 2; repeat++) {
                [prefsController setShowBodyControlsInTopSection:YES sender:nil];
                [prefsController setShowBodyControlsInTopSection:NO sender:nil];
                [prefsController setShowNotesList:NO sender:nil];
                [prefsController setShowNotesList:YES sender:nil]; Pump();
            }
            for (NSUInteger i = 0; i < 6; i++) Pump();
            NSLog(@"MEASURE visible_viewer_reflow cycle=%lu count_calls=%lu layout_calls=%lu pref_calls=%lu display_calls=%lu js_calls=%lu",
                cycle + 1, CountCalls, LayoutCalls, PreferenceCalls, DisplayCalls, JSCalls);
            Check(CountCalls == 0 && DisplayCalls == 0,
                @"visible viewer header and list changes cause no word count or render request");
            ResetCounters();
            [self toggleSourcePreview:self]; for (NSUInteger i = 0; i < 8; i++) Pump();
            Check(![self isViewingNote] && [[provider view] isHidden], @"Source command hides the existing viewer");
            NSUInteger sourceDisplays = DisplayCalls, sourceJS = JSCalls;
            [self toggleSourcePreview:self];
            deadline = [NSDate dateWithTimeIntervalSinceNow:10];
            while ([provider loading] && [deadline timeIntervalSinceNow] > 0) Pump();
            for (NSUInteger i = 0; i < 8; i++) Pump();
            NSLog(@"MEASURE mode_cycle cycle=%lu count_calls=%lu layout_calls=%lu source_display_calls=%lu source_js_calls=%lu total_display_calls=%lu total_js_calls=%lu",
                cycle + 1, CountCalls, LayoutCalls, sourceDisplays, sourceJS, DisplayCalls, JSCalls);
            Check([self isViewingNote] && ![[provider view] isHidden] && ![provider loading], @"Preview command returns to the same loaded viewer");
            Check([self valueForKey:@"previewController"] == provider && CountCalls == 0,
                @"Source/Preview cycle reuses its provider and does not count words");
            Check([[[[app editingSessionForNote:html] textStorage] layoutManagers] count] == 1,
                @"Source/Preview cycle preserves one shared source layout for its note");
        }
        Check([[[note contentString] string] isEqual:expected] && [[[html contentString] string] isEqual:@"<p>alpha beta gamma</p>"],
            @"all lifecycle, resize, and visibility commands preserve exact note source");
        [html release]; [note release];
        NSLog(@"DAN LUU ROUND 2 REVIEW PASSED: %lu checks", Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
