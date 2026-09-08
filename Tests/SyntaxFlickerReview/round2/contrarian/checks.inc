- (void)cq_checkQueriesWithPeer:(AppController *)peer first:(NSString *)first second:(NSString *)second {
    LinkingEditor *other = [peer valueForKey:@"textView"];
    Check([[[self browserSession] searchString] isEqual:first] && [[[peer browserSession] searchString] isEqual:second],
        @"each browser retains its independent actual query");
    Check([CQBackgrounds(textView) isEqual:CQMatches([textView string], first)],
        @"first window drawing backgrounds cover exactly its query matches");
    Check([CQBackgrounds(other) isEqual:CQMatches([other string], second)],
        @"peer drawing backgrounds cover exactly its different query matches");
}
- (void)cq_refreshQueriesWithPeer:(AppController *)peer {
    // The native preference callback removes old search backgrounds and rebuilds
    // them from each browser's real cached query. No temporary attributes are injected.
    [[GlobalPrefs defaultPrefs] setShouldHighlightSearchTerms:NO sender:self];
    [[GlobalPrefs defaultPrefs] setShouldHighlightSearchTerms:YES sender:self];
    [self cq_checkQueriesWithPeer:peer first:@"alpha" second:@"beta"];
}
- (void)nv_runTests {
    BOOL baseline = getenv("NV_CQ_BASELINE") != NULL;
    NVApplicationController *app = [NVApplicationController sharedController];
    NotationController *library = [self sharedNotationController];
    [self nv_activateBrowser]; [app newWindow:self];
    AppController *peer = [[app browserControllers] lastObject];
    LinkingEditor *other = [peer valueForKey:@"textView"];
    Check(peer != self, @"actual query review has two browser windows");
    [[GlobalPrefs defaultPrefs] setShouldHighlightSearchTerms:YES sender:self];
    NoteObject *plain = MakeNote(library, @"Uncolored control", @"alpha and beta plain source only");
    NSArray *fixtures = @[
        @{@"syntax":@"markdown", @"source":@"# Alpha heading\n\nBeta body\n\nAlpha and beta tail\n", @"token":@"Alpha"},
        @{@"syntax":@"html", @"source":@"<h1>Alpha</h1><p>Beta body</p><p>Alpha and beta</p>", @"token":@"h1"},
        @{@"syntax":@"json", @"source":@"{\"Alpha\":42,\"Beta\":\"Alpha and beta\"}", @"token":@"Alpha"}
    ];
    for (NSDictionary *fixture in fixtures) {
        NSString *source = fixture[@"source"], *syntax = fixture[@"syntax"];
        NoteObject *note = MakeNote(library, [@"Query fixture " stringByAppendingString:syntax], source);
        [self searchForString:@"alpha"]; [self revealNote:note options:0];
        [peer searchForString:@"beta"]; [peer revealNote:note options:0];
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:syntax action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
        [item setRepresentedObject:syntax]; [self selectSourceSyntax:item];
        Check(CQWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([other layoutManager]); }), @"both query windows start with current syntax");
        [self cq_checkQueriesWithPeer:peer first:@"alpha" second:@"beta"];
        NSUInteger token = [source rangeOfString:fixture[@"token"]].location;
        NSColor *color = [[CQDraw(textView,token)[NSForegroundColorAttributeName] copy] autorelease];
        NSColor *peerColor = [[CQDraw(other,token)[NSForegroundColorAttributeName] copy] autorelease];
        Check(color && ![color isEqual:[self foregrndColor]], @"unaffected token starts with a drawn syntax color");
        [self nv_activateBrowser]; [window makeFirstResponder:textView];
        [textView insertText:@" alpha beta" replacementRange:NSMakeRange([source length], 0)];
        Check(!NVSourceCapturesAreCurrent([textView layoutManager]), @"native insertion makes analysis obsolete before the run loop");
        BOOL retained = [CQDraw(textView,token)[NSForegroundColorAttributeName] isEqual:color] && [CQDraw(other,token)[NSForegroundColorAttributeName] isEqual:peerColor];
        NSLog(@"OBSERVATION %@ provisional color retained=%d baseline=%d", syntax, retained, baseline);
        if (!baseline) Check(retained, @"actual query windows keep unaffected syntax colors while analysis is pending");
        Check([CQBackgrounds(textView) count] == 0, @"editing begins by clearing only the active editor's search backgrounds");
        Check([CQBackgrounds(other) isEqual:CQMatches(source,@"beta")], @"peer keeps its existing beta query ranges immediately after the shared insertion");
        [self finishEditing];
        NSString *edited = [source stringByAppendingString:@" alpha beta"];
        Check([[textView string] isEqual:edited] && [[other string] isEqual:edited] && [[[note contentString] string] isEqual:edited], @"native insertion preserves exact shared and committed source");
        [self cq_refreshQueriesWithPeer:peer];
        Check(!NVSourceCapturesAreCurrent([textView layoutManager]), @"real query refresh also works while syntax is provisional");
        [textView undo:self];
        Check([[textView string] isEqual:source] && [[other string] isEqual:source], @"native Undo restores exact source in both query windows");
        [self cq_refreshQueriesWithPeer:peer];
        [textView redo:self];
        Check([[textView string] isEqual:edited] && [[other string] isEqual:edited], @"native Redo restores exact source in both query windows");
        [self cq_refreshQueriesWithPeer:peer];
        Check(CQWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([other layoutManager]); }), @"both windows receive current captures after Undo and Redo");
        [self cq_checkQueriesWithPeer:peer first:@"alpha" second:@"beta"];
        Check([CQDraw(textView,token)[NSForegroundColorAttributeName] isEqual:color] && [CQDraw(other,token)[NSForegroundColorAttributeName] isEqual:peerColor], @"fresh syntax preserves drawn colors with real query backgrounds");
        [textView insertText:@" " replacementRange:NSMakeRange([edited length],0)];
        Check(!NVSourceCapturesAreCurrent([other layoutManager]), @"note-switch history starts with pending shared analysis");
        [self revealNote:plain options:0];
        Check([self selectedNoteObject] == plain && [peer selectedNoteObject] == note && [[textView string] isEqual:[[plain contentString] string]], @"switch attaches only the active editor to the plain note");
        BOOL plainColors = YES, privateCapture = NO;
        for (NSUInteger index=0; index<[[textView string] length]; index++) {
            NSDictionary *drawn = CQDraw(textView,index);
            plainColors &= [drawn[NSForegroundColorAttributeName] isEqual:[self foregrndColor]];
            privateCapture |= drawn[NVSourceCaptureAttributeName] != nil;
        }
        Check(plainColors && !privateCapture, @"pending old-note syntax cannot color any character of the plain note");
        Check([CQBackgrounds(textView) isEqual:CQMatches([textView string],@"alpha")], @"plain note receives only the active window's actual alpha query backgrounds");
        if (!baseline) Check([CQDraw(other,token)[NSForegroundColorAttributeName] isEqual:peerColor], @"switching a peer away keeps this window's provisional source colors");
        [self revealNote:note options:0];
        Check([self selectedNoteObject] == note && [textView textStorage] == [other textStorage], @"return attaches the original shared source storage");
        [self cq_refreshQueriesWithPeer:peer];
        Check(CQWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([other layoutManager]); }), @"returned note receives fresh analysis in both query windows");
        [self cq_checkQueriesWithPeer:peer first:@"alpha" second:@"beta"];
        Check([CQDraw(textView,token)[NSForegroundColorAttributeName] isEqual:color], @"returned note restores its syntax color instead of the plain-note color");
        Check([[[note contentString] string] isEqual:[edited stringByAppendingString:@" "]], @"note switches preserve the final exact committed source");
        NSLog(@"COMPLETED actual-query history %@", syntax);
    }
    NSLog(@"CONTRARIAN ROUND 2 COMPLETE: %lu checks baseline=%d", (unsigned long)Checks, baseline);
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
}
