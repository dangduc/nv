- (void)nv_runTests {
    @try {
        // Run only against the saved app from before Simplenote removal.
        Check(NSClassFromString(@"SimplenoteSession") != Nil, @"fixture producer is an app with Simplenote support");
        NSString *body = @"# Local café 😀\r\n\tunsent changes\n";
        NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
            title:@"Local synced title" delegate:nil format:SingleDatabaseFormat labels:@"keep, 日本語"] autorelease];
        CFUUIDBytes identifier = { 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef };
        *[note uniqueNoteIDBytes] = identifier;
        note->createdDate = 700000000.25; note->modifiedDate = 700000123.5;
        [note incrementLSN];
        [note setValue:[NSMutableDictionary dictionaryWithDictionary:@{@"Simplenote": @{@"key": @"legacy-remote-note", @"version": @7, @"dirty": @YES}}] forKey:@"syncServicesMD"];
        NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
        [prefs setSourceMetadata:@{@"syntax": @"markdown"} forNoteUUID:[NSString uuidStringWithBytes:identifier]];
        [prefs setValue:[NSMutableDictionary dictionaryWithDictionary:@{@"Simplenote": [NSMutableDictionary dictionaryWithDictionary:@{@"enabled": @YES, @"username": @"fixture@example.invalid", @"frequency": @1}]}] forKey:@"syncServiceAccounts"];
        NoteObject *removed = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"Previously removed"] autorelease]
            title:@"Removed remote note" delegate:nil format:SingleDatabaseFormat labels:@""] autorelease];
        *[removed uniqueNoteIDBytes] = (CFUUIDBytes){ 0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00 };
        NSData *fixture = [FrozenNotation frozenDataWithExistingNotes:[NSMutableArray arrayWithObject:note]
            deletedNotes:[NSMutableSet setWithObject:[DeletedNoteObject deletedNoteWithNote:removed]] prefs:prefs];
        NSString *output = [NSString stringWithUTF8String:getenv("NV_LEGACY_FIXTURE_DIRECTORY")];
        Check([fixture writeToFile:[output stringByAppendingPathComponent:@"legacy-simplenote.notation"] atomically:YES], @"pre-removal app writes the legacy local library fixture");
        NSLog(@"LEGACY FIXTURE GENERATED: %lu bytes", (unsigned long)[fixture length]);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@", exception); _exit(1); }
}
