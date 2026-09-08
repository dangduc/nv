    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        method_setImplementation(class_getInstanceMethod([SyncResponseFetcher class], @selector(start)),
            imp_implementationWithBlock(^BOOL(id object) { Check(NO, @"isolated review does not start network requests"); return NO; }));
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *browser = self;
        NSMutableString *source = [NSMutableString stringWithString:@"# Review A\n\n"];
        for (NSUInteger row = 0; row < 100; row++) [source appendFormat:@"Paragraph %lu contains newer words.\n\n", (unsigned long)row];
        NoteObject *a = MakeNote(library, @"Review A", source);
        NoteObject *b = MakeNote(library, @"Review B", @"# Review B\n\nOther note.");
        NSString *key = [NSString uuidStringWithBytes:*[a uniqueNoteIDBytes]];
        [browser revealNote:a options:0];
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [[editor layoutManager] ensureLayoutForTextContainer:[editor textContainer]];
        [editor scrollPoint:NSMakePoint(0, 280)];
        [browser setViewingNote:YES];
        Check(Await(^BOOL { return PreviewShows(browser, @"Review A"); }, 15), @"real browser A preview loads");
        PreviewController *viewer = [browser valueForKey:@"previewController"];
        [[viewer valueForKey:@"_stateTimer"] invalidate];
        [viewer restoreViewerState:@{@"scrollY": @100,@"find":@"Paragraph"}];
        NSString *base = NativeJavaScript([viewer webView], @"document.baseURI");
        NativeJavaScript([viewer webView], @"window.scrollTo(0,420)");
        NSMutableArray *held = [NSMutableArray array];
        Method method = class_getInstanceMethod([WKWebView class], @selector(evaluateJavaScript:completionHandler:));
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(WKWebView *object, NSString *script, void (^completion)(id, NSError *)) {
            if (object == [viewer webView] && [script isEqual:@"[document.baseURI,window.scrollX,window.scrollY]"])
                [held addObject:[[completion copy] autorelease]];
            else ((void(*)(id, SEL, NSString *, id))original)(object, @selector(evaluateJavaScript:completionHandler:), script, completion);
        });
        method_setImplementation(method, replacement);
        // Save-state capture can already be outstanding when the user changes Find.
        [browser browserWindowState];
        NSSearchField *find = [viewer valueForKey:@"_findField"];
        [find setStringValue:@"newer"];
        Check([NSApp sendAction:[find action] to:[find target] from:find], @"native Find action enters a newer query");
        Check([[[viewer viewerState] objectForKey:@"find"] isEqual:@"newer"], @"provider records the newer query before refresh");
        // Same production method called by a pending peer-editor refresh. No
        // private state is changed; only WebKit callback delivery is controlled.
        [browser updateViewerSnapshot];
        Check([viewer loading], @"same-note refresh is loading before a further note departure");
        [browser revealNote:b options:0];
        Check([held count] == 1, @"departure joins the existing A DOM read");
        void (^reply)(id, NSError *) = [held objectAtIndex:0];
        reply(@[base,@0,@420],nil);
        method_setImplementation(method, original); imp_removeBlock(replacement);
        NSDictionary *bodyState = [[browser valueForKey:@"noteBodyStates"] objectForKey:key];
        NSString *savedQuery = [[[bodyState objectForKey:@"viewers"] objectForKey:@"markdown"] objectForKey:@"find"];
        NSPoint savedSource = NSPointFromString([bodyState objectForKey:@"sourceScroll"]);
        [browser revealNote:a options:0];
        Check(Await(^BOOL { return PreviewShows(browser, @"Review A"); }, 15), @"A returns after joined capture completion");
        NSString *returnedQuery = [[viewer valueForKey:@"_findField"] stringValue];
        double returnedScroll = [NativeJavaScript([viewer webView], @"window.scrollY") doubleValue];
        printf("Actual browser: latest query newer; saved query %s; restored field %s; preview scroll %.0f; source scroll %.0f\n", [savedQuery UTF8String], [returnedQuery UTF8String], returnedScroll, savedSource.y);
        Check(savedSource.y == 280 && returnedScroll == 420, @"neighboring source and preview offsets survive the same history");
        BOOL losesQuery = ![savedQuery isEqual:@"newer"] && ![returnedQuery isEqual:@"newer"];
        printf("%s: browser consumer %s newer Find state after capture, same-note refresh, departure, and return. Checks: %lu\n", losesQuery ? "CONFIRMED" : "REJECTED", losesQuery ? "loses" : "preserves", (unsigned long)Checks);
        fflush(stdout); _exit(losesQuery ? 2 : 0);
    } @catch (NSException *exception) { NSLog(@"Review probe exception: %@", exception); _exit(1); }
}
@end
