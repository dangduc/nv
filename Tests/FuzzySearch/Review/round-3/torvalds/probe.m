#import <Foundation/Foundation.h>
#include <stdatomic.h>
#include "reviewed-service.m"

static _Atomic NSUInteger checks;
#define CHECK(...) do { atomic_fetch_add(&checks, 1); if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
static NSValue *Range(NSUInteger location, NSUInteger length) { return [NSValue valueWithRange:NSMakeRange(location, length)]; }
static NSString *Repeat(NSString *text, NSUInteger length) { return [@"" stringByPaddingToLength:length withString:text startingAtIndex:0]; }
static void Wait(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(done());
}

/* Explicit NFC scalar counts and original UTF-16 lengths. No normalization or
   composed-sequence enumeration builds these expectations. */
static void MappingBoundaries(void) {
    NSArray *atoms = @[@"e\u0301", @"a\u0315\u0300", @"\u1100\u1161\u11a8", @"🇯🇵", @"👩🏽‍💻", @"\r\n"];
    const NSUInteger units[] = {2, 3, 3, 4, 7, 2}, scalars[] = {1, 2, 1, 2, 4, 2};
    for (NSUInteger prefix = 4095; prefix <= 4097; prefix++) {
        NSMutableString *source = [NSMutableString stringWithString:Repeat(@"x", prefix)];
        NSMutableData *offsets = [NSMutableData data];
        for (uint32_t i = 0; i < prefix; i++) [offsets appendBytes:&i length:sizeof(i)];
        NSMutableDictionary *boundaries = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i <= prefix; i++) [boundaries setObject:@(i) forKey:@(i)];
        NSUInteger scalar = prefix, utf16 = prefix;
        for (NSUInteger atom = 0; atom < [atoms count]; atom++) {
            CHECK([[atoms objectAtIndex:atom] length] == units[atom]);
            [source appendString:[atoms objectAtIndex:atom]];
            for (NSUInteger i = 0; i < scalars[atom]; i++) { uint32_t offset = (uint32_t)(scalar + i); [offsets appendBytes:&offset length:sizeof(offset)]; }
            scalar += scalars[atom]; utf16 += units[atom]; [boundaries setObject:@(scalar) forKey:@(utf16)];
        }
        NSMutableArray *ranges = [NSMutableArray array]; NVSearchRangeCursor cursor = {0}; NVFZFStatus status;
        NSUInteger batches = 0;
        for (;;) {
            NSUInteger previous = cursor.utf16Index;
            BOOL done = NVSearchMapRangesBatch(source, [offsets bytes], [offsets length] / sizeof(uint32_t), NULL, &status, &cursor, ranges);
            CHECK(status == NVFZF_OK && cursor.utf16Index > previous);
            CHECK([boundaries objectForKey:@(cursor.utf16Index)] != nil);
            CHECK([[boundaries objectForKey:@(cursor.utf16Index)] unsignedIntegerValue] == cursor.scalarIndex);
            CHECK(cursor.positionIndex == cursor.scalarIndex);
            CHECK([ranges isEqual:@[Range(0, cursor.utf16Index)]]);
            batches++; if (done) break;
        }
        CHECK(batches >= 2 && [ranges isEqual:@[Range(0, utf16)]]);
    }
    NSString *source = [Repeat(@"x", 8192) stringByAppendingString:@"e\u0301"];
    uint32_t selected[] = {0, 8192};
    NVSearchRangeCursor cursor = {0}; NVFZFStatus status; NSMutableArray *ranges = [NSMutableArray array];
    NVFZFCancel *cancel = nvfzf_cancel_create(); CHECK(cancel != NULL);
    CHECK(!NVSearchMapRangesBatch(source, selected, 2, cancel, &status, &cursor, ranges));
    CHECK(status == NVFZF_OK && [ranges isEqual:@[Range(0, 1)]]);
    NVSearchRangeCursor saved = cursor;
    nvfzf_cancel_set(cancel);
    CHECK(NVSearchMapRangesBatch(source, selected, 2, cancel, &status, &cursor, ranges));
    CHECK(status == NVFZF_CANCELLED && !memcmp(&saved, &cursor, sizeof(cursor)));
    nvfzf_cancel_free(cancel);

    unichar invalid = 0xd800;
    source = [Repeat(@"x", 8192) stringByAppendingString:[NSString stringWithCharacters:&invalid length:1]];
    cursor = (NVSearchRangeCursor){0}; [ranges removeAllObjects];
    while (!NVSearchMapRangesBatch(source, selected, 2, NULL, &status, &cursor, ranges)) CHECK(status == NVFZF_OK);
    CHECK(status == NVFZF_INVALID_INPUT && [ranges count] == 0);
    puts("PASS: three explicit composed-boundary resumes coalesce across batches; cancellation stops its cursor and normalization error discards partial ranges.");
}

