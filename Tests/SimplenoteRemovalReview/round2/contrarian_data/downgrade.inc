- (void)nv_runTests {
    @try {
        NSString *service = [NSClassFromString(@"SimplenoteSession") serviceName];
        Check([service isEqual:@"SN"], @"passive downgrade reader uses the actual old app");
        NSString *directory = [NSString stringWithUTF8String:getenv("NV_ENCRYPTED_REVIEW_DIRECTORY")];
        for (NSString *name in @[@"rewritten-1.notation",@"rewritten-2.notation"]) {
            FrozenNotation *frozen = ReadEncryptedArchive([NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]],NO);
            Check(![[frozen notationPrefs] syncServiceIsEnabled:service] && [[frozen deletedNotes] count] == 0 &&
                  [[[[frozen valueForKey:@"allNotes"] firstObject] syncServicesMD] count] == 0,
                  @"old reader sees local source with no restored account, remote metadata, or remote tombstones");
            NSLog(@"PASSIVE DOWNGRADE HISTORY PASSED: %@",name);
        }
        Check(OfflineKeychainCleanupCalls == 0, @"passive old reader needed no keychain cleanup override");
        NSLog(@"ENCRYPTED OLD READER CHECKS PASSED: %lu",(unsigned long)Checks); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
