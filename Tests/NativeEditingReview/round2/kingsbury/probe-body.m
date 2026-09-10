
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *a = self;
        NoteObject *note = MakeNote(library, @"Round 2 shared source",
            @"# Initial\nbody\n");
        NoteObject *other = MakeNote(library, @"Round 2 peer note", @"other\n");
        [note setSourceSyntaxIdentifier:@"markdown"];
        [a revealNote:note options:0];
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        [b revealNote:note options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"];
        LinkingEditor *eb = [b valueForKey:@"textView"];
        NVNoteEditingSession *session = [app editingSessionForNote:note];

        Check([ea textStorage] == [eb textStorage] &&
              [ea textStorage] == [session textStorage],
              @"two windows share the session's character storage");
        Check([ea layoutManager] != [eb layoutManager] &&
              [[[session textStorage] layoutManagers] count] == 2,
              @"two windows retain independent layouts");
        Check(Await(^BOOL {
            return NVSourceCapturesAreCurrent([ea layoutManager]) &&
                   NVSourceCapturesAreCurrent([eb layoutManager]);
        }, 3.0), @"both layouts converge on the initial syntax revision");

        // Force rapid responder, syntax, search-overlay, and character transitions.
        // The final replacement gives the asynchronous worker an unambiguous result.
        NSArray *syntaxes = @[@"markdown", @"html", @"json", @"plain"];
        for (NSUInteger index = 0; index < 48; index++) {
            AppController *browser = index % 2 ? b : a;
            LinkingEditor *editor = index % 2 ? eb : ea;
            [[browser window] makeKeyAndOrderFront:self];
            [[browser window] makeFirstResponder:editor];
            [note setSourceSyntaxIdentifier:[syntaxes objectAtIndex:index % [syntaxes count]]];
            [editor setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, 1)]]];
            [editor insertText:index % 2 ? @"b" : @"a"
              replacementRange:NSMakeRange([[editor string] length], 0)];
        }
        [[a window] makeKeyAndOrderFront:self];
        [[a window] makeFirstResponder:ea];
        [note setSourceSyntaxIdentifier:@"json"];
        [ea insertText:@"{\"key\": 1}\n" replacementRange:NSMakeRange(0, [[ea string] length])];
        Pump();
        Check([[ea string] isEqual:[eb string]] &&
              [[ea string] isEqual:[[note contentString] string]],
              @"rapid cross-window edits converge in both views and the model");
        Check(!HasBackground(ea) && !HasBackground(eb),
              @"shared edits invalidate per-layout search backgrounds");
        Check(Await(^BOOL {
            return NVSourceCapturesAreCurrent([ea layoutManager]) &&
                   NVSourceCapturesAreCurrent([eb layoutManager]);
        }, 4.0), @"the final JSON generation supersedes all stale syntax work");
        Check(!HasCurrentCapture(ea, 0, @"text.title") &&
              !HasCurrentCapture(eb, 0, @"text.title"),
              @"no Markdown capture survives the final JSON transition");

        // An external write during input-method composition is held until the
        // local transaction ends, then merged because the edits do not overlap.
        [note setSourceSyntaxIdentifier:@"plain"];
        [ea insertText:@"alpha beta" replacementRange:NSMakeRange(0, [[ea string] length])]; Pump();
        [[note undoManager] removeAllActions];
        [ea setSelectedRange:NSMakeRange(0, 0)];
        [ea setMarkedText:@"local " selectedRange:NSMakeRange(6, 0)
          replacementRange:NSMakeRange(0, 0)]; Pump();
        Check([ea hasMarkedText], @"first editor owns an active composition");
        [note setContentString:[[[NSAttributedString alloc]
            initWithString:@"alpha beta remote"] autorelease]]; Pump();
        Check([ea hasMarkedText] && [[ea string] isEqual:@"local alpha beta"],
              @"external content waits while local composition remains visible");
        [ea unmarkText]; [a finishEditing]; Pump();
        Check([[ea string] isEqual:@"local alpha beta remote"] &&
              [[eb string] isEqual:[ea string]] &&
              [[[note contentString] string] isEqual:[ea string]],
              @"nonoverlapping local and external changes merge in every window");
        [session undo]; Pump();
        Check([[ea string] isEqual:@"alpha beta remote"] &&
              [[eb string] isEqual:[ea string]],
              @"Undo preserves the external baseline after the merged composition");
        [session redo]; Pump();
        Check([[ea string] isEqual:@"local alpha beta remote"],
              @"Redo restores the merged local transaction");

        // Close the syntax worker by detaching its last layout while work is
        // queued, then attach fresh layouts and require a current revision.
        NSMutableString *large = [NSMutableString string];
        // Stay below the intentional 4,096 cross-layout display-operation cap.
        for (NSUInteger index = 0; index < 160; index++)
            [large appendFormat:@"## heading %lu\nbody *value*\n", (unsigned long)index];
        [note setSourceSyntaxIdentifier:@"markdown"];
        [ea insertText:large replacementRange:NSMakeRange(0, [[ea string] length])];
        [a revealNote:other options:0];
        [b revealNote:other options:0]; Pump();
        Check([[[session textStorage] layoutManagers] count] == 0,
              @"switching both windows detaches the last layout during queued analysis");
        [a revealNote:note options:0];
        [b revealNote:note options:0]; Pump();
        Check([ea textStorage] == [eb textStorage] &&
              [[[session textStorage] layoutManagers] count] == 2,
              @"reattachment restores one shared storage and two layouts");
        Check(Await(^BOOL {
            return NVSourceCapturesAreCurrent([ea layoutManager]) &&
                   NVSourceCapturesAreCurrent([eb layoutManager]);
        }, 8.0), @"replacement highlighter converges after last-layout detachment");
        Check([[ea string] isEqual:large] && [[eb string] isEqual:large] &&
              [[[note contentString] string] isEqual:large],
              @"worker lifecycle transitions do not lose source characters");

        // The window that produced the edit can disappear before history runs.
        [[note undoManager] removeAllActions];
        [[b window] makeKeyAndOrderFront:self];
        [[b window] makeFirstResponder:eb];
        [eb insertText:@"origin" replacementRange:NSMakeRange([[eb string] length], 0)]; Pump();
        NSString *withOrigin = [[[eb string] copy] autorelease];
        [[b window] close]; Pump();
        Check([[app browserControllers] count] == 1 &&
              [[[session textStorage] layoutManagers] count] == 1,
              @"closing the originating window detaches only its layout");
        [[a window] makeKeyAndOrderFront:self];
        [[a window] makeFirstResponder:ea];
        [ea undo:self]; Pump();
        Check([[ea string] isEqual:large] && [[[note contentString] string] isEqual:large],
              @"history remains available after the originating window closes");
        [ea redo:self]; Pump();
        Check([[ea string] isEqual:withOrigin] &&
              [[[note contentString] string] isEqual:withOrigin],
              @"redo also survives responder and window lifecycle changes");

        NSLog(@"KINGSBURY ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults]
            removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"KINGSBURY ROUND 2 EXCEPTION %@ %@\n%@", [exception name],
              [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
