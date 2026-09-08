- (void)nv_runTests {
    @try {
        NSString *path = [NSString stringWithUTF8String:getenv("NV_DATA_REVIEW_FIXTURE")];
        NSData *data = [NSData dataWithContentsOfFile:path];
        Check(data != nil, @"fixture guard reads the specified synthetic archive");
        SourceCheckLegacyFixtureMetadata(data);
        NSLog(@"FIXTURE GUARD CHECKS PASSED: %lu",(unsigned long)Checks); _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@",exception); _exit(1); }
}
