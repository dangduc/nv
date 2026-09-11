
    @try {
        HistoryRecords = [NSMutableArray array];
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = app.library;
        GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
        [prefs setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        [self searchForString:@""]; Pump();
        LinkingEditor *editor = [self valueForKey:@"textView"];
        NSString *base = @"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu. "
            "Unicode preserves Việt 中文 👩🏽‍💻 and a\u0301 through shared edits.\n"
            "Second paragraph has short words beside a tab\tthen ordinary spaces     and a final word.\n"
            "Last paragraph makes distant invalidation visible while the caret stays near the start.";
        NoteObject *note = MakeNote(library, @"History A", base);
        [note setSourceSyntaxIdentifier:@"plain"];
        [self revealNote:note options:0]; Pump();
        [app newWindow:self]; Pump();
        AppController *peer = [app.browserControllers lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        [self.window setContentSize:NSMakeSize(470, 620)];
        [peer.window setContentSize:NSMakeSize(825, 620)]; Pump();
        Check([editor.layoutManager.typesetter isKindOfClass:NSClassFromString(@"NVSourceTypesetter")] &&
            [peerEditor.layoutManager.typesetter isKindOfClass:NSClassFromString(@"NVSourceTypesetter")] &&
            editor.layoutManager.typesetter != peerEditor.layoutManager.typesetter,
            @"two actual editors use separate production typesetters");
        HistorySource(note, editor, peerEditor, base, @"H1 baseline");
        [[note undoManager] removeAllActions];

        // Edit a cached first paragraph, split it, edit the last paragraph in the
        // other window, then reverse and replay the complete shared history.
        NSMutableArray *states = [NSMutableArray arrayWithObject:base];
        NSString *prefix = @"prefix words shift each cached paragraph\n";
        NSString *state = [prefix stringByAppendingString:base];
        HistoryReplace(self, editor, NSMakeRange(0, 0), prefix);
        [states addObject:state];
        HistorySource(note, editor, peerEditor, state, @"H1 prefix insertion");
        NSRange replaced = [state rangeOfString:@"gamma delta epsilon"];
        NSString *split = @"short\nnew middle words";
        state = [state stringByReplacingCharactersInRange:replaced withString:split];
        HistoryReplace(peer, peerEditor, replaced, split);
        [states addObject:state];
        [self.window setContentSize:NSMakeSize(645, 620)];
        [peer.window setContentSize:NSMakeSize(475, 620)]; Pump();
        HistorySource(note, editor, peerEditor, state, @"H1 split plus crossed widths");
        replaced = [state rangeOfString:@"distant invalidation"];
        NSString *replacement = @"new words that alter the distant cache";
        state = [state stringByReplacingCharactersInRange:replaced withString:replacement];
        HistoryReplace(self, editor, replaced, replacement);
        [states addObject:state];
        HistorySource(note, editor, peerEditor, state, @"H1 distant edit");
        for (NSInteger index = 2; index >= 0; index--) {
            [peerEditor undo:peer]; Pump();
            HistorySource(note, editor, peerEditor, states[index],
                [NSString stringWithFormat:@"H1 Undo %ld", (long)(3-index)]);
        }
        for (NSUInteger index = 1; index < states.count; index++) {
            [editor redo:self]; Pump();
            HistorySource(note, editor, peerEditor, states[index],
                [NSString stringWithFormat:@"H1 Redo %lu", (unsigned long)index]);
        }

        // Equal length prevents range checks alone from detecting the wrong note.
        NSString *switchA = @"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu alpha beta gamma delta epsilon zeta";
        NSString *switchB = @"alpha-beta-gamma-delta-epsilon-zeta-eta-theta-iota-kappa-lambda-mu-alpha-beta-gamma-delta-epsilon-zeta";
        Check(switchA.length == switchB.length, @"H2 note fixtures have equal source lengths");
        NoteObject *a = MakeNote(library, @"Equal length A", switchA);
        NoteObject *b = MakeNote(library, @"Equal length B", switchB);
        NoteObject *empty = MakeNote(library, @"Empty interlude", @"");
        [self revealNote:a options:0]; [peer revealNote:a options:0]; Pump();
        id typesetter = editor.layoutManager.typesetter;
        HistorySource(a, editor, peerEditor, switchA, @"H2 original attachment");
        NSDictionary *peerBefore = [[HistoryGeometry(peerEditor.layoutManager, peerEditor.textContainer) copy] autorelease];
        for (NoteObject *target in @[b, empty, b, a]) {
            [self revealNote:target options:0]; Pump();
            Check(editor.layoutManager.typesetter == typesetter, @"H2 note switches retain the editor typesetter identity");
            Check([peerBefore isEqual:HistoryGeometry(peerEditor.layoutManager, peerEditor.textContainer)] &&
                [peerEditor.string isEqual:switchA], @"H2 switching the first window preserves the peer layout and source");
            HistoryObserve(editor, [NSString stringWithFormat:@"H2 switch to %@", titleOfNote(target)]);
        }
        [[a undoManager] removeAllActions];
        NSString *editedA = [switchA stringByAppendingString:@" appended words"];
        HistoryReplace(peer, peerEditor, NSMakeRange(switchA.length, 0), @" appended words");
        [self revealNote:b options:0]; Pump();
        [peerEditor undo:peer]; Pump();
        Check([editor.string isEqual:switchB], @"H2 Undo in detached peer leaves the selected other note unchanged");
        [self revealNote:a options:0]; Pump();
        HistorySource(a, editor, peerEditor, switchA, @"H2 return after detached Undo");
        [editor redo:self]; Pump();
        HistorySource(a, editor, peerEditor, editedA, @"H2 Redo after return");

        // Native composition remains live across a peer resize and note switch.
        [self revealNote:note options:0]; [peer revealNote:note options:0]; Pump();
        [note setContentString:[[[NSAttributedString alloc] initWithString:base] autorelease]]; Pump();
        [[note undoManager] removeAllActions];
        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:editor];
        NSRange composition = [base rangeOfString:@"gamma delta epsilon"];
        NSString *marked = @"日本語 alpha beta composed words";
        [editor setMarkedText:marked selectedRange:NSMakeRange(marked.length, 0) replacementRange:composition];
        NSString *live = [base stringByReplacingCharactersInRange:composition withString:marked];
        Check(editor.hasMarkedText && [editor.string isEqual:live] && [peerEditor.string isEqual:live] &&
            [[[note contentString] string] isEqual:base], @"H3 marked text is shared while the model retains committed source");
        HistoryObserve(editor, @"H3 first marked value / composing editor");
        HistoryObserve(peerEditor, @"H3 first marked value / peer");
        [peer.window setContentSize:NSMakeSize(815, 620)];
        [peer revealNote:b options:0]; Pump();
        Check(editor.hasMarkedText && [editor.string isEqual:live], @"H3 peer resize and detach preserve native composition");
        NSString *marked2 = @"日本語 second choice with more words 👩🏽‍💻";
        [editor setMarkedText:marked2 selectedRange:NSMakeRange(marked2.length, 0) replacementRange:editor.markedRange];
        live = [base stringByReplacingCharactersInRange:composition withString:marked2];
        [self.window setContentSize:NSMakeSize(480, 620)];
        [peer revealNote:note options:0]; Pump();
        Check(editor.hasMarkedText && [editor.string isEqual:live] && [peerEditor.string isEqual:live] &&
            [[[note contentString] string] isEqual:base], @"H3 a replaced composition reattaches with exact pending source");
        HistoryObserve(editor, @"H3 second marked value / resized editor");
        HistoryObserve(peerEditor, @"H3 second marked value / reattached peer");
        [editor unmarkText]; [self finishEditing]; Pump();
        HistorySource(note, editor, peerEditor, live, @"H3 composition commit");
        [peerEditor undo:peer]; Pump();
        HistorySource(note, editor, peerEditor, base, @"H3 composition Undo from peer");
        [editor redo:self]; Pump();
        HistorySource(note, editor, peerEditor, live, @"H3 composition Redo");

        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"HISTORY REVIEW PASSED (%lu checks)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: HISTORY EXCEPTION %@ %@\n%@", exception.name, exception.reason, exception.callStackSymbols);
        exit(1);
    }
}
@end
