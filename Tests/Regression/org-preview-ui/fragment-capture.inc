        {
            NSMutableString *fragmentSource = [NSMutableString stringWithString:@"* Contents\n[[*Destination][Jump to destination]]\n\n"];
            for (NSUInteger line = 0; line < 65; line++) [fragmentSource appendFormat:@"Opening paragraph %lu.\n\n", (unsigned long)line];
            [fragmentSource appendString:@"* Destination\n\n"];
            for (NSUInteger line = 0; line < 65; line++) [fragmentSource appendFormat:@"Final paragraph %lu.\n\n", (unsigned long)line];
            NoteObject *fragmentNote = MakeNote(library, @"Org heading navigation", fragmentSource);
            [browser revealNote:fragmentNote options:0]; [browser selectPreviewMode:PreviewItem(@"org")];
            Check(Await(^BOOL { return Ready(preview, @"org") && [[[preview snapshot] source] isEqual:fragmentSource]; }, 20), @"heading navigation fixture renders in the actual browser");
            // A periodic sample must not hide a broken immediate capture.
            [[preview valueForKey:@"stateTimer"] invalidate];
            [preview restoreViewerState:@{@"scrollY": @0, @"find": @"fragment query"}];
            NSDictionary *beforeClick = NativeJavaScript([preview webView], @"(()=>{window.scrollTo(0,0);const a=Array.from(document.links).find(x=>x.textContent==='Jump to destination');return {href:a.getAttribute('href'),base:document.baseURI}})()");
            Check([beforeClick[@"href"] hasPrefix:@"#"], @"rendered Org heading link uses a document fragment");
            NativeJavaScript([preview webView], @"Array.from(document.links).find(x=>x.textContent==='Jump to destination').click()");
            Check(Await(^BOOL { return [NativeJavaScript([preview webView], @"location.hash.length>1 && window.scrollY>500") boolValue]; }, 3), @"real heading-link navigation changes the native URL fragment and scroll position");
            NSDictionary *afterClick = NativeJavaScript([preview webView], @"({base:document.baseURI,y:window.scrollY})");
            Check(![afterClick[@"base"] isEqual:beforeClick[@"base"]] && [afterClick[@"base"] hasPrefix:beforeClick[@"base"]], @"WebKit reports the same document base with its new fragment");
            __block NSDictionary *immediate = nil;
            NVNoteContentSnapshot *expectedSnapshot = [preview snapshot];
            [preview captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
                Check(snapshot == expectedSnapshot && [identifier isEqual:@"org"], @"fragment capture preserves the requested snapshot and viewer identity");
                immediate = [state copy];
            }];
            Check(Await(^BOOL { return immediate != nil; }, 3) && fabs([immediate[@"scrollY"] doubleValue] - [afterClick[@"y"] doubleValue]) <= 2, @"immediate capture reads heading scroll without a periodic timer sample");
            Check([immediate[@"find"] isEqual:@"fragment query"], @"fragment capture retains its call-time Find state");
            [immediate release];

            NSString *documentBase = [[[preview valueForKey:@"documentBaseURL"] absoluteString] copy];
            NSArray *replies = @[
                @{@"base": [documentBase stringByAppendingString:@"#another-heading"], @"accept": @YES, @"reason": @"a different fragment in the same document"},
                @{@"base": [documentBase stringByAppendingString:@"#"], @"accept": @YES, @"reason": @"an empty fragment in the same document"},
                @{@"base": @"nvalt-asset://different-document/#heading", @"accept": @NO, @"reason": @"a different document host"},
                @{@"base": [documentBase stringByAppendingString:@"other/#heading"], @"accept": @NO, @"reason": @"a different document path"},
                @{@"base": [documentBase stringByAppendingString:@"?view=other#heading"], @"accept": @NO, @"reason": @"a different document query"},
                @{@"base": [documentBase stringByAppendingString:@"%23heading"], @"accept": @NO, @"reason": @"an encoded hash in the path"},
                @{@"base": [documentBase stringByAppendingString:@"?view=%23heading#ignored"], @"accept": @NO, @"reason": @"an encoded hash in a changed query"},
                @{@"base": [documentBase stringByReplacingOccurrencesOfString:@"nvalt-asset:" withString:@"https:"], @"accept": @NO, @"reason": @"a different URL scheme"},
                @{@"base": @42, @"accept": @NO, @"reason": @"a non-string document identity"}
            ];
            Method originalJavaScript = class_getInstanceMethod([WKWebView class], @selector(evaluateJavaScript:completionHandler:));
            Method gatedJavaScript = class_getInstanceMethod([WKWebView class], @selector(nv_orgCaptureJavaScript:completionHandler:));
            OrgCaptureReplyView = [preview webView]; OrgCaptureReplies = [[NSMutableArray alloc] init];
            method_exchangeImplementations(originalJavaScript, gatedJavaScript);
            for (NSDictionary *fixture in replies) {
                [preview restoreViewerState:@{@"scrollY": @41, @"find": @"identity guard"}];
                NSUInteger index = [OrgCaptureReplies count];
                __block NSUInteger completions = 0;
                __block NSDictionary *captured = nil;
                [preview captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
                    completions++; captured = [state copy];
                }];
                Check([OrgCaptureReplies count] == index + 1 && completions == 0, @"document identity check reaches the gated native DOM boundary");
                void (^reply)(id, NSError *) = OrgCaptureReplies[index];
                reply(@[fixture[@"base"], @0, @777], nil);
                double expected = [fixture[@"accept"] boolValue] ? 777 : 41;
                Check(completions == 1 && [captured[@"scrollY"] doubleValue] == expected && [[[preview viewerState] objectForKey:@"scrollY"] doubleValue] == expected,
                    [NSString stringWithFormat:@"capture %@ %@", [fixture[@"accept"] boolValue] ? @"accepts" : @"rejects", fixture[@"reason"]]);
                Check([captured[@"find"] isEqual:@"identity guard"], @"document identity checks preserve the caller's Find state");
                reply(@[[documentBase stringByAppendingString:@"#late-reply"], @0, @999], nil);
                Check(completions == 1 && [[[preview viewerState] objectForKey:@"scrollY"] doubleValue] == expected, @"a duplicate DOM reply cannot finish or change the capture twice");
                [captured release];
            }
            [preview restoreViewerState:@{@"scrollY": @41}];
            NSUInteger oldCapture = [OrgCaptureReplies count];
            __block NSUInteger olderCompletions = 0;
            [preview captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
                olderCompletions++;
                Check([state[@"scrollY"] doubleValue] == 777, @"superseded fragment capture still returns its own document position");
            }];
            [preview restoreViewerState:@{@"scrollY": @333}];
            void (^oldReply)(id, NSError *) = OrgCaptureReplies[oldCapture];
            oldReply(@[[documentBase stringByAppendingString:@"#heading"], @0, @777], nil);
            Check(olderCompletions == 1 && [[[preview viewerState] objectForKey:@"scrollY"] doubleValue] == 333, @"an older fragment reply cannot overwrite a newer explicit restoration");
            method_exchangeImplementations(originalJavaScript, gatedJavaScript);
            OrgCaptureReplyView = nil; [OrgCaptureReplies release]; OrgCaptureReplies = nil;
            [documentBase release];
            Check([[[fragmentNote contentString] string] isEqual:fragmentSource], @"fragment navigation and capture checks preserve source characters");
        }