static void NativeOwnership(void) {
    NVFZFEngine *engine = nvfzf_engine_create(); CHECK(engine != NULL);
    NSData *bytes = [[Repeat(@"x", 8192) stringByAppendingString:@"needle"] dataUsingEncoding:NSUTF8StringEncoding];
    NVFZFTerm term = {"needle", 6, NVFZF_TERM_EXACT}; NVFZFPositions first = {0};
    CHECK(nvfzf_positions_terms(engine, (NVFZFCandidate){[bytes bytes], [bytes length]}, &term, 1, NULL, &first) == NVFZF_OK);
    CHECK(first.matched && first.count == 6);
    uint32_t expected[] = {8192, 8193, 8194, 8195, 8196, 8197};
    CHECK(!memcmp(first.offsets, expected, sizeof(expected)));
    for (NSUInteger iteration = 0; iteration < 3; iteration++) {
        NVFZFCandidate candidates[] = {{"n e e d l e", 11}, {"needle", 6}, {"none", 4}};
        NVFZFSearchResult result = {0}; NVFZFPositions next = {0};
        NVFZFTerm fuzzy = {"needle", 6, NVFZF_TERM_FUZZY};
        CHECK(nvfzf_search_terms(engine, candidates, 3, &fuzzy, 1, NULL, &result) == NVFZF_OK && result.count == 2);
        CHECK(nvfzf_positions_terms(engine, candidates[0], &fuzzy, 1, NULL, &next) == NVFZF_OK && next.count == 6);
        nvfzf_positions_free(&next); nvfzf_search_result_free(&result);
        CHECK(first.count == 6 && !memcmp(first.offsets, expected, sizeof(expected)));
    }
    nvfzf_engine_free(engine);
    CHECK(!memcmp(first.offsets, expected, sizeof(expected)));
    nvfzf_positions_free(&first); CHECK(!first.offsets && !first.count && !first.matched);
    puts("PASS: owned native offsets survive interleaved search/position calls and engine disposal.");
}

