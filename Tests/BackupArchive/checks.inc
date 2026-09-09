- (void)nv_backupRoundTrip:(NSInteger)format encrypted:(BOOL)encrypted {
    NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
    [prefs prepareForOfflineBackupRestore];
    [prefs setNotesStorageFormat:format];
    NSData *password = [@"disposable archive password" dataUsingEncoding:NSUTF8StringEncoding];
    if (encrypted) {
        [prefs setPassphraseData:password inKeychain:NO];
        [prefs setDoesEncryption:YES];
    }
    [prefs setValue:@"synthetic-backup-keychain-reference" forKey:@"keychainDatabaseIdentifier"];
    [prefs setValue:@YES forKey:@"storesPasswordInKeychain"];
    NSMutableArray *notes = [NSMutableArray array];
    NoteObject *unicode = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"# café 雪\n🙂\n"] autorelease]
        title:@"Unicode" delegate:nil format:format labels:@"alpha, β"] autorelease];
    NSMutableData *original = [NSMutableData dataWithBytes:"\xff\xfe" length:2];
    [original appendData:[@"# café 雪\n🙂\n" dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
    [unicode rememberSourceData:original encoding:NSUTF16LittleEndianStringEncoding];
    [unicode setValue:@"old-directory-file.txt" forKey:@"filename"];
    [unicode setValue:@42 forKey:@"nodeID"];
    [unicode setValue:@99 forKey:@"logSequenceNumber"];
    [notes addObject:unicode];
    NoteObject *pending = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"edited 雪"] autorelease]
        title:@"Pending" delegate:nil format:format labels:@"encoding"] autorelease];
    [pending rememberSourceData:[@"before" dataUsingEncoding:NSMacOSRomanStringEncoding] encoding:NSMacOSRomanStringEncoding];
    [pending setValue:@YES forKey:@"sourceConversionPending"];
    [notes addObject:pending];
    CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(NULL, [unicode uniqueNoteIDBytes][0]);
    NSString *identifier = [(NSString*)CFUUIDCreateString(NULL, uuid) autorelease]; CFRelease(uuid);
    NSDictionary *metadata = @{@"syntax": @"markdown"};
    [prefs setSourceMetadata:metadata forNoteUUID:identifier];
    [prefs setBackupCheckpointGeneration:8 date:[NSDate dateWithTimeIntervalSince1970:1700000000]];
    NSData *archiveData = [FrozenNotation frozenDataWithExistingNotes:notes prefs:prefs];
    NSError *error = nil;
    NSDictionary *result = [NVBackupArchive restoredArchiveFromData:archiveData passphraseData:password error:&error];
    Check(result != nil && !error, [NSString stringWithFormat:@"offline archive round trip format=%ld encrypted=%d", (long)format, encrypted]);
    Check(![[result objectForKey:@"libraryIdentifier"] isEqual:[prefs backupLibraryIdentifier]], @"restore gives the copied library an independent backup identity");
    FrozenNotation *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:[result objectForKey:@"data"]];
    NotationPrefs *restoredPrefs = [decoded notationPrefs];
    Check([restoredPrefs notesStorageFormat] == SingleDatabaseFormat, @"a restored text-file archive opens as a database before reconciliation");
    Check([restoredPrefs doesEncryption] == encrypted && ![restoredPrefs storesPasswordInKeychain], @"restore preserves encryption without storing passwords in the keychain");
    Check([[restoredPrefs valueForKey:@"seenDiskUUIDEntries"] count] == 0 && ![restoredPrefs valueForKey:@"keychainDatabaseIdentifier"], @"restore removes prior disk and keychain associations");
    if (encrypted) Check([restoredPrefs canLoadPassphraseData:password], @"restored encrypted archive accepts the original password");
    OSStatus status = noErr;
    NSArray *restoredNotes = [decoded unpackedNotesWithPrefs:restoredPrefs returningError:&status];
    Check(status == noErr && [restoredNotes count] == [notes count], @"restored note count is exact");
    for (NSUInteger index = 0; index < [notes count]; index++) {
        NoteObject *before = [notes objectAtIndex:index], *after = [restoredNotes objectAtIndex:index];
        Check([[[before contentString] string] isEqual:[[after contentString] string]] && [before->titleString isEqual:after->titleString] && [before->labelString isEqual:after->labelString], @"source, title, and tags survive offline restore");
        Check(!memcmp([before uniqueNoteIDBytes], [after uniqueNoteIDBytes], sizeof(CFUUIDBytes)) && before->createdDate == after->createdDate && before->modifiedDate == after->modifiedDate, @"UUID and authored dates survive restore");
        Check([[before valueForKey:@"sourceOriginalData"] isEqual:[after valueForKey:@"sourceOriginalData"]] &&
            [[before valueForKey:@"sourceOriginalEncoding"] isEqual:[after valueForKey:@"sourceOriginalEncoding"]] && [before sourceConversionPending] == [after sourceConversionPending], @"original source bytes, encoding and pending conversion survive restore");
        Check(!after->filename && [[after valueForKey:@"nodeID"] unsignedIntValue] == 0 && [after logSequenceNumber] == 0 && after->currentFormatID == SingleDatabaseFormat, @"restored notes cannot refer to old files or journal sequence numbers");
    }
    Check([[restoredPrefs sourceMetadataForNoteUUID:identifier] isEqual:metadata], @"syntax metadata remains associated with the original note UUID");
    Check([[unicode valueForKey:@"sourceByteOrderMark"] isEqual:[[restoredNotes objectAtIndex:0] valueForKey:@"sourceByteOrderMark"]], @"byte-order mark survives restore");
    if (encrypted) {
        error = nil;
        Check(![NVBackupArchive restoredArchiveFromData:archiveData passphraseData:[@"wrong" dataUsingEncoding:NSUTF8StringEncoding] error:&error] && error,
            @"an incorrect old backup password fails before any library is opened");
    }
}

