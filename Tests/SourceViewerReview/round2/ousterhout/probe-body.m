
    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        method_setImplementation(class_getInstanceMethod([SyncResponseFetcher class], @selector(start)),
            imp_implementationWithBlock(^BOOL(id object) { Check(NO, @"isolated review does not start network requests"); return NO; }));
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *browser = self;
        NSMutableString *source = [NSMutableString stringWithString:@"# Review A\n\n"];
        for (NSUInteger row = 0; row < 120; row++) [source appendFormat:@"Paragraph %lu contains ordinary source text.\n\n", (unsigned long)row];
        NoteObject *a = MakeNote(library, @"Review A", source);
        NoteObject *b = MakeNote(library, @"Review B", @"# Review B\n\nOther note.");
        NSString *key = [NSString uuidStringWithBytes:*[a uniqueNoteIDBytes]];
        double (^savedScroll)(void) = ^double {
            NSDictionary *state = [[browser valueForKey:@"noteBodyStates"] objectForKey:key];
            return [[[[state objectForKey:@"viewers"] objectForKey:@"markdown"] objectForKey:@"scrollY"] doubleValue];
        };
        NSUInteger reproduced = 0;
        for (NSUInteger scenario = 0; scenario < 3; scenario++) {
            [browser setViewingNote:NO]; [browser discardViewer];
            [[browser valueForKey:@"noteBodyStates"] removeAllObjects];
            [browser revealNote:a options:0]; [browser setViewingNote:YES];
            Check(Await(^BOOL { return PreviewShows(browser, @"Review A"); }, 15), @"fresh real browser A preview loads");
            PreviewController *viewer = [browser valueForKey:@"previewController"];
            [[viewer valueForKey:@"_stateTimer"] invalidate];
            [viewer restoreViewerState:@{@"scrollY": @100}];
            NSString *base = NativeJavaScript([viewer webView], @"document.baseURI");
            Check([NativeJavaScript([viewer webView], @"window.scrollTo(0,420);window.scrollY") doubleValue] == 420,
                @"actual document scroll is 420 while restoration cache is 100");
            NSMutableArray *held = [NSMutableArray array];
            Method method = class_getInstanceMethod([WKWebView class], @selector(evaluateJavaScript:completionHandler:));
            IMP original = method_getImplementation(method);
            IMP replacement = imp_implementationWithBlock(^(WKWebView *object, NSString *script, void (^completion)(id, NSError *)) {
                if (object == [viewer webView] && [script isEqual:@"[document.baseURI,window.scrollX,window.scrollY]"])
                    [held addObject:[[completion copy] autorelease]];
                else ((void(*)(id, SEL, NSString *, id))original)(object, @selector(evaluateJavaScript:completionHandler:), script, completion);
            });
            method_setImplementation(method, replacement);
            [browser revealNote:b options:0]; [browser revealNote:a options:0];
            Check([held count] == 1 && [viewer hasPendingViewerStateCaptureForSnapshot:[viewer snapshot] viewerIdentifier:@"markdown"],
                @"first A to B to A retains the exact A capture");
            if (scenario == 1) [browser revealNote:b options:0];
            else if (scenario == 2) [browser setViewingNote:NO];
            void (^reply)(id, NSError *) = [held objectAtIndex:0];
            reply(@[base, @0, @420], nil);
            method_setImplementation(method, original); imp_removeBlock(replacement);
            double captured = savedScroll();
            if (scenario == 1) [browser revealNote:a options:0];
            else if (scenario == 2) [browser setViewingNote:YES];
            Check(Await(^BOOL { return PreviewShows(browser, @"Review A"); }, 15), @"return A renders after exact capture completion");
            double visible = [NativeJavaScript([viewer webView], @"window.scrollY") doubleValue];
            printf("Scenario %lu (%s): browser canonical %.0f, returned DOM %.0f, expected 420\n", (unsigned long)scenario,
                scenario == 0 ? "A-B-A control" : scenario == 1 ? "A-B-A-B-A" : "A-B-A-Source-A", captured, visible);
            if (scenario == 0) Check(captured == 420 && visible == 420, @"single return control preserves exact scroll");
            else if (captured != 420 && visible != 420) reproduced++;
        }
        Check(reproduced == 2, @"two repeated-transition schedules reproduce lost exact state");
        // Closure must discard late callbacks from the old provider even after a new one exists.
        PreviewController *old = [[browser valueForKey:@"previewController"] retain];
        __block NSUInteger completions = 0;
        [old captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) { completions++; }];
        [browser discardViewer];
        Check(completions == 1 && ![old loading] && [old renderedHTML] == nil, @"close completes capture once and clears rendered state");
        [browser updateBodyPresentation]; [browser updateViewerSnapshot];
        Check(Await(^BOOL { return PreviewShows(browser, @"Review A"); }, 15), @"replacement provider renders after close");
        Check(completions == 1 && [browser valueForKey:@"previewController"] != old, @"late close callback cannot reopen prior provider");
        [old release];
        printf("CONFIRMED: loading-state captures supersede outstanding exact state after repeated returns. Checks: %lu\n", (unsigned long)Checks);
        fflush(stdout); _exit(0);
    } @catch (NSException *exception) { NSLog(@"Review probe exception: %@", exception); _exit(1); }
}
@end
