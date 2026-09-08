- (void)danR3_checkLedger:(NSArray *)ledger library:(NotationController *)library {
    BOOL exact = YES; NSUInteger survivors = 0;
    for (NSUInteger index = 0; index < [ledger count]; index++) {
        CFUUIDBytes uuid; [ledger[index] getBytes:&uuid length:sizeof(uuid)];
        NoteObject *note = [library noteForUUIDBytes:&uuid];
        BOOL present = index % 4 == 0;
        exact = exact && (note != nil) == present;
        if (present) {
            survivors++;
            exact = exact && [titleOfNote(note) isEqualToString:DanR3Title(index)] &&
                [[[note contentString] string] isEqualToString:DanR3Body(index)] &&
                [labelsOfNote(note) isEqualToString:@"local, retained"];
        }
    }
    Check(exact, @"independent UUID ledger verifies each deletion and exact surviving title, source, and tags");
    Check([[library allNotes] count] == survivors, @"survivor count excludes all deleted identities and duplicates");
}
- (void)nv_runTests {
    @try {
        BOOL baseline = NSClassFromString(@"SimplenoteSession") != Nil;
        BOOL remoteMetadata = baseline && !getenv("NV_DAN_R3_NO_REMOTE_METADATA");
        NSString *directory = [TestDirectory stringByAppendingPathComponent:@"RemovalMeasured"];
        Check([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL],
            @"create an isolated disposable database library");
        NotationController *library = DanR3Open(directory);
        [library stopFileNotifications];
        Check([library currentNoteStorageFormat] == SingleDatabaseFormat && [library delegate] == nil,
            @"measured library uses database storage without browser or editing-session ownership");
        if (baseline) Check([[library.notationPrefs valueForKey:@"syncServiceAccounts"] count] == 0,
            @"baseline has no configured or enabled sync accounts");
        NSUndoManager *undo = [[NSUndoManager alloc] init];
        [undo setGroupsByEvent:NO]; [library setUndoManager:undo];
        Check([library flushAllNoteChanges], @"store initial empty library before counting");
        DanR3Library = library; DanR3Journal = [library valueForKey:@"walWriter"];
        Check(DanR3Journal != nil, @"real journal writer is present");
        DanR3OriginalPointers = [[NSMutableSet alloc] init];
        DanR3Swap([NoteObject class], @selector(dealloc), @selector(danR3_dealloc));
        DanR3Swap([NoteObject class], @selector(encodeWithCoder:), @selector(danR3_encode:));
        DanR3Swap([DeletedNoteObject class], @selector(encodeWithCoder:), @selector(danR3_encode:));
        DanR3Swap([WALStorageController class], @selector(writeNoteObject:), @selector(danR3_write:));
        DanR3Swap([NotationController class], @selector(storeDataAtomicallyInNotesDirectory:withName:destinationRef:verifyWithSelector:verificationDelegate:),
            @selector(danR3_store:withName:destinationRef:verifyWithSelector:verificationDelegate:));
        NSMutableArray *ledger = [[NSMutableArray alloc] init];
        NSMutableArray *retentionControl = [[NSMutableArray alloc] init];
        for (NSUInteger batch = 0; batch < 4; batch++) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSUInteger noteWritesStart = DanR3NoteWrites, removalWritesStart = DanR3RemovalWrites;
            for (NSUInteger item = 0; item < 24; item++) {
                NSUInteger index = batch * 24 + item;
                NoteObject *note = [[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:DanR3Body(index)] autorelease]
                    title:DanR3Title(index) delegate:library format:SingleDatabaseFormat labels:
                    getenv("NV_DAN_R3_CONSTRUCTOR_TAGS") ? @"local, retained" : @""];
                [DanR3OriginalPointers addObject:[NSValue valueWithPointer:note]]; DanR3Created++;
                if (remoteMetadata) {
                    // Passive historical model metadata only. No account or service is enabled.
                    [note setValue:[NSMutableDictionary dictionaryWithDictionary:@{@"SN":
                        [NSMutableDictionary dictionaryWithDictionary:@{@"key": DanR3Title(index), @"version": @7, @"dirty": @YES,
                            @"modify": @(modifiedDateOfNote(note))}]}]
                        forKey:@"syncServicesMD"];
                }
                [ledger addObject:[NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)]];
                [library addNewNote:note];
                [note setLabelString:@"local, retained"];
                [undo beginUndoGrouping]; [library removeNote:note]; [undo endUndoGrouping];
                [undo undo]; [undo redo];
                if (index % 4 == 0) [undo undo];
                else if (getenv("NV_DAN_R3_RETAIN_DELETED")) [retentionControl addObject:note];
                [undo removeAllActions];
                [note release];
            }
            Check(![undo canUndo] && ![undo canRedo], @"each batch clears deletion and restoration Undo ownership");
            [pool drain];
            for (NSUInteger cleanup = 0; cleanup < 2; cleanup++) {
                NSAutoreleasePool *idlePool = [[NSAutoreleasePool alloc] init];
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
                [idlePool drain];
            }
            NSUInteger survivors = (batch + 1) * 6, deleted = (batch + 1) * 18;
            NSLog(@"DAN_R3_LIFETIME batch=%lu created=%lu released=%lu live=%lu", (unsigned long)(batch + 1),
                (unsigned long)DanR3Created, (unsigned long)DanR3Released, (unsigned long)[DanR3OriginalPointers count]);
            Check([DanR3OriginalPointers count] == (remoteMetadata ? DanR3Created : survivors) &&
                DanR3Released == (remoteMetadata ? 0 : deleted),
                @"drained pools leave only the expected original notes retained after Undo is cleared");
            Check(DanR3NoteWrites - noteWritesStart == 78 && DanR3RemovalWrites - removalWritesStart == 48,
                @"24 create/tag/delete/Undo/Redo histories emit 78 note records and 48 local removal records");
            Check([DanR3Journal synchronize], @"journal synchronization succeeds after each bounded batch");
            [self danR3_checkLedger:ledger library:library];
            DanR3EncodedNotes = DanR3EncodedTombstones = 0;
            DanR3SnapshotPhase = YES;
            Check([library flushAllNoteChanges], @"bounded removal history stores a verified checkpoint");
            DanR3SnapshotPhase = NO;
            Check(DanR3EncodedNotes == survivors && DanR3EncodedTombstones == (remoteMetadata ? deleted : 0),
                @"checkpoint encodes every surviving note once and only the expected remote deletion history");
            NSLog(@"DAN_R3_BATCH app=%@ batch=%lu created=%lu released=%lu liveOriginals=%lu survivors=%lu noteRecords=%lu removalRecords=%lu snapshotNotes=%lu snapshotTombstones=%lu snapshots=%lu",
                baseline ? @"baseline" : @"current", (unsigned long)(batch + 1), (unsigned long)DanR3Created, (unsigned long)DanR3Released,
                (unsigned long)[DanR3OriginalPointers count], (unsigned long)survivors, (unsigned long)(DanR3NoteWrites - noteWritesStart),
                (unsigned long)(DanR3RemovalWrites - removalWritesStart), (unsigned long)DanR3EncodedNotes,
                (unsigned long)DanR3EncodedTombstones, (unsigned long)DanR3Snapshots);
        }
        Check(DanR3Snapshots == 4 && DanR3NoteWrites == 312 && DanR3RemovalWrites == 192,
            @"complete workload writes four checkpoints and 504 expected local journal records");
        DanR3Library = nil; DanR3Journal = nil;
        [library closeAllResources]; [library release]; [undo release];
        library = DanR3Open(directory); [library stopFileNotifications];
        [self danR3_checkLedger:ledger library:library];
        Check([[library allNotes] count] == 24, @"real controller reopen preserves 24 survivors without resurrecting 72 deletions");
        [library closeAllResources]; [library release];
        NSLog(@"DAN_R3_RESULT app=%@ histories=96 survivors=24 deleted=72 checks=%lu",
            baseline ? @"baseline" : @"current", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
