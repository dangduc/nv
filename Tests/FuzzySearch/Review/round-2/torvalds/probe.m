/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <Foundation/Foundation.h>
#import "NVSearchService.h"

static NSUInteger checks;
#define CHECK(...) do { checks++; if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
static BOOL Spin(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!done() && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    return done();
}
static NVSearchQuery *Query(NSString *string) { return [[[NVSearchQuery alloc] initWithString:string] autorelease]; }
static NSValue *Range(NSUInteger location, NSUInteger length) { return [NSValue valueWithRange:NSMakeRange(location, length)]; }
static void GoodRanges(NSArray *ranges, NSString *source) {
    NSUInteger previous = 0;
    for (NSValue *value in ranges) {
        NSRange r = [value rangeValue];
        CHECK(r.length && r.location >= previous && r.location <= [source length] && r.length <= [source length] - r.location);
        CHECK(NSEqualRanges(r, [source rangeOfComposedCharacterSequencesForRange:r]));
        previous = NSMaxRange(r);
    }
}
static void LiteralBoundaries(void) {
    NSString *source = [@"a " stringByPaddingToLength:4200 withString:@"a " startingAtIndex:0];
    NSUInteger caps[] = {0, 1, 2047, 2048, 2049, NSUIntegerMax};
    for (NSUInteger i = 0; i < sizeof caps / sizeof caps[0]; i++) {
        NSUInteger cap = caps[i], expected = MIN(cap, 2100);
        NSArray *ranges = [Query(@"a") literalRangesInString:source maximumCount:cap cancellation:nil];
        CHECK([ranges count] == expected);
        for (NSUInteger j = 0; j < expected; j++) CHECK([[ranges objectAtIndex:j] isEqual:Range(j * 2, 1)]);
        GoodRanges(ranges, source);
    }
    NSString *adjacent = [@"a" stringByPaddingToLength:2100 withString:@"a" startingAtIndex:0];
    CHECK([[Query(@"a") literalRangesInString:adjacent maximumCount:2048 cancellation:nil] isEqual:@[Range(0, 2048)]]);
    CHECK([[Query(@"a a z") literalRangesInString:@"a z a" maximumCount:3 cancellation:nil] isEqual:@[Range(0, 1), Range(4, 1)]]);
    CHECK([[Query(@"\"a:b\" !x") literalRangesInString:@"a:b !x a b" maximumCount:2 cancellation:nil] isEqual:@[Range(0, 3), Range(4, 2)]]);
    CHECK([[Query(@"\"a\nb\"") literalRangesInString:@"x a\nb y" maximumCount:1 cancellation:nil] isEqual:@[Range(2, 3)]]);
    CHECK([[Query(@"é") literalRangesInString:@"x e\u0301 y" maximumCount:1 cancellation:nil] isEqual:@[Range(2, 2)]]);
    CHECK([[Query(@"🏽") literalRangesInString:@"x 👩🏽‍💻 y" maximumCount:1 cancellation:nil] isEqual:@[Range(2, 7)]]);
    CHECK([[Query(@" :\t\r\n\"\"") literalRangesInString:source maximumCount:1 cancellation:nil] count] == 0);
    __block NSUInteger calls = 0;
    CHECK([Query(@"a") literalRangesInString:source maximumCount:2048 cancellation:^BOOL { return ++calls == 3; }] == nil);
    CHECK(calls == 3);
    CHECK([Query(@"a") literalRangesInString:source maximumCount:0 cancellation:^BOOL { return YES; }] == nil);
    CHECK([Query(@"") literalRangesInString:@"" maximumCount:0 cancellation:^BOOL { return YES; }] == nil);
    puts("PASS: occurrence caps 0/1/2047/2048/2049/unlimited, merged ranges, parsed-term order, literals, graphemes, and cancellation.");
}
static void ScalarMapping(void) {
    unichar nul = 0;
    NSArray *atoms = @[@"a", @"é", @"e\u0301", @"a\u0315\u0300", @"가", @"가", @"🇯🇵", @"👩🏽‍💻", @"\r\n", [NSString stringWithCharacters:&nul length:1]];
    const NSUInteger counts[] = {1, 1, 1, 2, 1, 1, 2, 4, 2, 1};
    NSMutableString *source = [NSMutableString string];
    NSMutableArray *origins = [NSMutableArray array];
    for (NSString *atom in atoms) {
        [origins addObject:Range([source length], [atom length])];
        [source appendString:atom]; [source appendString:@"/"];
    }
    for (NSUInteger mask = 0; mask < 1024; mask++) {
        uint32_t offsets[32]; NSUInteger count = 0, scalar = 0;
        NSMutableArray *expected = [NSMutableArray array];
        for (NSUInteger atom = 0; atom < [atoms count]; atom++) {
            if (mask & (1u << atom)) {
                for (NSUInteger j = 0; j < counts[atom]; j++) offsets[count++] = (uint32_t)(scalar + j);
                [expected addObject:origins[atom]];
            }
            scalar += counts[atom] + 1;
        }
        NSArray *actual = NVSearchOriginalRanges(source, offsets, count);
        CHECK([actual isEqual:expected]); GoodRanges(actual, source);
    }
    uint32_t all[64]; NSUInteger scalarCount = [atoms count];
    for (NSUInteger i = 0; i < [atoms count]; i++) scalarCount += counts[i];
    for (NSUInteger i = 0; i < scalarCount; i++) all[i] = (uint32_t)i;
    CHECK([NVSearchOriginalRanges(source, all, scalarCount) isEqual:@[Range(0, [source length])]]);
    puts("PASS: all 1,024 scalar subsets map to independently specified UTF-16 graphemes; adjacent fields merge only across selected separators.");
}
static NSArray *Literal(NVSearchService *service, id owner, NSString *source, NSString *matching, NSString *query) {
    __block BOOL done = NO; __block NSArray *result = nil;
    [service requestLiteralRangesInSource:source matchingSource:matching query:query owner:owner completion:^(NSArray *ranges, NSString *copy, NSError *error) {
        CHECK([NSThread isMainThread]); CHECK(!error); CHECK([copy isEqual:source]); result = [ranges copy]; done = YES;
    }];
    CHECK(!done); CHECK(Spin(^BOOL { return done; })); return [result autorelease];
}
static void AsyncBoundaries(NVSearchService *service, id owner, id peer) {
    NSArray *mismatches = @[@[@"é", @"e\u0301"], @[@"a\u0301\u0327", @"a\u0327\u0301"], @[@"a\r\nb", @"a\nb"], @[@"a x", @"a y"], @[@"", @"a"]];
    for (NSArray *pair in mismatches) CHECK([Literal(service, owner, pair[0], pair[1], @"a é") count] == 0);
    CHECK([Literal(service, owner, @"x e\u0301 y", @"x e\u0301 y", @"é") isEqual:@[Range(2, 2)]]);
    NSMutableString *source = [NSMutableString stringWithString:@"a x"], *displayed = [NSMutableString stringWithString:@"a x"], *query = [NSMutableString stringWithString:@"a"];
    __block BOOL copied = NO;
    [service requestLiteralRangesInSource:source matchingSource:displayed query:query owner:owner completion:^(NSArray *ranges, NSString *text, NSError *error) {
        CHECK(!error && [text isEqual:@"a x"] && [ranges isEqual:@[Range(0, 1)]]); copied = YES;
    }];
    [source setString:@"changed"]; [displayed setString:@"also changed"]; [query setString:@"absent"];
    CHECK(Spin(^BOOL { return copied; }));
    NSMutableArray *ranges = [NSMutableArray array];
    for (NSUInteger i = 0; i < 2050; i++) [ranges addObject:Range(i * 2, 1)];
    NSString *longSource = [@"a " stringByPaddingToLength:4100 withString:@"a " startingAtIndex:0];
    __block BOOL validated = NO;
    [service validateSourceRanges:ranges source:longSource matchingSource:longSource owner:owner completion:^(NSArray *found, NSString *text, NSError *error) {
        CHECK(!error && [found count] == 2048 && [[found lastObject] isEqual:Range(4094, 1)]); GoodRanges(found, text); validated = YES;
    }];
    [ranges removeAllObjects]; CHECK(Spin(^BOOL { return validated; }));
    __block NSUInteger obsolete = 0, latest = 0, peers = 0;
    [service requestLiteralRangesInSource:@"a" query:@"a" owner:owner completion:^(NSArray *r, NSString *s, NSError *e) { obsolete++; }];
    [service requestLiteralRangesInSource:@"a" query:@"a" owner:peer completion:^(NSArray *r, NSString *s, NSError *e) { CHECK([r isEqual:@[Range(0, 1)]]); peers++; }];
    [service requestLiteralRangesInSource:@"b" query:@"b" owner:owner completion:^(NSArray *r, NSString *s, NSError *e) { CHECK([r isEqual:@[Range(0, 1)]]); latest++; }];
    CHECK(Spin(^BOOL { return latest == 1 && peers == 1; }) && !obsolete);
    [service requestLiteralRangesInSource:@"a" query:@"a" owner:owner completion:^(NSArray *r, NSString *s, NSError *e) { obsolete++; }];
    [service invalidate];
    CHECK([Literal(service, peer, @"b", @"b", @"b") isEqual:@[Range(0, 1)]] && !obsolete);
    puts("PASS: deferred publication, exact source compatibility, copied mutable inputs, native presentation cap, owner replacement, peer isolation, and invalidation.");
}
static NSData *UUID(NSUInteger number) {
    unsigned char bytes[16] = {0x98, 0xf4, 0xb1, 0x6d};
    bytes[12] = number >> 24; bytes[13] = number >> 16; bytes[14] = number >> 8; bytes[15] = number;
    return [NSData dataWithBytes:bytes length:sizeof bytes];
}
static NVSearchNoteSnapshot *Note(NSUInteger number, NSString *title, NSString *tags, NSString *body) {
    return [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(number) title:title tags:tags source:body revision:1] autorelease];
}
static NSUInteger Search(NVSearchService *service, id owner, NSString *query, NSUInteger titles, NSUInteger fuzzy) {
    __block BOOL done = NO;
    NSUInteger request = [service requestForOwner:owner query:query completion:^(NVSearchResult *result, NSError *error) {
        CHECK(!error && [[result titleNoteUUIDs] count] == titles && [[result fuzzyNoteUUIDs] count] == fuzzy); done = YES;
    }];
    CHECK(Spin(^BOOL { return done; })); return request;
}
static void ServiceMapping(NVSearchService *service, id owner) {
    NVSearchNoteSnapshot *note = Note(1, @"e\u0301", @"🇯🇵", @"👩🏽‍💻 x a\u0315\u0300");
    [service synchronizeWithSnapshots:@[note]];
    NSUInteger request = Search(service, owner, @"\"é\" \"🇯🇵\" \"👩🏽‍💻\" \"à\u0315\"", 0, 1);
    __block BOOL done = NO;
    [service requestPositionsForNoteUUID:[note noteUUID] requestID:request owner:owner completion:^(NVSearchPositions *positions, NSError *error) {
        CHECK(!error); CHECK([[positions titleRanges] isEqual:@[Range(0, 2)]]);
        CHECK([[positions tagsRanges] isEqual:@[Range(0, 4)]]);
        CHECK([[positions sourceRanges] isEqual:@[Range(0, 7), Range(10, 3)]]); done = YES;
    }];
    CHECK(Spin(^BOOL { return done; }));
    NSMutableArray *notes = [NSMutableArray array];
    for (NSUInteger i = 0; i < NVSearchMaximumDisplayedRanges + 5; i++) [notes addObject:Note(i + 1, @"alpha", @"", @"alpha")];
    [service synchronizeWithSnapshots:notes];
    Search(service, owner, @"alpha", [notes count], [notes count]);
    puts("PASS: native positions map into original title/tag/source UTF-16 fields; both complete result groups exceed the presentation cap.");
}
int main(void) { @autoreleasepool {
    LiteralBoundaries(); ScalarMapping();
    NVSearchService *service = [[[NVSearchService alloc] init] autorelease];
    NSObject *owner = [[[NSObject alloc] init] autorelease], *peer = [[[NSObject alloc] init] autorelease];
    AsyncBoundaries(service, owner, peer); ServiceMapping(service, owner); [service invalidate];
    printf("ROUND 2 C/FOUNDATION BOUNDARY REVIEW PASSED: %lu assertions.\n", (unsigned long)checks);
} return 0; }
