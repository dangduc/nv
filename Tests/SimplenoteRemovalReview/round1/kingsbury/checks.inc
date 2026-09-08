- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NSString *expectationPath = [TestDirectory stringByAppendingPathComponent:@"kingsbury-expectations.plist"];
        NSInteger phase = [[[NSProcessInfo processInfo] environment][@"NV_REVIEW_PHASE"] integerValue];
        if (phase >= 2) {
            NSArray *expected = [NSArray arrayWithContentsOfFile:expectationPath];
            Check([expected count] == 11, @"second process loads the independent expected-state ledger");
            NSUInteger survivors = 0;
            for (NSDictionary *entry in expected) {
                CFUUIDBytes identifier;
                [entry[@"uuid"] getBytes:&identifier length:sizeof(identifier)];
                NoteObject *note = [library noteForUUIDBytes:&identifier];
                BOOL present = [entry[@"present"] boolValue];
                Check((note != nil) == present, [NSString stringWithFormat:@"restart history %@ has expected existence=%d", entry[@"history"], present]);
                if (!present) continue;
                survivors++;
                Check([[[note contentString] string] isEqual:entry[@"body"]], [NSString stringWithFormat:@"restart %@ preserves exact source", entry[@"history"]]);
                Check([titleOfNote(note) isEqual:entry[@"title"]] && [labelsOfNote(note) isEqual:entry[@"tags"]], [NSString stringWithFormat:@"restart %@ preserves title and tags", entry[@"history"]]);
                Check([[note sourceSyntaxIdentifier] isEqual:entry[@"syntax"]], [NSString stringWithFormat:@"restart %@ preserves checkpointed local syntax", entry[@"history"]]);
                Check([note logSequenceNumber] == [entry[@"lsn"] unsignedIntValue], [NSString stringWithFormat:@"restart %@ selects expected newest LSN", entry[@"history"]]);
            }
            Check([[library allNotes] count] == survivors, @"recovery contains no duplicate, lost, or resurrected synthetic notes");
            Check([library flushAllNoteChanges], @"recovered snapshot saves successfully");
            NSLog(@"KINGSBURY PASS: 11 histories, %lu assertions in restart process", (unsigned long)Checks);
            [NSApp terminate:self]; return;
        }
        Check([[library allNotes] count] == 0, @"first process starts with an empty synthetic library");
        NSUndoManager *undo = [[[NSUndoManager alloc] init] autorelease];
        [undo setGroupsByEvent:NO];
        [library setUndoManager:undo];
        NSMutableArray *notes = [NSMutableArray array];
        NSArray *names = @[@"dirty-delete", @"dirty-delete-undo", @"delete-undo-redo", @"edit-survives", @"batch-undo-a", @"batch-undo-b", @"twenty-cycles", @"late-stale-tombstone", @"untouched-control"];
        for (NSString *name in names) {
            NoteObject *note = MakeNote(library, name, [@"checkpoint\r\n café 😀\n" stringByAppendingString:name]);
            [note setSourceSyntaxIdentifier:@"markdown"];
            [notes addObject:note];
        }
        Check([library flushAllNoteChanges], @"nine-note checkpoint saves before the WAL-only history");
        NSData *checkpoint = [NSData dataWithContentsOfFile:[[TestDirectory stringByAppendingPathComponent:@"Notes"] stringByAppendingPathComponent:@"Notes & Settings"]];
        Check([checkpoint length] > 0, @"checkpoint bytes are available for an unchanged-database crash-cut check");
        [undo removeAllActions];
        NSMutableArray *histories = [NSMutableArray arrayWithArray:names];
        NSMutableSet *absent = [NSMutableSet set];
        NoteObject *a = notes[0], *b = notes[1], *c = notes[2], *edit = notes[3];
        [a setContentString:[[[NSAttributedString alloc] initWithString:@"unsaved body immediately before delete"] autorelease]];
        [undo beginUndoGrouping]; [library removeNote:a]; [undo endUndoGrouping];
        [absent addObject:@0];
        Check(![library noteForUUIDBytes:[a uniqueNoteIDBytes]], @"dirty deletion removes the live note");
        [undo removeAllActions];
        [b setContentString:[[[NSAttributedString alloc] initWithString:@"restored current source\r\n日本語\t😀\n"] autorelease]];
        [b setTitleString:@"renamed before deletion"];
        [b setLabelString:@"keep, café"];
        [undo beginUndoGrouping]; [library removeNote:b]; [undo endUndoGrouping];
        unsigned int deletionLSN = [b logSequenceNumber];
        [undo undo];
        Check([library noteForUUIDBytes:[b uniqueNoteIDBytes]] == b && [b logSequenceNumber] > deletionLSN, @"deletion Undo restores the same UUID with a newer journal sequence");
        [undo removeAllActions];
        [undo beginUndoGrouping]; [library removeNote:c]; [undo endUndoGrouping];
        [undo undo]; [undo redo]; [absent addObject:@2];
        Check(![library noteForUUIDBytes:[c uniqueNoteIDBytes]], @"deletion Redo removes the restored note");
        [undo removeAllActions];
        [edit setContentString:[[[NSAttributedString alloc] initWithString:@"journal-only source\r\n\tΩ😀\n"] autorelease]];
        [library synchronizeNoteChanges:nil];
        [undo beginUndoGrouping]; [library removeNotes:@[notes[4], notes[5]]]; [undo endUndoGrouping];
        [undo undo];
        Check([library noteForUUIDBytes:[notes[4] uniqueNoteIDBytes]] && [library noteForUUIDBytes:[notes[5] uniqueNoteIDBytes]], @"batch deletion Undo restores both identities");
        [undo removeAllActions];
        for (NSUInteger cycle = 0; cycle < 20; cycle++) {
            [undo beginUndoGrouping]; [library removeNote:notes[6]]; [undo endUndoGrouping];
            [undo undo]; [undo removeAllActions];
        }
        Check([notes[6] logSequenceNumber] >= 41, @"twenty deletion and Undo cycles advance journal ordering");
        [undo beginUndoGrouping]; [library removeNote:notes[7]]; [undo endUndoGrouping];
        DeletedNoteObject *stale = [[[DeletedNoteObject alloc] initWithExistingObject:notes[7]] autorelease];
        [undo undo]; [undo removeAllActions];
        WALStorageController *writer = [library valueForKey:@"walWriter"];
        Check([writer writeNoteObject:stale], @"late physical tombstone record is written after its newer restored note");
        NoteObject *freshDeleted = MakeNote(library, @"born-and-deleted", @"never in the checkpoint");
        [notes addObject:freshDeleted]; [histories addObject:@"born-and-deleted"];
        [undo beginUndoGrouping]; [library removeNote:freshDeleted]; [undo endUndoGrouping];
        [absent addObject:@9]; [undo removeAllActions];
        NoteObject *freshRestored = MakeNote(library, @"born-deleted-restored", @"survivor after checkpoint\n😀");
        [notes addObject:freshRestored]; [histories addObject:@"born-deleted-restored"];
        [undo beginUndoGrouping]; [library removeNote:freshRestored]; [undo endUndoGrouping];
        [undo undo]; [undo removeAllActions];
        NSMutableArray *ledger = [NSMutableArray array];
        for (NSUInteger index = 0; index < [notes count]; index++) {
            NoteObject *note = notes[index];
            NSString *expectedBody = index == 1 ? @"restored current source\r\n日本語\t😀\n" :
                index == 3 ? @"journal-only source\r\n\tΩ😀\n" :
                index == 9 ? @"never in the checkpoint" :
                index == 10 ? @"survivor after checkpoint\n😀" :
                [@"checkpoint\r\n café 😀\n" stringByAppendingString:histories[index]];
            if (index == 0) expectedBody = @"unsaved body immediately before delete";
            NSString *expectedTitle = index == 1 ? @"renamed before deletion" : histories[index];
            NSString *expectedTags = index == 1 ? @"keep, café" : @"";
            NSString *expectedSyntax = index < 9 ? @"markdown" : @"plain";
            Check([[[note contentString] string] isEqual:expectedBody] && [titleOfNote(note) isEqual:expectedTitle] &&
                [labelsOfNote(note) isEqual:expectedTags] && [[note sourceSyntaxIdentifier] isEqual:expectedSyntax],
                [NSString stringWithFormat:@"live %@ matches the literal operation model before crash", histories[index]]);
            [ledger addObject:@{@"history": histories[index], @"uuid": [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)],
                @"present": @(![absent containsObject:@(index)]), @"title": expectedTitle, @"body": expectedBody,
                @"tags": expectedTags, @"syntax": expectedSyntax, @"lsn": @([note logSequenceNumber])}];
        }
        Check([ledger writeToFile:expectationPath atomically:YES], @"independent operation ledger is written outside the note database");
        Check([writer synchronize], @"WAL fsync succeeds before abrupt exit");
        Check([checkpoint isEqual:[NSData dataWithContentsOfFile:[[TestDirectory stringByAppendingPathComponent:@"Notes"] stringByAppendingPathComponent:@"Notes & Settings"]]], @"database bytes still equal the original checkpoint at the crash cut");
        // Deliberately bypass NSApplication termination and its database flush.
        // Only the disposable app process exits; no personal app is touched.
        NSLog(@"KINGSBURY CRASH CUT: checkpoint=9 notes, expected=8 survivors, ledger=11 histories, assertions=%lu", (unsigned long)Checks);
        fflush(NULL); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: unexpected exception %@", exception); exit(1); }
}
