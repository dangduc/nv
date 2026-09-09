- (NSDictionary *)nv_luuGeometry:(NSString *)phase scenario:(NSString *)scenario {
    NSRect frame = [field convertRect:[field bounds] toView:nil];
    NSView *container = [dualFieldItem view];
    CGFloat width = NSWidth([window frame]);
    BOOL fills = NSWidth(frame) >= width - 130 && width - NSMaxX(frame) >= 0 && width - NSMaxX(frame) <= 30;
    BOOL attached = [field window] == window && ![field isHiddenOrHasHiddenAncestor];
    BOOL constrained = NSEqualRects([field frame], [container bounds]);
    NSDictionary *row = @{@"scenario": scenario, @"phase": phase,
        @"windowWidth": @(width), @"searchWidth": @(NSWidth(frame)),
        @"leading": @(NSMinX(frame)), @"trailing": @(width - NSMaxX(frame)),
        @"height": @(NSHeight(frame)), @"attached": @(attached), @"fills": @(fills),
        @"constrained": @(constrained), @"activeFieldEditor": @([field currentEditor] != nil)};
    NSLog(@"GEOMETRY %@", row);
    Check(fills && attached && constrained && NSHeight(frame) >= 24,
        [NSString stringWithFormat:@"%@ %@: attached Search fills available toolbar width", scenario, phase]);
    return row;
}

- (void)nv_luuWaitPreview:(PreviewController *)provider {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    NSLog(@"PREVIEW_WAIT before providerLoading=%d webLoading=%d rendered=%d error=%@",
        [provider loading], [[provider webView] isLoading], [provider renderedHTML] != nil, [provider renderError]);
    while (([provider loading] || [[provider webView] isLoading] || ![provider renderedHTML]) &&
        [deadline timeIntervalSinceNow] > 0) Pump();
    Check([self isViewingNote] && ![[provider view] isHidden] && [provider renderedHTML] &&
        ![provider loading] && ![[provider webView] isLoading], @"Preview contains a completed real HTML render");
}

- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSMutableString *longQuery = [NSMutableString string];
        for (NSUInteger i = 0; i < 1024; i++) [longQuery appendString:@"x"];
        NSMutableString *source = [NSMutableString stringWithFormat:@"<html><body><p>%@</p>", longQuery];
        for (NSUInteger i = 0; i < 120; i++) [source appendFormat:@"<p>Paragraph %lu: alpha beta gamma delta.</p>", (unsigned long)i];
        [source appendString:@"</body></html>"];
        NoteObject *note = [MakeNote(library, @"Actual browser geometry", source) retain];
        [self revealNote:note options:0]; Pump();
        [self nv_activateBrowser];
        [prefsController setShowWordCount:YES]; // Hide the independently controlled word count.
        [window setFrame:NSMakeRect(100, 100, 780, 660) display:YES]; Pump();
        Check([self valueForKey:@"previewController"] == nil, @"Source starts without a preview provider");
        Check([window titleVisibility] == NSWindowTitleHidden && [[window title] isEqual:titleOfNote(note)],
            @"native window title remains available while its title-bar display is hidden");

        if (getenv("NV_TITLEBAR_CAP_WIDTH")) {
            [dualFieldItem setMaxSize:NSMakeSize(325, 24)];
            [window setFrame:NSMakeRect(100, 100, 1200, 660) display:YES];
            [[[window contentView] superview] layoutSubtreeIfNeeded]; Pump();
            [self nv_luuGeometry:@"settled" scenario:@"negative-control-max-width-325"];
            Check(NO, @"the independent width-cap negative control must fail the geometry assertion");
        }

        NSMutableArray *rows = [NSMutableArray array], *timings = [NSMutableArray array];
        NSArray *widths = @[@480, @780, @1200, @1600, @1200, @780, @480];
        PreviewController *provider = nil;
        for (NSUInteger mode = 0; mode < 2; mode++) {
            if (mode) {
                NSMenuItem *choice = [[[NSMenuItem alloc] init] autorelease];
                [choice setRepresentedObject:@"html"]; [self selectPreviewMode:choice];
                provider = [self valueForKey:@"previewController"];
                [self nv_luuWaitPreview:provider];
            }
            for (NSUInteger list = 0; list < 2; list++) {
                [prefsController setShowNotesList:list sender:nil];
                for (NSUInteger header = 0; header < 2; header++) {
                    [prefsController setShowTitleInTopSection:header sender:nil];
                    [prefsController setShowTagsInTopSection:header sender:nil];
                    [prefsController setShowBodyControlsInTopSection:header sender:nil]; Pump();
                    Check([[[browserSplitController splitViewItems] firstObject] isCollapsed] == !list &&
                        [noteTitleField isHidden] == !header && [noteTagsField isHidden] == !header &&
                        [bodyModeControl isHidden] == !header, @"browser matches the requested list and header visibility");
                    for (NSUInteger query = 0; query < 2; query++) {
                        NSString *queryString = query ? longQuery : @"";
                        [self searchForString:queryString mode:@"exact"];
                        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
                        while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
                        [self revealNote:note options:0]; Pump();
                        if (mode) {
                            // Search can clear selection and discard the previous provider.
                            // Measure the selected note's current provider, not that closed object.
                            provider = [self valueForKey:@"previewController"];
                            [self nv_luuWaitPreview:provider];
                        }
                        Check([[self browserSession] searchResultsAreCurrent] && [self selectedNoteObject] == note &&
                            [[field stringValue] isEqual:queryString], @"matching query preserves the selected note in its real browser");
                        for (NSUInteger focused = 0; focused < 2; focused++) {
                            if (focused) [self bringFocusToControlField:self]; else [self focusNoteBody];
                            Pump();
                            Check(([field currentEditor] != nil) == (focused != 0), @"native field-editor presence matches the requested focus state");
                            for (NSNumber *requestedWidth in widths) {
                                NSString *scenario = [NSString stringWithFormat:@"%@-list%lu-header%lu-query%lu-focus%lu-width%@",
                                    mode ? @"preview" : @"source", (unsigned long)list, (unsigned long)header,
                                    (unsigned long)query, (unsigned long)focused, requestedWidth];
                                NSRect frame = [window frame]; frame.size.width = [requestedWidth doubleValue];
                                double start = [NSDate timeIntervalSinceReferenceDate];
                                [window setFrame:frame display:YES];
                                double resize = ([NSDate timeIntervalSinceReferenceDate] - start) * 1000;
                                [rows addObject:[self nv_luuGeometry:@"on-return" scenario:scenario]];
                                start = [NSDate timeIntervalSinceReferenceDate];
                                [[[window contentView] superview] layoutSubtreeIfNeeded];
                                double layout = ([NSDate timeIntervalSinceReferenceDate] - start) * 1000;
                                Pump();
                                [rows addObject:[self nv_luuGeometry:@"settled" scenario:scenario]];
                                [timings addObject:@{@"scenario": scenario, @"resizeMilliseconds": @(resize), @"explicitLayoutMilliseconds": @(layout)}];
                                Check([[field stringValue] isEqual:queryString] &&
                                    [self selectedNoteObject] == note && [self isViewingNote] == (mode != 0) &&
                                    (([field currentEditor] != nil) == (focused != 0)),
                                    @"resize preserves the query, note, body mode, and native search-editor focus");
                            }
                        }
                    }
                }
            }
        }
        Check([[[note contentString] string] isEqual:source] && [library totalNoteCount] == 1,
            @"all view transitions preserve the complete fixture source and its one-note library");
        [self nv_luuWaitPreview:provider];
        Check([self valueForKey:@"previewController"] == provider && [provider renderedHTML] &&
            ![provider loading] && ![[provider webView] isLoading], @"the completed HTML preview survives every geometry transition");
        NSString *path = [NSString stringWithUTF8String:getenv("NV_TITLEBAR_RESULT")];
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"geometry": rows, @"timings": timings,
            @"checks": @(Checks), @"sourceLength": @([source length])} options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:path atomically:YES], @"measurement artifact is complete");
        [note release];
        NSLog(@"LUU_ROUND_2_PASS checks=%lu resizes=%lu geometry=%lu", (unsigned long)Checks,
            (unsigned long)[timings count], (unsigned long)[rows count]);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
