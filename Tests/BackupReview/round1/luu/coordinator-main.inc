int main(int argc, const char *argv[]) { @autoreleasepool {
    Check(argc == 2, @"temporary test root supplied");
    testRoot = [[NSString stringWithUTF8String:argv[1]] copy];
    memoryDefaults = [MemoryDefaults new]; completionQueue = [ManualQueue new];
    ReplaceClassMethod([NSUserDefaults class], @selector(standardUserDefaults), (IMP)MemoryStandardDefaults);
    ReplaceClassMethod([NSDate class], @selector(date), (IMP)ClockDate);
    ReplaceClassMethod([NSDate class], @selector(dateWithTimeIntervalSinceNow:), (IMP)ClockRelativeDate);
    ReplaceClassMethod([NSOperationQueue class], @selector(mainQueue), (IMP)ManualMainQueue);
    NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
    [[controller valueForKey:@"timer"] invalidate];
    ManualQueue *worker = [ManualQueue new]; [controller setValue:worker forKey:@"worker"];
    FixtureLibrary *library = [[FixtureLibrary alloc] initWithIdentifier:[[NSUUID UUID] UUIDString]];
    Attach(controller, library);
    for (NSUInteger index=0; index<5; index++) { clockTime++; [controller backupNow:nil]; Complete(worker); }
    NSURL *destination = [controller destinationURL]; NSError *error = nil;
    NSArray *initialEntries = [NVBackupStore snapshotsInDirectory:destination error:&error];
    if ([initialEntries count] != 5) NSLog(@"Probe setup status=%@ entries=%@ error=%@", [controller statusText], initialEntries, error);
    Check([initialEntries count] == 5, @"five actual packages created");
    Check([controller setSettings:@{@"recent":@3, @"daily":@0, @"weekly":@0} error:&error], @"stricter retention accepted");
    Tick(controller, clockTime); Complete(worker);
    NSUInteger afterSetting = [[NVBackupStore snapshotsInDirectory:destination error:&error] count];
    Tick(controller, clockTime+900); Complete(worker);
    NSUInteger afterRetry = [[NVBackupStore snapshotsInDirectory:destination error:&error] count];
#ifdef EXPECT_FIXED
    Check(afterSetting == 3 && afterRetry == 3, @"policy update prunes unchanged archives without another publication");
#else
    Check(afterSetting == 5 && afterRetry == 5, @"BUG: policy update and next tick leave excess packages on disk");
#endif
    [controller backupNow:nil]; Complete(worker);
    Check([[NVBackupStore snapshotsInDirectory:destination error:&error] count] == 3, @"manual publication applies the same valid retention policy");
    library->generation++;
    NVBackupStoreFailurePoint = @"prune";
    [controller backupNow:nil]; Complete(worker);
    Check([[controller statusText] rangeOfString:@"Injected backup failure: prune"].location != NSNotFound, @"prune failure initially reported");
    NVBackupStoreFailurePoint = nil;
    Tick(controller, clockTime+900); Complete(worker);
    NSUInteger afterErrorRetry = [[NVBackupStore snapshotsInDirectory:destination error:&error] count];
    BOOL errorCleared = [[controller statusText] rangeOfString:@"Injected backup failure: prune"].location == NSNotFound;
#ifdef EXPECT_FIXED
    Check(afterErrorRetry == 3 && errorCleared, @"next tick retries successful cleanup before clearing retention error");
#else
    Check(afterErrorRetry == 4 && errorCleared, @"BUG: next tick clears retention error without retrying cleanup");
#endif
    printf("RETENTION_GAP stricter_policy_count=%lu next_tick_count=%lu failed_prune_next_tick_count=%lu prune_error_cleared=%s\n",
        (unsigned long)afterSetting, (unsigned long)afterRetry, (unsigned long)afterErrorRetry, errorCleared ? "yes" : "no");
#ifdef EXPECT_FIXED
    puts("PASS: corrected production controller + filesystem store; library, defaults and queues are fixtures");
#else
    puts("PASS: bugs reproduced with baseline production controller + filesystem store; library, defaults and queues are fixtures");
#endif
    [controller stop]; [controller release]; [library release]; [worker release];
}}
