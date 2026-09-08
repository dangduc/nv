- (void)nv_runTests {
    @try {
        Check(NSClassFromString(@"SimplenoteSession") != Nil, @"producer contains the old Simplenote implementation");
        NSString *output = [NSString stringWithUTF8String:getenv("NV_DATA_REVIEW_DIRECTORY")];
        NSMutableArray *notes = [NSMutableArray array], *expected = [NSMutableArray array];
        NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
        [prefs setValue:[NSMutableDictionary dictionaryWithDictionary:@{
            @"SN": [NSMutableDictionary dictionaryWithDictionary:@{@"enabled": @YES,
                @"username": @"data-review@example.invalid", @"frequency": @5, @"shouldmerge": @"data-review@example.invalid"}],
            @"RetiredService": [NSMutableDictionary dictionaryWithDictionary:@{@"username": @"offline@example.invalid", @"enabled": @NO}]
        }] forKey:@"syncServiceAccounts"];
        NSArray *bodies = @[@"{\"local\":\"café 😀\"}\r\n\t", @"<p>Local café £</p>\r\n", @"Local unsent emoji 😀\r\n"];
        NSArray *syntaxes = @[@"json", @"html", @"markdown"];
        for (NSUInteger i = 0; i < [bodies count]; i++) {
            NSString *body = [bodies objectAtIndex:i];
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
                title:[NSString stringWithFormat:@"Pending source %lu", (unsigned long)i] delegate:nil format:SingleDatabaseFormat
                labels:@"local, café, 日本語"] autorelease];
            CFUUIDBytes uuid = {0x21,0x43,0x65,0x87,0xa9,0xcb,0xed,0x0f,0x31,0x53,0x75,0x97,0xb9,0xdb,0xfd,(UInt8)i};
            *[note uniqueNoteIDBytes] = uuid;
            [note setValue:@(710000000.25 + i) forKey:@"createdDate"];
            [note setValue:@(710000111.75 + i) forKey:@"modifiedDate"];
            [note setValue:@(0x71234560U + i) forKey:@"logSequenceNumber"];
            NSMutableDictionary *remote = [NSMutableDictionary dictionaryWithDictionary:@{
                @"key": [NSString stringWithFormat:@"pending-%lu", (unsigned long)i], @"modify": @(710000111.75 + i),
                @"dirty": @YES, @"SepStr": @"e\n\n{", @"unrecognizedFutureFlag": @[@1,@"ordinary"]}];
            if (i != 1) [remote setObject:@17 forKey:@"version"];
            [note setValue:[NSMutableDictionary dictionaryWithDictionary:@{@"SN": remote}] forKey:@"syncServicesMD"];
            NSData *source = nil;
            if (i == 0) {
                const UInt8 bom[] = {0xff,0xfe};
                NSMutableData *utf16 = [NSMutableData dataWithBytes:bom length:2];
                [utf16 appendData:[body dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
                source = utf16;
                [note rememberSourceData:source encoding:NSUTF16LittleEndianStringEncoding];
            } else {
                source = [(i == 2 ? @"Previous local café £\r\n" : body) dataUsingEncoding:NSWindowsCP1252StringEncoding];
                [note rememberSourceData:source encoding:NSWindowsCP1252StringEncoding];
            }
            if (i == 2) {
                [note setValue:@YES forKey:@"sourceConversionPending"];
                [note markAsSourceConflictCopyOfNote:[notes firstObject]];
            }
            [prefs setSourceMetadata:@{@"syntax": [syntaxes objectAtIndex:i], @"futureLocalProperty": @{@"keep": @YES, @"value": @42}}
                forNoteUUID:[NSString uuidStringWithBytes:uuid]];
            [notes addObject:note];
            [expected addObject:DataSnapshot(note,prefs)];
        }
        NoteObject *removed = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"Already deleted locally"] autorelease]
            title:@"Pending remote deletion" delegate:nil format:SingleDatabaseFormat labels:@""] autorelease];
        [removed setValue:[NSMutableDictionary dictionaryWithDictionary:@{@"SN": @{@"key": @"pending-delete", @"version": @29, @"dirty": @YES}}] forKey:@"syncServicesMD"];
        [removed setValue:@98 forKey:@"logSequenceNumber"];
        NSData *data = [FrozenNotation frozenDataWithExistingNotes:notes
            deletedNotes:[NSMutableSet setWithObject:[DeletedNoteObject deletedNoteWithNote:removed]] prefs:prefs];
        Check(data && ArchiveContainsKey(data,@"syncServiceAccounts") && ArchiveContainsKey(data,@"deletedNoteSet"), @"old encoder writes enabled SN account and pending remote deletion history");
        FrozenNotation *baseline = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        Check(ArchiveContainsKey([[baseline valueForKey:@"notesData"] uncompressedData],@"syncServicesMD"), @"old notes include pending SN upload/API1 metadata");
        OSStatus error = noErr;
        NSArray *decoded = [baseline unpackedNotesReturningError:&error];
        Check(error == noErr && [decoded count] == 3, @"old app reads all independent source fixtures");
        for (NSUInteger i = 0; i < [decoded count]; i++) {
            if (![DataSnapshot([decoded objectAtIndex:i],[baseline notationPrefs]) isEqual:[expected objectAtIndex:i]])
                NSLog(@"baseline actual=%@ expected=%@",DataSnapshot([decoded objectAtIndex:i],[baseline notationPrefs]),[expected objectAtIndex:i]);
            Check([DataSnapshot([decoded objectAtIndex:i],[baseline notationPrefs]) isEqual:[expected objectAtIndex:i]], @"old writer and reader preserve the exact source-state oracle");
        }
        Check([data writeToFile:[output stringByAppendingPathComponent:@"old-native.notation"] atomically:YES] &&
            [expected writeToFile:[output stringByAppendingPathComponent:@"expected.plist"] atomically:YES], @"independent fixture and oracle are saved");
        NSLog(@"DATA FIXTURE GENERATOR PASSED: %lu", (unsigned long)Checks); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
