- (void)nv_runTests {
    @try {
        Check(NSClassFromString(@"SimplenoteSession") == Nil, @"reader is the Simplenote removal app");
        NSString *directory = [NSString stringWithUTF8String:getenv("NV_DATA_REVIEW_DIRECTORY")];
        NSArray *expected = [NSArray arrayWithContentsOfFile:[directory stringByAppendingPathComponent:@"expected.plist"]];
        Check([expected count] == 3, @"independent old-app source oracle is available");
        NSArray *names = @[@"old-native", @"obsolete-null", @"obsolete-string", @"obsolete-array", @"obsolete-data"];
        if (getenv("NV_DATA_REVIEW_NEGATIVE")) names = @[@"negative-local-sequence"];
        for (NSString *name in names) {
            NSData *data = [NSData dataWithContentsOfFile:[[directory stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"notation"]];
            Check(data && ArchiveContainsKey(data,@"syncServiceAccounts") && ArchiveContainsKey(data,@"deletedNoteSet"), @"fixture still has obsolete archive fields");
            for (NSUInteger rewrite = 0; rewrite < 4; rewrite++) {
                FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                Check(frozen != nil, @"obsolete account/deletion values do not prevent snapshot decoding");
                OSStatus error = noErr;
                NSArray *notes = [frozen unpackedNotesReturningError:&error];
                Check(error == noErr && [notes count] == [expected count], @"pending remote deletion does not remove or resurrect local records");
                for (NSUInteger i = 0; i < [notes count]; i++) {
                    NoteObject *note = [notes objectAtIndex:i];
                    NSDictionary *snapshot = DataSnapshot(note,[frozen notationPrefs]);
                    if (![snapshot isEqual:[expected objectAtIndex:i]]) NSLog(@"snapshot=%@ expected=%@",snapshot,[expected objectAtIndex:i]);
                    Check([snapshot isEqual:[expected objectAtIndex:i]], @"UUID, local characters, tags, dates, sequence, encoding, BOM, conversion/conflict state and syntax remain exact");
                    if (i < 2) Check([[note sourceDataReturningError:NULL] isEqual:[[expected objectAtIndex:i] objectForKey:@"sourceOriginalData"]], @"unchanged Unicode or CP1252 source export returns the original exact bytes");
                }
                data = [FrozenNotation frozenDataWithExistingNotes:[NSMutableArray arrayWithArray:notes] prefs:[frozen notationPrefs]];
                Check(!ArchiveContainsKey(data,@"syncServiceAccounts") && !ArchiveContainsKey(data,@"deletedNoteSet"), @"rewrite drops obsolete account and remote deletion fields");
                FrozenNotation *inspection = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                Check(!ArchiveContainsKey([[inspection valueForKey:@"notesData"] uncompressedData],@"syncServicesMD"), @"rewrite drops remote note metadata");
            }
            NSLog(@"HISTORY PASSED: %@, initial read plus 3 rewrite reads",name);
        }
        NSLog(@"CONTRARIAN DATA CHECKS PASSED: %lu",(unsigned long)Checks); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
