- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NSString *databasePath = [TestDirectory stringByAppendingPathComponent:@"Notes/Notes & Settings"];
        CFUUIDBytes oldID = NVLegacyUUID, remoteID = NVRemoteDeletedUUID, freshID = NVFreshUUID, goneID = NVBornDeletedUUID;
        NSString *originalBody = @"# Local café 😀\r\n\tunsent changes\n";
        NSString *editedBody = @"# Local edit survives\r\n\tcafé Ω😀\n";
        NSString *freshBody = @"{\"local\":true,\"text\":\"日本語😀\"}\r\n";
        Check(NSClassFromString(@"SimplenoteSession") == Nil && ![library respondsToSelector:NSSelectorFromString(@"startSyncServices")],
            @"only the current app opens the enabled-account archive; remote service code is absent");
        Check(![library noteForUUIDBytes:&remoteID], @"obsolete pending remote deletion never becomes a live note");
        NoteObject *legacy = [library noteForUUIDBytes:&oldID];
        Check(legacy != nil, @"fixed legacy identity is present in the live library");

        if (NVMigrationPhase == 1) {
            Check([[library allNotes] count] == 1, @"the real old fixture initially supplies exactly one local note");
            Check([[[legacy contentString] string] isEqual:originalBody] &&
                [[legacy sourceDataReturningError:NULL] isEqual:[originalBody dataUsingEncoding:NSUTF8StringEncoding]],
                @"unsent local source and exact UTF-8 bytes survive the first live open");
            Check([titleOfNote(legacy) isEqual:@"Local synced title"] && [labelsOfNote(legacy) isEqual:@"keep, 日本語"],
                @"old live note title and tags match the literal fixture ledger");
            Check([legacy logSequenceNumber] == 1 && createdDateOfNote(legacy) == 700000000.25 && modifiedDateOfNote(legacy) == 700000123.5,
                @"old identity has its fixed original sequence and dates");
            Check([[legacy sourceSyntaxIdentifier] isEqual:@"markdown"], @"local syntax survives obsolete enabled account metadata");
            Check([NVMigrationFixture isEqual:[NSData dataWithContentsOfFile:databasePath]],
                @"the checkpoint is still the old archive before local operations");
            Check(NVMigrationArchiveHasKey(NVMigrationFixture, @"syncServiceAccounts") &&
                NVMigrationArchiveHasKey(NVMigrationFixture, @"deletedNoteSet"), @"crash checkpoint retains both obsolete outer archive fields");

            NSUndoManager *undo = [[[NSUndoManager alloc] init] autorelease];
            [undo setGroupsByEvent:NO]; [library setUndoManager:undo];
            [legacy setContentString:[[[NSAttributedString alloc] initWithString:editedBody] autorelease]];
            [legacy setTitleString:@"Migrated local title"];
            [legacy setLabelString:@"keep, restart"];
            [library synchronizeNoteChanges:nil];
            Check([legacy logSequenceNumber] == 2, @"one explicit edit journal drain advances old sequence 1 to 2");
            [undo removeAllActions];
            [undo beginUndoGrouping]; [library removeNote:legacy]; [undo endUndoGrouping];
            Check(![library noteForUUIDBytes:&oldID] && [legacy logSequenceNumber] == 3,
                @"local deletion writes sequence 3 after the edited record");
            [undo undo]; [undo removeAllActions];
            Check([library noteForUUIDBytes:&oldID] == legacy && [legacy logSequenceNumber] == 4,
                @"deletion Undo restores the same old UUID as sequence 4");

            NoteObject *fresh = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:freshBody] autorelease]
                title:@"Born during migration" delegate:library format:SingleDatabaseFormat labels:@"new, local"] autorelease];
            *[fresh uniqueNoteIDBytes] = freshID; fresh->createdDate = 710000000.5;
            [library addNewNote:fresh];
            Check([fresh logSequenceNumber] == 1, @"new fixed identity receives its first durable local journal sequence");
            NoteObject *gone = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"never in a database snapshot"] autorelease]
                title:@"Born then removed" delegate:library format:SingleDatabaseFormat labels:@""] autorelease];
            *[gone uniqueNoteIDBytes] = goneID;
            [library addNewNote:gone];
            [undo beginUndoGrouping]; [library removeNote:gone]; [undo endUndoGrouping]; [undo removeAllActions];
            Check(![library noteForUUIDBytes:&goneID] && [gone logSequenceNumber] == 2,
                @"newly created then deleted identity ends with a sequence 2 tombstone");
            Check(![library flushAllNoteChanges] && NVRejectedMigrationStores > 0,
                @"controlled checkpoint rejection prevents migration rewrite while normal serialization and WAL drain run");
            WALStorageController *writer = [library valueForKey:@"walWriter"];
            Check(writer && [writer logFileStillExists] && [writer synchronize],
                @"real encrypted local WAL remains present and its explicit fsync succeeds");
            Check([NVMigrationFixture isEqual:[NSData dataWithContentsOfFile:databasePath]],
                @"at abrupt exit the sole checkpoint is byte-for-byte the 4,233-byte old archive");
        }

        // This literal ledger is rebuilt independently in every process. It is
        // not learned from the recovered objects or a re-encoded current fixture.
        NSArray *ledger = @[
            @{@"uuid": [NSData dataWithBytes:&oldID length:sizeof(oldID)], @"title": @"Migrated local title",
              @"body": editedBody, @"tags": @"keep, restart", @"syntax": @"markdown", @"lsn": @4, @"created": @700000000.25},
            @{@"uuid": [NSData dataWithBytes:&freshID length:sizeof(freshID)], @"title": @"Born during migration",
              @"body": freshBody, @"tags": @"new, local", @"syntax": @"plain", @"lsn": @1, @"created": @710000000.5}
        ];
        for (NSDictionary *entry in ledger) {
            CFUUIDBytes identifier; [entry[@"uuid"] getBytes:&identifier length:sizeof(identifier)];
            NoteObject *note = [library noteForUUIDBytes:&identifier];
            Check(note != nil, [NSString stringWithFormat:@"literal ledger identity exists: %@", entry[@"title"]]);
            Check([[[note contentString] string] isEqual:entry[@"body"]] &&
                [[note sourceDataReturningError:NULL] isEqual:[entry[@"body"] dataUsingEncoding:NSUTF8StringEncoding]],
                [NSString stringWithFormat:@"exact source and exported bytes match: %@", entry[@"title"]]);
            Check([titleOfNote(note) isEqual:entry[@"title"]] && [labelsOfNote(note) isEqual:entry[@"tags"]],
                [NSString stringWithFormat:@"literal title and tags match: %@", entry[@"title"]]);
            Check([[note sourceSyntaxIdentifier] isEqual:entry[@"syntax"]] && [note logSequenceNumber] == [entry[@"lsn"] unsignedIntValue],
                [NSString stringWithFormat:@"checkpoint syntax and newest literal sequence match: %@", entry[@"title"]]);
            Check(createdDateOfNote(note) == [entry[@"created"] doubleValue],
                [NSString stringWithFormat:@"fixed local creation date matches: %@", entry[@"title"]]);
        }
        Check([[library allNotes] count] == 2 && ![library noteForUUIDBytes:&goneID] && ![library noteForUUIDBytes:&remoteID],
            @"exactly two local survivors; neither remote nor new local tombstone is resurrected");

        if (NVMigrationPhase == 1) {
            if (getenv("NV_MIGRATION_DROP_WAL")) {
                [library closeJournal];
                NSLog(@"CONTROL: deliberately remove the durable WAL before abrupt exit");
            }
            NSLog(@"KINGSBURY ROUND3 CRASH CUT: %lu assertions, rejected stores=%lu", (unsigned long)Checks,
                (unsigned long)NVRejectedMigrationStores);
            fflush(NULL); _exit(0);
        }
        Check([library flushAllNoteChanges], @"recovered migration stores a successful current snapshot");
        NSData *rewritten = [NSData dataWithContentsOfFile:databasePath];
        Check(![rewritten isEqual:NVMigrationFixture], @"successful migration replaces the old checkpoint");
        Check(!NVMigrationArchiveHasKey(rewritten, @"syncServiceAccounts") && !NVMigrationArchiveHasKey(rewritten, @"deletedNoteSet"),
            @"rewritten outer archive omits obsolete accounts and remote deletion history");
        FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:rewritten];
        NSData *unpacked = [[frozen valueForKey:@"notesData"] uncompressedData];
        Check(!NVMigrationArchiveHasKey(unpacked, @"syncServicesMD"), @"rewritten packed notes omit remote upload metadata");
        OSStatus error = noErr;
        Check([[frozen unpackedNotesReturningError:&error] count] == 2 && error == noErr,
            @"independent reread of rewritten snapshot contains the two recovered notes");
        NSLog(@"KINGSBURY ROUND3 phase%lu: %lu assertions passed", (unsigned long)NVMigrationPhase, (unsigned long)Checks);
        [NSApp terminate:self];
    } @catch (NSException *exception) { NSLog(@"FAIL: unexpected migration exception %@", exception); _exit(1); }
}
