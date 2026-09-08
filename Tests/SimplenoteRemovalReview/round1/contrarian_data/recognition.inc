- (void)nv_runTests {
    @try {
        Class service = NSClassFromString(@"SimplenoteSession");
        Class controller = NSClassFromString(@"SyncSessionController");
        NSString *serviceName = [service serviceName];
        Check([serviceName isEqual:@"SN"] && [[controller allServiceNames] isEqual:@[@"SN"]],
            @"actual old app recognizes only SN as its registered Simplenote service");
        NSString *root = [NSString stringWithUTF8String:getenv("NV_DATA_REVIEW_REPOSITORY")];
        NSArray *paths = @[@"Tests/SimplenoteRemovalReview/round1/contrarian_data/original-regression.notation",
            @"Tests/SimplenoteRemovalReview/round1/contrarian_data/old-native.notation"];
        for (NSUInteger i = 0; i < [paths count]; i++) {
            FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:
                [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:[paths objectAtIndex:i]]]];
            OSStatus error = noErr;
            NSArray *notes = [frozen unpackedNotesReturningError:&error];
            Check(error == noErr && [notes count] > 0, @"old app reads the fixture for passive inspection");
            NotationPrefs *prefs = [frozen notationPrefs];
            BOOL registeredEnabled = [prefs syncServiceIsEnabled:serviceName];
            NSDictionary *remote = [[notes firstObject] syncServicesMD];
            NSDictionary *recognizedRemote = [remote objectForKey:serviceName];
            NSDictionary *deletedRemote = [[[[frozen deletedNotes] allObjects] firstObject] syncServicesMD];
            NSLog(@"RECOGNITION fixture=%@ registered=%@ enabled=%d noteKeys=%@ recognizedDirty=%d tombstoneKeys=%@",
                [paths objectAtIndex:i], serviceName, registeredEnabled, [remote allKeys],
                [[recognizedRemote objectForKey:@"dirty"] boolValue], [deletedRemote allKeys]);
            if (i == 0) {
                Check(!registeredEnabled && [prefs syncServiceIsEnabled:@"Simplenote"],
                    @"permanent fixture enables the unregistered display-name key while recognized SN stays disabled");
                Check(recognizedRemote == nil && [remote objectForKey:@"Simplenote"] != nil,
                    @"permanent fixture remote note metadata is invisible to the registered SN service");
                Check([deletedRemote objectForKey:serviceName] == nil,
                    @"permanent fixture tombstone has no recognized pending SN deletion metadata");
            } else {
                Check(registeredEnabled && [[recognizedRemote objectForKey:@"dirty"] boolValue],
                    @"independent old-native fixture enables SN and has recognized pending upload metadata");
                Check([deletedRemote objectForKey:serviceName] != nil,
                    @"independent old-native fixture has recognized pending SN deletion metadata");
            }
        }
        NSLog(@"PASSIVE SERVICE RECOGNITION CHECKS PASSED: %lu",(unsigned long)Checks); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@",exception); _exit(1); }
}
