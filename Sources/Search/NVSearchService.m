#import "NVSearchService.h"
#import "NVFZF.h"

static NSError *NVSearchError(NVFZFStatus status) {
    return [NSError errorWithDomain:@"NVSearchError" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:nvfzf_status_message(status)]}];
}
static NSValue *NVSearchOwnerKey(id owner) { return [NSValue valueWithPointer:owner]; }
static void NVSearchAssertMain(void) { NSCAssert([NSThread isMainThread], @"Search ownership belongs to main"); }

@interface NVSearchResult (Private)
- (id)initWithRequestID:(NSUInteger)requestID revision:(NSUInteger)revision query:(NVSearchQuery *)query snapshots:(NSArray *)snapshots titles:(NSArray *)titles fuzzy:(NSArray *)fuzzy;
@end
@implementation NVSearchResult
@synthesize requestID = _requestID, corpusRevision = _corpusRevision, query = _query;
@synthesize titleNoteUUIDs = _titleNoteUUIDs, fuzzyNoteUUIDs = _fuzzyNoteUUIDs;
- (id)initWithRequestID:(NSUInteger)requestID revision:(NSUInteger)revision query:(NVSearchQuery *)query snapshots:(NSArray *)snapshots titles:(NSArray *)titles fuzzy:(NSArray *)fuzzy {
    if ((self = [super init])) {
        _requestID = requestID; _corpusRevision = revision; _query = [query retain];
        _titleNoteUUIDs = [titles copy]; _fuzzyNoteUUIDs = [fuzzy copy];
        NSMutableDictionary *byUUID = [NSMutableDictionary dictionary];
        for (NVSearchNoteSnapshot *snapshot in snapshots) [byUUID setObject:snapshot forKey:[snapshot noteUUID]];
        _snapshotsByUUID = [byUUID copy];
    }
    return self;
}
- (void)dealloc { [_query release]; [_titleNoteUUIDs release]; [_fuzzyNoteUUIDs release]; [_snapshotsByUUID release]; [super dealloc]; }
- (NVSearchNoteSnapshot *)snapshotForUUID:(NSData *)uuid { return [_snapshotsByUUID objectForKey:uuid]; }
- (NSUInteger)distinctNoteCount { NSMutableSet *ids = [NSMutableSet setWithArray:_titleNoteUUIDs]; [ids addObjectsFromArray:_fuzzyNoteUUIDs]; return [ids count]; }
@end

static NSArray *NVSearchRangesInField(NSArray *ranges, NSRange field) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSValue *value in ranges) {
        NSRange intersection = NSIntersectionRange([value rangeValue], field);
        if (intersection.length) { intersection.location -= field.location; [result addObject:[NSValue valueWithRange:intersection]]; }
    }
    return result;
}
@interface NVSearchPositions (Private)
- (id)initWithRanges:(NSArray *)ranges snapshot:(NVSearchNoteSnapshot *)snapshot;
@end
@implementation NVSearchPositions
@synthesize titleRanges = _titleRanges, tagsRanges = _tagsRanges, sourceRanges = _sourceRanges, snapshot = _snapshot;
- (id)initWithRanges:(NSArray *)ranges snapshot:(NVSearchNoteSnapshot *)snapshot {
    if ((self = [super init])) {
        _snapshot = [snapshot retain];
        _titleRanges = [NVSearchRangesInField(ranges, [snapshot titleRange]) copy];
        _tagsRanges = [NVSearchRangesInField(ranges, [snapshot tagsRange]) copy];
        _sourceRanges = [NVSearchRangesInField(ranges, [snapshot sourceRange]) copy];
    }
    return self;
}
- (void)dealloc { [_titleRanges release]; [_tagsRanges release]; [_sourceRanges release]; [_snapshot release]; [super dealloc]; }
@end

/* Borrowed offsets and string must remain alive until the cursor completes. */
typedef struct {
    NSUInteger utf16Index, scalarIndex, positionIndex;
} NVSearchRangeCursor;

