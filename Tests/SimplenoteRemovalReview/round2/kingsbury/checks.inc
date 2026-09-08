- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NVFailureLibrary = library;
        NSInteger phase = atoi(getenv("NV_REVIEW_PHASE"));
        NSString *databasePath = [[TestDirectory stringByAppendingPathComponent:@"Notes"] stringByAppendingPathComponent:@"Notes & Settings"];
        NSString *ledgerPath = [TestDirectory stringByAppendingPathComponent:@"snapshot-failure-expectations.plist"];
        if (phase > 1) {
            NSArray *ledger = [NSArray arrayWithContentsOfFile:ledgerPath];
            Check([ledger count] == 5, @"restart loads all five independent identity expectations");
            for (NSDictionary *entry in ledger) {
                CFUUIDBytes uuid; [entry[@"uuid"] getBytes:&uuid length:sizeof(uuid)];
                NoteObject *note = [library noteForUUIDBytes:&uuid];
                Check((note != nil) == [entry[@"present"] boolValue],
                    [NSString stringWithFormat:@"recovery existence matches %@", entry[@"history"]]);
                if (!note) continue;
                Check([[[note contentString] string] isEqual:entry[@"body"]],
                    [NSString stringWithFormat:@"recovery exact source matches %@", entry[@"history"]]);
                Check([titleOfNote(note) isEqual:entry[@"title"]] && [labelsOfNote(note) isEqual:entry[@"tags"]],
                    [NSString stringWithFormat:@"recovery local metadata matches %@", entry[@"history"]]);
                Check([[note sourceSyntaxIdentifier] isEqual:entry[@"syntax"]] && [note logSequenceNumber] == [entry[@"lsn"] unsignedIntValue],
                    [NSString stringWithFormat:@"recovery checkpointed syntax and newest sequence match %@", entry[@"history"]]);
            }
            Check([[library allNotes] count] == 3, @"recovery has exactly three notes without loss, duplication, or resurrection");
            Check([library flushAllNoteChanges], @"recovered local snapshot stores successfully");
            Check(![[library valueForKey:@"notesChanged"] boolValue] && ![[library notationPrefs] preferencesChanged],
                @"successful recovery checkpoint clears dirty flags");
            [library closeAllResources];
            Check(NVJournalCloses == 1 && [library valueForKey:@"walWriter"] == nil,
                @"successful close after recovery destroys the obsolete WAL");
            NSLog(@"KINGSBURY ROUND2 phase%ld: %lu assertions passed", (long)phase, (unsigned long)Checks);
            [NSApp terminate:self]; return;
        }

        Check([[library allNotes] count] == 0, @"failure history starts from an empty disposable library");
        NSUndoManager *undo = [[[NSUndoManager alloc] init] autorelease]; [undo setGroupsByEvent:NO]; [library setUndoManager:undo];
        NoteObject *edited = MakeNote(library, @"edited", @"checkpoint α\r\n");
        NoteObject *retryDeleted = MakeNote(library, @"delete-before-retry", @"checkpoint deletion A");
        NoteObject *closeDeleted = MakeNote(library, @"delete-before-close", @"checkpoint deletion B");
        NoteObject *untouched = MakeNote(library, @"untouched", @"unchanged 日本語\t😀\n");
        NSArray *initial = @[edited, retryDeleted, closeDeleted, untouched];
        Check([library flushAllNoteChanges], @"four-note checkpoint stores before failure injection");
        NSData *checkpoint = [[NSData dataWithContentsOfFile:databasePath] retain];
        Check([checkpoint length] > 0 && ![[library valueForKey:@"notesChanged"] boolValue] &&
            ![[library notationPrefs] preferencesChanged], @"checkpoint bytes exist and both dirty flags are clear");
        WALStorageController *firstWriter = [library valueForKey:@"walWriter"];
        Check(firstWriter && [firstWriter logFileStillExists], @"checkpoint retains a live WAL for subsequent edits");
        NVSuccessfulStores = 0; NVFailedStores = 0; NVJournalCloses = 0;

        // Failure history A: local body + metadata + deletion + syntax setting.
        [edited setContentString:[[[NSAttributedString alloc] initWithString:@"retry body Ω\r\n\t😀\n"] autorelease]];
        [edited setTitleString:@"retained through failure"];
        [edited setLabelString:@"keep, café"];
        [edited setSourceSyntaxIdentifier:@"json"];
        [NSObject cancelPreviousPerformRequestsWithTarget:[library notationPrefs] selector:NSSelectorFromString(@"storeSourceMetadata") object:nil];
        [undo beginUndoGrouping]; [library removeNote:retryDeleted]; [undo endUndoGrouping]; [undo removeAllActions];
        Check([[library valueForKey:@"notesChanged"] boolValue] && [[library notationPrefs] preferencesChanged],
            @"history A has dirty local notes and dirty local syntax preferences before the store");
        NVFailSnapshot = YES;
        Check(![library flushAllNoteChanges], @"explicit snapshot write failure propagates as a failed flush");
        Check(NVFailedStores == 1 && NVSuccessfulStores == 0 && NVLastRejectedBytes > 0,
            @"fault is hit once after serialization and before database replacement");
        Check([[library valueForKey:@"notesChanged"] boolValue] && [[library notationPrefs] preferencesChanged],
            @"failed snapshot does not mark local notes or preferences stored");
        Check([checkpoint isEqual:[NSData dataWithContentsOfFile:databasePath]], @"failed snapshot leaves the previous checkpoint byte-for-byte unchanged");
        Check([library valueForKey:@"walWriter"] == firstWriter && [firstWriter logFileStillExists] && NVJournalCloses == 0,
            @"failed snapshot keeps the same WAL and never closes the sole new local records");
        Check([firstWriter synchronize], @"preserved WAL can still synchronize after the failed snapshot");

        // The complete-flush caller also must not delete/recreate the WAL on failure.
        [library flushEverything];
        Check(NVFailedStores == 2 && NVJournalCloses == 0 && [library valueForKey:@"walWriter"] == firstWriter && [firstWriter logFileStillExists],
            @"failed flushEverything preserves its original journal instead of rotating it");
        NVFailSnapshot = NO;
        [library flushEverything];
        Check(NVSuccessfulStores == 1 && NVJournalCloses == 1 && [library valueForKey:@"walWriter"] != nil,
            @"successful retry stores the snapshot before closing and restarting its WAL");
        Check(![[library valueForKey:@"notesChanged"] boolValue] && ![[library notationPrefs] preferencesChanged],
            @"successful retry clears both dirty flags");
        NSData *retryCheckpoint = [[NSData dataWithContentsOfFile:databasePath] retain];
        Check([retryCheckpoint length] > 0 && ![retryCheckpoint isEqual:checkpoint], @"retry replaces the checkpoint with changed local data");
        Check([[[edited contentString] string] isEqual:@"retry body Ω\r\n\t😀\n"] &&
            [library noteForUUIDBytes:[retryDeleted uniqueNoteIDBytes]] == nil && [[edited sourceSyntaxIdentifier] isEqual:@"json"],
            @"successful retry retains local edit, deletion, and syntax without reintroducing a removed note");

        // Failure history B: new changes exist only in the WAL at failed close.
        [edited setContentString:[[[NSAttributedString alloc] initWithString:@"after retry; close must retain this\r\n\t世界😀\n"] autorelease]];
        [undo beginUndoGrouping]; [library removeNote:closeDeleted]; [undo endUndoGrouping]; [undo removeAllActions];
        NoteObject *created = MakeNote(library, @"created-before-failed-close", @"only after successful checkpoint\nЖ😀");
        NSMutableArray *notes = [NSMutableArray arrayWithArray:initial]; [notes addObject:created];
        NSMutableArray *ledger = [NSMutableArray array];
        NSArray *bodies = @[@"after retry; close must retain this\r\n\t世界😀\n", @"checkpoint deletion A", @"checkpoint deletion B",
            @"unchanged 日本語\t😀\n", @"only after successful checkpoint\nЖ😀"];
        for (NSUInteger index = 0; index < [notes count]; index++) {
            NoteObject *note = notes[index]; BOOL present = index != 1 && index != 2;
            NSString *title = index == 0 ? @"retained through failure" : index == 1 ? @"delete-before-retry" : index == 2 ? @"delete-before-close" :
                index == 3 ? @"untouched" : @"created-before-failed-close";
            NSString *tags = index == 0 ? @"keep, café" : @"";
            NSString *syntax = index == 0 ? @"json" : @"plain";
            Check([[[note contentString] string] isEqual:bodies[index]] && [titleOfNote(note) isEqual:title] && [labelsOfNote(note) isEqual:tags],
                [NSString stringWithFormat:@"history B live state matches independent source and metadata model for %@", title]);
            [ledger addObject:@{@"history": title, @"uuid": [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)],
                @"present": @(present), @"title": title, @"body": bodies[index], @"tags": tags, @"syntax": syntax}];
        }
        WALStorageController *closeWriter = [library valueForKey:@"walWriter"];
        NVFailSnapshot = YES;
        [library closeAllResources];
        Check(NVFailedStores == 3 && NVSuccessfulStores == 1, @"closeAllResources attempts the failed snapshot store exactly once");
        Check([[library valueForKey:@"notesChanged"] boolValue], @"failed resource close leaves the pending local snapshot dirty");
        Check(NVJournalCloses == 1 && [library valueForKey:@"walWriter"] == closeWriter && [closeWriter logFileStillExists],
            @"failed resource close preserves the sole WAL containing local edits, creation, and deletion");
        Check([closeWriter synchronize] && [retryCheckpoint isEqual:[NSData dataWithContentsOfFile:databasePath]],
            @"crash cut has a durable WAL and exactly the previous successful checkpoint");
        struct stat information;
        Check(fstat([[closeWriter valueForKey:@"logFD"] intValue], &information) == 0 && information.st_size > 0,
            @"preserved WAL is an open nonempty file at the crash cut");
        for (NSUInteger index = 0; index < [notes count]; index++) {
            NSMutableDictionary *entry = [ledger[index] mutableCopy]; entry[@"lsn"] = @([notes[index] logSequenceNumber]);
            ledger[index] = entry; [entry release];
        }
        Check([ledger writeToFile:ledgerPath atomically:YES], @"independent expected identities and newest sequences are saved outside the database");
        NSLog(@"KINGSBURY ROUND2 phase1: %lu assertions passed; 2 failure histories, 3 rejected stores, 1 successful retry; crash cut", (unsigned long)Checks);
        fflush(NULL); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: snapshot fault review exception %@", exception); exit(1); }
}
