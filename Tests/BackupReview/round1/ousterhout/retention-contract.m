// Execute production NVBackupController against the existing deterministic fixtures.
#define main ExistingCoordinatorMain
#include "../../../BackupCoordinator/coordinator.m"
#undef main

static IMP originalPublication;
static BOOL failRetention;
static id PublicationWithRetentionFailure(id cls, SEL selector, NSData *data, NSDictionary *metadata,
                                          NSURL *directory, NSDictionary *retention, NSError **error) {
    id result = ((id (*)(id, SEL, id, id, id, id, NSError **))originalPublication)(cls, selector, data, metadata, directory, retention, error);
    if (!result || !failRetention) return result;
    NSMutableDictionary *failed = [[result mutableCopy] autorelease];
    [failed setObject:[NSError errorWithDomain:@"ReviewRetention" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Injected retention failure"}]
              forKey:@"retentionError"];
    return failed;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc == 2, @"temporary path supplied");
        testRoot = [[NSString stringWithUTF8String:argv[1]] copy];
        memoryDefaults = [MemoryDefaults new]; completionQueue = [ManualQueue new];
        publishedMetadata = [NSMutableArray new]; publishedDestinations = [NSMutableArray new]; publishedData = [NSMutableArray new];
        expectedArchiveData = [NSMutableDictionary new]; verificationURLs = [NSMutableArray new];
        ReplaceClassMethod([NSUserDefaults class], @selector(standardUserDefaults), (IMP)MemoryStandardDefaults);
        ReplaceClassMethod([NSDate class], @selector(date), (IMP)ClockDate);
        ReplaceClassMethod([NSDate class], @selector(dateWithTimeIntervalSinceNow:), (IMP)ClockRelativeDate);
        ReplaceClassMethod([NSOperationQueue class], @selector(mainQueue), (IMP)ManualMainQueue);
        SEL selector = @selector(publishArchiveData:metadata:inDirectory:retention:error:);
        originalPublication = method_getImplementation(class_getClassMethod([NVBackupStore class], selector));
        ReplaceClassMethod([NVBackupStore class], selector, (IMP)PublicationWithRetentionFailure);
        NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
        [[controller valueForKey:@"timer"] invalidate];
        ManualQueue *worker = [ManualQueue new]; [controller setValue:worker forKey:@"worker"];
        FixtureLibrary *library = [[FixtureLibrary alloc] initWithIdentifier:@"retention-contract"];
        Attach(controller, library);
        failRetention = YES;
        Tick(controller, 1000000); Complete(worker);
        Check([[controller statusText] containsString:@"Injected retention failure"], @"publication retention failure is reported");
        printf("publication count after retention failure: %lu\n", (unsigned long)publications);
        failRetention = NO;
        Tick(controller, 1000900); Complete(worker);
        Check(publications == 1 && [verificationURLs count] == 1, @"unchanged check does not duplicate publication");
#ifdef EXPECT_FIXED
        Check(maintenanceCalls == 1 && ![[controller statusText] containsString:@"Injected retention failure"], @"successful maintenance resolves retention error");
#else
        Check(maintenanceCalls == 0 && ![[controller statusText] containsString:@"Injected retention failure"], @"unchanged verification erases unresolved retention error");
#endif
        NSError *error = nil;
        Check([controller setSettings:@{@"recent":@3, @"daily":@0, @"weekly":@0} error:&error], @"lower retention accepted");
        Tick(controller, 1000900); Complete(worker);
        Check(publications == 1 && [verificationURLs count] == 2, @"lower retention does not duplicate the current snapshot");
#ifdef EXPECT_FIXED
        Check(maintenanceCalls == 2, @"lower retention reaches the store without another snapshot");
#else
        Check(maintenanceCalls == 0, @"lower retention only verifies archive and never reaches store policy");
#endif
        printf("publication count after retry and changed retention: %lu\n", (unsigned long)publications);
#ifdef EXPECT_FIXED
        printf("PASS: corrected retention contract; failed pruning retries and changed policy reaches the store without duplicate snapshots\n");
#else
        printf("PASS: baseline retention defect; unresolved error is erased, changed policy is not applied to unchanged library\n");
#endif
        [controller stop]; [controller release];
    }
    return 0;
}
