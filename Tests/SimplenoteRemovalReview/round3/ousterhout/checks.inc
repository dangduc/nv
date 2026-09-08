- (void)nv_setReviewMetadata:(NSString *)value title:(BOOL)isTitle {
    [self nv_activateBrowser];
    if (isTitle) [self renameNote:self]; else [self tagNote:self];
    NSTextField *metadataField = [self valueForKey:isTitle ? @"noteTitleField" : @"noteTagsField"];
    NSTextView *fieldEditor = (id)[metadataField currentEditor];
    Check(fieldEditor != nil, @"metadata action opens its actual native field editor");
    [fieldEditor insertText:value replacementRange:NSMakeRange(0, [[fieldEditor string] length])];
    [self control:metadataField textView:fieldEditor doCommandBySelector:@selector(insertNewline:)]; Pump();
}
- (void)nv_reviewLibraryHistory:(SEL)action {
    [self nv_activateBrowser];
    NSView *list = [self valueForKey:@"notesTableView"];
    Check([[self window] makeFirstResponder:list] && [[self window] firstResponder] == list,
        @"library history command starts with the notes list focused");
    Check([self windowWillReturnUndoManager:[self window]] == [[self sharedNotationController] undoManager],
        @"focused list selects the real library Undo manager");
    NSMenuItem *command = [[[NSMenuItem alloc] initWithTitle:NSStringFromSelector(action) action:action keyEquivalent:@""] autorelease];
    Check([NSApp sendAction:action to:nil from:command], @"native responder chain accepts library history command");
    Pump(); Pump();
}
- (void)nv_runTests {
    @try {
        NVApplicationController *owner = [NVApplicationController sharedController];
        NotationController *library = [owner library];
        [[GlobalPrefs defaultPrefs] setConfirmNoteDeletion:NO sender:self];
        [owner newWindow:self]; Pump();
        AppController *peer = [[owner browserControllers] lastObject];
        Check(peer != self && [[owner browserControllers] count] == 2, @"two real browser windows share this library");
        NoteObject *sentinel = MakeNote(library, @"Unrelated source", @"sentinel source\n");
        NSString *original = @"# Review café 😀\r\n\t<source> & exact\r\n";
        for (NSString *history in @[@"two-attached", @"peer-switched", @"peer-closed"]) {
            NSLog(@"DELETION OWNERSHIP HISTORY %@", history);
            NoteObject *note = MakeNote(library, history, original);
            [note setSourceSyntaxIdentifier:@"markdown"];
            [self searchForString:@""]; [peer searchForString:@""];
            [self revealNote:note options:0]; [peer revealNote:note options:0]; Pump();
            NVNoteEditingSession *session = [owner editingSessionForNote:note];
            NSTextStorage *storage = [session textStorage];
            LinkingEditor *a = [self valueForKey:@"textView"], *b = [peer valueForKey:@"textView"];
            Check([a textStorage] == storage && [b textStorage] == storage && [[storage layoutManagers] count] == 2,
                @"both native editors attach distinct layouts to the one cached source");
            [[note undoManager] removeAllActions];
            [self nv_activateBrowser]; [[self window] makeFirstResponder:a];
            [a insertText:@"first\n" replacementRange:NSMakeRange([[a string] length], 0)]; Pump();
            NSString *firstBody = [original stringByAppendingString:@"first\n"];
            [self nv_setReviewMetadata:[history stringByAppendingString:@" renamed"] title:YES];
            [peer nv_activateBrowser]; [[peer window] makeFirstResponder:b];
            [b insertText:@"peer\n" replacementRange:NSMakeRange([[b string] length], 0)]; Pump();
            [peer nv_setReviewMetadata:@"retained" title:NO];
            NSString *finalBody = [firstBody stringByAppendingString:@"peer\n"];
            NSString *finalTitle = [history stringByAppendingString:@" renamed"];
            CFUUIDBytes uuid = *[note uniqueNoteIDBytes];
            Check([[a string] isEqual:finalBody] && [[b string] isEqual:finalBody] &&
                [[[note contentString] string] isEqual:finalBody], @"both native edits preserve the exact UTF-16 source in both views and model");
            Check([titleOfNote(note) isEqual:finalTitle] && [labelsOfNote(note) isEqual:@"retained"],
                @"native title and tags commit to the intended note before deletion");
            Check([[note undoManager] canUndo] && [session canUndo], @"source and metadata have a real note history before deletion");

            if ([history isEqual:@"peer-switched"]) {
                [peer revealNote:sentinel options:0]; Pump();
                Check([[storage layoutManagers] count] == 1 && [b textStorage] != storage,
                    @"peer switch leaves exactly the deleting browser attached");
            }
            [[library undoManager] removeAllActions];
            [self nv_activateBrowser]; [[self window] makeFirstResponder:[self valueForKey:@"notesTableView"]];
            Check([self selectedNoteObject] == note, @"browser Delete targets the intended selected note");
            Check([NSApp sendAction:@selector(deleteNote:) to:owner from:self], @"application command routing dispatches actual browser Delete");
            Pump(); Pump();
            Check([[library allNotes] indexOfObjectIdenticalTo:note] == NSNotFound, @"browser Delete removes the model from the authoritative library");
            Check([self selectedNoteObject] != note && [peer selectedNoteObject] != note && [[storage layoutManagers] count] == 0,
                @"list refresh detaches every editor from the removed note");
            Check([a textStorage] != storage && [b textStorage] != storage,
                @"no live browser editor still exposes the deleted cached session");
            Check([[library undoManager] canUndo], @"actual browser deletion registers a recoverable library Undo action");
            Check([[storage string] isEqual:finalBody] && [owner editingSessionForNote:note] == session,
                @"cached session keeps exact source for deletion Undo without a live editor attachment");
            [owner setNote:note metadataValue:@"must not apply" isTitle:YES];
            Check([titleOfNote(note) isEqual:finalTitle], @"application metadata routing rejects a removed note");
            if ([history isEqual:@"peer-switched"])
                Check([peer selectedNoteObject] == sentinel && [[b string] isEqual:@"sentinel source\n"],
                    @"deleting elsewhere preserves the peer's unrelated selection and source");
            if ([history isEqual:@"peer-closed"]) {
                [[peer window] close]; Pump(); Pump();
                Check([[owner browserControllers] count] == 1 && [[storage layoutManagers] count] == 0,
                    @"closing the detached peer keeps the removed session detached");
                peer = nil; b = nil;
            }

            [self nv_reviewLibraryHistory:@selector(undo:)];
            Check([[library allNotes] indexOfObjectIdenticalTo:note] != NSNotFound && [self selectedNoteObject] == note,
                @"native library Undo restores the same model and reveals it in the active browser");
            Check(!memcmp(&uuid, [note uniqueNoteIDBytes], sizeof(uuid)) && [[note sourceSyntaxIdentifier] isEqual:@"markdown"] &&
                [titleOfNote(note) isEqual:finalTitle] && [labelsOfNote(note) isEqual:@"retained"] && [[[note contentString] string] isEqual:finalBody],
                @"deletion Undo preserves UUID, local syntax, title, tags and exact source");
            Check([a textStorage] == storage && [owner editingSessionForNote:note] == session,
                @"deletion Undo reattaches the original cached editing session");
            [self nv_reviewLibraryHistory:@selector(redo:)];
            Check([[library allNotes] indexOfObjectIdenticalTo:note] == NSNotFound && [self selectedNoteObject] != note &&
                [[storage layoutManagers] count] == 0, @"native library Redo removes the note and detaches the restored layout again");
            [self nv_reviewLibraryHistory:@selector(undo:)];
            Check([[library allNotes] indexOfObjectIdenticalTo:note] != NSNotFound && [[a string] isEqual:finalBody],
                @"a second native deletion Undo recovers exact source after Redo");
            if (!peer) { [owner newWindow:self]; Pump(); peer = [[owner browserControllers] lastObject]; }
            [peer revealNote:note options:0]; Pump(); b = [peer valueForKey:@"textView"];
            Check([a textStorage] == storage && [b textStorage] == storage && [[storage layoutManagers] count] == 2,
                @"the surviving or reopened peer reuses the restored session and its source");

            // The separate note history must retain its original ordering through
            // library deletion Undo/Redo, peer detachment and peer closure.
            NSArray *undoBodies = @[finalBody, firstBody, firstBody, original];
            NSArray *undoTitles = @[finalTitle, finalTitle, history, history];
            [self nv_activateBrowser]; [[self window] makeFirstResponder:a];
            for (NSUInteger step = 0; step < 4; step++) {
                [a undo:self]; Pump();
                Check([[a string] isEqual:undoBodies[step]] && [[b string] isEqual:undoBodies[step]] &&
                    [[[note contentString] string] isEqual:undoBodies[step]] && [titleOfNote(note) isEqual:undoTitles[step]] &&
                    [labelsOfNote(note) length] == 0, [NSString stringWithFormat:@"source Undo step %lu preserves shared body and ordered metadata", (unsigned long)step + 1]);
            }
            Check(![session canUndo] && [session canRedo], @"all four source and metadata history entries are accounted for");
            NSArray *redoBodies = @[firstBody, firstBody, finalBody, finalBody];
            NSArray *redoTitles = @[history, finalTitle, finalTitle, finalTitle];
            for (NSUInteger step = 0; step < 4; step++) {
                [b redo:self]; Pump();
                Check([[a string] isEqual:redoBodies[step]] && [[b string] isEqual:redoBodies[step]] &&
                    [[[note contentString] string] isEqual:redoBodies[step]] && [titleOfNote(note) isEqual:redoTitles[step]] &&
                    [labelsOfNote(note) isEqual:(step == 3 ? @"retained" : @"")],
                    [NSString stringWithFormat:@"peer Redo step %lu restores shared body and ordered metadata", (unsigned long)step + 1]);
            }
            Check(![session canRedo] && [session canUndo], @"replayed note history ends without an extra Redo action");
            [self revealNote:sentinel options:0]; [peer revealNote:sentinel options:0]; Pump();
            Check([[storage layoutManagers] count] == 0 && [[storage string] isEqual:finalBody],
                @"leaving the restored note detaches both layouts without changing its source");
        }
        Check([library flushAllNoteChanges], @"all final local note changes flush successfully");
        [library closeJournal];
        NSLog(@"OUSTERHOUT ROUND 3 PASSED (%lu checks; three browser deletion histories)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
