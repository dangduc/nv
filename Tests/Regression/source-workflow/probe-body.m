    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        IMP networkStart = method_setImplementation(class_getInstanceMethod([SyncResponseFetcher class], @selector(start)),
            imp_implementationWithBlock(^BOOL(id object) { Check(NO, @"workflow fixtures do not start network requests"); return NO; }));
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        IMP generalPasteboard = method_setImplementation(class_getClassMethod([NSPasteboard class], @selector(generalPasteboard)),
            imp_implementationWithBlock(^id(id object) { return pasteboard; }));
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *a = self;
        [NSApp activateIgnoringOtherApps:YES];
        [[a window] makeKeyAndOrderFront:self];
        Check(Await(^BOOL { return [NSApp isActive] && [[a window] isKeyWindow]; }, 3), @"source workflow owns an active native window");
        Check(![a isViewingNote], @"new browser starts in Source mode");
        NSMutableString *body = [NSMutableString stringWithString:@"# Source workflow\n\nEditable **Markdown** stays in the note.\n\n"];
        for (NSUInteger line = 0; line < 80; line++) [body appendFormat:@"Paragraph %lu has source characters, café and 😀.\n\n", (unsigned long)line];
        NoteObject *note = MakeNote(library, @"Source workflow", body);
        // Creating a note enters Source. Prepare both notes before the controlled
        // preview transitions so only reveals determine their scheduling.
        NoteObject *intermediate = MakeNote(library, @"Intermediate capture note", @"# Intermediate B");
        [a revealNote:note options:0];
        LinkingEditor *ea = [a valueForKey:@"textView"];
        Check(Await(^BOOL { return [a selectedNoteObject] == note && [[ea string] isEqualToString:body]; }, 2), @"source note attaches to its native editor");
        NSSegmentedControl *mode = [a valueForKey:@"bodyModeControl"];
        NSPopUpButton *syntaxControl = [a valueForKey:@"sourceSyntaxControl"];
        NSPopUpButton *viewerControl = [a valueForKey:@"viewerTypeControl"];
        Check([mode selectedSegment] == 0 && [mode isEnabled] && ![mode isHiddenOrHasHiddenAncestor], @"Source and Preview controls are visible for a selected note");
        Check([[note sourceSyntaxIdentifier] isEqualToString:@"plain"] && [[[syntaxControl selectedItem] representedObject] isEqualToString:@"plain"], @"new note and syntax selector start with Plain Text");
        Check(![syntaxControl isHidden] && [viewerControl isHidden], @"Source mode exposes syntax selection");
        [a selectSourceSyntax:SourceItem(@"markdown", @selector(selectSourceSyntax:))];
        Check(![a isViewingNote] && [[note sourceSyntaxIdentifier] isEqualToString:@"markdown"], @"syntax selection changes source analysis without selecting a viewer");
        NSUInteger heading = [[ea string] rangeOfString:@"Source workflow"].location;
        Check(Await(^BOOL { return [[ea layoutManager] temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:heading effectiveRange:NULL] != nil; }, 5), @"Markdown highlighting reaches the visible source layout");
        Check([[note contentString] attribute:NVSourceCaptureAttributeName atIndex:heading effectiveRange:NULL] == nil, @"source highlight captures stay out of the note model");
        [[a window] makeFirstResponder:ea];
        [ea insertText:@"An undoable source edit.\n\n" replacementRange:NSMakeRange(0, 0)];
        [a finishEditing];
        Check([[note undoManager] canUndo], @"source fixture has a committed undoable edit");
        NSString *committed = [[[note contentString] string] copy];
        CFAbsoluteTime modified = modifiedDateOfNote(note), created = createdDateOfNote(note);
        CFUUIDBytes uuid = *[note uniqueNoteIDBytes];
        NSString *undoName = [[[note undoManager] undoActionName] copy];
        NSRange caret = NSMakeRange(120, 7);
        [ea setSelectedRange:caret];
        [[ea layoutManager] ensureLayoutForTextContainer:[ea textContainer]];
        [ea scrollPoint:NSMakePoint(0, 280)];
        Check(Await(^BOOL { return SourceOrigin(a).y > 100; }, 2), @"source fixture has a nonzero scroll position");
        NSPoint sourceScroll = SourceOrigin(a);
        ChangeMode(a, YES);
        Check(Await(^BOOL { return PreviewShows(a, @"Source workflow"); }, 15), @"Markdown preview renders the selected note inside the browser");
        PreviewController *preview = [a valueForKey:@"previewController"];
        Check([syntaxControl isHidden] && ![viewerControl isHidden] && [mode selectedSegment] == 1, @"Preview mode exposes the independent viewer selector");
        Check([ea isHiddenOrHasHiddenAncestor] && [[preview view] superview] == [[ea enclosingScrollView] superview], @"read-only viewer occupies the source body area");
        Check(![[a window] firstResponder] || [[a window] firstResponder] != ea, @"Preview focus leaves the hidden source editor");
        Check([[note sourceSyntaxIdentifier] isEqualToString:@"markdown"] && [[a selectedViewerIdentifier] isEqualToString:@"markdown"], @"initial Markdown viewer keeps explicit source syntax");
        {
            // Exercise the real browser state consumer, with only WebKit reply
            // delivery controlled. The provider still owns its 0.5 s fallback.
            NSString *noteKey = [NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]];
            double (^savedScroll)(void) = ^double {
                return [[[[[a valueForKey:@"noteBodyStates"] objectForKey:noteKey] objectForKey:@"viewers"] objectForKey:@"markdown"][@"scrollY"] doubleValue];
            };
            NSMutableArray *replies = [NSMutableArray array];
            [[preview valueForKey:@"_stateTimer"] invalidate];
            NSString *documentBase = NativeJavaScript([preview webView], @"document.baseURI");
            Method evaluateMethod = class_getInstanceMethod([WKWebView class], @selector(evaluateJavaScript:completionHandler:));
            IMP originalEvaluate = method_getImplementation(evaluateMethod);
            IMP controlledEvaluate = imp_implementationWithBlock(^(WKWebView *object, NSString *script, void (^completion)(id, NSError *)) {
                if (object == [preview webView] && [script isEqual:@"[document.baseURI,window.scrollX,window.scrollY]"])
                    [replies addObject:[[completion copy] autorelease]];
                else ((void(*)(id, SEL, NSString *, id))originalEvaluate)(object, @selector(evaluateJavaScript:completionHandler:), script, completion);
            });
            method_setImplementation(evaluateMethod, controlledEvaluate);
            for (NSUInteger order = 0; order < 3; order++) {
                NSUInteger first = [replies count];
                [preview restoreViewerState:@{@"scrollY": @100}]; [a captureBodyPresentation];
                [preview restoreViewerState:@{@"scrollY": @200}]; [a captureBodyPresentation];
                Check([replies count] == first + 2, @"browser requests two overlapping captures of the same note and viewer");
                void (^older)(id, NSError *) = replies[first], (^newer)(id, NSError *) = replies[first + 1];
                if (order == 0) {
                    older(@[documentBase, @0, @100], nil);
                    Check(savedScroll() == 200, @"browser rejects an older completion while a newer capture remains pending");
                    newer(@[documentBase, @0, @200], nil);
                } else {
                    newer(@[documentBase, @0, @200], nil);
                    if (order == 1) older(@[documentBase, @0, @100], nil);
                    else Check(Await(^BOOL { return [[preview valueForKey:@"_stateCaptures"] count] == 0; }, 2), @"older browser capture reaches its production timeout");
                }
                Check(savedScroll() == 200 && [[[preview viewerState] objectForKey:@"scrollY"] doubleValue] == 200,
                    @"ordered replies, reversed replies, and an older timeout preserve browser and provider canonical state");
                older(@[documentBase, @0, @999], nil);
                Check(savedScroll() == 200, @"late repeated WebKit replies cannot replace the browser's latest saved state");
            }
            for (NSUInteger history = 0; history < 3; history++) {
                // Return before the exact A read replies and before B renders.
                documentBase = NativeJavaScript([preview webView], @"document.baseURI");
                [preview restoreViewerState:@{@"scrollY": @100, @"find": @"Paragraph"}];
                Check([NativeJavaScript([preview webView], @"window.scrollTo(0,420);window.scrollY") doubleValue] == 420,
                    @"real browser DOM has fresh scroll while the restoration cache remains older");
                NSUInteger returningCapture = [replies count];
                [a revealNote:intermediate options:0]; [a revealNote:note options:0];
                Check([a isViewingNote] && [[[preview snapshot] noteIdentifier] isEqual:noteKey] &&
                    [preview hasPendingViewerStateCaptureForSnapshot:[preview snapshot] viewerIdentifier:@"markdown"],
                    @"rapid browser A to B to A retains A's pending capture instead of superseding it with cached restoration");
                if (history == 1) [a revealNote:intermediate options:0];
                else if (history == 2) [a setViewingNote:NO];
                Check([replies count] == returningCapture + 1 && savedScroll() == 100,
                    @"repeated loading departure preserves useful browser cache and joins the original exact read");
                void (^returningReply)(id, NSError *) = replies[returningCapture];
                returningReply(@[documentBase, @0, @420], nil);
                Check(savedScroll() == 420, @"browser's latest capture request receives the pending exact scroll after repeated departures");
                if (history == 1) [a revealNote:note options:0];
                else if (history == 2) [a setViewingNote:YES];
                Check(Await(^BOOL { return PreviewShows(a, @"Source workflow"); }, 15), @"rapid browser history finishes after the capture barrier");
                Check(savedScroll() == 420 && fabs([NativeJavaScript([preview webView], @"window.scrollY") doubleValue] - 420) <= 2,
                    history == 0 ? @"A to B to A restores the exact scroll in browser state and visible DOM" :
                    history == 1 ? @"A to B to A to B to A restores the exact scroll in browser state and visible DOM" :
                    @"A to B to A to Source to A restores the exact scroll in browser state and visible DOM");
                Check([[[preview viewerState] objectForKey:@"find"] isEqual:@"Paragraph"] &&
                    [[[preview valueForKey:@"_findField"] stringValue] isEqual:@"Paragraph"],
                    @"pending presentation return retains its saved Find query in provider state and the native search field");
                Check(fabs(NSPointFromString([[[a valueForKey:@"noteBodyStates"] objectForKey:noteKey] objectForKey:@"sourceScroll"]).y - sourceScroll.y) <= 1,
                    @"preview note histories preserve the source position when hidden layout changes its clip origin");
            }

            // Authoritative saved-window restoration must invalidate pending
            // captures in both the browser and the old provider.
            [preview restoreViewerState:@{@"scrollY": @100}]; [a captureBodyPresentation];
            NSMutableDictionary *restoredWindow = [[[a browserWindowState] mutableCopy] autorelease];
            Check(fabs(NSPointFromString([restoredWindow objectForKey:@"editorScroll"]).y - sourceScroll.y) <= 1,
                @"preview window serialization uses the saved source position instead of the hidden editor's clip origin");
            NSMutableDictionary *restoredBody = [[[restoredWindow objectForKey:@"bodyState"] mutableCopy] autorelease];
            [restoredBody setObject:@{@"markdown": @{@"scrollY": @300}} forKey:@"viewers"];
            [restoredWindow setObject:restoredBody forKey:@"bodyState"];
            PreviewController *oldProvider = [preview retain];
            [a restoreBrowserWindowState:restoredWindow];
            Check([a valueForKey:@"previewController"] != oldProvider, @"explicit window restoration replaces the provider with pending captures");
            for (void (^reply)(id, NSError *) in replies) reply(@[documentBase, @0, @999], nil);
            method_setImplementation(evaluateMethod, originalEvaluate); imp_removeBlock(controlledEvaluate);
            Check(Await(^BOOL { return PreviewShows(a, @"Source workflow"); }, 15), @"explicitly restored viewer renders after closing the old provider");
            preview = [a valueForKey:@"previewController"];
            Check(savedScroll() == 300 && fabs([NativeJavaScript([preview webView], @"window.scrollY") doubleValue] - 300) <= 2,
                @"old callbacks cannot overwrite the authoritative restored browser or provider position");
            Check(![oldProvider loading] && [oldProvider renderedHTML] == nil, @"late restoration callbacks cannot reopen the discarded provider");
            [oldProvider release];
        }
        ChangeMode(a, NO);
        Check(Await(^BOOL { return ![a isViewingNote] && ![ea isHiddenOrHasHiddenAncestor]; }, 2), @"Source control returns to the editable native view");
        Check([[[note contentString] string] isEqualToString:committed] && memcmp(&uuid, [note uniqueNoteIDBytes], sizeof(uuid)) == 0 &&
            modifiedDateOfNote(note) == modified && createdDateOfNote(note) == created, @"mode round-trip preserves source, UUID, and dates without pending edits");
        Check([[note undoManager] canUndo] && [[[note undoManager] undoActionName] isEqualToString:undoName],
            @"mode round-trip preserves the existing Undo history");
        Check(NSEqualRanges([ea selectedRange], caret), @"mode round-trip restores the source selection");
        Check(fabs(SourceOrigin(a).y - sourceScroll.y) <= 1.0, @"mode round-trip restores the source scroll position");
        [ea undo:self];
        Check(Await(^BOOL { return [[[note contentString] string] isEqualToString:body]; }, 2), @"Undo after preview removes exactly the preceding source edit");
        [ea redo:self];
        Check(Await(^BOOL { return [[[note contentString] string] isEqualToString:committed]; }, 2), @"Redo after preview restores exactly that source edit");
        [undoName release];

        // Choose viewers independently of the local insertion and highlighting syntax.
        [a selectPreviewMode:SourceItem(@"textile", @selector(selectPreviewMode:))];
        Check(Await(^BOOL { return PreviewShows(a, @"Source workflow"); }, 15), @"Textile viewer renders in the same browser body");
        Check([[a selectedViewerIdentifier] isEqualToString:@"textile"] && [[note sourceSyntaxIdentifier] isEqualToString:@"markdown"], @"Textile viewer selection leaves Markdown source syntax unchanged");
        [a selectSourceSyntax:SourceItem(@"json", @selector(selectSourceSyntax:))];
        Check([[a selectedViewerIdentifier] isEqualToString:@"textile"] && [[note sourceSyntaxIdentifier] isEqualToString:@"json"], @"source syntax changes leave the viewer selection unchanged");
        [a selectSourceSyntax:SourceItem(@"markdown", @selector(selectSourceSyntax:))];

        // Source commands must not mutate an editor that Preview hides.
        NSString *beforeHidden = [[[note contentString] string] copy];
        [ea setSelectedRange:NSMakeRange(0, 2)];
        [ea insertText:@"UNWANTED" replacementRange:NSMakeRange(0, 0)];
        [ea deleteBackward:self];
        [ea bold:self];
        [ea undo:self];
        [pasteboard declareTypes:@[NSStringPboardType] owner:nil];
        [pasteboard setString:@"UNWANTED PASTE" forType:NSStringPboardType];
        Check(![ea readSelectionFromPasteboard:pasteboard type:NSStringPboardType], @"hidden source editor rejects paste");
        [a finishEditing];
        Check([[[note contentString] string] isEqualToString:beforeHidden], @"Preview blocks source insertion, deletion, formatting, and Undo commands");
        [beforeHidden release];

        [app newWindow:self];
        AppController *b = [[app browserControllers] lastObject];
        Check(b != a && ![b isViewingNote], @"a second browser starts independently in Source");
        [b revealNote:note options:0];
        LinkingEditor *eb = [b valueForKey:@"textView"];
        Check(Await(^BOOL { return [b selectedNoteObject] == note && [[eb string] isEqualToString:committed]; }, 2), @"source peer attaches to the same shared note");
        [a selectPreviewMode:SourceItem(@"markdown", @selector(selectPreviewMode:))];
        Check(Await(^BOOL { return PreviewShows(a, @"Source workflow"); }, 15), @"Markdown preview is ready before the peer scroll fixture");
        preview = [a valueForKey:@"previewController"];
        double markdownScroll = [NativeJavaScript([preview webView], @"window.scrollTo(0,420);window.scrollY") doubleValue];
        Check(markdownScroll > 300 && Await(^BOOL { return fabs([[[preview viewerState] objectForKey:@"scrollY"] doubleValue] - markdownScroll) <= 2; }, 3), @"viewer captures a nonzero Markdown scroll position");
        [[b window] makeKeyAndOrderFront:self]; [[b window] makeFirstResponder:eb];
        Check(Await(^BOOL { return [[b window] isKeyWindow]; }, 2), @"source peer owns keyboard focus");
        [eb insertText:@"\nPeer source update 2026.\n" replacementRange:NSMakeRange([[eb string] length], 0)];
        [b finishEditing];
        Check(Await(^BOOL { return PreviewShows(a, @"Peer source update 2026."); }, 15), @"preview peer refreshes after a shared source edit");
        Check([a isViewingNote] && ![b isViewingNote] && [[ea string] isEqualToString:[eb string]], @"two browsers retain separate modes over the same source storage");
        Check(fabs([NativeJavaScript([preview webView], @"window.scrollY") doubleValue] - markdownScroll) <= 2, @"same-note peer edits preserve the latest preview scroll position");
        [a selectPreviewMode:SourceItem(@"textile", @selector(selectPreviewMode:))];
        Check(Await(^BOOL { return PreviewShows(a, @"Peer source update 2026."); }, 15), @"second viewer is ready for independent scroll state");
        Check([NativeJavaScript([preview webView], @"window.scrollY") doubleValue] <= 2, @"a viewer without saved scroll starts at the top");
        double textileScroll = [NativeJavaScript([preview webView], @"window.scrollTo(0,180);window.scrollY") doubleValue];
        Check(textileScroll > 100 && Await(^BOOL { return fabs([[[preview viewerState] objectForKey:@"scrollY"] doubleValue] - textileScroll) <= 2; }, 3), @"second viewer captures its own scroll position");
        [a selectPreviewMode:SourceItem(@"markdown", @selector(selectPreviewMode:))];
        Check(Await(^BOOL { return PreviewShows(a, @"Peer source update 2026."); }, 15), @"Markdown viewer returns after the alternate provider");
        Check(fabs([NativeJavaScript([preview webView], @"window.scrollY") doubleValue] - markdownScroll) <= 2, @"returning to Markdown restores its separate scroll position");
        [a selectPreviewMode:SourceItem(@"textile", @selector(selectPreviewMode:))];
        Check(Await(^BOOL { return PreviewShows(a, @"Peer source update 2026."); }, 15), @"Textile viewer returns after Markdown");
        Check(fabs([NativeJavaScript([preview webView], @"window.scrollY") doubleValue] - textileScroll) <= 2, @"returning to Textile restores its separate scroll position");
        [a selectPreviewMode:SourceItem(@"markdown", @selector(selectPreviewMode:))];

        // Only a browser's own composition can finish during its mode switch.
        NoteObject *composition = MakeNote(library, @"Composition", @"Base source.");
        ChangeMode(a, NO); [a revealNote:composition options:0]; [b revealNote:composition options:0];
        [[a window] makeKeyAndOrderFront:self]; [[a window] makeFirstResponder:ea];
        [ea setMarkedText:@"Own draft " selectedRange:NSMakeRange(10,0) replacementRange:NSMakeRange(0,0)];
        Check([ea hasMarkedText], @"source editor starts its own input-method composition");
        ChangeMode(a, YES);
        Check(![ea hasMarkedText] && [[[composition contentString] string] isEqualToString:@"Own draft Base source."], @"switching the composing browser finalizes its existing source edit");
        Check(Await(^BOOL { return PreviewShows(a, @"Own draft Base source."); }, 15), @"viewer receives the committed own-composition source");
        ChangeMode(a, NO);
        [[b window] makeKeyAndOrderFront:self]; [[b window] makeFirstResponder:eb];
        [eb setMarkedText:@"Peer draft " selectedRange:NSMakeRange(11,0) replacementRange:NSMakeRange(0,0)];
        Check([eb hasMarkedText], @"peer source editor starts input-method composition");
        NSString *beforePeerCommit = [[[composition contentString] string] copy];
        [a setViewingNote:YES];
        Check([eb hasMarkedText] && [[[composition contentString] string] isEqualToString:beforePeerCommit], @"switching another browser leaves the peer composition and committed model unchanged");
        Check(Await(^BOOL { return PreviewShows(a, @"Own draft Base source."); }, 15), @"viewer uses committed source while its peer composes");
        preview = [a valueForKey:@"previewController"];
        Check([[preview renderedHTML] rangeOfString:@"Peer draft"].location == NSNotFound, @"uncommitted peer source stays out of the viewer snapshot");
        [eb unmarkText]; [b finishEditing];
        Check(Await(^BOOL { return PreviewShows(a, @"Peer draft Own draft Base source."); }, 15), @"viewer refreshes when peer composition commits");
        [beforePeerCommit release];

        // Replace pending requests by a different note and a different provider.
        NSMutableString *slowSource = [NSMutableString stringWithString:@"# Obsolete preview marker\n\n"];
        for (NSUInteger line = 0; line < 700; line++) [slowSource appendString:@"A paragraph with **markup** and `code`.\n\n"];
        NoteObject *obsolete = MakeNote(library, @"Obsolete", slowSource);
        NSData *pixel = [[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aNCcAAAAASUVORK5CYII=" options:0] autorelease];
        Check([pixel writeToURL:[[library notesDirectoryURL] URLByAppendingPathComponent:@"workflow-pixel.png"] atomically:YES], @"local preview asset is created in the disposable library");
        NoteObject *current = MakeNote(library, @"Current HTML", @"<h1>Current preview marker</h1><p>Native source &amp; readonly output.</p><img id='local-image' src='workflow-pixel.png'>");
        [a revealNote:obsolete options:0];
        [a selectPreviewMode:SourceItem(@"markdown", @selector(selectPreviewMode:))];
        [a revealNote:current options:0];
        [a selectPreviewMode:SourceItem(@"html", @selector(selectPreviewMode:))];
        Check(Await(^BOOL { return PreviewShows(a, @"Current preview marker"); }, 15), @"the latest note and HTML provider replace obsolete preview requests");
        preview = [a valueForKey:@"previewController"];
        Check([[preview renderedHTML] rangeOfString:@"Obsolete preview marker"].location == NSNotFound && [a selectedNoteObject] == current, @"obsolete render output cannot replace the selected note");
        Check([[current sourceSyntaxIdentifier] isEqualToString:@"plain"], @"HTML interpretation does not change Plain Text source syntax");
        id DOM = NativeJavaScript([preview webView], @"({heading:document.querySelector('h1').textContent, editable:document.designMode==='on'||!!document.querySelector('[contenteditable=true]')})");
        Check([DOM isKindOfClass:[NSDictionary class]] && [[DOM objectForKey:@"heading"] isEqualToString:@"Current preview marker"] && ![[DOM objectForKey:@"editable"] boolValue], @"native viewer displays direct HTML in a read-only document");
        Check(Await(^BOOL { return [NativeJavaScript([preview webView], @"document.getElementById('local-image').naturalWidth") integerValue] == 1; }, 5), @"database-backed notes resolve passive local assets within their library");

        NSDictionary *saved = [[a browserWindowState] copy];
        [app newWindow:self];
        AppController *restored = [[app browserControllers] lastObject];
        [restored restoreBrowserWindowState:saved];
        Check(Await(^BOOL { return [restored selectedNoteObject] == current && PreviewShows(restored, @"Current preview marker"); }, 15), @"restored browser selects its saved note and read-only viewer");
        Check([[restored selectedViewerIdentifier] isEqualToString:@"html"] && ![b isViewingNote], @"presentation restoration leaves source peers unchanged");
        for (id malformed in @[@{ @"sourceScroll": @42, @"viewers": @[] }, @{ @"sourceScroll": @"{NaN, infinity}", @"viewers": @{ @"html": @[@1] } }, @{ @"viewers": @{ @"html": @{ @"scrollX": @"wrong", @"scrollY": @(-500), @"find": @[] } } }]) {
            NSMutableDictionary *invalidState = [[saved mutableCopy] autorelease];
            [invalidState setObject:malformed forKey:@"bodyState"];
            ChangeMode(restored, NO);
            [restored restoreBrowserWindowState:invalidState];
            Check(Await(^BOOL { return PreviewShows(restored, @"Current preview marker"); }, 15), @"malformed nested body presentation state restores without an exception");
            PreviewController *restoredPreview = [restored valueForKey:@"previewController"];
            NSNumber *scrollY = NativeJavaScript([restoredPreview webView], @"window.scrollY");
            Check([scrollY isKindOfClass:[NSNumber class]] && isfinite([scrollY doubleValue]) && [scrollY doubleValue] >= 0, @"malformed presentation state cannot install an invalid viewer scroll");
        }
        [restored newNote:self];
        Check(![restored isViewingNote] && [restored selectedNoteObject] != current && [[[restored selectedNoteObject] sourceSyntaxIdentifier] isEqualToString:@"plain"], @"New Note exits Preview and creates Plain Text source");
        [saved release];

        const char *artifacts = getenv("NV_UI_ARTIFACTS");
        if (artifacts) {
            NSString *folder = [NSString stringWithUTF8String:artifacts];
            [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
            [a revealNote:note options:0]; [a selectSourceSyntax:SourceItem(@"markdown", @selector(selectSourceSyntax:))];
            ChangeMode(a, NO); [[a window] makeKeyAndOrderFront:self]; [ea setSelectedRange:NSMakeRange(0,0)]; [ea scrollPoint:NSZeroPoint];
            Check(Await(^BOOL { return [[a window] isKeyWindow] && ![ea isHiddenOrHasHiddenAncestor]; }, 3), @"source artifact window is visible");
            Check(CaptureBrowser([a window], [folder stringByAppendingPathComponent:@"editable-source.png"]), @"source controls screenshot captures");
            [a selectPreviewMode:SourceItem(@"markdown", @selector(selectPreviewMode:))];
            Check(Await(^BOOL { return PreviewShows(a, @"Source workflow"); }, 15), @"preview artifact finishes rendering");
            NativeJavaScript([[a valueForKey:@"previewController"] webView], @"window.scrollTo(0,0)");
            Check(CaptureBrowser([a window], [folder stringByAppendingPathComponent:@"readonly-preview.png"]), @"preview controls screenshot captures");
        }
        [committed release];
        [library flushAllNoteChanges]; [library closeJournal];
        method_setImplementation(class_getInstanceMethod([SyncResponseFetcher class], @selector(start)), networkStart);
        method_setImplementation(class_getClassMethod([NSPasteboard class], @selector(generalPasteboard)), generalPasteboard);
        [pasteboard releaseGlobally];
        NSLog(@"SOURCE WORKFLOW CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
