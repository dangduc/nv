
    @try {
        HistoryRecords = [NSMutableArray array];
        Class typeClass = NSClassFromString(@"NVSourceTypesetter");
        Check(typeClass && class_getInstanceVariable(typeClass, "paragraphMeasure") &&
            class_getInstanceVariable(typeClass, "lineBreaks"), @"production typesetter exposes both observed cache slots");
        Method endParagraph = class_getInstanceMethod(typeClass, @selector(endParagraph));
        Check(endParagraph != NULL, @"production typesetter has a paragraph completion method");
        OriginalEndParagraph = method_setImplementation(endParagraph, (IMP)HistoryEndParagraph);
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = app.library;
        GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
        [prefs setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        [self searchForString:@""]; Pump();
        LinkingEditor *editor = [self valueForKey:@"textView"];
        ObservedTypesetters[0] = editor.layoutManager.typesetter;
        NSString *paragraph = @"Words remain complete when the source editor wraps a paragraph across several visual lines. "
            "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu. "
            "Unicode preserves Việt 中文 👩🏽‍💻 and a\u0301 alongside ordinary spaces     and tabs\tbetween words.";
        NSString *base = [NSString stringWithFormat:@"%@\nSecond paragraph: %@\nFinal paragraph: %@", paragraph, paragraph, paragraph];
        NoteObject *note = MakeNote(library, @"Lifecycle deletion fixture", base);
        NoteObject *replacement = MakeNote(library, @"Replacement note", paragraph);
        [self revealNote:note options:0]; Pump();
        [app newWindow:self]; Pump();
        AppController *peer = [app.browserControllers lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        ObservedTypesetters[1] = peerEditor.layoutManager.typesetter;
        [self.window setContentSize:NSMakeSize(485, 600)];
        [peer.window setContentSize:NSMakeSize(765, 600)]; Pump();
        Check([ObservedTypesetters[0] isKindOfClass:typeClass] && [ObservedTypesetters[1] isKindOfClass:typeClass] &&
            ObservedTypesetters[0] != ObservedTypesetters[1], @"both real browser editors own separate production typesetters");

        // L1: caches populated by real layout must be released before the empty
        // note, its Undo restoration, and deletion of the shared selected note.
        HistorySource(note, editor, peerEditor, base, @"L1 original paragraphs");
        Check(EndsWithMeasure > 0 && EndsWithBreaks > 0,
            @"L1 actual editor paragraph completion observed allocated measurements and break tables");
        [[note undoManager] removeAllActions];
        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:editor];
        editor.selectedRange = NSMakeRange(0, editor.string.length);
        [editor deleteBackward:self]; [self finishEditing]; Pump();
        HistorySource(note, editor, peerEditor, @"", @"L1 native delete-all to empty");
        Check(HistoryCacheIsEmpty(ObservedTypesetters[0]) && HistoryCacheIsEmpty(ObservedTypesetters[1]),
            @"L1 idle empty editors hold no prior paragraph analysis");
        [peerEditor undo:peer]; Pump();
        HistorySource(note, editor, peerEditor, base, @"L1 Undo empty replacement");
        [library removeNotes:@[note]]; Pump();
        Check(self.selectedNoteObject != note && peer.selectedNoteObject != note &&
            ![[library allNotes] containsObject:note], @"L1 deleting the selected note detaches it from both browsers and the library");
        HistoryObserve(editor, @"L1 first editor immediately after note deletion");
        HistoryObserve(peerEditor, @"L1 peer immediately after note deletion");
        [self revealNote:replacement options:0]; [peer revealNote:replacement options:0]; Pump();
        HistorySource(replacement, editor, peerEditor, paragraph, @"L1 replacement note after deletion");

        // L2: closing a noncomposing peer must not end the surviving composition
        // or retain its cached source. Commit merges a deferred model replacement.
        NoteObject *composed = MakeNote(library, @"Lifecycle composition fixture", base);
        [self revealNote:composed options:0]; [peer revealNote:composed options:0]; Pump();
        [[composed undoManager] removeAllActions];
        HistorySource(composed, editor, peerEditor, base, @"L2 initial shared source");
        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:editor];
        NSRange localRange = [base rangeOfString:@"Alpha beta gamma"];
        NSString *marked = @"日本語 local choice with short words";
        [editor setMarkedText:marked selectedRange:NSMakeRange(marked.length, 0) replacementRange:localRange];
        NSString *local = [base stringByReplacingCharactersInRange:localRange withString:marked];
        NSString *external = [base stringByAppendingString:@"\nExternal appended words remain after history changes."];
        [composed setContentString:[[[NSAttributedString alloc] initWithString:external] autorelease]];
        Check(editor.hasMarkedText && [editor.string isEqual:local] && [peerEditor.string isEqual:local] &&
            [[[composed contentString] string] isEqual:external],
            @"L2 composition remains shared while the external model replacement waits");
        HistoryObserve(editor, @"L2 composing editor with deferred external source");
        HistoryObserve(peerEditor, @"L2 peer with deferred external source");
        NSUInteger windowsBefore = app.browserControllers.count;
        [peer.window close]; Pump();
        ObservedTypesetters[1] = nil;
        Check(app.browserControllers.count == windowsBefore - 1 && editor.hasMarkedText && [editor.string isEqual:local],
            @"L2 closing the peer preserves the surviving composition and exact local source");
        [self.window setContentSize:NSMakeSize(705, 600)]; Pump();
        HistoryObserve(editor, @"L2 surviving composition after peer closure and resize");
        [editor unmarkText]; [self finishEditing]; Pump();
        NSString *merged = [external stringByReplacingCharactersInRange:localRange withString:marked];
        Check([editor.string isEqual:merged] && [[[composed contentString] string] isEqual:merged],
            @"L2 commit preserves both the local composition and nonoverlapping external text");
        HistoryObserve(editor, @"L2 merged source after peer closure");
        [editor undo:self]; Pump();
        Check([editor.string isEqual:external] && [[[composed contentString] string] isEqual:external],
            @"L2 Undo removes only the local composition and preserves the external replacement");
        HistoryObserve(editor, @"L2 Undo after deferred external merge");
        [editor redo:self]; Pump();
        Check([editor.string isEqual:merged] && [[[composed contentString] string] isEqual:merged],
            @"L2 Redo restores the merged source in the surviving editor and model");
        HistoryObserve(editor, @"L2 Redo after deferred external merge");
        Check(EndCalls > 0 && EndsWithMeasure > 0 && EndsWithBreaks > 0 && EndsRetainingAnalysis == 0,
            @"both lifecycle histories observed populated production caches and zero retained caches after paragraph completion");
        NSLog(@"LIFECYCLE COUNTERS end=%lu measure=%lu breaks=%lu retained=%lu", (unsigned long)EndCalls,
            (unsigned long)EndsWithMeasure, (unsigned long)EndsWithBreaks, (unsigned long)EndsRetainingAnalysis);
        method_setImplementation(endParagraph, OriginalEndParagraph);
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"LIFECYCLE REVIEW PASSED (%lu checks)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: LIFECYCLE EXCEPTION %@ %@\n%@", exception.name, exception.reason, exception.callStackSymbols);
        exit(1);
    }
}
@end
