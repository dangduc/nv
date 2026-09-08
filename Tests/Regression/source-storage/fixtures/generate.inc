- (void)nv_runTests {
    @try {
        // Run only against the saved app from before Simplenote removal.
        Check(NSClassFromString(@"SimplenoteSession") != Nil, @"fixture producer is an app with Simplenote support");
        NSString *serviceName = [SimplenoteSession serviceName];
        Check([serviceName isEqualToString:@"SN"] && [[SyncSessionController allServiceNames] containsObject:serviceName],
              @"fixture uses the old app's registered Simplenote service identifier");
        NSString *body = @"# Local café 😀\r\n\tunsent changes\n";
        NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
            title:@"Local synced title" delegate:nil format:SingleDatabaseFormat labels:@"keep, 日本語"] autorelease];
        CFUUIDBytes identifier = { 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef };
        *[note uniqueNoteIDBytes] = identifier;
        note->createdDate = 700000000.25; note->modifiedDate = 700000123.5;
        [note incrementLSN];
        NSDictionary *uploadMetadata = @{@"key": @"legacy-remote-note", @"version": @7, @"dirty": @YES,
            @"modify": @700000123.5, @"SepStr": @"e\n\n#"};
        [note setValue:[NSMutableDictionary dictionaryWithDictionary:@{serviceName: uploadMetadata}] forKey:@"syncServicesMD"];
        NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
        [prefs setSourceMetadata:@{@"syntax": @"markdown"} forNoteUUID:[NSString uuidStringWithBytes:identifier]];
        [prefs setValue:[NSMutableDictionary dictionaryWithDictionary:@{serviceName: [NSMutableDictionary dictionaryWithDictionary:@{@"enabled": @YES, @"username": @"fixture@example.invalid", @"frequency": @1}]}] forKey:@"syncServiceAccounts"];
        NoteObject *removed = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"Previously removed"] autorelease]
            title:@"Removed remote note" delegate:nil format:SingleDatabaseFormat labels:@""] autorelease];
        *[removed uniqueNoteIDBytes] = (CFUUIDBytes){ 0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00 };
        NSDictionary *deletionMetadata = @{@"key": @"legacy-remote-deletion", @"version": @11,
            @"dirty": @YES, @"modify": @700000124.5};
        [removed setValue:[NSMutableDictionary dictionaryWithDictionary:@{serviceName: deletionMetadata}] forKey:@"syncServicesMD"];
        DeletedNoteObject *tombstone = [DeletedNoteObject deletedNoteWithNote:removed];
        Check([prefs syncServiceIsEnabled:serviceName], @"old app recognizes the enabled fixture account before archiving");
        Check([[[note syncServicesMD] objectForKey:serviceName] isEqual:uploadMetadata], @"live note has recognized pending upload metadata before archiving");
        Check([[[tombstone syncServicesMD] objectForKey:serviceName] isEqual:deletionMetadata], @"tombstone has recognized pending deletion metadata before archiving");
        NSData *fixture = [FrozenNotation frozenDataWithExistingNotes:[NSMutableArray arrayWithObject:note]
            deletedNotes:[NSMutableSet setWithObject:tombstone] prefs:prefs];
        FrozenNotation *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:fixture];
        OSStatus error = noErr;
        NSArray *decodedNotes = [decoded unpackedNotesReturningError:&error];
        Check(error == noErr && [decodedNotes count] == 1 && [[decoded deletedNotes] count] == 1, @"old app reads back the live note and deletion tombstone");
        Check([[decoded notationPrefs] syncServiceIsEnabled:serviceName], @"old app recognizes the archived account as enabled");
        Check([[[[decodedNotes firstObject] syncServicesMD] objectForKey:serviceName] isEqual:uploadMetadata], @"archived note retains recognized pending upload metadata");
        Check([[[[[[decoded deletedNotes] allObjects] firstObject] syncServicesMD] objectForKey:serviceName] isEqual:deletionMetadata], @"archived tombstone retains recognized pending deletion metadata");
        NSString *output = [NSString stringWithUTF8String:getenv("NV_LEGACY_FIXTURE_DIRECTORY")];
        Check([fixture writeToFile:[output stringByAppendingPathComponent:@"legacy-simplenote.notation"] atomically:YES], @"pre-removal app writes the legacy local library fixture");
        NSLog(@"LEGACY FIXTURE GENERATED: %lu bytes", (unsigned long)[fixture length]);
        NSLog(@"LEGACY FIXTURE PRODUCER CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@", exception); _exit(1); }
}
