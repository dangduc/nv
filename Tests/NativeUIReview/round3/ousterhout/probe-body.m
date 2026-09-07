    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        void (^activate)(AppController *) = ^(AppController *browser) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [NSApp activateIgnoringOtherApps:YES];
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [[browser window] makeKeyAndOrderFront:browser];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
            while ((![[browser window] isKeyWindow] || ![[browser window] isMainWindow] || ![NSApp isActive]) &&
                   [deadline timeIntervalSinceNow] > 0) Pump();
            Check([NSApp isActive] && [[browser window] isKeyWindow] && [[browser window] isMainWindow] &&
                  [app activeBrowser] == browser, @"native activation supplies the actual key and main browser");
        };
        NoteObject *note = [MakeNote(library, @"Title000", @"Body000") retain];
        [self revealNote:note options:0]; Pump();
        activate(self);
        [[self window] makeFirstResponder:textView];
        NVNoteEditingSession *session = [app editingSessionForNote:note];
        NSUndoManager *undo = [note undoManager];
        [undo removeAllActions];
        void *targetAddress = [session valueForKey:@"metadataUndoTarget"];
        Check([undo levelsOfUndo] == 200 && ![undo canUndo] && ![undo canRedo],
              @"the note begins with an empty history and the production 200-action limit");

        // This oracle derives values from the input index, not from model snapshots.
        void (^expectState)(NSUInteger, NSString *) = ^(NSUInteger index, NSString *phase) {
            NSUInteger titleIndex = index ? index - ((index - 1) % 3) : 0;
            NSUInteger tagsIndex = index >= 2 ? index - ((index - 2) % 3) : 0;
            NSUInteger bodyIndex = index - (index % 3);
            NSString *title = [NSString stringWithFormat:@"Title%03lu", (unsigned long)titleIndex];
            NSString *tags = tagsIndex ? [NSString stringWithFormat:@"tag%03lu", (unsigned long)tagsIndex] : @"";
            NSString *body = [NSString stringWithFormat:@"Body%03lu", (unsigned long)bodyIndex];
            BOOL matches = [titleOfNote(note) isEqual:title] && [(labelsOfNote(note) ?: @"") isEqual:tags] &&
                           [[[note contentString] string] isEqual:body] && [[textView string] isEqual:body];
            if (!matches) NSLog(@"STATE MISMATCH %@ index=%lu title=%@/%@ tags=%@/%@ body=%@/%@", phase,
                (unsigned long)index, titleOfNote(note), title, labelsOfNote(note), tags, [[note contentString] string], body);
            Check(matches, [NSString stringWithFormat:@"%@ matches the input oracle at action %lu", phase, (unsigned long)index]);
        };
        void (^historyStep)(SEL, NSUInteger, NSString *) = ^(SEL action, NSUInteger index, NSString *phase) {
            Check([NSApp isActive] && [NSApp keyWindow] == [self window] && [NSApp mainWindow] == [self window] &&
                  [[self window] firstResponder] == textView, @"history dispatch retains the actual native body responder");
            Check([NSApp sendAction:action to:nil from:self], @"the responder chain dispatches the history action");
            expectState(index, phase);
            if (index % 25 == 0) Pump();
        };

        // Case 1: 217 independent edits exceed the limit by 17 actions.
        for (NSUInteger index = 1; index <= 217; index++) {
            NSAutoreleasePool *stepPool = [NSAutoreleasePool new];
            if (index % 3 == 1) {
                [app setNote:note metadataValue:[NSString stringWithFormat:@"Title%03lu", (unsigned long)index] isTitle:YES];
            } else if (index % 3 == 2) {
                [app setNote:note metadataValue:[NSString stringWithFormat:@"tag%03lu", (unsigned long)index] isTitle:NO];
            } else {
                [textView insertText:[NSString stringWithFormat:@"Body%03lu", (unsigned long)index]
                   replacementRange:NSMakeRange(0, [[textView string] length])];
            }
            expectState(index, @"Forward edit");
            Check([app editingSessionForNote:note] == session &&
                  (void *)[session valueForKey:@"metadataUndoTarget"] == targetAddress,
                  @"repeated body and metadata edits keep the same session and metadata target");
            if (index % 25 == 0) Pump();
            [stepPool drain];
        }
        Pump();
        NSUInteger undos = 0;
        while ([session canUndo] && undos < 218) {
            undos++;
            historyStep(@selector(undo:), 217 - undos, @"Undo");
        }
        NSLog(@"R3 CAP firstUndoCount=%lu floorAction=%lu expectedCount=200 expectedFloor=17",
              (unsigned long)undos, (unsigned long)(217 - undos));
        Check(undos == 200 && ![session canUndo] && [session canRedo],
              @"Undo exposes exactly the latest 200 actions and stops at the retained floor");
        expectState(17, @"Retained floor");
        NSUInteger redos = 0;
        while ([session canRedo] && redos < 218) {
            redos++;
            historyStep(@selector(redo:), 17 + redos, @"Redo");
        }
        Check(redos == 200 && ![session canRedo], @"Redo restores exactly the 200 retained actions");
        expectState(217, @"Restored final state");
        NSLog(@"R3 CAP firstRedoCount=%lu finalAction=217", (unsigned long)redos);

        // Case 2: a pending native title commit on close must evict one more action.
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:note options:0]; Pump();
        activate(peer);
        [peer renameNote:peer];
        NSTextField *field = [peer valueForKey:@"noteTitleField"];
        NSTextView *fieldEditor = (id)[field currentEditor];
        Check(fieldEditor != nil, @"the full-history browser opens a native title field editor");
        [fieldEditor insertText:@"Title committed on close at capacity"
              replacementRange:NSMakeRange(0, [[fieldEditor string] length])];
        Check([titleOfNote(note) isEqual:@"Title217"], @"the close fixture leaves the title pending in the field editor");
        [[peer window] close]; Pump();
        Check([titleOfNote(note) isEqual:@"Title committed on close at capacity"] && [[app browserControllers] count] == 1,
              @"browser closure commits the pending title while history is full");
        activate(self);
        [[self window] makeFirstResponder:textView];
        Check((void *)[session valueForKey:@"metadataUndoTarget"] == targetAddress && ![session canRedo],
              @"the close commit uses the existing target and leaves no redo branch");
        historyStep(@selector(undo:), 217, @"Undo close commit");
        NSUInteger afterCloseUndos = 1;
        while ([session canUndo] && afterCloseUndos < 219) {
            afterCloseUndos++;
            historyStep(@selector(undo:), 218 - afterCloseUndos, @"Undo after close");
        }
        NSLog(@"R3 CAP closeUndoCount=%lu floorAction=%lu expectedCount=200 expectedFloor=18",
              (unsigned long)afterCloseUndos, (unsigned long)(218 - afterCloseUndos));
        Check(afterCloseUndos == 200 && ![session canUndo],
              @"the close commit evicts one oldest action and retains exactly 200 actions");
        expectState(18, @"Floor after close commit");
        for (NSUInteger index = 19; index <= 217; index++) historyStep(@selector(redo:), index, @"Redo after close");
        Check([session canRedo] && [NSApp sendAction:@selector(redo:) to:nil from:self],
              @"the final retained redo dispatches the close commit");
        Check([titleOfNote(note) isEqual:@"Title committed on close at capacity"] &&
              [labelsOfNote(note) isEqual:@"tag215"] && [[[note contentString] string] isEqual:@"Body216"] &&
              ![session canRedo], @"Redo restores the close commit and preserves the final tags and body");
        NSLog(@"R3 CAP closeRedoCount=200 finalTitle=%@", titleOfNote(note));
        [library flushAllNoteChanges]; [library closeJournal]; [note release];
        NSLog(@"OUSTERHOUT ROUND3 PASSED (%lu checks)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        _exit(0);
    } @catch(NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
@end
