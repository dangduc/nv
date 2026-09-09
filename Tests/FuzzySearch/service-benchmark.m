#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <sys/resource.h>
#import "NVSearchService.h"

static double PrepareMS, TitleMS, ResultMS;
static NSData *UUID(NSUInteger index) {
    // Production UUIDs contain entropy in all bytes. Sequential big-endian
    // integer NSData keys cluster in Foundation's dictionary implementation.
    uint64_t mixed = index + UINT64_C(0x9e3779b97f4a7c15);
    mixed = (mixed ^ (mixed >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    mixed = (mixed ^ (mixed >> 27)) * UINT64_C(0x94d049bb133111eb);
    mixed ^= mixed >> 31;
    unsigned char bytes[16];
    for (NSUInteger i = 0; i < 8; ++i) { bytes[7-i] = (mixed >> (i*8)) & 255; bytes[15-i] = (index >> (i*8)) & 255; }
    return [NSData dataWithBytes:bytes length:16];
}
static BOOL Wait(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    if (!condition()) { fprintf(stderr, "benchmark timed out\n"); exit(1); } return YES;
}
static double Search(NVSearchService *service, id owner, NSString *query, const char *kind) {
    __block BOOL done = NO; __block NSUInteger rows = 0;
    PrepareMS = TitleMS = ResultMS = 0;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    [service requestForOwner:owner query:query completion:^(NVSearchResult *result, NSError *error) {
        if (error) { fprintf(stderr, "benchmark search error: %s\n", [[error description] UTF8String]); exit(1); }
        rows = [[result titleNoteUUIDs] count] + [[result fuzzyNoteUUIDs] count]; done = YES;
    }];
    double submit = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    Wait(^BOOL { return done; }, 60);
    double elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    printf("query,%s,%s,%.3f,%.3f,%lu\n", kind, [query UTF8String], submit, elapsed, (unsigned long)rows);
    printf("components,%s,prepare_ms,%.3f,title_ms,%.3f,result_ms,%.3f\n", [query UTF8String], PrepareMS, TitleMS, ResultMS);
    return elapsed;
}
static void Cancel(NVSearchService *service, id owner, NSString *query, const char *label, NSUInteger bytes, NSTimeInterval delay) {
    __block BOOL done = NO, delivered = NO; __block double releaseMS = 0;
    [service requestForOwner:owner query:query completion:^(NVSearchResult *r, NSError *e) { delivered = YES; }];
    [NSThread sleepForTimeInterval:delay];
    CFAbsoluteTime cancelled = CFAbsoluteTimeGetCurrent(); [service cancelRequestsForOwner:owner];
    // Test-only queue observation measures when the serial lane is available.
    Ivar ivar = class_getInstanceVariable([NVSearchService class], "_worker");
    dispatch_queue_t queue = *(dispatch_queue_t *)((char *)service + ivar_getOffset(ivar));
    dispatch_async(queue, ^{
        releaseMS = (CFAbsoluteTimeGetCurrent() - cancelled) * 1000;
        dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    });
    Wait(^BOOL { return done; }, 60);
    if (delivered) { fprintf(stderr, "cancelled benchmark completion published\n"); exit(1); }
    printf("cancel,%s,%lu,%.3f\n", label, (unsigned long)bytes, releaseMS);
}
int main(int argc, char **argv) { setvbuf(stdout, NULL, _IOLBF, 0); @autoreleasepool {
    printf("environment,arch,%s\n", sizeof(void*) == 8 ?
#if defined(__arm64__)
        "arm64"
#else
        "x86_64"
#endif
        : "other");
    printf("environment,os,%s\n", [[[NSProcessInfo processInfo] operatingSystemVersionString] UTF8String]);
    Method prepareMethod = class_getInstanceMethod([NVSearchNoteSnapshot class], @selector(preparedUTF8WithCancellation:status:));
    IMP prepareIMP = method_getImplementation(prepareMethod);
    method_setImplementation(prepareMethod, imp_implementationWithBlock(^id(id object, NVFZFCancel *cancel, NVFZFStatus *status) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        id result = ((id(*)(id, SEL, NVFZFCancel *, NVFZFStatus *))prepareIMP)(object, @selector(preparedUTF8WithCancellation:status:), cancel, status);
        PrepareMS += (CFAbsoluteTimeGetCurrent()-start)*1000; return result;
    }));
    Method titleMethod = class_getInstanceMethod([NVSearchQuery class], @selector(matchesTitle:));
    IMP titleIMP = method_getImplementation(titleMethod);
    method_setImplementation(titleMethod, imp_implementationWithBlock(^BOOL(id object, NSString *title) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        BOOL result = ((BOOL(*)(id, SEL, id))titleIMP)(object, @selector(matchesTitle:), title);
        TitleMS += (CFAbsoluteTimeGetCurrent()-start)*1000; return result;
    }));
    SEL resultSelector = NSSelectorFromString(@"initWithRequestID:revision:query:snapshots:titles:fuzzy:");
    Method resultMethod = class_getInstanceMethod([NVSearchResult class], resultSelector);
    IMP resultIMP = method_getImplementation(resultMethod);
    method_setImplementation(resultMethod, imp_implementationWithBlock(^id(id object, NSUInteger request, NSUInteger revision, id query, id snapshots, id titles, id fuzzy) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        id result = ((id(*)(id, SEL, NSUInteger, NSUInteger, id, id, id, id))resultIMP)(object, resultSelector, request, revision, query, snapshots, titles, fuzzy);
        ResultMS += (CFAbsoluteTimeGetCurrent()-start)*1000; return result;
    }));
    NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; NSObject *owner = [[[NSObject alloc] init] autorelease];
    if (argc == 1) {
    NSMutableArray *notes = [NSMutableArray arrayWithCapacity:10000]; NSUInteger bytes = 0;
    CFAbsoluteTime captureStart = CFAbsoluteTimeGetCurrent();
    for (NSUInteger i = 0; i < 10000; ++i) {
        NSString *title = [NSString stringWithFormat:@"Project %05lu %@", (unsigned long)i, i % 5 == 0 ? @"Road map" : @"Research"];
        NSString *tags = i % 3 == 0 ? @"planning meetings" : @"archive finance";
        NSString *seed = [NSString stringWithFormat:@"Record %lu: meeting notes, budget review, deployment status, source editing and weekly road map. %@ ", (unsigned long)i, i % 7 == 0 ? @"copper lantern" : @"ordinary material"];
        NSString *source = [seed stringByPaddingToLength:5243 withString:seed startingAtIndex:0];
        NVSearchNoteSnapshot *note = [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(i) title:title tags:tags source:source revision:1] autorelease];
        [notes addObject:note]; bytes += [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [title lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [tags lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 2;
    }
    CFAbsoluteTime syncStart = CFAbsoluteTimeGetCurrent(); [service synchronizeWithSnapshots:notes];
    printf("corpus,notes,%lu,bytes,%lu,capture_ms,%.3f,synchronize_ms,%.3f\n", (unsigned long)[notes count], (unsigned long)bytes, (syncStart-captureStart)*1000, (CFAbsoluteTimeGetCurrent()-syncStart)*1000);
    Search(service, owner, @"mtg", "cold");
    NSMutableArray *times = [NSMutableArray array];
    for (NSString *query in @[@"road", @"copper", @"budget", @"deploy", @"finance", @"planning", @"source", @"weekly", @"archive", @"lantern", @"mtg", @"review"]) [times addObject:@(Search(service, owner, query, "warm"))];
    [times sortUsingSelector:@selector(compare:)];
    printf("summary,warm_p50_ms,%.3f,warm_p95_ms,%.3f\n", [times[[times count]/2] doubleValue], [[times lastObject] doubleValue]);
    }
    for (NSNumber *size in (argc > 1 ? @[@(8*1024*1024)] : @[@(1024*1024)])) { @autoreleasepool {
        NSUInteger target = [size unsignedIntegerValue];
        NSString *source = [@"e\u0301" stringByPaddingToLength:(target/3)*2 withString:@"e\u0301" startingAtIndex:0];
        NVSearchNoteSnapshot *note = [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(20001) title:@"Long Unicode line" tags:@"" source:source revision:target] autorelease];
        [service synchronizeWithSnapshots:@[note]];
        Cancel(service, owner, @"éé", "cold_unicode", [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding], .002);
        Cancel(service, owner, @"éé", "cold_normalization_unicode", [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding], target > 1024*1024 ? .040 : .005);
        Search(service, owner, @"\"no literal match\"", "prepare_long_unicode");
        Cancel(service, owner, @"ééé", "warm_unicode", [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding], .002);
    } }
    struct rusage usage; getrusage(RUSAGE_SELF, &usage);
    printf("memory,peak_resident_bytes,%ld\n", usage.ru_maxrss);
    [service invalidate];
} return 0; }