static BOOL NVSearchMapRangesBatch(NSString *string, const uint32_t *offsets, NSUInteger count,
                                   NVFZFCancel *cancel, NVFZFStatus *status,
                                   NVSearchRangeCursor *cursor, NSMutableArray *ranges) {
    *status = NVFZF_OK;
    if (nvfzf_cancel_is_set(cancel)) { *status = NVFZF_CANCELLED; return YES; }
    if (cursor->positionIndex == count || cursor->utf16Index == [string length]) return YES;
    __block NSUInteger sequences = 0;
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 0.004;
    NSRange remaining = NSMakeRange(cursor->utf16Index, [string length] - cursor->utf16Index);
    [string enumerateSubstringsInRange:remaining options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange range, NSRange enclosingRange, BOOL *stop) {
        if (nvfzf_cancel_is_set(cancel)) { *status = NVFZF_CANCELLED; *stop = YES; return; }
        NVFZFStatus normalizationStatus;
        NSData *normalized = NVSearchCanonicalUTF8(substring, cancel, &normalizationStatus);
        if (normalizationStatus != NVFZF_OK) { *status = normalizationStatus; [ranges removeAllObjects]; *stop = YES; return; }
        NSUInteger scalarCount = 0;
        const unsigned char *bytes = [normalized bytes];
        for (NSUInteger i = 0; i < [normalized length]; ++i) if ((bytes[i] & 0xc0) != 0x80) ++scalarCount;
        BOOL found = NO;
        while (cursor->positionIndex < count && offsets[cursor->positionIndex] < cursor->scalarIndex + scalarCount) {
            if (offsets[cursor->positionIndex] >= cursor->scalarIndex) found = YES;
            ++cursor->positionIndex;
        }
        if (found) {
            NSRange previous = [ranges count] ? [[ranges lastObject] rangeValue] : NSMakeRange(NSNotFound, 0);
            if (previous.location != NSNotFound && NSMaxRange(previous) == range.location) {
                [ranges removeLastObject]; range = NSUnionRange(previous, range);
            }
            [ranges addObject:[NSValue valueWithRange:range]];
        }
        cursor->utf16Index = NSMaxRange(range);
        cursor->scalarIndex += scalarCount;
        ++sequences;
        if (cursor->positionIndex == count || sequences == 4096 ||
            (!(sequences & 63) && CFAbsoluteTimeGetCurrent() >= deadline)) *stop = YES;
    }];
    return *status != NVFZF_OK || cursor->positionIndex == count || cursor->utf16Index == [string length];
}

NSArray *NVSearchOriginalRanges(NSString *string, const uint32_t *offsets, NSUInteger count) {
    NSMutableArray *ranges = [NSMutableArray array];
    NVSearchRangeCursor cursor = {0}; NVFZFStatus status;
    while (!NVSearchMapRangesBatch(string, offsets, count, NULL, &status, &cursor, ranges)) {}
    return ranges;
}

/* A request captures one immutable corpus. Only cancellation crosses queues.
   The completion/result fields are touched on main; scan state on the worker. */
@interface NVSearchWork : NSObject {
@public
    NSUInteger requestID, revision, preparedCount;
    NSValue *ownerKey;
    NVSearchQuery *query;
    NSArray *snapshots;
    NVSearchCompletion completion;
    NVFZFCancel *cancel;
    NVFZFCandidate *candidates;
    NVFZFJob *job;
    NSMutableArray *titleIDs;
    NVSearchResult *result;
    NSError *error;
    BOOL completed;
}
- (void)cancel;
@end
@implementation NVSearchWork
- (id)init { if ((self = [super init])) { cancel = nvfzf_cancel_create(); titleIDs = [[NSMutableArray alloc] init]; } return self; }
- (void)cancel {
    nvfzf_cancel_set(cancel);
    NVSearchCompletion callback = completion; completion = nil;
    [callback release];
}
- (void)dealloc {
    nvfzf_job_free(job); free(candidates); nvfzf_cancel_free(cancel);
    [ownerKey release]; [query release]; [snapshots release]; [completion release]; [titleIDs release]; [result release]; [error release]; [super dealloc];
}
@end
@interface NVSearchPositionWork : NSObject {
@public
    NVFZFCancel *cancel;
    NVSearchPositionsCompletion completion;
    NSValue *searchOwnerKey, *positionOwnerKey;
    NSUInteger requestID;
    NVSearchQuery *query;
    NVSearchNoteSnapshot *snapshot;
    NVFZFPositions output;
    NVSearchRangeCursor cursor;
    NSMutableArray *ranges;
    BOOL hasPositions;
}
- (void)cancel;
@end
@implementation NVSearchPositionWork
- (id)init {
    if ((self = [super init])) { cancel = nvfzf_cancel_create(); ranges = [[NSMutableArray alloc] init]; }
    return self;
}
- (void)cancel {
    nvfzf_cancel_set(cancel);
    NVSearchPositionsCompletion callback = completion; completion = nil;
    [callback release];
}
- (void)dealloc {
    nvfzf_positions_free(&output); nvfzf_cancel_free(cancel);
    [completion release]; [searchOwnerKey release]; [positionOwnerKey release];
    [query release]; [snapshot release]; [ranges release]; [super dealloc];
}
@end

