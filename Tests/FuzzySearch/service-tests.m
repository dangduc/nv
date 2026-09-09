#import <Foundation/Foundation.h>
#import "NVSearchService.h"

static NSUInteger checks;
static void Check(BOOL condition, const char *name) {
    ++checks;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name); exit(1); }
}
static NSData *UUID(unsigned char value) { unsigned char bytes[16] = {0}; bytes[15] = value; return [NSData dataWithBytes:bytes length:16]; }
static NVSearchNoteSnapshot *Note(unsigned char value, NSString *title, NSString *tags, NSString *source, NSUInteger revision) {
    return [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(value) title:title tags:tags source:source revision:revision] autorelease];
}
static BOOL Spin(BOOL (^finished)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!finished() && [limit timeIntervalSinceNow] > 0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    return finished();
}
static NVSearchResult *Search(NVSearchService *service, id owner, NSString *query, NSError **errorOut) {
    __block BOOL finished = NO; __block NVSearchResult *result = nil; __block NSError *error = nil;
    NSUInteger request = [service requestForOwner:owner query:query completion:^(NVSearchResult *value, NSError *failure) {
        result = [value retain]; error = [failure retain]; finished = YES;
    }];
    Check(Spin(^BOOL { return finished; }), "search completes");
    Check([service isRequestCurrent:request forOwner:owner], "completion identity current");
    if (errorOut) *errorOut = [error autorelease]; else { Check(error == nil, "no search error"); [error release]; }
    return [result autorelease];
}
int main(void) { @autoreleasepool {
    NVSearchQuery *grammar = [[[NVSearchQuery alloc] initWithString:@"road:map\t\"blue sky\" 'x !x ^x $x |x \\x \"unfinished phrase"] autorelease];
    NSArray *terms = [grammar terms]; Check([terms count] == 10, "legacy separator grammar count");
    Check([[[terms objectAtIndex:2] text] isEqualToString:@"blue sky"] && [[terms objectAtIndex:2] isPhrase], "quoted phrase type");
    Check([[[terms lastObject] text] isEqualToString:@"unfinished phrase"] && [[terms lastObject] isPhrase], "unclosed phrase type");
    for (NSUInteger i = 3; i < 9; ++i) Check(![[terms objectAtIndex:i] isPhrase], "punctuation remains fuzzy literal");
    Check(![[[[NVSearchQuery alloc] initWithString:@" :\t\r\n\"\""] autorelease] hasTerms], "separators have no terms");
    Check([[[[NVSearchQuery alloc] initWithString:@"road map"] autorelease] matchesTitle:@"Map for ROAD"], "Cocoa title literal AND case matching");
    Check([[[[NVSearchQuery alloc] initWithString:@"road map"] autorelease] matchesTitle:@"roadmap?"], "literal substrings need no word boundary");

    for (NSString *sample in @[@"", @"ASCII punctuation !|$^", @"e\u0301", @"각", @"a\u0301\u0327", @"😀 鴨 🧑🏽‍💻"]) {
        NVFZFStatus status;
        NSData *actual = NVSearchCanonicalUTF8(sample, NULL, &status);
        NSData *expected = [[sample precomposedStringWithCanonicalMapping] dataUsingEncoding:NSUTF8StringEncoding];
        Check(status == NVFZF_OK && [actual isEqual:expected], "pinned canonical composition preserves expected NFC");
    }
    unichar candidateNull[] = {'a', 0, 'e', 0x301}; NVFZFStatus normalizationStatus;
    NSData *normalizedNull = NVSearchCanonicalUTF8([NSString stringWithCharacters:candidateNull length:4], NULL, &normalizationStatus);
    const unsigned char expectedNull[] = {'a', 0, 0xc3, 0xa9};
    Check(normalizationStatus == NVFZF_OK && [normalizedNull isEqual:[NSData dataWithBytes:expectedNull length:4]], "canonical composition preserves embedded candidate NUL");
    NVFZFCancel *normalizationCancel = nvfzf_cancel_create(); nvfzf_cancel_set(normalizationCancel);
    Check(NVSearchCanonicalUTF8(@"e\u0301", normalizationCancel, &normalizationStatus) == nil && normalizationStatus == NVFZF_CANCELLED, "canonical preparation obeys cancellation");
    nvfzf_cancel_free(normalizationCancel);

    NSMutableString *mutableTitle = [NSMutableString stringWithString:@"Road map"];
    NVSearchNoteSnapshot *a = Note(3, mutableTitle, @"project", @"Road map body with ne\u0301bula. 😀 e\u0301 鴨 🧑🏽‍💻", 1);
    [mutableTitle setString:@"changed"]; Check([[a title] isEqualToString:@"Road map"], "snapshot copies mutable strings");
    NVSearchNoteSnapshot *b = Note(1, @"Other", @"road map", @"r--o--a--d", 1);
    NVSearchNoteSnapshot *c = Note(2, @"ROAD diary", @"", @"literal !bang and ^anchor $cash |pipe 'quote \\slash", 1);
    NVSearchCorpus *corpus = [[[NVSearchCorpus alloc] init] autorelease];
    Check([corpus synchronizeWithSnapshots:@[a, b, c]], "initial corpus changed");
    Check([[[[corpus snapshots] objectAtIndex:0] noteUUID] isEqual:UUID(1)], "UUID producer order");
    NSUInteger revision = [corpus revision];
    NVSearchNoteSnapshot *same = Note(3, [a title], [a tags], [a source], 999);
    Check(![corpus updateSnapshot:same] && [corpus revision] == revision, "content reuse ignores display revision");
    Check([corpus snapshotForUUID:UUID(3)] == a, "unchanged version identity reused");
    Check([corpus updateSnapshot:Note(3, @"Changed title", @"", @"new body", 2)], "same-count replacement");
    Check([corpus removeUUID:UUID(1)] && ![corpus removeUUID:UUID(1)], "delete idempotent");
    Check([corpus updateSnapshot:b] && [[[corpus snapshots] firstObject] noteUUID] == [b noteUUID], "insertion maintains UUID order");

    NVSearchService *service = [[[NVSearchService alloc] init] autorelease];
    NSObject *owner = [[[NSObject alloc] init] autorelease];
    NSObject *peer = [[[NSObject alloc] init] autorelease];
    [service synchronizeWithSnapshots:@[a, b, c]];
    NVSearchResult *result = Search(service, owner, @"road", NULL);
    Check([[result titleNoteUUIDs] isEqual:@[UUID(2), UUID(3)]], "title group excludes tag/body matches");
    Check([[result fuzzyNoteUUIDs] count] == 3, "complete fuzzy group includes title overlap");
    Check([result distinctNoteCount] == 3, "distinct count independent of row count");
    Check([[result titleNoteUUIDs] count] + [[result fuzzyNoteUUIDs] count] == 5, "duplicate result occurrences retained");
    Check([[Search(service, owner, @"\"road map\"", NULL) fuzzyNoteUUIDs] count] == 2, "quoted literal phrase accepts title and tags");
    Check([[Search(service, owner, @"\"r d\"", NULL) fuzzyNoteUUIDs] count] == 0, "phrase does not fuzzy match gaps");
    for (NSString *literal in @[@"!bang", @"^anchor", @"$cash", @"|pipe", @"'quote", @"\\slash"]) {
        result = Search(service, owner, literal, NULL);
        Check([[result fuzzyNoteUUIDs] isEqual:@[UUID(2)]], "native punctuation literal");
    }
    result = Search(service, owner, @"nébula", NULL);
    Check([[result fuzzyNoteUUIDs] isEqual:@[UUID(3)]], "NFC query matches original NFD body");
    __block BOOL positioned = NO;
    [service requestPositionsForNoteUUID:UUID(3) requestID:[result requestID] owner:owner completion:^(NVSearchPositions *positions, NSError *error) {
        Check(error == nil && [[positions sourceRanges] count] > 0, "lazy source positions");
        NSString *piece = [[positions snapshot].source substringWithRange:[[[positions sourceRanges] firstObject] rangeValue]];
        Check([piece isEqualToString:@"ne\u0301bula"], "positions map NFC back to complete original grapheme"); positioned = YES;
    }];
    Check(Spin(^BOOL { return positioned; }), "position request completes");
    __block BOOL sourceChannel = NO, excerptChannel = NO;
    NSObject *excerptOwner = [[[NSObject alloc] init] autorelease];
    [service requestPositionsForNoteUUID:UUID(3) requestID:[result requestID] owner:owner completion:^(NVSearchPositions *p, NSError *e) { sourceChannel = YES; }];
    [service requestPositionsForNoteUUID:UUID(3) requestID:[result requestID] owner:owner positionOwner:excerptOwner completion:^(NVSearchPositions *p, NSError *e) { excerptChannel = YES; }];
    Check(Spin(^BOOL { return sourceChannel && excerptChannel; }), "source and excerpt position channels coexist");
    __block BOOL cancelledPosition = NO;
    [service requestPositionsForNoteUUID:UUID(3) requestID:[result requestID] owner:owner positionOwner:excerptOwner completion:^(NVSearchPositions *p, NSError *e) { cancelledPosition = YES; }];
    [service cancelPositionRequestsForOwner:excerptOwner];
    uint32_t offsets[] = {0, 2, 4, 6};
    NSArray *ranges = NVSearchOriginalRanges(@"😀 e\u0301 鴨 🧑🏽‍💻", offsets, 4);
    Check([ranges count] == 4, "unicode positions span four graphemes");
    for (NSValue *value in ranges) Check(NSMaxRange([value rangeValue]) <= [@"😀 e\u0301 鴨 🧑🏽‍💻" length], "UTF16 range in bounds");
    Check([[ @"😀 e\u0301 鴨 🧑🏽‍💻" substringWithRange:[[ranges lastObject] rangeValue]] isEqualToString:@"🧑🏽‍💻"], "ZWJ emoji expands to grapheme");

    __block BOOL obsoleteCalled = NO, latestCalled = NO, peerCalled = NO;
    NSUInteger old = [service requestForOwner:owner query:@"old" completion:^(NVSearchResult *r, NSError *e) { obsoleteCalled = YES; }];
    NSUInteger latest = [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *r, NSError *e) { latestCalled = YES; Check([r requestID] != old, "supersession advances identity"); }];
    [service requestForOwner:peer query:@"Other" completion:^(NVSearchResult *r, NSError *e) { peerCalled = YES; }];
    Check(![service isRequestCurrent:old forOwner:owner] && [service isRequestCurrent:latest forOwner:owner], "old request unavailable synchronously");
    Check(Spin(^BOOL { return latestCalled && peerCalled; }) && !obsoleteCalled, "two owners finish without stale callback");
    __block BOOL repeated = NO;
    NSUInteger reused = [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *r, NSError *e) { repeated = YES; }];
    Check(reused == latest && Spin(^BOOL { return repeated; }), "completed identical request reused with deferred callback");

    __block BOOL mutationStaleCalled = NO;
    NSUInteger stale = [service requestForOwner:owner query:@"nebula" completion:^(NVSearchResult *r, NSError *e) { mutationStaleCalled = YES; }];
    Check([service updateSnapshot:Note(3, @"New", @"", @"new needle", 2)], "service captures changed note");
    Check(![service isRequestCurrent:stale forOwner:owner], "mutation invalidates before runloop publication");
    Check([[Search(service, owner, @"new needle", NULL) fuzzyNoteUUIDs] isEqual:@[UUID(3)]], "same-count edit searched");
    Check(!mutationStaleCalled, "mutation rejects obsolete completion");
    Check(!cancelledPosition, "independent position cancellation fences publication");
    Check([service removeUUID:UUID(3)] && [[Search(service, owner, @"new needle", NULL) fuzzyNoteUUIDs] count] == 0, "deletion removes all matching occurrences");
    NSError *error = nil; unichar nullQuery[] = {'x', 0, 'y'};
    result = Search(service, owner, [NSString stringWithCharacters:nullQuery length:3], &error);
    Check(result == nil && error != nil, "query NUL fails and never publishes zero result");
    result = Search(service, owner, [@"x" stringByPaddingToLength:65537 withString:@"x" startingAtIndex:0], &error);
    Check(result == nil && error != nil, "query size limit reports error");
    // Compare cached incremental mutation results with a fresh corpus search.
    NSArray *changed = @[Note(1, @"Road map", @"changed tags", @"body", 8), Note(2, @"ROAD diary", @"road", @"newly matching", 2), Note(4, @"Body", @"", @"road", 1)];
    [service synchronizeWithSnapshots:changed];
    NVSearchService *fresh = [[[NVSearchService alloc] init] autorelease]; [fresh synchronizeWithSnapshots:changed];
    for (NSString *query in @[@"road", @"newly", @"changed tags", @"body"]) {
        NVSearchResult *cachedResult = Search(service, owner, query, NULL);
        NVSearchResult *freshResult = Search(fresh, peer, query, NULL);
        Check([[cachedResult titleNoteUUIDs] isEqual:[freshResult titleNoteUUIDs]] && [[cachedResult fuzzyNoteUUIDs] isEqual:[freshResult fuzzyNoteUUIDs]], "incremental cache equals fresh complete result");
    }
    [fresh invalidate];
    __block BOOL closureCalled = NO;
    [service requestForOwner:owner query:@"closed owner" completion:^(NVSearchResult *r, NSError *e) { closureCalled = YES; }];
    [service cancelRequestsForOwner:owner];
    Search(service, peer, @"road", NULL);
    Check(!closureCalled, "closed owner cannot publish");
    [service cancelRequestsForOwner:owner]; [service cancelRequestsForOwner:peer]; [service invalidate];
    fprintf(stdout, "SEARCH SERVICE: %lu checks passed\n", (unsigned long)checks);
} return 0; }
