#include <math.h>
int main(int argc, const char *argv[]) { @autoreleasepool {
    Check(argc == 2, @"disposable root supplied");
    testRoot = [[NSString stringWithUTF8String:argv[1]] copy];
    memoryDefaults = [MemoryDefaults new]; completionQueue = [ManualQueue new];
    ReplaceClassMethod([NSUserDefaults class], @selector(standardUserDefaults), (IMP)MemoryStandardDefaults);
    ReplaceClassMethod([NSDate class], @selector(date), (IMP)ClockDate);
    ReplaceClassMethod([NSDate class], @selector(dateWithTimeIntervalSinceNow:), (IMP)ClockRelativeDate);
    ReplaceClassMethod([NSOperationQueue class], @selector(mainQueue), (IMP)ManualMainQueue);
    NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
    [[controller valueForKey:@"timer"] invalidate];
    FixtureLibrary *library = [[FixtureLibrary alloc] initWithIdentifier:[[NSUUID UUID] UUIDString]];
    Attach(controller, library);
    // Parse these at runtime so the compiler cannot fold the NaN fixture itself.
    NSArray *values = @[@(strtod("nan", NULL)), @(strtod("inf", NULL)), @(strtod("-inf", NULL)), @"900", [NSNull null], @900.5];
    NSArray *names = @[@"nan", @"positive_inf", @"negative_inf", @"string", @"null", @"fraction"];
    NSUInteger accepted = 0, cases = 0;
    for (NSString *key in @[@"interval", @"recent", @"daily", @"weekly", @"maxBytes"]) {
        for (NSUInteger index = 0; index < [values count]; index++) {
            NSError *error = nil;
            BOOL result = [controller setSettings:@{key:[values objectAtIndex:index]} error:&error];
            cases++; accepted += result;
            if (result) printf("SETTINGS_ACCEPTED key=%s value=%s\n", [key UTF8String], [[names objectAtIndex:index] UTF8String]);
        }
    }
    NSError *error = nil;
    Check([controller setSettings:@{@"interval":@60, @"recent":@3, @"daily":@0, @"weekly":@0, @"maxBytes":@1048576} error:&error], @"valid lower bounds accepted");
    printf("SETTINGS_NUMERIC cases=%lu invalid_accepted=%lu\n", (unsigned long)cases, (unsigned long)accepted);
    [controller stop]; [controller release]; [library release];
    return accepted ? 2 : 0;
}}