@interface NVSearchLiteralWork : NSObject {
@public
    NVFZFCancel *cancel;
    NVSearchLiteralRangesCompletion completion;
    NSString *source, *query, *matchingSource;
    NSArray *validatedRanges;
}
- (void)cancel;
@end
@implementation NVSearchLiteralWork
- (id)init { if ((self = [super init])) cancel = nvfzf_cancel_create(); return self; }
- (void)cancel {
    nvfzf_cancel_set(cancel);
    // Release captured browser objects on the cancelling main thread, even
    // when the immutable scan is still waiting in the worker queue.
    NVSearchLiteralRangesCompletion callback = completion; completion = nil;
    [callback release];
}
- (void)dealloc { nvfzf_cancel_free(cancel); [completion release]; [source release]; [query release]; [matchingSource release]; [validatedRanges release]; [super dealloc]; }
@end

/* NSData objects own the literal normalized bytes for this native call. */
static NVFZFStatus NVSearchBuildTerms(NVSearchQuery *query, NVFZFTerm **output, NSArray **dataOwner) {
    *output = NULL; *dataOwner = nil;
    NSData *original = [[query string] dataUsingEncoding:NSUTF8StringEncoding];
    if (!original || [original length] > NVFZF_MAX_QUERY_BYTES || ([original length] && memchr([original bytes], 0, [original length]))) return NVFZF_INVALID_INPUT;
    NSUInteger count = [[query terms] count];
    if (!count) return NVFZF_OK;
    NVFZFTerm *terms = calloc(count, sizeof(*terms));
    if (!terms) return NVFZF_OUT_OF_MEMORY;
    NSMutableArray *data = [NSMutableArray arrayWithCapacity:count];
    NSUInteger index = 0;
    for (NVSearchTerm *term in [query terms]) {
        NVFZFStatus normalizationStatus;
        NSData *bytes = NVSearchCanonicalUTF8([term text], NULL, &normalizationStatus);
        if (!bytes) { free(terms); return normalizationStatus; }
        [data addObject:bytes]; terms[index++] = (NVFZFTerm){[bytes bytes], [bytes length], [term isPhrase] ? NVFZF_TERM_EXACT : NVFZF_TERM_FUZZY};
    }
    *output = terms; *dataOwner = data;
    return NVFZF_OK;
}

