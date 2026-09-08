- (void)nv_runTests {
    @try {
        KeepObsoleteObserver = [[[NSProcessInfo processInfo] arguments] containsObject:@"--retain-obsolete-observer"];
        OwnershipSwap([NVNoteEditingSession class], @selector(close), @selector(ownership_close));
        OwnershipSwap([NVNoteEditingSession class], @selector(reloadFromNote), @selector(ownership_reload));
        NVApplicationController *owner = [NVApplicationController sharedController];
        NotationController *library = [owner library];
        [owner newWindow:self]; Pump();
        AppController *peer = [[owner browserControllers] lastObject];
        Check(peer != self && [[owner browserControllers] count] == 2, @"two real browser controllers own separate windows");
        NoteObject *main = MakeNote(library, @"Library 0", @"# Origin café 😀\n");
        NoteObject *sentinel = MakeNote(library, @"Sentinel 0", @"independent source");

        for (NSUInteger generation = 1; generation <= 3; generation++) {
            NSLog(@"OWNERSHIP HISTORY %lu", (unsigned long)generation);
            [self searchForString:@""]; [peer searchForString:@""];
            [self revealNote:main options:0]; [peer revealNote:main options:0]; Pump();
            LinkingEditor *a = [self valueForKey:@"textView"], *b = [peer valueForKey:@"textView"];
            NVNoteEditingSession *oldSession = [[owner editingSessionForNote:main] retain];
            NoteObject *oldMain = [main retain];
            NotationController *oldLibrary = [library retain];
            NSTextStorage *oldStorage = [oldSession textStorage];
            Check([self sharedNotationController] == library && [peer sharedNotationController] == library,
                @"both browsers access the same library owner");
            Check([a layoutManager] != [b layoutManager] && [a textStorage] == oldStorage && [b textStorage] == oldStorage,
                @"two separate layouts attach to one cached text storage");
            Check([[oldStorage layoutManagers] count] == 2, @"selected note has exactly two editor attachments");
            [self nv_activateBrowser]; [[self window] makeFirstResponder:a];
            [a insertText:@"typed\n" replacementRange:NSMakeRange([[a string] length], 0)]; Pump();
            Check([[a string] isEqual:[b string]] && [[a string] isEqual:[[main contentString] string]],
                @"native source typing commits once and appears in the peer editor");
            NSString *edited = [[a string] copy];
            [peer revealNote:sentinel options:0]; Pump();
            Check([a textStorage] == oldStorage && [b textStorage] != oldStorage && [[oldStorage layoutManagers] count] == 1,
                @"switching the peer note detaches only its own layout");
            Check([[a string] isEqual:edited] && [[b string] isEqual:[[sentinel contentString] string]],
                @"detaching the peer preserves both exact note bodies");
            [peer revealNote:main options:0]; Pump();
            Check([b textStorage] == oldStorage && [[oldStorage layoutManagers] count] == 2,
                @"returning to the note reuses the original session");

            // Prepare an independent same-UUID library before the active library
            // closes. Journal isolation above avoids a fixture-only cache collision.
            NSString *directory = [TestDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"Library%lu", (unsigned long)generation]];
            Check([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL],
                @"replacement uses a new disposable notes directory");
            FSRef ref; OSStatus err = FSPathMakeRef((const UInt8 *)[directory fileSystemRepresentation], &ref, NULL);
            Check(err == noErr, @"replacement directory has a valid file reference");
            NotationController *replacement = [[NotationController alloc] initWithDirectoryRef:&ref error:&err];
            Check(replacement != nil && err == noErr && [[replacement allNotes] count] == 0,
                @"replacement starts with an independent empty library");
            NSString *newBody = [NSString stringWithFormat:@"{\"generation\": %lu, \"source\": \"new\"}\n", (unsigned long)generation];
            NoteObject *newMain = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:newBody] autorelease]
                title:[NSString stringWithFormat:@"Library %lu", (unsigned long)generation] delegate:replacement
                format:[replacement currentNoteStorageFormat] labels:@"replacement"] autorelease];
            memcpy([newMain uniqueNoteIDBytes], [oldMain uniqueNoteIDBytes], sizeof(CFUUIDBytes));
            [replacement addNewNote:newMain];
            [newMain setSourceSyntaxIdentifier:@"json"];
            NoteObject *newSentinel = MakeNote(replacement, @"Other source", @"replacement sentinel");
            Check(newMain != oldMain && !memcmp([newMain uniqueNoteIDBytes], [oldMain uniqueNoteIDBytes], sizeof(CFUUIDBytes)),
                @"same UUID deliberately names distinct model objects across libraries");

            [peer nv_activateBrowser]; [[peer window] makeFirstResponder:b];
            [b setMarkedText:@"未確定" selectedRange:NSMakeRange(3, 0) replacementRange:NSMakeRange([[b string] length], 0)];
            Check([b hasMarkedText] && [[oldMain contentString].string isEqual:edited],
                @"peer has a real uncommitted marked-text edit at the replacement boundary");
            NSString *expectedOld = [edited stringByAppendingString:@"未確定"];
            ObservedSession = oldSession; ObservedCloses = ClosedSessionReloads = 0; SessionHasClosed = NO;
            [owner setLibrary:replacement]; Pump();
            Check([[oldMain contentString].string isEqual:expectedOld] && ![b hasMarkedText],
                @"library replacement commits composition into its original note before detaching");
            Check(ObservedCloses == 1 && [oldSession valueForKey:@"sourceHighlighter"] == nil,
                @"old cached session closes exactly once and releases its source analysis");
            Check([[oldStorage layoutManagers] count] == 0, @"both browser layouts leave the closed session");
            Check(![[oldMain undoManager] canUndo] && ![[oldMain undoManager] canRedo],
                @"closed session removes its old source Undo and Redo targets");
            Check([oldLibrary delegate] == nil && [replacement delegate] == owner,
                @"coordinator detaches the old library delegate before owning the replacement");
            Check([self sharedNotationController] == replacement && [peer sharedNotationController] == replacement,
                @"both windows switch to the replacement library");
            Check([self selectedNoteObject] == nil && [peer selectedNoteObject] == nil,
                @"replacement clears both old note selections");
            Check(![[[owner valueForKey:@"editingSessions"] allValues] containsObject:oldSession],
                @"replacement evicts the old session from the UUID cache");
            [self revealNote:newMain options:0]; [peer revealNote:newMain options:0]; Pump();
            NVNoteEditingSession *newSession = [owner editingSessionForNote:newMain];
            Check(newSession != oldSession && [newSession note] == newMain,
                @"reused UUID receives a new session for the replacement model identity");
            Check([a textStorage] == [newSession textStorage] && [b textStorage] == [newSession textStorage] &&
                [[a string] isEqual:newBody] && [[b string] isEqual:newBody],
                @"both layouts show exact replacement source despite the matching old UUID");

            OwnershipDeferredChange *change = [[OwnershipDeferredChange alloc] initWithNote:oldMain body:@"late old-library source"];
            [change performSelector:@selector(deliver) withObject:nil afterDelay:0];
            [change release];
            for (NSUInteger spin = 0; spin < 8; spin++) Pump();
            Check([[oldMain contentString].string isEqual:@"late old-library source"],
                @"delayed old-model update actually executes after replacement");
            Check(ClosedSessionReloads == 0, @"closed session receives no old-model notification callbacks");
            Check([[oldStorage string] isEqual:expectedOld], @"closed storage keeps its final committed source after late notifications");
            Check([self selectedNoteObject] == newMain && [peer selectedNoteObject] == newMain &&
                [[a string] isEqual:newBody] && [[b string] isEqual:newBody] && [[newMain contentString].string isEqual:newBody],
                @"late old-note notifications cannot replace the active model or either editor");
            Check([[replacement allNotes] count] == 2 && [[newMain sourceSyntaxIdentifier] isEqual:@"json"] &&
                [labelsOfNote(newMain) isEqual:@"replacement"],
                @"late callbacks preserve replacement note count, syntax and tags");
            Check([[owner valueForKey:@"editingSessions"] count] == 1 && [owner editingSessionForNote:newMain] == newSession,
                @"late callbacks do not pollute the replacement session cache");

            [self nv_activateBrowser]; [[self window] makeFirstResponder:a];
            [a insertText:@"next" replacementRange:NSMakeRange([[a string] length], 0)]; Pump();
            [newSession undo]; Pump();
            Check([[a string] isEqual:newBody] && [[b string] isEqual:newBody],
                @"replacement source Undo restores only replacement content in both windows");
            [newSession redo]; Pump();
            Check([[a string] isEqual:[newBody stringByAppendingString:@"next"]] && [[a string] isEqual:[b string]],
                @"replacement source Redo remains shared after stale callbacks");
            [[peer window] close]; Pump();
            Check([[owner browserControllers] count] == 1 && [[[newSession textStorage] layoutManagers] count] == 1,
                @"closing the peer detaches its layout without closing the shared session");
            [owner newWindow:self]; Pump(); peer = [[owner browserControllers] lastObject];
            [peer revealNote:newMain options:0]; Pump();
            Check([owner editingSessionForNote:newMain] == newSession && [[[newSession textStorage] layoutManagers] count] == 2,
                @"a replacement peer window attaches to the surviving shared session");
            Check([[[peer valueForKey:@"textView"] string] isEqual:[[newMain contentString] string]],
                @"new peer displays the current committed source");
            Check([oldLibrary flushAllNoteChanges], @"old disposable library can flush its isolated late update");
            [oldLibrary closeJournal];
            ObservedSession = nil; SessionHasClosed = NO;
            [oldSession release]; [oldMain release]; [oldLibrary release]; [edited release];
            library = replacement; main = newMain; sentinel = newSentinel;
            [replacement release];
        }
        Check([library flushAllNoteChanges], @"final active library flush succeeds"); [library closeJournal];
        NSLog(@"OUSTERHOUT ROUND 2 PASSED (%lu checks; three replacement histories)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
