// Real browser/session histories. Included inside the disposable AppController category.
- (void)nv_ownershipSyntax:(NSString *)identifier {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:identifier action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
    [item setRepresentedObject:identifier]; [self selectSourceSyntax:item];
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSString *original = @"# Ownership heading\n\nbase";
        NSString *external = [original stringByAppendingString:@" REMOTE"];
        NSString *live = [original stringByReplacingCharactersInRange:NSMakeRange(2,0) withString:@"draft "];
        NSString *merged = [external stringByReplacingCharactersInRange:NSMakeRange(2,0) withString:@"draft "];
        NoteObject *alpha = [MakeNote(library,@"Ownership Alpha",original) retain];
        NoteObject *plain = [MakeNote(library,@"Ownership Plain",@"ordinary uncolored source") retain];
        [app newWindow:self]; Pump();
        AppController *peer = [[[app browserControllers] lastObject] retain];
        LinkingEditor *other = [peer valueForKey:@"textView"];
        [self searchForString:@""]; [peer searchForString:@""];
        [self revealNote:alpha options:0]; [peer revealNote:alpha options:0];
        [self setViewingNote:NO]; [peer setViewingNote:NO];
        [self nv_ownershipSyntax:@"markdown"];
        Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([other layoutManager]); }), @"both browser layouts start with current shared Markdown analysis");
        Check([textView textStorage] == [other textStorage], @"both real browser editors attach to one session storage");
        NSUInteger heading = [original rangeOfString:@"Ownership"].location;
        NSColor *color = [[CRColor(textView,heading) copy] autorelease];
        Check(color != nil && ![color isEqual:[self foregrndColor]], @"the heading has an actual foreground color through the drawing delegate");
        [[alpha undoManager] removeAllActions];
        [peer nv_activateBrowser]; [[peer window] makeFirstResponder:other];
        [other setMarkedText:@"draft " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(2,0)];
        Check([other hasMarkedText] && [[[alpha contentString] string] isEqual:original] && ![[alpha undoManager] canUndo], @"native composition changes shared live source without committing the model or adding Undo");
        Check(!NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesCanDisplay([textView layoutManager]), @"composition makes syntax obsolete while preserving provisional display");
        Check([CRColor(textView,heading+6) isEqual:color] && [CRColor(other,heading+6) isEqual:color], @"TextKit shifts the retained heading color in both browser layouts");
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:external] autorelease]];
        Check([other hasMarkedText] && [[textView string] isEqual:live] && [[[alpha contentString] string] isEqual:external], @"the external model snapshot stays deferred behind a peer composition");
        Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]); }), @"the parser completes on the live composition while the external snapshot is deferred");
        Check([other hasMarkedText] && [[[alpha contentString] string] isEqual:external] && ![[alpha undoManager] canUndo], @"completed analysis cannot commit composition, overwrite the external model, or create Undo");
        [textView undo:self]; Pump();
        Check(![other hasMarkedText] && [[[alpha contentString] string] isEqual:external] && [[textView string] isEqual:external] && [[other string] isEqual:external], @"Undo from the peer finishes composition and removes only local draft while preserving external text");
        [textView undo:self]; Pump();
        Check([[[alpha contentString] string] isEqual:external], @"a second Undo cannot resurrect an earlier whole-note snapshot");
        [other redo:self]; Pump();
        Check([[[alpha contentString] string] isEqual:merged] && [[textView string] isEqual:merged] && [[other string] isEqual:merged], @"Redo restores exactly the merged source in both browser editors");
        Check([library totalNoteCount] == 2, @"disjoint external and local edits create no conflict copy");
        Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([other layoutManager]); }), @"both editors eventually receive current analysis after cross-window Undo and Redo");

        // Switch one actual browser immediately, before the 60 ms parser debounce.
        // The remaining editor must retain its old-note display and exact source.
        [[alpha undoManager] removeAllActions];
        [peer nv_activateBrowser]; [[peer window] makeFirstResponder:other];
        [other insertText:@"!" replacementRange:NSMakeRange([[other string] length],0)];
        NSString *edited = [merged stringByAppendingString:@"!"];
        Check(!NVSourceCapturesAreCurrent([other layoutManager]) && NVSourceCapturesCanDisplay([other layoutManager]), @"ordinary editing establishes another provisional revision before a browser switch");
        [self revealNote:plain options:0];
        Check([textView textStorage] != [other textStorage] && [[textView string] isEqual:@"ordinary uncolored source"], @"switching detaches only the originating browser layout");
        Check(!NVSourceCapturesCanDisplay([textView layoutManager]) && [CRColor(textView,2) isEqual:[self foregrndColor]], @"a plain note cannot draw retained colors from the prior note");
        Check([[other string] isEqual:edited] && [[[alpha contentString] string] isEqual:edited], @"the peer keeps the exact edited source and committed model after the other browser switches");
        Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([other layoutManager]); }), @"the still-attached peer completes its pending original-note parse");
        Check([CRColor(textView,2) isEqual:[self foregrndColor]] && ![[plain undoManager] canUndo], @"late original-note completion cannot color the plain note or create its Undo history");
        [peer revealNote:plain options:0];
        Check([textView textStorage] == [other textStorage] && [CRColor(other,2) isEqual:[peer foregrndColor]], @"the last old-note detach also leaves the new note uncolored");
        [self revealNote:alpha options:0];
        Check([[textView string] isEqual:edited] && !NVSourceCapturesCanDisplay([textView layoutManager]), @"return after the last detach starts from exact source without reusing the closed highlighter revision");
        Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]); }), @"returning creates and completes new analysis for the original note");
        [textView undo:self]; Pump();
        Check([[[alpha contentString] string] isEqual:merged] && [[textView string] isEqual:merged] && [[other string] isEqual:@"ordinary uncolored source"], @"Undo after full detach removes exactly the earlier insertion without changing the peer note");
        [textView redo:self]; Pump();
        Check([[[alpha contentString] string] isEqual:edited], @"Redo after full detach restores exactly the insertion");

        // Library deletion uses library Undo; body history stays with its note.
        [[library undoManager] removeAllActions];
        [library removeNote:alpha]; Pump();
        Check(![[library allNotes] containsObject:alpha] && [CRColor(other,2) isEqual:[peer foregrndColor]], @"deleting the colored note leaves the plain-note peer display uncolored");
        [[library undoManager] undo]; Pump(); [self revealNote:alpha options:0];
        Check([[library allNotes] containsObject:alpha] && [[[alpha contentString] string] isEqual:edited] && [[alpha sourceSyntaxIdentifier] isEqual:@"markdown"], @"deletion Undo restores the exact source and its local syntax identity");
        Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]); }), @"the restored note receives fresh current syntax analysis");
        [textView undo:self]; Pump();
        // Library Undo reveals the restored note in the active peer browser.
        // Assert that this browser owns its newly selected source, and that the
        // unselected plain note has not acquired either content or Undo changes.
        Check([[[alpha contentString] string] isEqual:merged] && [peer selectedNoteObject] == alpha && [[other string] isEqual:merged], @"body Undo after deletion Undo retains the original edit boundary in both restored-note editors");
        Check([[[plain contentString] string] isEqual:@"ordinary uncolored source"], @"library Undo selection routing cannot rewrite the previously selected plain note");
        __block BOOL leaked = NO;
        for (NoteObject *note in @[alpha,plain]) {
            [[note contentString] enumerateAttribute:NVSourceCaptureAttributeName inRange:NSMakeRange(0,[[note contentString] length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) leaked = YES; }];
        }
        Check(!leaked, @"neither committed model contains temporary syntax capture attributes after the histories");
        Check([library totalNoteCount] == 2 && ![[plain undoManager] canUndo], @"all histories retain exactly two notes and no unrelated plain-note Undo actions");
        NSLog(@"OUSTERHOUT SYNTAX ROUND 2 COMPLETE: %lu checks",(unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal]; [peer release]; [alpha release]; [plain release]; exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@",exception); exit(1); }
}