@interface NVSearchService (Private)
- (void)cancelAllRequests;
- (NSArray *)detachRequestsForOwnerKey:(NSValue *)key;
- (BOOL)isRequestCurrent:(NSUInteger)requestID ownerKey:(NSValue *)key;
- (void)runBatch:(NVSearchWork *)work;
- (void)runPositionBatch:(NVSearchPositionWork *)work;
- (void)enqueueSourceRanges:(NSArray *)ranges source:(NSString *)source matchingSource:(NSString *)displayedSource query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion;
- (void)finishWork:(NVSearchWork *)work status:(NVFZFStatus)status fuzzy:(NSArray *)fuzzy;
@end
@implementation NVSearchService
- (id)init {
    if ((self = [super init])) {
        _corpus = [[NVSearchCorpus alloc] init];
        _requests = [[NSMutableDictionary alloc] init]; _positionRequests = [[NSMutableDictionary alloc] init];
        _literalRangeRequests = [[NSMutableDictionary alloc] init];
        _worker = dispatch_queue_create("org.nvalt.search", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_worker, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    }
    return self;
}
- (void)dealloc {
    /* Queued blocks retain this service, so the engine has no active caller. */
    [self cancelAllRequests]; nvfzf_engine_free(_engine);
    dispatch_release(_worker); [_requests release]; [_positionRequests release]; [_literalRangeRequests release]; [_corpus release]; [super dealloc];
}
- (NSUInteger)corpusRevision { NVSearchAssertMain(); return [_corpus revision]; }
- (NVSearchNoteSnapshot *)snapshotForUUID:(NSData *)uuid { NVSearchAssertMain(); return [_corpus snapshotForUUID:uuid]; }
- (BOOL)synchronizeWithSnapshots:(NSArray *)snapshots {
    NVSearchAssertMain(); BOOL changed = [_corpus synchronizeWithSnapshots:snapshots]; if (changed) [self cancelAllRequests]; return changed;
}
- (BOOL)updateSnapshot:(NVSearchNoteSnapshot *)snapshot {
    NVSearchAssertMain(); BOOL changed = [_corpus updateSnapshot:snapshot]; if (changed) [self cancelAllRequests]; return changed;
}
- (BOOL)removeUUID:(NSData *)uuid {
    NVSearchAssertMain(); BOOL changed = [_corpus removeUUID:uuid]; if (changed) [self cancelAllRequests]; return changed;
}
- (void)invalidate { NVSearchAssertMain(); [_corpus invalidate]; [self cancelAllRequests]; }
- (void)cancelAllRequests {
    NSMutableArray *detached = [NSMutableArray arrayWithArray:[_requests allValues]];
    [detached addObjectsFromArray:[_positionRequests allValues]];
    [detached addObjectsFromArray:[_literalRangeRequests allValues]];
    [_requests removeAllObjects]; [_positionRequests removeAllObjects]; [_literalRangeRequests removeAllObjects];
    // A callback release can destroy a browser and reenter cancellation. Detach
    // every old entry first, so reentrant requests cannot be removed here.
    for (id work in detached) [work cancel];
}
- (NSArray *)detachRequestsForOwnerKey:(NSValue *)key {
    NSMutableArray *detached = [NSMutableArray array];
    id work = [_requests objectForKey:key]; if (work) [detached addObject:work];
    [_requests removeObjectForKey:key];
    work = [_literalRangeRequests objectForKey:key]; if (work) [detached addObject:work];
    [_literalRangeRequests removeObjectForKey:key];
    for (NSValue *positionKey in [[[_positionRequests allKeys] copy] autorelease]) {
        NVSearchPositionWork *positions = [_positionRequests objectForKey:positionKey];
        if ([positions->searchOwnerKey isEqual:key]) {
            [detached addObject:positions]; [_positionRequests removeObjectForKey:positionKey];
        }
    }
    return detached;
}
- (void)cancelRequestsForOwner:(id)owner {
    NVSearchAssertMain();
    for (id work in [self detachRequestsForOwnerKey:NVSearchOwnerKey(owner)]) [work cancel];
}
- (BOOL)isRequestCurrent:(NSUInteger)requestID forOwner:(id)owner {
    return [self isRequestCurrent:requestID ownerKey:NVSearchOwnerKey(owner)];
}
- (BOOL)isRequestCurrent:(NSUInteger)requestID ownerKey:(NSValue *)key {
    NVSearchAssertMain(); NVSearchWork *work = [_requests objectForKey:key];
    return work && work->requestID == requestID && work->revision == [_corpus revision] && !nvfzf_cancel_is_set(work->cancel);
}
- (NSUInteger)requestForOwner:(id)owner query:(NSString *)string completion:(NVSearchCompletion)completion {
    NVSearchAssertMain(); NSParameterAssert(owner);
    NSValue *key = NVSearchOwnerKey(owner); NVSearchWork *existing = [_requests objectForKey:key];
    if (existing && existing->revision == [_corpus revision] && [[existing->query string] isEqualToString:(string ?: @"")] && !nvfzf_cancel_is_set(existing->cancel)) {
        // Install the replacement before releasing the old capture. Its owner
        // may reenter cancellation or submit a newer request during dealloc.
        [[existing retain] autorelease];
        NVSearchCompletion previous = existing->completion;
        existing->completion = [completion copy];
        if (existing->completed) dispatch_async(dispatch_get_main_queue(), ^{
            if ([_requests objectForKey:key] == existing && !nvfzf_cancel_is_set(existing->cancel) && existing->completion) {
                NVSearchCompletion callback = existing->completion; existing->completion = nil;
                callback(existing->result, existing->error); [callback release];
            }
        });
        [previous release];
        return existing->requestID;
    }
    NSArray *detached = [self detachRequestsForOwnerKey:key];
    NVSearchWork *work = [[[NVSearchWork alloc] init] autorelease];
    work->requestID = ++_nextRequestID; work->revision = [_corpus revision]; work->ownerKey = [key retain];
    work->query = [[NVSearchQuery alloc] initWithString:string]; work->snapshots = [[_corpus snapshots] retain]; work->completion = [completion copy];
    [_requests setObject:work forKey:key];
    dispatch_async(_worker, ^{ @autoreleasepool { [self runBatch:work]; } });
    for (id previous in detached) [previous cancel];
    return work->requestID;
}
- (void)finishWork:(NVSearchWork *)work status:(NVFZFStatus)status fuzzy:(NSArray *)fuzzy {
    if (status == NVFZF_CANCELLED || nvfzf_cancel_is_set(work->cancel)) return;
    NVSearchResult *result = status == NVFZF_OK ? [[[NVSearchResult alloc] initWithRequestID:work->requestID revision:work->revision query:work->query snapshots:work->snapshots titles:work->titleIDs fuzzy:fuzzy] autorelease] : nil;
    NSError *error = status == NVFZF_OK ? nil : NVSearchError(status);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_requests objectForKey:work->ownerKey] != work || work->revision != [_corpus revision] || nvfzf_cancel_is_set(work->cancel)) return;
        work->completed = YES; work->result = [result retain]; work->error = [error retain];
        NVSearchCompletion callback = work->completion; work->completion = nil;
        if (callback) callback(result, error);
        [callback release];
    });
}
- (void)runBatch:(NVSearchWork *)work {
    if (nvfzf_cancel_is_set(work->cancel)) return;
    if (!work->cancel) { [self finishWork:work status:NVFZF_OUT_OF_MEMORY fuzzy:nil]; return; }
    if (!_engine) _engine = nvfzf_engine_create();
    if (!_engine) { [self finishWork:work status:NVFZF_OUT_OF_MEMORY fuzzy:nil]; return; }
    NSUInteger count = [work->snapshots count];
    if (!work->candidates && count) {
        if (count > UINT32_MAX || count > SIZE_MAX / sizeof(NVFZFCandidate)) { [self finishWork:work status:NVFZF_INVALID_INPUT fuzzy:nil]; return; }
        work->candidates = calloc(count, sizeof(NVFZFCandidate));
        if (!work->candidates) { [self finishWork:work status:NVFZF_OUT_OF_MEMORY fuzzy:nil]; return; }
    }
    if (work->preparedCount < count) {
        NSUInteger end = MIN(count, work->preparedCount + 64);
        CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 0.004;
        while (work->preparedCount < end) {
            if (nvfzf_cancel_is_set(work->cancel)) return;
            NVSearchNoteSnapshot *snapshot = [work->snapshots objectAtIndex:work->preparedCount];
            NVFZFStatus preparationStatus;
            NSData *bytes = [snapshot preparedUTF8WithCancellation:work->cancel status:&preparationStatus];
            if (preparationStatus != NVFZF_OK) { [self finishWork:work status:preparationStatus fuzzy:nil]; return; }
            work->candidates[work->preparedCount++] = (NVFZFCandidate){[bytes bytes], [bytes length]};
            if ([work->query matchesTitle:[snapshot title]]) [work->titleIDs addObject:[snapshot noteUUID]];
            if (CFAbsoluteTimeGetCurrent() >= deadline) break;
        }
        if (work->preparedCount < count) { dispatch_async(_worker, ^{ @autoreleasepool { [self runBatch:work]; } }); return; }
    }
    NVFZFStatus status = NVFZF_OK;
    if (!work->job) {
        NVFZFTerm *terms = NULL; NSArray *dataOwner = nil;
        status = NVSearchBuildTerms(work->query, &terms, &dataOwner);
        if (status == NVFZF_OK) status = nvfzf_job_create_terms(work->candidates, count, terms, [[work->query terms] count], work->cancel, &work->job);
        (void)dataOwner; free(terms);
    }
    bool finished = false;
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 0.004;
    for (NSUInteger batch = 0; status == NVFZF_OK && !finished && batch < 64; ++batch) {
        status = nvfzf_job_step(_engine, work->job, 1, &finished);
        if (CFAbsoluteTimeGetCurrent() >= deadline) break;
    }
    if (status != NVFZF_OK) { [self finishWork:work status:status fuzzy:nil]; return; }
    if (!finished) { dispatch_async(_worker, ^{ @autoreleasepool { [self runBatch:work]; } }); return; }
    NVFZFSearchResult output = {0}; status = nvfzf_job_finish(work->job, &output);
    NSMutableArray *fuzzy = [NSMutableArray arrayWithCapacity:output.count];
    if (status == NVFZF_OK) for (NSUInteger i = 0; i < output.count; ++i) {
        if (nvfzf_cancel_is_set(work->cancel)) { status = NVFZF_CANCELLED; break; }
        [fuzzy addObject:[[work->snapshots objectAtIndex:output.matches[i].candidate_index] noteUUID]];
    }
    nvfzf_search_result_free(&output);
    nvfzf_job_free(work->job); work->job = NULL;
    free(work->candidates); work->candidates = NULL;
    [self finishWork:work status:status fuzzy:fuzzy];
}
- (void)cancelPositionRequestsForOwner:(id)positionOwner {
    NVSearchAssertMain(); NSValue *key = NVSearchOwnerKey(positionOwner);
    NVSearchPositionWork *work = [[_positionRequests objectForKey:key] retain];
    [_positionRequests removeObjectForKey:key];
    [work cancel]; [work release];
}
- (void)requestPositionsForNoteUUID:(NSData *)uuid requestID:(NSUInteger)requestID owner:(id)owner completion:(NVSearchPositionsCompletion)completion {
    [self requestPositionsForNoteUUID:uuid requestID:requestID owner:owner positionOwner:owner completion:completion];
}
- (void)requestPositionsForNoteUUID:(NSData *)uuid requestID:(NSUInteger)requestID owner:(id)owner positionOwner:(id)positionOwner completion:(NVSearchPositionsCompletion)completion {
    NVSearchAssertMain(); NSParameterAssert(positionOwner);
    NSValue *key = NVSearchOwnerKey(owner), *positionKey = NVSearchOwnerKey(positionOwner);
    NVSearchWork *search = [_requests objectForKey:key];
    if (![self isRequestCurrent:requestID forOwner:owner] || !search->completed || !search->result) return;
    NVSearchNoteSnapshot *snapshot = [search->result snapshotForUUID:uuid]; if (!snapshot) return;
    NVSearchPositionWork *old = [[_positionRequests objectForKey:positionKey] retain];
    NVSearchPositionWork *work = [[[NVSearchPositionWork alloc] init] autorelease];
    work->completion = [completion copy]; work->searchOwnerKey = [key retain];
    work->positionOwnerKey = [positionKey retain]; work->requestID = requestID;
    work->query = [search->query retain]; work->snapshot = [snapshot retain];
    [_positionRequests setObject:work forKey:positionKey];
    dispatch_async(_worker, ^{ @autoreleasepool { [self runPositionBatch:work]; } });
    [old cancel]; [old release];
}
- (void)runPositionBatch:(NVSearchPositionWork *)work {
    if (nvfzf_cancel_is_set(work->cancel)) return;
    NVFZFStatus status = work->cancel ? NVFZF_OK : NVFZF_OUT_OF_MEMORY;
    if (status == NVFZF_OK && !work->hasPositions) {
        NVFZFTerm *terms = NULL; NSArray *dataOwner = nil;
        status = NVSearchBuildTerms(work->query, &terms, &dataOwner);
        NSData *bytes = [work->snapshot preparedUTF8];
        if (status == NVFZF_OK) status = nvfzf_positions_terms(_engine, (NVFZFCandidate){[bytes bytes], [bytes length]}, terms, [[work->query terms] count], work->cancel, &work->output);
        (void)dataOwner; free(terms); work->hasPositions = YES;
    }
    if (status == NVFZF_OK && !NVSearchMapRangesBatch([work->snapshot candidate], work->output.offsets, work->output.count, work->cancel, &status, &work->cursor, work->ranges)) {
        // Preserve every native offset while letting another browser's queued
        // query run between complete composed-character mapping batches.
        dispatch_async(_worker, ^{ @autoreleasepool { [self runPositionBatch:work]; } });
        return;
    }
    nvfzf_positions_free(&work->output);
    if (status == NVFZF_CANCELLED || nvfzf_cancel_is_set(work->cancel)) return;
    NVSearchPositions *positions = status == NVFZF_OK ? [[[NVSearchPositions alloc] initWithRanges:work->ranges snapshot:work->snapshot] autorelease] : nil;
    NSError *error = status == NVFZF_OK ? nil : NVSearchError(status);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_positionRequests objectForKey:work->positionOwnerKey] != work || ![self isRequestCurrent:work->requestID ownerKey:work->searchOwnerKey] || nvfzf_cancel_is_set(work->cancel)) return;
        NVSearchPositionsCompletion callback = work->completion; work->completion = nil;
        [_positionRequests removeObjectForKey:work->positionOwnerKey];
        if (callback) callback(positions, error);
        [callback release];
    });
}
- (void)cancelLiteralRangesForOwner:(id)owner {
    NVSearchAssertMain(); NSValue *key = NVSearchOwnerKey(owner);
    NVSearchLiteralWork *work = [[_literalRangeRequests objectForKey:key] retain];
    [_literalRangeRequests removeObjectForKey:key];
    [work cancel]; [work release];
}
- (void)requestLiteralRangesInSource:(NSString *)source query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion {
    [self requestLiteralRangesInSource:source matchingSource:source query:query owner:owner completion:completion];
}
- (void)requestLiteralRangesInSource:(NSString *)source matchingSource:(NSString *)displayedSource query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion {
    [self enqueueSourceRanges:nil source:source matchingSource:displayedSource query:query owner:owner completion:completion];
}
- (void)validateSourceRanges:(NSArray *)ranges source:(NSString *)source matchingSource:(NSString *)displayedSource owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion {
    [self enqueueSourceRanges:(ranges ?: @[]) source:source matchingSource:displayedSource query:nil owner:owner completion:completion];
}
- (void)enqueueSourceRanges:(NSArray *)ranges source:(NSString *)source matchingSource:(NSString *)displayedSource query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion {
    NVSearchAssertMain(); NSParameterAssert(owner);
    NSValue *key = NVSearchOwnerKey(owner);
    NVSearchLiteralWork *old = [[_literalRangeRequests objectForKey:key] retain];
    NVSearchLiteralWork *work = [[[NVSearchLiteralWork alloc] init] autorelease];
    work->source = [(source ?: @"") copy]; work->matchingSource = [(displayedSource ?: @"") copy];
    work->query = [(query ?: @"") copy]; work->completion = [completion copy];
    if (ranges) work->validatedRanges = [[ranges subarrayWithRange:NSMakeRange(0, MIN([ranges count], NVSearchMaximumDisplayedRanges))] copy];
    [_literalRangeRequests setObject:work forKey:key];
    dispatch_async(_worker, ^{ @autoreleasepool {
        if (nvfzf_cancel_is_set(work->cancel)) return;
        NSArray *ranges = @[];
        if (work->cancel && [work->source isEqual:work->matchingSource]) {
            if (work->validatedRanges) ranges = work->validatedRanges;
            else {
                NVSearchQuery *query = [[[NVSearchQuery alloc] initWithString:work->query] autorelease];
                ranges = [query literalRangesInString:work->source maximumCount:NVSearchMaximumDisplayedRanges cancellation:^BOOL {
                    return nvfzf_cancel_is_set(work->cancel);
                }];
            }
        }
        if (nvfzf_cancel_is_set(work->cancel)) return;
        NSError *error = work->cancel ? nil : NVSearchError(NVFZF_OUT_OF_MEMORY);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([_literalRangeRequests objectForKey:key] != work || nvfzf_cancel_is_set(work->cancel)) return;
            NVSearchLiteralRangesCompletion callback = work->completion; work->completion = nil;
            [_literalRangeRequests removeObjectForKey:key];
            if (callback) callback(ranges, work->source, error);
            [callback release];
        });
    } });
    [old cancel]; [old release];
}

@end
