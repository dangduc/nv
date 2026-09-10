    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();
        NSArray *fixtures = @[
            @[@"alpha beta gamma\nlast line", @"alpha beta gamma\nlast lin", @"26", @"0"],
            @[@"    text", @"   text", @"4", @"0"],
            @[@"first\nsecond", @"firstsecond", @"6", @"0"],
            @[@"a🙂z", @"az", @"3", @"0"],
            @[@"caféz", @"cafz", @"5", @"0"],
            @[@"alpha beta gamma", @"alpha gamma", @"6", @"5"],
            @[@"\n", @"", @"1", @"0"]
        ];
        NSUInteger fixtureNumber = 0;
        for (NSString *syntax in @[@"plain", @"org", @"markdown", @"json", @"html"]) {
            for (NSArray *fixture in fixtures) {
                NSString *source = fixture[0], *expected = fixture[1];
                NoteObject *note = MakeNote(library, [NSString stringWithFormat:@"Backspace %lu", (unsigned long)fixtureNumber++], source);
                [note setSourceSyntaxIdentifier:syntax];
                [browser setViewingNote:NO]; [browser revealNote:note options:0]; Pump();
                Check([browser selectedNoteObject] == note && [[editor string] isEqual:source], @"fixture opens the exact disposable source");
                [[browser window] makeKeyAndOrderFront:self]; [[browser window] makeFirstResponder:editor];
                Check([[browser window] firstResponder] == editor && [editor isEditable], @"native source editor owns keyboard focus");
                [editor setSelectedRange:NSMakeRange([fixture[2] integerValue], [fixture[3] integerValue])];
                InstallBackground(editor);
                Check(HasBackground(editor) && Render(editor) != nil, @"search backgrounds and cached native layout exist before deletion");
                if (fixtureNumber == 1) NSLog(@"BACKSPACE FIRST DELETE length=%lu", (unsigned long)[[editor string] length]);
                [editor deleteBackward:self];
                Check([[editor string] isEqual:expected], @"backspace preserves the expected source characters");
                Check(Render(editor) != nil, @"native editor renders immediately after deletion");
                Check(Await(^BOOL { return !HasBackground(editor); }, 2), @"deletion clears search backgrounds after TextKit updates");
                Check([[[note contentString] string] isEqual:expected], @"backspace commits the exact source to its note");
                Check([[note sourceSyntaxIdentifier] isEqual:syntax], @"backspace preserves syntax metadata");
                if (getenv("NV_BACKSPACE_REPRO_ONLY")) {
                    NSLog(@"SOURCE BACKSPACE PASSED (original failure did not recur)"); exit(0);
                }
            }
        }

        // Real Cocoa Undo uses the note's shared editing-session history.
        NoteObject *undoNote = MakeNote(library, @"Backspace Undo", @"undo source");
        [browser revealNote:undoNote options:0]; Pump();
        [[undoNote undoManager] removeAllActions];
        [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
        InstallBackground(editor); Render(editor); [editor deleteBackward:self]; Pump();
        Check([[undoNote undoManager] canUndo], @"source deletion registers Undo");
        [editor undo:self]; Pump();
        Check([[editor string] isEqual:@"undo source"] && [[[undoNote contentString] string] isEqual:@"undo source"], @"Undo restores source characters and model");
        [[undoNote undoManager] redo]; Pump();
        Check([[editor string] isEqual:@"undo sourc"] && [[[undoNote contentString] string] isEqual:@"undo sourc"], @"Redo reapplies only the deletion");

        NoteObject *shared = MakeNote(library, @"Shared source Org backspace", @"* TODO Shared\nbody tail");
        [shared setSourceSyntaxIdentifier:@"org"];
        NoteObject *other = MakeNote(library, @"Other backspace note", @"other source");
        [browser revealNote:shared options:0];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        [peer searchForString:@""]; [peer revealNote:shared options:0]; Pump();
        Check(peer != browser && [editor textStorage] == [peerEditor textStorage] &&
            [editor layoutManager] != [peerEditor layoutManager], @"two browser layouts share one source storage");
        Check(Await(^BOOL { return HasCurrentCapture(editor, 2, @"keyword.todo") && HasCurrentCapture(peerEditor, 2, @"keyword.todo"); }, 4),
            @"both layouts have current Org captures before backspace");
        NSDictionary *drawnBefore = nil;
        for (LinkingEditor *view in @[editor, peerEditor]) {
            InstallBackground(view); Render(view);
            Check(HasBackground(view), @"each peer starts with installed search backgrounds");
        }
        drawnBefore = [[[editor layoutManager] temporaryAttributesAtCharacterIndex:2 effectiveRange:NULL] copy];
        Check(drawnBefore[NSBackgroundColorAttributeName] != nil && [drawnBefore[NVSourceCaptureAttributeName] isEqual:@"keyword.todo"],
            @"retained drawing fixture contains both search background and real Org capture");
        [[browser window] makeKeyAndOrderFront:self]; [[browser window] makeFirstResponder:editor];
        NSString *committed = [[[shared contentString] string] copy];
        NSUInteger generation = [[browser valueForKey:@"searchHighlightGeneration"] unsignedIntegerValue];
        NSUInteger peerGeneration = [[peer valueForKey:@"searchHighlightGeneration"] unsignedIntegerValue];
        __block NSUInteger suppressedLayouts = 0, coloredLayouts = 0;
        // DidProcessEditing follows every WillProcessEditing observer, but still
        // precedes TextKit's layout-range updates. Inspect the retained input
        // dictionary without asking the layout manager for stale range data.
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification
            object:[editor textStorage] queue:nil usingBlock:^(NSNotification *notification) {
                if (!([(NSTextStorage *)[notification object] editedMask] & NSTextStorageEditedCharacters)) return;
                for (LinkingEditor *view in @[editor, peerEditor]) {
                    NSDictionary *drawn = DrawingAttributes(view, drawnBefore, 2);
                    NSDictionary *plain = DrawingAttributes(view, @{}, 2);
                    if (!drawn[NSBackgroundColorAttributeName]) ++suppressedLayouts;
                    if (drawn[NSForegroundColorAttributeName] && ![drawn[NSForegroundColorAttributeName] isEqual:plain[NSForegroundColorAttributeName]]) ++coloredLayouts;
                }
            }];
        // Replacing two characters with one enters an uncommitted, shrinking IME edit.
        [editor setMarkedText:@"x" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange([committed length] - 2, 2)];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        Check([editor hasMarkedText] && [[[shared contentString] string] isEqual:committed], @"composition shrinks live source without committing the model");
        Check([[browser valueForKey:@"searchHighlightGeneration"] unsignedIntegerValue] > generation &&
            [[peer valueForKey:@"searchHighlightGeneration"] unsignedIntegerValue] > peerGeneration,
            @"uncommitted shared edits invalidate old highlight completions in both browsers");
        Check(suppressedLayouts == 2, @"both layouts suppress stale backgrounds before TextKit updates their ranges");
        Check(coloredLayouts == 2, @"stale-background suppression retains both layouts' Org syntax colors");
        for (LinkingEditor *view in @[editor, peerEditor]) {
            Check(Render(view) != nil, @"both layouts render during uncommitted composition");
        }
        Check(Await(^BOOL { return !HasBackground(editor) && !HasBackground(peerEditor); }, 2), @"both layouts eventually remove stale background storage");
        [editor unmarkText]; [browser finishEditing]; Pump();
        Check([[editor string] isEqual:[peerEditor string]] && [[[shared contentString] string] isEqual:[editor string]],
            @"composition completion preserves identical shared source and model");
        Check(Await(^BOOL { return HasCurrentCapture(editor, 2, @"keyword.todo") && HasCurrentCapture(peerEditor, 2, @"keyword.todo"); }, 4),
            @"both layouts publish current Org captures after composition");
        Check(Await(^BOOL { return [[browser browserSession] searchResultsAreCurrent] && [[peer browserSession] searchResultsAreCurrent]; }, 4),
            @"both search sessions finish processing the committed composition");
        Pump();
        [drawnBefore release]; [committed release];

        // Switch and close before the zero-delay cleanup can run. A new note's
        // highlights must not be removed by work scheduled for the old note.
        // A real query matches the old title and the new body, so ordinary
        // selection refresh may replace, but must not discard, the new matches.
        [browser searchForString:@"source" mode:@"exact"];
        Check(Await(^BOOL { return [[browser browserSession] searchResultsAreCurrent]; }, 4), @"lifecycle search has current exact results");
        [browser revealNote:shared options:0]; Pump();
        Check([browser selectedNoteObject] == shared && [[[browser browserSession] searchString] isEqual:@"source"],
            @"lifecycle search retains the old note through its matching title");
        InstallBackground(editor); InstallBackground(peerEditor); Render(editor); Render(peerEditor);
        [editor invalidateSearchHighlights]; [peerEditor invalidateSearchHighlights];
        Check(HasBackground(editor) && HasBackground(peerEditor) &&
            !DrawingAttributes(editor, @{NSBackgroundColorAttributeName:[NSColor yellowColor]}, 2)[NSBackgroundColorAttributeName] &&
            !DrawingAttributes(peerEditor, @{NSBackgroundColorAttributeName:[NSColor yellowColor]}, 2)[NSBackgroundColorAttributeName],
            @"lifecycle fixture has deferred background cleanup in both layouts");
        [browser revealNote:other options:0];
        Check([browser selectedNoteObject] == other && [[editor string] isEqual:@"other source"], @"note switch installs the new source before pending cleanup");
        InstallBackground(editor);
        Check(HasBackground(editor), @"new note accepts fresh search backgrounds");
        [[peer window] close]; Pump();
        Check(![[app browserControllers] containsObject:peer], @"peer closes while old-source cleanup was pending");
        Check([[editor string] isEqual:@"other source"] && Await(^BOOL { return HasBackground(editor); }, 4),
            @"new note retains search highlights after the old source's cleanup and closure");
        Check(Render(editor) != nil, @"remaining browser renders after peer closure");
        [editor removeHighlightedTerms];
        NSLog(@"SOURCE BACKSPACE PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"SOURCE BACKSPACE EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
