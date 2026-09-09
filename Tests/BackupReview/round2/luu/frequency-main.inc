#include <sys/resource.h>
extern unsigned long long ReviewArchiveReadBytes;
static unsigned long long MeasureTick(NVBackupController *controller, ManualQueue *worker, NSTimeInterval timestamp) {
    ReviewArchiveReadBytes = 0;
    Tick(controller, timestamp); Complete(worker);
    return ReviewArchiveReadBytes;
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    Check(argc == 2, @"disposable root supplied");
    testRoot = [[NSString stringWithUTF8String:argv[1]] copy];
    memoryDefaults = [MemoryDefaults new]; completionQueue = [ManualQueue new];
    ReplaceClassMethod([NSUserDefaults class], @selector(standardUserDefaults), (IMP)MemoryStandardDefaults);
    ReplaceClassMethod([NSDate class], @selector(date), (IMP)ClockDate);
    ReplaceClassMethod([NSDate class], @selector(dateWithTimeIntervalSinceNow:), (IMP)ClockRelativeDate);
    ReplaceClassMethod([NSOperationQueue class], @selector(mainQueue), (IMP)ManualMainQueue);
    ReviewArchiveData = [[NSMutableData alloc] initWithLength:1024 * 1024];
    memset([(NSMutableData *)ReviewArchiveData mutableBytes], 0x51, [ReviewArchiveData length]);
    const unsigned long long MiB = 1024 * 1024;
    NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
    [[controller valueForKey:@"timer"] invalidate];
    ManualQueue *worker = [ManualQueue new]; [controller setValue:worker forKey:@"worker"];
    FixtureLibrary *library = [[FixtureLibrary alloc] initWithIdentifier:[[NSUUID UUID] UUIDString]];
    Attach(controller, library);
    NSError *error = nil;
    Check([controller setSettings:@{@"recent":@64, @"daily":@0, @"weekly":@0} error:&error], @"initial retention accepted");
    MeasureTick(controller, worker, clockTime);
    NSURL *destination = [controller destinationURL];
    NSString *lastSnapshot = [[[controller settings] objectForKey:@"lastSnapshot"] copy];
    NSDate *lastDate = [[[controller settings] objectForKey:@"lastDate"] retain];
    NSURL *firstURL = [NSURL fileURLWithPath:lastSnapshot];
    for (NSUInteger index = 1; index < 32; index++) { @autoreleasepool {
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSURL *copy = [destination URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"nvbackup"] isDirectory:YES];
        Check([[NSFileManager defaultManager] copyItemAtURL:firstURL toURL:copy error:&error], @"copy bounded archive fixture");
        NSMutableDictionary *manifest = [NSMutableDictionary dictionaryWithContentsOfURL:[copy URLByAppendingPathComponent:@"manifest.plist"]];
        [manifest setObject:identifier forKey:@"snapshotIdentifier"];
        Check([manifest writeToURL:[copy URLByAppendingPathComponent:@"manifest.plist"] atomically:YES], @"match copied manifest identity");
    }}
    Check([[NVBackupStore snapshotsInDirectory:destination error:&error] count] == 32, @"all packages pass production checksum checks");
    Check([controller setSettings:@{@"recent":@63} error:&error], @"retention change accepted");
    unsigned long long policyReads = MeasureTick(controller, worker, clockTime);
    Check(policyReads == 65 * MiB, @"policy maintenance reads one current archive and two full histories");
    unsigned long long routineReads = 0;
    for (NSUInteger index=0; index<4; index++) {
        unsigned long long reads = MeasureTick(controller, worker, clockTime + 900);
        Check(reads == MiB, @"ordinary unchanged check reads only the current archive");
        routineReads += reads;
    }
    Check([controller setSettings:@{@"recent":@63, @"daily":@0, @"weekly":@0} error:&error], @"unchanged settings accepted");
    Check(MeasureTick(controller, worker, clockTime) == MiB, @"unchanged retention submission does not scan history");
    Check([controller setSettings:@{@"interval":@300} error:&error], @"interval change accepted");
    Check(MeasureTick(controller, worker, clockTime) == MiB, @"interval change does not scan history");
    Check([controller setSettings:@{@"interval":@900} error:&error], @"default interval restored");
    Check(MeasureTick(controller, worker, clockTime) == MiB, @"interval reset does not scan history");
    unsigned long long dailyReads = MeasureTick(controller, worker, (floor(clockTime / 86400.0) + 1) * 86400.0 + 123);
    Check(dailyReads == 65 * MiB, @"new UTC day runs maintenance once");
    Check(MeasureTick(controller, worker, clockTime + 900) == MiB, @"same-day check after maintenance reads only current archive");
    Check([controller setSettings:@{@"recent":@62} error:&error], @"second retention change accepted");
    NVBackupStoreFailurePoint = @"prune";
    unsigned long long failedReads = MeasureTick(controller, worker, clockTime);
    Check(failedReads == 33 * MiB, @"failure before pruning still reads current archive and status history");
    NSTimeInterval failureTime = clockTime;
    ReviewArchiveReadBytes = 0;
    Tick(controller, failureTime + 299);
    Check([worker pendingCount] == 0 && ReviewArchiveReadBytes == 0, @"default interval does not retry before 300 seconds");
    Tick(controller, failureTime + 300);
    Check([[controller statusText] containsString:@"Injected backup failure: prune"], @"error remains visible while retry is pending");
    Complete(worker);
    Check(ReviewArchiveReadBytes == 33 * MiB, @"repeated failure has the same bounded read count");
    NVBackupStoreFailurePoint = nil;
    Check(MeasureTick(controller, worker, clockTime + 300) == 65 * MiB, @"successful retry runs cleanup and status scans");
    Check(![[controller statusText] containsString:@"Injected backup failure: prune"], @"successful cleanup clears error");
    Check([[[controller settings] objectForKey:@"lastSnapshot"] isEqual:lastSnapshot] && [[[controller settings] objectForKey:@"lastDate"] isEqual:lastDate], @"all unchanged maintenance preserves snapshot identity and date");
    Check([[NVBackupStore snapshotsInDirectory:destination error:&error] count] == 32, @"all unchanged maintenance creates no duplicate packages");

    Check([controller setSettings:@{@"interval":@60, @"recent":@61} error:&error], @"minimum interval accepted");
    NVBackupStoreFailurePoint = @"prune";
    Check(MeasureTick(controller, worker, clockTime) == 33 * MiB, @"minimum-interval failure reports same cost");
    failureTime = clockTime;
    Tick(controller, failureTime + 30);
    Check([worker pendingCount] == 0, @"first timer tick does not immediately retry");
    NSTimeInterval retryDeadline = [[controller valueForKey:@"nextAttempt"] timeIntervalSinceReferenceDate];
    Check(retryDeadline == failureTime + 300, @"minimum interval preserves the full five-minute deadline");
    for (NSNumber *elapsed in @[@60, @90, @299]) {
        Tick(controller, failureTime + [elapsed doubleValue]);
        Check([worker pendingCount] == 0, @"short-interval maintenance does not retry before five minutes");
    }
    Tick(controller, failureTime + 300);
    Check([worker pendingCount] == 1, @"unchanged cleanup retries after five minutes");
    Complete(worker);
    Check([[controller statusText] containsString:@"Injected backup failure: prune"], @"failed retry keeps its error");
    NSTimeInterval movedBack = clockTime - 86400;
    Tick(controller, movedBack);
    Check([[controller valueForKey:@"nextAttempt"] timeIntervalSinceReferenceDate] == movedBack + 300,
        @"actual backward clock movement bounds the maintenance retry to five minutes");
    Tick(controller, movedBack + 299);
    Check([worker pendingCount] == 0, @"backward movement preserves the full retry delay");
    NVBackupStoreFailurePoint = nil;
    MeasureTick(controller, worker, movedBack + 300);
    Check(![[controller statusText] containsString:@"Injected backup failure: prune"], @"maintenance recovers at the corrected retry deadline");
    printf("RETENTION_READS packages=32 archive_mib=1 policy_mib=%llu ordinary_checks=4 ordinary_total_mib=%llu daily_mib=%llu failed_prune_mib=%llu\n", policyReads/MiB, routineReads/MiB, dailyReads/MiB, failedReads/MiB);
    printf("RETRY_BOUND interval_900_retry_seconds=300 interval_60_retry_seconds=%.0f expected_failure_retry_seconds=300\n", retryDeadline-failureTime);
    puts("PASS: production controller/store schedule and read assertions; short intervals preserve failure delays and actual backward-clock correction");
    [controller stop]; [controller release]; [library release]; [worker release];
    [lastSnapshot release]; [lastDate release]; [ReviewArchiveData release];
}}
