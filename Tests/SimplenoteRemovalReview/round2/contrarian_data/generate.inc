- (void)nv_runTests {
    @try {
        Class oldService = NSClassFromString(@"SimplenoteSession");
        NSString *service = [oldService serviceName];
        Check([service isEqual:@"SN"], @"encrypted producer is the old app with the registered SN service");
        NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:FixtureSource()] autorelease]
            title:@"Encrypted local source" delegate:nil format:SingleDatabaseFormat labels:@"local, café"] autorelease];
        *[note uniqueNoteIDBytes] = FixtureUUID();
        [note setValue:@23 forKey:@"logSequenceNumber"];
        [note setValue:@711234500.25 forKey:@"createdDate"];
        [note setValue:@711234567.75 forKey:@"modifiedDate"];
        [note rememberSourceData:FixtureSourceBytes() encoding:NSUTF32LittleEndianStringEncoding];
        [note setValue:[NSMutableDictionary dictionaryWithDictionary:@{service:@{@"key":@"encrypted-pending-upload", @"version":@31, @"modify":@711234567.75, @"dirty":@YES}}] forKey:@"syncServicesMD"];
        NotationPrefs *prefs = [[[NVEncryptedFixturePrefs alloc] init] autorelease];
        [prefs setSourceMetadata:FixtureSyntax() forNoteUUID:[NSString uuidStringWithBytes:FixtureUUID()]];
        [prefs setValue:[NSMutableDictionary dictionaryWithDictionary:@{service:[NSMutableDictionary dictionaryWithDictionary:
            @{@"enabled":@YES,@"username":@"encrypted-fixture@example.invalid",@"frequency":@3}]}] forKey:@"syncServiceAccounts"];
        [prefs setPassphraseData:FixturePassphrase() inKeychain:NO];
        [prefs setDoesEncryption:YES];
        Check(OfflineKeychainCleanupCalls == 1 && [prefs valueForKey:@"keychainDatabaseIdentifier"] == nil,
              @"test intercepts legacy cleanup before any keychain access or identifier allocation");
        Check([prefs syncServiceIsEnabled:service] && [[[[note syncServicesMD] objectForKey:service] objectForKey:@"dirty"] boolValue],
              @"encrypted fixture starts with recognized enabled-account and pending-upload state");
        NoteObject *removed = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"deleted locally"] autorelease]
            title:@"Encrypted fixture tombstone" delegate:nil format:SingleDatabaseFormat labels:@""] autorelease];
        *[removed uniqueNoteIDBytes] = (CFUUIDBytes){0xf2,0xe3,0xd4,0xc5,0xb6,0xa7,0x98,0x89,0x7a,0x6b,0x5c,0x4d,0x3e,0x2f,0x10,0x01};
        [removed setValue:[NSMutableDictionary dictionaryWithDictionary:@{service:@{@"key":@"encrypted-pending-deletion",@"version":@9,@"dirty":@YES}}] forKey:@"syncServicesMD"];
        NSData *data = [FrozenNotation frozenDataWithExistingNotes:[NSMutableArray arrayWithObject:note]
            deletedNotes:[NSMutableSet setWithObject:[DeletedNoteObject deletedNoteWithNote:removed]] prefs:prefs];
        FrozenNotation *read = ReadEncryptedArchive(data,YES);
        Check([[read notationPrefs] isMemberOfClass:[NotationPrefs class]], @"fixture archives the production preferences class");
        Check([[read notationPrefs] syncServiceIsEnabled:service] && [[read deletedNotes] count] == 1,
              @"old encrypted self-read retains recognized remote account and deletion history");
        NSString *path = [[NSString stringWithUTF8String:getenv("NV_ENCRYPTED_REVIEW_DIRECTORY")] stringByAppendingPathComponent:@"old-encrypted.notation"];
        Check([data writeToFile:path atomically:YES], @"old app writes the fixed encrypted compatibility artifact");
        NSLog(@"ENCRYPTED OLD PRODUCER CHECKS PASSED: %lu",(unsigned long)Checks); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
