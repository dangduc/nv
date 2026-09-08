- (void)nv_runTests {
    @try {
        Check(NSClassFromString(@"SimplenoteSession") == Nil, @"probe uses the app after Simplenote removal");
        NSString *directory = [NSString stringWithUTF8String:getenv("NV_FIXTURE_REVIEW_DIR")];
        NSArray *manifest = [NSArray arrayWithContentsOfFile:[directory stringByAppendingPathComponent:@"manifest.plist"]];
        Check([manifest count] == 8, @"one correct fixture, six metadata controls, and one retained-field control are available");
        GuardOutcomes = [NSMutableArray new];
        for (NSDictionary *row in manifest) {
            NSString *name = [row objectForKey:@"name"];
            NSLog(@"BEGIN HISTORY: %@", name);
            NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:
                [name stringByAppendingPathExtension:@"notation"]]];
            Check([data length] > 0, @"history has an archive");
            [GuardOutcomes removeAllObjects];
            SourceCheckLegacyFixtureMetadata(data);
            Check([GuardOutcomes isEqual:[row objectForKey:@"guards"]], @"exact final guard accepts or rejects each specified precondition");
            for (NSUInteger cycle = 0; cycle < 2; cycle++) {
                FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                Check(frozen != nil && ![[frozen notationPrefs] doesEncryption], @"local decoder reads the unencrypted fixture");
                OSStatus error = noErr;
                NSMutableArray *notes = [frozen unpackedNotesReturningError:&error];
                Check(error == noErr && [notes count] == 1, @"one live local note remains and remote deletion history creates no note");
                BOOL localMatches = LocalValuesMatch([notes firstObject], [frozen notationPrefs]);
                NSLog(@"LOCAL ORACLE %@: %@ cycle %lu", localMatches ? @"ACCEPT" : @"REJECT", name, (unsigned long)cycle);
                Check(localMatches == [[row objectForKey:@"local"] boolValue],
                    @"local UUID, characters, title, tags, dates, sequence, source bytes, and syntax satisfy the independent oracle");
                data = [FrozenNotation frozenDataWithExistingNotes:notes prefs:[frozen notationPrefs]];
                Check([data length] > 0 && !RawArchiveHasKey(data, @"syncServiceAccounts") && !RawArchiveHasKey(data, @"deletedNoteSet"),
                    @"current rewrite omits old account settings and remote deletion history");
                FrozenNotation *inspection = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                Check(!RawArchiveHasKey([[inspection valueForKey:@"notesData"] uncompressedData], @"syncServicesMD"),
                    @"current rewrite omits obsolete note upload metadata");
            }
            NSLog(@"HISTORY PASSED: %@ (original read and rewritten read)", name);
        }
        [GuardOutcomes release];
        NSLog(@"R3 DATA GUARD CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
