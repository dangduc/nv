- (void)nv_runTests {
    @try {
        Check(NSClassFromString(@"SimplenoteSession") == Nil, @"encrypted reader is the Simplenote removal app");
        NSString *directory = [NSString stringWithUTF8String:getenv("NV_ENCRYPTED_REVIEW_DIRECTORY")];
        NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"old-encrypted.notation"]];
        for (NSUInteger generation = 0; generation < 3; generation++) {
            FrozenNotation *frozen = ReadEncryptedArchive(data,generation == 0);
            NSLog(@"ENCRYPTED HISTORY PASSED: generation %lu",(unsigned long)generation);
            if (generation < 2) {
                NSData *oldSalt = [[[[frozen notationPrefs] valueForKey:@"dataSessionSalt"] copy] autorelease];
                data = [FrozenNotation frozenDataWithExistingNotes:[frozen valueForKey:@"allNotes"] prefs:[frozen notationPrefs]];
                Check(data && ![[[frozen notationPrefs] valueForKey:@"dataSessionSalt"] isEqual:oldSalt],
                      @"current rewrite uses a new encryption session while preserving the passphrase");
                Check([data writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"rewritten-%lu.notation",(unsigned long)(generation+1)]] atomically:YES],
                      @"rewritten encrypted archive is retained for independent old-reader verification");
            }
        }
        Check(OfflineKeychainCleanupCalls == 0, @"reader needed no keychain cleanup override");
        NSLog(@"ENCRYPTED CURRENT READER CHECKS PASSED: %lu",(unsigned long)Checks); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