- (void)nv_runTests {
    NotationController *library = [self sharedNotationController];
    NSError *error = nil;
    MakeNote(library, @"Snapshot", @"first source\n");
    NSDictionary *first = [library backupSnapshotWithError:&error];
    Check(first && !error, @"capture returns an explicit successful checkpoint");
    NSData *disk = [NSData dataWithContentsOfURL:[[library notesDirectoryURL] URLByAppendingPathComponent:NotesDatabaseFileName]];
    Check([disk isEqual:[first objectForKey:@"data"]], @"captured bytes exactly equal the verified database checkpoint");
    NSDictionary *unchanged = [library backupSnapshotWithError:&error];
    Check([[first objectForKey:@"generation"] isEqual:[unchanged objectForKey:@"generation"]] && [[first objectForKey:@"data"] isEqual:[unchanged objectForKey:@"data"]], @"unchanged capture neither increments generation nor serializes another archive");
    NotationPrefs *prefs = [library notationPrefs];
    [prefs setSourceMetadata:@{@"syntax": @"json"} forNoteUUID:@"fixture-syntax"];
    unsigned long long before = [prefs backupCheckpointGeneration];
    Swap([NotationController class], @selector(storeDataAtomicallyInNotesDirectory:withName:destinationRef:verifyWithSelector:verificationDelegate:), @selector(nv_backupStore:withName:destinationRef:verifyWithSelector:verificationDelegate:));
    NVFailBackupCheckpoint = YES;
    Check(![library backupSnapshotWithError:&error] && error, @"a failed checkpoint returns an error instead of stale success");
    Check([prefs backupCheckpointGeneration] == before && [[NSData dataWithContentsOfURL:[[library notesDirectoryURL] URLByAppendingPathComponent:NotesDatabaseFileName]] isEqual:disk], @"failed checkpoint retains the committed generation and archive");
    NVFailBackupCheckpoint = NO;
    Swap([NotationController class], @selector(storeDataAtomicallyInNotesDirectory:withName:destinationRef:verifyWithSelector:verificationDelegate:), @selector(nv_backupStore:withName:destinationRef:verifyWithSelector:verificationDelegate:));
    NSDictionary *retry = [library backupSnapshotWithError:&error];
    Check(retry && !error && [[retry objectForKey:@"generation"] unsignedLongLongValue] == before + 1, @"retry advances generation exactly once for a syntax-only change");
    [prefs setSourceMetadata:@{@"syntax": @"markdown"} forNoteUUID:@"fixture-syntax"];
    Swap([WALStorageController class], @selector(synchronize), @selector(nv_backupSynchronize));
    NVFailBackupJournalSync = YES;
    NSDictionary *journalFailure = [library backupSnapshotWithError:&error];
    Check(journalFailure && [journalFailure objectForKey:@"journalWriteError"], @"a complete archive reports a primary journal sync failure separately");
    NVFailBackupJournalSync = NO;
    NSDictionary *journalRecovery = [library backupSnapshotWithError:&error];
    Check(journalRecovery && ![journalRecovery objectForKey:@"journalWriteError"] &&
        [[journalRecovery objectForKey:@"generation"] isEqual:[journalFailure objectForKey:@"generation"]], @"an unchanged capture clears a recovered journal error without requiring another edit");
    Swap([WALStorageController class], @selector(synchronize), @selector(nv_backupSynchronize));
    NSString *previousIdentity = [[prefs backupLibraryIdentifier] copy];
    [prefs renewBackupLibraryIdentifier];
    NSDictionary *copied = [library backupSnapshotWithError:&error];
    Check(copied && ![[copied objectForKey:@"libraryIdentifier"] isEqual:previousIdentity] && [[copied objectForKey:@"generation"] unsignedLongLongValue] == 1, @"copied library identity is committed with its own generation");
    [previousIdentity release];
    [self nv_backupRoundTrip:SingleDatabaseFormat encrypted:NO];
    [self nv_backupRoundTrip:PlainTextFormat encrypted:NO];
    [self nv_backupRoundTrip:SingleDatabaseFormat encrypted:YES];
    [self nv_backupRoundTrip:PlainTextFormat encrypted:YES];
    Check(![NVBackupArchive restoredArchiveFromData:[@"not an archive" dataUsingEncoding:NSUTF8StringEncoding] error:&error] && error, @"corrupt archive fails without touching the active library");
    NotationPrefs *emptyPrefs = [[[NotationPrefs alloc] init] autorelease];
    NSDictionary *empty = [NVBackupArchive restoredArchiveFromData:[FrozenNotation frozenDataWithExistingNotes:[NSMutableArray array] prefs:emptyPrefs] error:&error];
    Check(empty && [[empty objectForKey:@"noteCount"] unsignedIntegerValue] == 0, @"an empty library has a valid recoverable backup");
    NSString *journalDirectory = [TestDirectory stringByAppendingPathComponent:@"UnlinkFailure"];
    [[NSFileManager defaultManager] createDirectoryAtPath:journalDirectory withIntermediateDirectories:NO attributes:nil error:NULL];
    WALStorageController *journal = [[[WALStorageController alloc] initWithParentFSRep:[journalDirectory fileSystemRepresentation]
        encryptionKey:[NSMutableData dataWithLength:32]] autorelease];
    Check(journal != nil && [journal synchronize], @"isolated failure fixture has a valid journal");
    chmod([journalDirectory fileSystemRepresentation], 0500);
    Check(![journal destroyLogFilePreservingWriterOnFailure] && [journal synchronize] && [journal logFileStillExists], @"unlink permission failure leaves the journal descriptor open and usable");
    chmod([journalDirectory fileSystemRepresentation], 0700);
    Check([journal destroyLogFilePreservingWriterOnFailure], @"journal removal can succeed after the permission failure is corrected");
    // Prepare an encrypted recovered library entirely in memory. The original stays open.
    FrozenNotation *current = [NSKeyedUnarchiver unarchiveObjectWithData:[copied objectForKey:@"data"]];
    OSStatus readStatus = noErr;
    NSMutableArray *currentNotes = [current unpackedNotesReturningError:&readStatus];
    NotationPrefs *recoveryPrefs = [current notationPrefs];
    [recoveryPrefs prepareForOfflineBackupRestore];
    NSData *recoveryPassword = [@"disposable recovery password" dataUsingEncoding:NSUTF8StringEncoding];
    [recoveryPrefs setPassphraseData:recoveryPassword inKeychain:NO];
    [recoveryPrefs setDoesEncryption:YES];
    NSData *encryptedData = [FrozenNotation frozenDataWithExistingNotes:currentNotes prefs:recoveryPrefs];
    NSDictionary *prepared = [NVBackupArchive restoredArchiveFromData:encryptedData passphraseData:recoveryPassword error:&error];
    Check(prepared && !error, @"encrypted recovery is validated before closing the original library");
    NSString *restorePath = [TestDirectory stringByAppendingPathComponent:@"Restored"];
    [[NSFileManager defaultManager] createDirectoryAtPath:restorePath withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    Check([[prepared objectForKey:@"data"] writeToFile:[restorePath stringByAppendingPathComponent:NotesDatabaseFileName] atomically:YES], @"only the re-encrypted restored archive reaches the new folder");
    FSRef restoredRef;
    Check(FSPathMakeRef((const UInt8*)[restorePath fileSystemRepresentation], &restoredRef, NULL) == noErr, @"restored directory has a filesystem reference");
    NotationController *rejected = [[NotationController alloc] initWithRestoredDirectoryRef:&restoredRef unlockedPrefs:[prepared objectForKey:@"unlockedPrefs"] error:&readStatus];
    Check(!rejected && readStatus == kJournalingError && [[GlobalPrefs defaultPrefs] notationPrefs] == [library notationPrefs], @"restored initialization cannot recover the still-active original journal or change its preferences");
    Check([library prepareForBackupRestoreWithError:&error] && !error, @"a committed library closes its journal before restore replacement");
    NSString *originalPath = [[library notesDirectoryURL] path];
    NSString *unavailablePath = [TestDirectory stringByAppendingPathComponent:@"OriginalUnavailable"];
    Check([[NSFileManager defaultManager] moveItemAtPath:originalPath toPath:unavailablePath error:&error], @"original directory is unavailable at its former location during recovery");
    NotationController *recovered = [[NotationController alloc] initWithRestoredDirectoryRef:&restoredRef unlockedPrefs:[prepared objectForKey:@"unlockedPrefs"] error:&readStatus];
    Check(recovered && readStatus == noErr && [recovered totalNoteCount] == [library totalNoteCount], @"encrypted restored library opens with its prepared in-memory key while original files and journal are unavailable");
    Check([recovered currentNoteStorageFormat] == SingleDatabaseFormat &&
        [[[[recovered allNotes] objectAtIndex:0] contentString].string isEqual:[[[[library allNotes] objectAtIndex:0] contentString] string]], @"recovered source is exact after normal library initialization");
    [recovered closeAllResources]; [recovered release];
    Check([[NSFileManager defaultManager] moveItemAtPath:unavailablePath toPath:originalPath error:&error], @"the original disposable library returns to its original path");
    [[GlobalPrefs defaultPrefs] setNotationPrefs:[library notationPrefs] sender:library];
    Check([library resumeAfterBackupRestoreFailureWithError:&error] && !error, @"failed replacement can reopen the original library journal");
    Check([library backupSnapshotWithError:&error] != nil, @"the resumed original library can capture backups");
    prepared = [NVBackupArchive restoredArchiveFromData:encryptedData passphraseData:recoveryPassword error:&error];
    Check(prepared && !error, @"coordinator recovery starts from a fresh validated archive and matching key");
    NVApplicationController *coordinator = [NVApplicationController sharedController];
    Check([coordinator library] == library, @"coordinator owns the original library for rollback checks");
    NSString *failedPath = [TestDirectory stringByAppendingPathComponent:@"CoordinatorFailure"];
    [[NSFileManager defaultManager] createDirectoryAtPath:failedPath withIntermediateDirectories:NO attributes:nil error:NULL];
    Swap([NotationController class], @selector(initWithRestoredDirectoryRef:unlockedPrefs:error:), @selector(nv_restoredInit:unlockedPrefs:error:));
    NVFailRestoredInitialization = YES;
    Check(![coordinator restoreBackupArchive:prepared toDirectory:[NSURL fileURLWithPath:failedPath] error:&error] && error,
        @"coordinator reports a restored-library initialization failure");
    NVFailRestoredInitialization = NO;
    Swap([NotationController class], @selector(initWithRestoredDirectoryRef:unlockedPrefs:error:), @selector(nv_restoredInit:unlockedPrefs:error:));
    Check([coordinator library] == library && [self sharedNotationController] == library && [library backupSnapshotWithError:&error],
        @"failed coordinator restore retains the original browser, model and usable journal");
    NSString *successPath = [TestDirectory stringByAppendingPathComponent:@"CoordinatorSuccess"];
    [[NSFileManager defaultManager] createDirectoryAtPath:successPath withIntermediateDirectories:NO attributes:nil error:NULL];
    [library retain];
    Check([coordinator restoreBackupArchive:prepared toDirectory:[NSURL fileURLWithPath:successPath] error:&error] && !error,
        @"coordinator opens a validated encrypted backup as a separate library");
    Check([coordinator library] != library && [self sharedNotationController] == [coordinator library] &&
        [[GlobalPrefs defaultPrefs] notationPrefs] == [[coordinator library] notationPrefs] &&
        [[coordinator library] totalNoteCount] == [library totalNoteCount],
        @"successful restore attaches browsers, preferences and backup ownership to the recovered library");
    [library release];
    NSLog(@"BACKUP ARCHIVE PASS: %lu checks", (unsigned long)Checks);
    [self nv_finishTests];
}
