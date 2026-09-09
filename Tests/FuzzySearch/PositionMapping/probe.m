#import <Foundation/Foundation.h>
#import "NVSearchService.h"
#include <stdatomic.h>
#include <time.h>
#include "mapper.inc"

static NSUInteger checks;
static void Check(BOOL condition, const char *message) {
    ++checks;
    if (!condition) { fprintf(stderr, "FAIL %s\n", message); exit(1); }
}
static double Now(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6; }
static _Atomic uint64_t nativeNanoseconds;
void NVPositionMappingNativeTime(uint64_t nanoseconds) { atomic_store(&nativeNanoseconds, nanoseconds); }

/* Independent oracle: materialize the original range for every NFC scalar,
   then look up each requested scalar without the production scan cursor. */
static NSArray *ScalarRanges(NSString *source) {
    NSMutableArray *result = [NSMutableArray array];
    [source enumerateSubstringsInRange:NSMakeRange(0, [source length]) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
        NVFZFStatus status;
        NSData *normalized = NVSearchCanonicalUTF8(part, NULL, &status);
        Check(status == NVFZF_OK, "oracle normalization succeeds");
        const unsigned char *bytes = [normalized bytes];
        for (NSUInteger i = 0; i < [normalized length]; ++i)
            if ((bytes[i] & 0xc0) != 0x80) [result addObject:[NSValue valueWithRange:range]];
    }];
    return result;
}
static NSArray *ExpectedRanges(NSArray *scalarRanges, const uint32_t *offsets, NSUInteger count) {
    NSMutableArray *ranges = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; ++i) {
        if (offsets[i] >= [scalarRanges count]) continue;
        NSRange current = [[scalarRanges objectAtIndex:offsets[i]] rangeValue];
        NSRange previous = [ranges count] ? [[ranges lastObject] rangeValue] : NSMakeRange(NSNotFound, 0);
        if (previous.location != NSNotFound && NSMaxRange(previous) >= current.location) {
            [ranges removeLastObject]; current = NSUnionRange(previous, current);
        }
        [ranges addObject:[NSValue valueWithRange:current]];
    }
    return ranges;
}
static void Parity(NSString *source, NSUInteger stride) {
    NSArray *scalarRanges = ScalarRanges(source);
    NSMutableData *offsetData = [NSMutableData data];
    for (uint32_t i = 0; i < [scalarRanges count]; i += stride) [offsetData appendBytes:&i length:sizeof(i)];
    const uint32_t *offsets = [offsetData bytes];
    NSUInteger count = [offsetData length] / sizeof(*offsets);
    NSArray *expected = ExpectedRanges(scalarRanges, offsets, count);
    NSMutableArray *actual = [NSMutableArray array];
    NVSearchRangeCursor cursor = {0}; NVFZFStatus status; NSUInteger batches = 0;
    for (;;) { @autoreleasepool {
        ++batches;
        BOOL finished = NVSearchMapRangesBatch(source, offsets, count, NULL, &status, &cursor, actual);
        Check(status == NVFZF_OK, "batch normalization succeeds");
        if (finished) break;
    }}
    Check([actual isEqual:expected], "batch ranges equal independent scalar oracle");
    if ([scalarRanges count] > 9000) Check(batches > 1, "long mapping has multiple bounded batches");
    if (stride == 2 && [expected count] > 2048) Check([actual count] > 2048, "mapping preserves every disjoint position range");
}
static void Correctness(void) {
    unichar nul[] = {'a', 0, 'e', 0x0301, 'z'};
    NSArray *samples = @[@"", @"ascii text", @"e\u0301", @"\u1100\u1161\u11a8", @"\u212b\u0344", @"a\u0315\u0300", @"\r\n", @"🇺🇸🇨🇦🇯🇵", @"🧑🏽‍💻😀", @"\u0600a", [NSString stringWithCharacters:nul length:5]];
    for (NSString *sample in samples) for (NSUInteger stride = 1; stride < 4; ++stride) Parity(sample, stride);
    NSString *mixed = @"e\u0301🧑🏽‍💻\u1100\u1161\u11a8🇺🇸a\u0315\u0300x\r\n";
    for (NSUInteger prefix = 4094; prefix <= 4097; ++prefix) {
        NSMutableString *text = [NSMutableString stringWithString:[@"" stringByPaddingToLength:prefix withString:@"x" startingAtIndex:0]];
        for (NSUInteger i = 0; i < 1500; ++i) [text appendString:mixed];
        for (NSUInteger stride = 1; stride <= 7; stride += 2) Parity(text, stride);
    }
    NSMutableString *disjoint = [NSMutableString string];
    for (NSUInteger i = 0; i < 10000; ++i) [disjoint appendString:@"a "];
    Parity(disjoint, 2);
    uint32_t offset = 0; NVSearchRangeCursor cursor = {0}; NVFZFStatus status;
    NSMutableArray *ranges = [NSMutableArray array]; NVFZFCancel *cancel = nvfzf_cancel_create(); nvfzf_cancel_set(cancel);
    Check(NVSearchMapRangesBatch(@"x", &offset, 1, cancel, &status, &cursor, ranges), "cancelled mapping ends without a batch");
    Check(status == NVFZF_CANCELLED && ![ranges count] && cursor.utf16Index == 0, "cancelled mapping does not return partial success");
    nvfzf_cancel_free(cancel);
}

