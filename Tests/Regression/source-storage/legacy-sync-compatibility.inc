        // This fixed archive was written by the actual pre-removal app. It
        // contains an enabled account, pending upload metadata, and a tombstone.
        NSString *legacySyncedBody = @"# Local café 😀\r\n\tunsent changes\n";
        CFUUIDBytes legacyIdentifier = { 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef };
        NSString *fixtureDirectory = [NSString stringWithUTF8String:getenv("NV_SOURCE_STORAGE_FIXTURES")];
        NSData *legacyLibraryData = [NSData dataWithContentsOfFile:[fixtureDirectory stringByAppendingPathComponent:@"legacy-simplenote.notation"]];
        SourceCheckLegacyFixtureMetadata(legacyLibraryData);
        Check(SourceArchiveHasKey(legacyLibraryData, @"syncServiceAccounts") && SourceArchiveHasKey(legacyLibraryData, @"deletedNoteSet"), @"legacy library fixture contains enabled account settings and remote deletion history");
        FrozenNotation *legacyFixture = [NSKeyedUnarchiver unarchiveObjectWithData:legacyLibraryData];
        Check(SourceArchiveHasKey([[legacyFixture valueForKey:@"notesData"] uncompressedData], @"syncServicesMD"), @"legacy note fixture includes remote upload metadata");
        NSString *legacySyncPath = [TestDirectory stringByAppendingPathComponent:@"Legacy synced library"];
        Check([[NSFileManager defaultManager] createDirectoryAtPath:legacySyncPath withIntermediateDirectories:NO attributes:nil error:NULL] &&
              [legacyLibraryData writeToFile:[legacySyncPath stringByAppendingPathComponent:@"Notes & Settings"] atomically:YES], @"legacy library fixture is stored in an isolated directory");
        FSRef legacySyncRef;
        Check(FSPathMakeRef((const UInt8 *)[legacySyncPath fileSystemRepresentation], &legacySyncRef, NULL) == noErr, @"legacy library directory resolves");
        // The application has one active library and one cache journal. Close
        // this fixture's first library journal before opening the legacy one.
        Check([library flushAllNoteChanges], @"current fixture library saves before the temporary library switch");
        [library closeJournal];
        OSStatus legacySyncError = noErr;
        NotationController *legacyLocalLibrary = [[[NotationController alloc] initWithDirectoryRef:&legacySyncRef error:&legacySyncError] autorelease];
        NoteObject *localSurvivor = [legacyLocalLibrary noteForUUIDBytes:&legacyIdentifier];
        Check(legacyLocalLibrary && legacySyncError == noErr && [[legacyLocalLibrary allNotes] count] == 1 && localSurvivor, @"enabled legacy sync settings and remote tombstones do not block opening local notes");
        Check([[[localSurvivor contentString] string] isEqual:legacySyncedBody] && [titleOfNote(localSurvivor) isEqual:@"Local synced title"] &&
              [labelsOfNote(localSurvivor) isEqual:@"keep, 日本語"], @"legacy local source, title, and tags survive service removal");
        Check([localSurvivor logSequenceNumber] == 1 && modifiedDateOfNote(localSurvivor) == 700000123.5 &&
              createdDateOfNote(localSurvivor) == 700000000.25, @"legacy note UUID lookup, journal sequence, and dates remain unchanged");
        Check([[localSurvivor sourceSyntaxIdentifier] isEqual:@"markdown"] && [[localSurvivor sourceDataReturningError:NULL] isEqual:[legacySyncedBody dataUsingEncoding:NSUTF8StringEncoding]], @"legacy notes retain local syntax and exact source bytes");
        Check(![[legacyLocalLibrary notationPrefs] respondsToSelector:NSSelectorFromString(@"syncServiceAccounts")] &&
              ![localSurvivor respondsToSelector:NSSelectorFromString(@"syncServicesMD")] &&
              ![legacyLocalLibrary respondsToSelector:NSSelectorFromString(@"startSyncServices")], @"decoded legacy objects expose no sync settings, metadata, or startup API");
        Check([(id<NSApplicationDelegate>)[NVApplicationController sharedController] applicationShouldTerminate:NSApp] == NSTerminateNow,
              @"application termination has no remote wait");
        Check([legacyLocalLibrary flushAllNoteChanges], @"legacy library rewrites its migrated settings without an account");
        [legacyLocalLibrary closeJournal]; [legacyLocalLibrary stopFileNotifications];
        Check([library initializeJournaling], @"current fixture library resumes its journal after the compatibility check");
        NSData *rewrittenLegacyData = [NSData dataWithContentsOfFile:[legacySyncPath stringByAppendingPathComponent:@"Notes & Settings"]];
        Check(!SourceArchiveHasKey(rewrittenLegacyData, @"syncServiceAccounts") && !SourceArchiveHasKey(rewrittenLegacyData, @"deletedNoteSet"), @"rewritten library omits obsolete account settings and remote deletion history");
        FrozenNotation *rewrittenLegacy = [NSKeyedUnarchiver unarchiveObjectWithData:rewrittenLegacyData];
        Check(!SourceArchiveHasKey([[rewrittenLegacy valueForKey:@"notesData"] uncompressedData], @"syncServicesMD"), @"rewritten notes omit obsolete remote metadata");
        NSArray *rewrittenLocalNotes = [rewrittenLegacy unpackedNotesReturningError:&legacySyncError];
        Check(legacySyncError == noErr && [rewrittenLocalNotes count] == 1 &&
              [[[[rewrittenLocalNotes firstObject] contentString] string] isEqual:legacySyncedBody], @"rewritten library reopens with all unsent local source characters");

        // Journal tombstones serve local crash recovery after service history
        // has gone. A later re-established record must also win during recovery.
        NoteObject *legacyRemoved = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"Previously removed"] autorelease]
            title:@"Removed local note" delegate:nil format:SingleDatabaseFormat labels:@""] autorelease];
        NSString *journalOnlyPath = [TestDirectory stringByAppendingPathComponent:@"Local deletion journal"];
        Check([[NSFileManager defaultManager] createDirectoryAtPath:journalOnlyPath withIntermediateDirectories:NO attributes:nil error:NULL], @"journal fixture uses a separate temporary directory");
        NSData *journalOnlyKey = [[library notationPrefs] WALSessionKey];
        WALStorageController *journalOnlyWriter = [[[WALStorageController alloc] initWithParentFSRep:[journalOnlyPath fileSystemRepresentation] encryptionKey:journalOnlyKey] autorelease];
        Check(journalOnlyWriter && [journalOnlyWriter writeEstablishedNote:legacyRemoved] && [journalOnlyWriter writeRemovalForNote:legacyRemoved] && [journalOnlyWriter synchronize], @"local note creation and deletion are durable journal records");
        WALRecoveryController *deletedReader = [[[WALRecoveryController alloc] initWithParentFSRep:[journalOnlyPath fileSystemRepresentation] encryptionKey:journalOnlyKey] autorelease];
        NSArray *deletedRecovery = [[deletedReader recoveredNotes] allValues];
        Check([deletedRecovery count] == 1 && [[deletedRecovery firstObject] isKindOfClass:[DeletedNoteObject class]] &&
              memcmp([[deletedRecovery firstObject] uniqueNoteIDBytes], [legacyRemoved uniqueNoteIDBytes], sizeof(CFUUIDBytes)) == 0, @"journal recovery retains the tombstone instead of reviving the older local note");
        Check([journalOnlyWriter writeEstablishedNote:legacyRemoved] && [journalOnlyWriter synchronize], @"restoring a deleted note writes a newer local journal record");
        WALRecoveryController *restoredReader = [[[WALRecoveryController alloc] initWithParentFSRep:[journalOnlyPath fileSystemRepresentation] encryptionKey:journalOnlyKey] autorelease];
        NSArray *restoredRecovery = [[restoredReader recoveredNotes] allValues];
        Check([restoredRecovery count] == 1 && [[restoredRecovery firstObject] isKindOfClass:[NoteObject class]] &&
              [[[[restoredRecovery firstObject] contentString] string] isEqual:[[legacyRemoved contentString] string]], @"journal recovery restores the newer note after deletion Undo");
        Check([journalOnlyWriter destroyLogFile], @"disposable journal cleanup succeeds");

        NSMutableData *sequentialLegacyData = [NSMutableData data];
        NSArchiver *sequentialLegacyWriter = [[[NSArchiver alloc] initForWritingWithMutableData:sequentialLegacyData] autorelease];
        [sequentialLegacyWriter encodeClassName:@"NVLegacySequentialTombstone" intoClassName:@"DeletedNoteObject"];
        [sequentialLegacyWriter encodeRootObject:@[[[[NVLegacySequentialTombstone alloc] init] autorelease], @"after legacy record"]];
        NSArray *sequentialLegacyRecords = [NSUnarchiver unarchiveObjectWithData:sequentialLegacyData];
        DeletedNoteObject *sequentialLegacyTombstone = [sequentialLegacyRecords firstObject];
        Check([sequentialLegacyTombstone isKindOfClass:[DeletedNoteObject class]] &&
              memcmp([sequentialLegacyTombstone uniqueNoteIDBytes], &legacyIdentifier, sizeof(CFUUIDBytes)) == 0 &&
              [sequentialLegacyTombstone logSequenceNumber] == 0xf1234567U &&
              [[sequentialLegacyRecords lastObject] isEqual:@"after legacy record"], @"legacy sequential tombstones consume obsolete metadata and preserve UUID, sequence, and following records");
