
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *a = self;
        NoteObject *note = MakeNote(library, @"Round 3 shared source",
            @"# Shared\nhttps://example.com [[Other]]\n");
        [note setSourceSyntaxIdentifier:@"markdown"];
        [a revealNote:note options:0];
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        [b revealNote:note options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"];
        LinkingEditor *eb = [b valueForKey:@"textView"];
        NVNoteEditingSession *session = [app editingSessionForNote:note];
        NSTextStorage *storage = [session textStorage];

        Check([ea textStorage] == storage && [eb textStorage] == storage,
              @"both windows use the session's single character store");
        Check([ea layoutManager] != [eb layoutManager] &&
              [[storage layoutManagers] count] == 2,
              @"both windows retain independent layout state");
        Check(Await(^BOOL {
            return NVSourceCapturesAreCurrent([ea layoutManager]) &&
                   NVSourceCapturesAreCurrent([eb layoutManager]);
        }, 3.0), @"both syntax layouts converge on the initial revision");

        NSRange initialURL = [[storage string] rangeOfString:@"https://example.com"];
        Check(initialURL.location != NSNotFound &&
              [storage attribute:NSLinkAttributeName atIndex:initialURL.location effectiveRange:NULL] != nil,
              @"the shared session starts with detected links");

        // Finder state belongs to a browser even though the source characters do not.
        [[b window] makeKeyAndOrderFront:self];
        [[b window] makeFirstResponder:eb];
        NSMenuItem *showFind = [[[NSMenuItem alloc] initWithTitle:@"Find"
            action:@selector(performFindPanelAction:) keyEquivalent:@""] autorelease];
        [showFind setTag:1];
        [eb performFindPanelAction:showFind]; Pump();
        Check([eb textFinderIsVisible], @"the second window opens its native find bar");
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:a];
        Pump();
        Check([eb textFinderIsVisible],
              @"a first-window finder notification does not hide the second find bar");

        // The session observes this valid TextKit character mutation and both layouts
        // receive it, but current link maintenance only runs from LinkingEditor hooks.
        NSString *directLine = @"direct https://session.example/path\n";
        NSUInteger directLocation = [storage length];
        [storage replaceCharactersInRange:NSMakeRange(directLocation, 0) withString:directLine];
        Pump();
        NSRange directURL = [[storage string] rangeOfString:@"https://session.example/path"];
        Check([[ea string] isEqual:[eb string]] && directURL.location != NSNotFound,
              @"a session-observed character mutation reaches both windows");
        Check([storage attribute:NSLinkAttributeName atIndex:directURL.location effectiveRange:NULL] == nil,
              @"session-observed characters do not receive link maintenance");
        [session commitTextChanges]; Pump();
        Check([[[note contentString] string] isEqual:[storage string]],
              @"the session can commit the same mutation despite missing link metadata");

        // By contrast, a foreground view edit invokes the view-owned maintenance.
        [[a window] makeKeyAndOrderFront:self];
        [[a window] makeFirstResponder:ea];
        NSString *viewLine = @"view https://view.example/path\n";
        [ea insertText:viewLine replacementRange:NSMakeRange([storage length], 0)]; Pump();
        NSRange viewURL = [[storage string] rangeOfString:@"https://view.example/path"];
        Check(viewURL.location != NSNotFound &&
              [storage attribute:NSLinkAttributeName atIndex:viewURL.location effectiveRange:NULL] != nil,
              @"the foreground view path applies link maintenance to shared storage");
        Check([[ea string] isEqual:[eb string]] &&
              [[ea string] isEqual:[[note contentString] string]],
              @"the foreground edit still converges in both windows and the model");

        [ea setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, 1)]]];
        [eb setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(2, 2)]]];
        Check(HasBackground(ea) && HasBackground(eb),
              @"search overlays remain layout-local before a shared edit");
        [eb insertText:@"x" replacementRange:NSMakeRange([[eb string] length], 0)]; Pump();
        Check(!HasBackground(ea) && !HasBackground(eb),
              @"a shared edit invalidates stale search overlays in both layouts");

        [note setSourceSyntaxIdentifier:@"json"];
        [ea insertText:@"{\"final\": true}\n"
          replacementRange:NSMakeRange(0, [[ea string] length])]; Pump();
        Check(Await(^BOOL {
            return NVSourceCapturesAreCurrent([ea layoutManager]) &&
                   NVSourceCapturesAreCurrent([eb layoutManager]);
        }, 4.0), @"the final JSON generation supersedes older syntax work");
        Check([[ea string] isEqual:[eb string]] &&
              [[ea string] isEqual:[[note contentString] string]],
              @"syntax work does not split shared source state");

        [[note undoManager] removeAllActions];
        [eb insertText:@"origin" replacementRange:NSMakeRange([[eb string] length], 0)]; Pump();
        NSString *withOrigin = [[[eb string] copy] autorelease];
        [[b window] close]; Pump();
        Check([[app browserControllers] count] == 1 &&
              [[storage layoutManagers] count] == 1,
              @"closing the origin window detaches only its layout");
        [[a window] makeKeyAndOrderFront:self];
        [[a window] makeFirstResponder:ea];
        [ea undo:self]; Pump();
        Check(![[ea string] isEqual:withOrigin] &&
              [[ea string] isEqual:[[note contentString] string]],
              @"Undo remains session-owned after the origin window closes");
        [ea redo:self]; Pump();
        Check([[ea string] isEqual:withOrigin] &&
              [[ea string] isEqual:[[note contentString] string]],
              @"Redo restores the shared model after the lifecycle change");

        NSLog(@"KINGSBURY ROUND 3 REPRODUCED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults]
            removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"KINGSBURY ROUND 3 EXCEPTION %@ %@\n%@", [exception name],
              [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