@interface ReviewService : NVSearchService
- (void)queue:(void (^)(void))block;
@end
@implementation ReviewService
- (void)queue:(void (^)(void))block { dispatch_async(_worker, block); }
@end
static NVSearchNoteSnapshot *Note(unsigned char number, NSString *title, NSString *source) {
    unsigned char uuid[16] = {0}; uuid[15] = number;
    return [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:[NSData dataWithBytes:uuid length:16] title:title tags:@"" source:source revision:1] autorelease];
}
static NVSearchResult *Search(ReviewService *service, id owner, NSString *query) {
    __block NVSearchResult *result = nil; __block BOOL done = NO;
    [service requestForOwner:owner query:query completion:^(NVSearchResult *value, NSError *error) {
        CHECK([NSThread isMainThread] && value && !error); result = [value retain]; done = YES;
    }];
    Wait(^BOOL { return done; }); return [result autorelease];
}
static void ServiceInterleaving(void) {
    ReviewService *service = [[[ReviewService alloc] init] autorelease];
    id a = [[[NSObject alloc] init] autorelease], b = [[[NSObject alloc] init] autorelease], peer = [[[NSObject alloc] init] autorelease];
    NVSearchNoteSnapshot *first = Note(1, @"body", [Repeat(@"e\u0301", 24576) stringByAppendingString:@"tango"]);
    NVSearchNoteSnapshot *second = Note(2, @"body", [Repeat(@"x", 16384) stringByAppendingString:@"delta"]);
    NVSearchNoteSnapshot *title = Note(3, @"tango", @"");
    [service synchronizeWithSnapshots:@[title, second, first]];
    NVSearchResult *ar = Search(service, a, @"tango"), *br = Search(service, b, @"delta");
    CHECK([[ar titleNoteUUIDs] isEqual:@[[title noteUUID]]]);
    CHECK([[ar fuzzyNoteUUIDs] isEqual:@[[title noteUUID], [first noteUUID]]]);
    CHECK([[br fuzzyNoteUUIDs] isEqual:@[[second noteUUID]]]);
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    [service queue:^{ CHECK(dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0); }];
    __block NSUInteger callbacks = 0; __block NVSearchPositions *retained = nil;
    [service requestPositionsForNoteUUID:[first noteUUID] requestID:[ar requestID] owner:a completion:^(NVSearchPositions *positions, NSError *error) {
        CHECK([NSThread isMainThread] && !error && positions);
        CHECK([[positions sourceRanges] isEqual:@[Range(24576, 5)]] && ![[positions titleRanges] count] && ![[positions tagsRanges] count]);
        retained = [positions retain]; callbacks++;
    }];
    [service requestPositionsForNoteUUID:[second noteUUID] requestID:[br requestID] owner:b completion:^(NVSearchPositions *positions, NSError *error) {
        CHECK([NSThread isMainThread] && !error && [[positions sourceRanges] isEqual:@[Range(16384, 5)]]); callbacks++;
    }];
    [service requestForOwner:peer query:@"tango" completion:^(NVSearchResult *result, NSError *error) {
        CHECK(!error && [[result titleNoteUUIDs] isEqual:[ar titleNoteUUIDs]] && [[result fuzzyNoteUUIDs] isEqual:[ar fuzzyNoteUUIDs]]); callbacks++;
    }];
    dispatch_semaphore_signal(gate); Wait(^BOOL { return callbacks == 3; });

    __block BOOL cancelled = NO, drained = NO; __block NSUInteger obsolete = 0, errors = 0;
    [service queue:^{ CHECK(dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0); }];
    [service requestPositionsForNoteUUID:[first noteUUID] requestID:[ar requestID] owner:a completion:^(NVSearchPositions *positions, NSError *error) { obsolete++; }];
    [service queue:^{ dispatch_sync(dispatch_get_main_queue(), ^{ [service cancelPositionRequestsForOwner:a]; cancelled = YES; }); }];
    unichar invalidQuery[] = {'x', 0, 'y'};
    [service requestForOwner:peer query:[NSString stringWithCharacters:invalidQuery length:3] completion:^(NVSearchResult *result, NSError *error) {
        CHECK([NSThread isMainThread] && result == nil && [error code] == NVFZF_INVALID_INPUT); errors++;
    }];
    dispatch_semaphore_signal(gate); Wait(^BOOL { return cancelled && errors == 1; });
    [service queue:^{ dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; }); }];
    Wait(^BOOL { return drained; }); CHECK(obsolete == 0);
    [service invalidate];
    CHECK([[retained sourceRanges] isEqual:@[Range(24576, 5)]] && [[retained snapshot] source] != nil);
    [retained release]; dispatch_release(gate);
    puts("PASS: overlapping service positions retain exact source ranges; title overlap and native order persist; between-batch cancellation publishes nothing and invalid query publishes only an error.");
}

int main(void) { @autoreleasepool {
    MappingBoundaries(); NativeOwnership(); ServiceInterleaving();
    printf("PASS: %lu focused checks\n", (unsigned long)atomic_load(&checks));
} return 0; }
