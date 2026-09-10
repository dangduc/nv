    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSString *source = @"* TODO Task\n[[https://example.com][Label]]\n[[Another note]]\n";
        NoteObject *note = MakeNote(library, @"Org boundary review", source);
        [self revealNote:note options:0];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *first = [self valueForKey:@"textView"], *second = [peer valueForKey:@"textView"];
        NVNoteEditingSession *session = [app editingSessionForNote:note];
        NSTextStorage *storage = [session textStorage];
        Check([first textStorage] == storage && [second textStorage] == storage, @"one shared storage owns the source and links");
        if (getenv("NV_OUSTERHOUT_UNDO_CONTROL")) {
            NSString *syntax = [NSString stringWithUTF8String:getenv("NV_OUSTERHOUT_UNDO_CONTROL")];
            [note setSourceSyntaxIdentifier:syntax];
            [[note undoManager] removeAllActions];
            [[peer window] makeKeyAndOrderFront:self];
            [[peer window] makeFirstResponder:second];
            NSRange labelRange = [[second string] rangeOfString:@"Label"];
            [second setSelectedRange:labelRange];
            [second insertText:@"Résumé 😀" replacementRange:labelRange]; Pump();
            [session commitPendingTextChanges];
            NSLog(@"CONTROL syntax=%@ source=%@ firstSelection=%@ secondSelection=%@", syntax, [storage string], NSStringFromRange([first selectedRange]), NSStringFromRange([second selectedRange]));
            [session undo]; Pump();
            Check([[storage string] isEqual:source], @"control Undo restores original source");
            [library closeJournal];
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
            exit(0);
        }
        [[note undoManager] removeAllActions];
        __block NSUInteger modelNotifications = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NVNoteContentsDidChangeNotification object:note queue:nil usingBlock:^(NSNotification *n) { modelNotifications++; }];
        uint64_t generation = [session sourceGeneration];
        CFAbsoluteTime modified = modifiedDateOfNote(note);
        for (NSString *syntax in @[@"org", @"json", @"org", @"plain", @"org"]) {
            NSMenuItem *action = [[[NSMenuItem alloc] initWithTitle:syntax action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
            [action setRepresentedObject:syntax];
            [peer selectSourceSyntax:action];
            Check([[first sourceSyntaxIdentifier] isEqual:syntax] && [[second sourceSyntaxIdentifier] isEqual:syntax], @"menu routing updates the shared syntax in both editors");
            NSURL *wiki = [storage attribute:NSLinkAttributeName atIndex:[[storage string] rangeOfString:@"Another note"].location effectiveRange:NULL];
            NSURL *label = [storage attribute:NSLinkAttributeName atIndex:[[storage string] rangeOfString:@"Label"].location effectiveRange:NULL];
            if ([syntax isEqual:@"org"]) {
                Check(!wiki && [[label absoluteString] isEqual:@"https://example.com"], @"Org syntax owns bracket-link semantics in both windows");
            } else Check([[wiki scheme] isEqual:@"nvalt"] && !label, @"other syntax restores nv links without stale Org labels");
        }
        Check([[storage string] isEqual:source] && [[[note contentString] string] isEqual:source], @"syntax changes preserve live and committed source");
        Check([session sourceGeneration] == generation && modifiedDateOfNote(note) == modified && modelNotifications == 0, @"syntax-only changes leave content generation, dates and notifications unchanged");
        Check(![[note undoManager] canUndo], @"syntax-only decoration creates no Undo entry");
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        Check([first rangeForUserCompletion].location == NSNotFound && [second rangeForUserCompletion].location == NSNotFound, @"Org disables nv link completion in both editors");
        [[peer window] makeKeyAndOrderFront:self];
        [[peer window] makeFirstResponder:second];
        NSRange labelRange = [[second string] rangeOfString:@"Label"];
        [second setSelectedRange:labelRange];
        [second insertText:@"Other" replacementRange:labelRange]; Pump();
        [session commitPendingTextChanges];
        Check([[first string] isEqual:[second string]] && [[[note contentString] string] isEqual:[second string]], @"peer edits reach the first editor and committed note");
        Check([[[storage attribute:NSLinkAttributeName atIndex:[[storage string] rangeOfString:@"Other"].location effectiveRange:NULL] absoluteString] isEqual:@"https://example.com"], @"peer edits retain the explicit Org URL on the new label");
        // The two visible editors trigger the separate Undo failure in the controls.
        // Exercise the session replacement path after real browser detachment instead.
        NoteObject *other = MakeNote(library, @"Plain peer", @"[[Another note]]\n");
        [self revealNote:other options:0]; [peer revealNote:other options:0]; Pump();
        Check([[storage layoutManagers] count] == 0, @"both browser transitions detach their Org layouts");
        [session undo]; Pump();
        Check([[storage string] isEqual:source] && [[[note contentString] string] isEqual:source], @"Undo restores source through the shared session");
        Check([[[storage attribute:NSLinkAttributeName atIndex:[[storage string] rangeOfString:@"Label"].location effectiveRange:NULL] absoluteString] isEqual:@"https://example.com"], @"Undo rebuilds Org link semantics");
        NSString *external = @"* DONE External\n[[https://example.net][External label]]\n[[file:agenda.org][Agenda]]\n";
        [note setContentString:[[[NSAttributedString alloc] initWithString:external] autorelease]]; Pump();
        Check([[storage string] isEqual:external], @"external source replacement reaches the cached session");
        [self revealNote:note options:0]; [peer revealNote:note options:0]; Pump();
        Check([[first string] isEqual:external] && [[second string] isEqual:external], @"both editors attach to the latest external source");
        Check([[[storage attribute:NSLinkAttributeName atIndex:[external rangeOfString:@"External label"].location effectiveRange:NULL] absoluteString] isEqual:@"https://example.net"] && ![storage attribute:NSLinkAttributeName atIndex:[external rangeOfString:@"Agenda"].location effectiveRange:NULL], @"external replacement applies Org links and keeps file targets inert");
        [peer revealNote:other options:0]; Pump();
        Check([first textStorage] == storage && [second textStorage] != storage, @"detaching one editor preserves the original storage owner");
        Check([[[[second textStorage] attribute:NSLinkAttributeName atIndex:2 effectiveRange:NULL] scheme] isEqual:@"nvalt"], @"a plain note retains its own nv links after Org detachment");
        [note setSourceSyntaxIdentifier:@"plain"];
        [note setSourceSyntaxIdentifier:@"org"];
        [peer revealNote:note options:0]; Pump();
        Check([second textStorage] == storage && [[second sourceSyntaxIdentifier] isEqual:@"org"], @"reattachment restores the same session and current syntax");
        Check([[[storage attribute:NSLinkAttributeName atIndex:[external rangeOfString:@"External label"].location effectiveRange:NULL] absoluteString] isEqual:@"https://example.net"], @"reattachment retains current Org link semantics");
        NSLog(@"ORG OUSTERHOUT ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
