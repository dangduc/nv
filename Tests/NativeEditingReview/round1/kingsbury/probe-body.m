
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *a = self;
        NoteObject *note = MakeNote(library, @"Shared native editing",
            @"# Heading\nalpha beta\n");
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
              @"both native editors use the session's one text storage");
        Check([ea layoutManager] != [eb layoutManager] &&
              [[[session textStorage] layoutManagers] count] == 2,
              @"each window has an independent layout attached to shared characters");
        Check(Await(^BOOL{
            return NVSourceCapturesAreCurrent([ea layoutManager]) &&
                   NVSourceCapturesAreCurrent([eb layoutManager]);
        }, 3.0), @"asynchronous Markdown highlighting converges in both layouts");
        Check(HasCurrentCapture(ea, 0, @"text.title") ==
              HasCurrentCapture(eb, 0, @"text.title"),
              @"peer layouts publish the same syntax revision");

        [ea setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(10, 5)]]];
        [eb setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(16, 4)]]];
        Check(HasBackground(ea) && HasBackground(eb),
              @"search backgrounds are installed independently in both layouts");
        [[a window] makeKeyAndOrderFront:self];
        [[a window] makeFirstResponder:ea];
        [ea insertText:@"!" replacementRange:NSMakeRange([[ea string] length], 0)]; Pump();
        Check([[ea string] isEqual:[eb string]] &&
              [[ea string] isEqual:[[note contentString] string]],
              @"a native edit converges in both windows and the model");
        Check(!HasBackground(ea) && !HasBackground(eb),
              @"a shared character edit invalidates search backgrounds in both layouts");
        Check(Await(^BOOL{
            return NVSourceCapturesAreCurrent([ea layoutManager]) &&
                   NVSourceCapturesAreCurrent([eb layoutManager]);
        }, 3.0), @"syntax highlighting reconverges after a native edit");

        NSString *committed = [[[note contentString] string] copy];
        [[a window] makeKeyAndOrderFront:self];
        [[a window] makeFirstResponder:ea];
        [ea setSelectedRange:NSMakeRange(10, 5)];
        [ea setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5, 0)
          replacementRange:NSMakeRange(10, 5)]; Pump();
        Check([ea hasMarkedText], @"first window owns an active marked-text composition");
        // Mutate the peer directly. Moving keyboard focus would ask AppKit to
        // finish the first view's composition before the peer can type.
        [eb insertText:@" PEER" replacementRange:NSMakeRange([[eb string] length], 0)]; Pump();
        NSString *composed = [[[ea string] copy] autorelease];
        Check(![ea hasMarkedText] && [composed isEqual:[eb string]] &&
              [composed isEqual:[[note contentString] string]],
              @"a peer mutation closes marked text and serializes both edits into the model");
        [[b window] makeKeyAndOrderFront:self];
        [[b window] makeFirstResponder:eb];
        [eb undo:self]; Pump();
        Check([[ea string] isEqual:committed] &&
              [[eb string] isEqual:committed] &&
              [[[note contentString] string] isEqual:committed],
              @"shared Undo reverses the serialized composition transaction in every view");
        [eb redo:self]; Pump();
        Check([[ea string] isEqual:composed] &&
              [[[note contentString] string] isEqual:composed],
              @"shared Redo restores both serialized edits and the model");
        [committed release];

        [ea setSelectedRange:NSMakeRange([[ea string] length], 0)];
        [ea setMarkedText:@"Z" selectedRange:NSMakeRange(1, 0)
          replacementRange:NSMakeRange([[ea string] length], 0)]; Pump();
        Check([ea hasMarkedText], @"composition survives before peer detachment");
        NoteObject *other = MakeNote(library, @"Detached peer", @"other");
        [b revealNote:other options:0]; Pump();
        Check([eb textStorage] != [ea textStorage] &&
              [[[session textStorage] layoutManagers] count] == 1 && [ea hasMarkedText],
              @"switching the peer detaches only its layout during composition");
        [ea unmarkText]; [a finishEditing]; Pump();
        Check([[[note contentString] string] isEqual:[ea string]],
              @"the remaining editor commits after peer lifecycle changes");
        Check(Await(^BOOL{ return NVSourceCapturesAreCurrent([ea layoutManager]); }, 3.0),
              @"highlighting converges with one layout after peer detachment");

        NSUInteger editCount = 40;
        [b revealNote:note options:0]; Pump();
        [[note undoManager] removeAllActions];
        for (NSUInteger index = 0; index < editCount; index++) {
            LinkingEditor *editor = index % 2 ? eb : ea;
            AppController *browser = index % 2 ? b : a;
            [[browser window] makeKeyAndOrderFront:self];
            [[browser window] makeFirstResponder:editor];
            [editor insertText:index % 2 ? @"b" : @"a"
              replacementRange:NSMakeRange([[editor string] length], 0)];
        }
        Pump();
        NSString *afterInterleave = [[[ea string] copy] autorelease];
        Check([afterInterleave isEqual:[eb string]] &&
              [afterInterleave isEqual:[[note contentString] string]],
              @"forty alternating native edits converge without lost updates");
        for (NSUInteger index = 0; index < editCount; index++) [session undo];
        Pump();
        Check([[ea string] isEqual:[eb string]] &&
              [[ea string] isEqual:[[note contentString] string]] &&
              [afterInterleave length] - [[ea string] length] == editCount,
              @"global history reverses all alternating edits in exact order");

        NSLog(@"KINGSBURY ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults]
            removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"KINGSBURY ROUND 1 EXCEPTION %@ %@\n%@", [exception name],
              [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