@interface GatedService : NVSearchService
- (void)gate:(dispatch_semaphore_t)gate entered:(dispatch_semaphore_t)entered;
- (void)afterQueuedWork:(void (^)(void))block;
@end
@implementation GatedService
- (void)gate:(dispatch_semaphore_t)gate entered:(dispatch_semaphore_t)entered {
    dispatch_async(_worker, ^{
        dispatch_semaphore_signal(entered);
        if (dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) abort();
    });
}
- (void)afterQueuedWork:(void (^)(void))block { dispatch_async(_worker, block); }
@end
static void Wait(BOOL (^finished)(void)) {
    double deadline = Now() + 20000;
    while (!finished() && Now() < deadline)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    Check(finished(), "bounded asynchronous completion");
}
static NVSearchResult *Search(NVSearchService *service, id owner, NSString *query, double *elapsed) {
    __block BOOL done = NO; __block NVSearchResult *output = nil; double start = Now();
    [service requestForOwner:owner query:query completion:^(NVSearchResult *result, NSError *error) {
        Check(!error && result != nil, "native query succeeds"); output = [result retain]; done = YES;
    }];
    Wait(^BOOL { return done; }); if (elapsed) *elapsed = Now() - start;
    return [output autorelease];
}
static void SharedWorker(BOOL unicode, NSUInteger utf16Length, BOOL cancelMapping) { @autoreleasepool {
    NSString *source = [[@"" stringByPaddingToLength:utf16Length withString:unicode ? @"e\u0301" : @"x" startingAtIndex:0] stringByAppendingString:@"needle"];
    unsigned char uuid[16] = {1};
    NVSearchNoteSnapshot *snapshot = [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:[NSData dataWithBytes:uuid length:16] title:@"fixture" tags:@"" source:source revision:1] autorelease];
    GatedService *service = [[[GatedService alloc] init] autorelease];
    [service synchronizeWithSnapshots:@[snapshot]];
    id owner = [[[NSObject alloc] init] autorelease], peer = [[[NSObject alloc] init] autorelease];
    NVSearchResult *result = Search(service, owner, @"needle", NULL);
    double baseline = 0; Search(service, peer, @"q", &baseline); [service cancelRequestsForOwner:peer];
    dispatch_semaphore_t gate = dispatch_semaphore_create(0), entered = dispatch_semaphore_create(0);
    [service gate:gate entered:entered];
    Check(!dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), "worker gate entered");
    __block BOOL positionsDone = NO, peerDone = NO, cancelled = NO, drained = NO;
    __block NSUInteger publicationIndex = 0, positionIndex = 0, peerIndex = 0;
    __block double positionsMS = 0, peerMS = 0; double start = Now();
    [service requestPositionsForNoteUUID:[snapshot noteUUID] requestID:[result requestID] owner:owner completion:^(NVSearchPositions *positions, NSError *error) {
        Check(!error && positions != nil, "resumed native positions succeed");
        Check([[positions sourceRanges] isEqual:@[[NSValue valueWithRange:NSMakeRange([source length] - 6, 6)]]], "late native match has exact original UTF-16 range");
        positionIndex = ++publicationIndex; positionsMS = Now() - start; positionsDone = YES;
    }];
    if (cancelMapping) [service afterQueuedWork:^{
        dispatch_sync(dispatch_get_main_queue(), ^{ [service cancelPositionRequestsForOwner:owner]; cancelled = YES; });
    }];
    [service requestForOwner:peer query:@"q" completion:^(NVSearchResult *peerResult, NSError *error) {
        Check(!error && peerResult != nil && ![[peerResult fuzzyNoteUUIDs] count], "peer query completes with every expected result");
        peerIndex = ++publicationIndex; peerMS = Now() - start; peerDone = YES;
    }];
    dispatch_semaphore_signal(gate);
    Wait(^BOOL { return peerDone && (cancelMapping ? cancelled : positionsDone); });
    if (cancelMapping) {
        [service afterQueuedWork:^{ dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; }); }];
        Wait(^BOOL { return drained; });
        Check(!positionsDone, "between-batch cancellation suppresses position callback");
    } else Check(peerIndex < positionIndex, "queued peer query publishes before long mapping finishes");
    printf("lane,%s,%lu,%lu,%s,baseline_ms=%.3f,peer_ms=%.3f,positions_ms=%.3f,native_positions_ms=%.3f\n", unicode ? "decomposed" : "ascii", [source length], [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding], cancelMapping ? "cancel" : "complete", baseline, peerMS, positionsMS, (double)atomic_load(&nativeNanoseconds) / 1e6);
    [service cancelRequestsForOwner:owner]; [service cancelRequestsForOwner:peer]; [service invalidate];
    dispatch_release(gate); dispatch_release(entered);
}}
int main(void) { @autoreleasepool {
    double start = Now(); Correctness();
    printf("correctness_ms=%.3f\n", Now() - start);
    SharedWorker(NO, 32768, NO); SharedWorker(YES, 32768, NO);
    SharedWorker(NO, 4 * 1024 * 1024, NO); SharedWorker(YES, 4 * 1024 * 1024, NO);
    SharedWorker(NO, 32768, YES); SharedWorker(YES, 32768, YES);
    printf("PASS %lu checks\n", checks);
} return 0; }
