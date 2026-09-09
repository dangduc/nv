#include <stdatomic.h>

/* The scheduling gate is a fixture subclass. Production work still runs in
   the original methods and owns its original data and cancellation flags. */
@interface NVSearchService (ReviewPrivate)
- (void)runPositionBatch:(id)work;
@end
@interface ContinuationService : NVSearchService {
    dispatch_semaphore_t entered, proceed;
    _Atomic NSUInteger batches;
    _Atomic BOOL pauseSecond;
}
- (void)armSecondBatch;
- (void)waitForSecondBatch;
- (void)resumeAndDrain;
- (NSUInteger)batchCount;
@end
@implementation ContinuationService
- (id)init {
    if ((self = [super init])) { entered = dispatch_semaphore_create(0); proceed = dispatch_semaphore_create(0); }
    return self;
}
- (void)armSecondBatch { atomic_store(&batches, 0); atomic_store(&pauseSecond, YES); }
- (void)runPositionBatch:(id)work {
    NSUInteger ordinal = atomic_fetch_add(&batches, 1) + 1;
    if (ordinal == 2 && atomic_exchange(&pauseSecond, NO)) {
        dispatch_semaphore_signal(entered);
        long expired = dispatch_semaphore_wait(proceed, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC));
        if (expired) { fprintf(stderr, "FAIL: fixture continuation gate exceeded its deadline\n"); exit(1); }
    }
    [super runPositionBatch:work];
}
- (void)waitForSecondBatch {
    Check(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC)) == 0,
          "production mapping queues a second worker continuation");
}
- (void)resumeAndDrain {
    __block BOOL drained = NO;
    dispatch_semaphore_signal(proceed);
    dispatch_async(_worker, ^{ dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; }); });
    Check(Spin(^BOOL { return drained; }), "queued work resumes after the continuation gate");
}
- (NSUInteger)batchCount { return atomic_load(&batches); }
- (void)dealloc { dispatch_release(entered); dispatch_release(proceed); [super dealloc]; }
@end

typedef struct { BOOL released, releasedOnMain; NSUInteger calls; } CaptureState;
@interface OwnedCapture : NSObject { @public CaptureState *state; void (^afterRelease)(void); }
@end
@implementation OwnedCapture
- (void)dealloc {
    state->released = YES; state->releasedOnMain = [NSThread isMainThread];
    Check(state->releasedOnMain, "callback capture disposal remains on main during reentry");
    if (afterRelease) afterRelease();
    [afterRelease release]; [super dealloc];
}
@end

static NSUInteger Submit(NVSearchService *service, NSString *channel, id owner, id positionOwner,
                         NSData *uuid, NSUInteger requestID, CaptureState *state,
                         void (^onCall)(void), void (^onRelease)(void)) {
    OwnedCapture *capture = [[OwnedCapture alloc] init]; capture->state = state; capture->afterRelease = [onRelease copy];
    void (^delivered)(void) = ^{
        Check([NSThread isMainThread], "successful callback executes on main");
        Check(!capture->state->released, "successful callback owns its capture during entry");
        capture->state->calls++;
        if (onCall) onCall();
        Check(!capture->state->released, "callback capture survives cancellation or replacement during its invocation");
    };
    if ([channel isEqual:@"search"] || [channel isEqual:@"cached-search"]) {
        requestID = [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *result, NSError *error) {
            Check(result && !error && result.distinctNoteCount == 1, "successful search retains the expected result"); delivered();
        }];
    } else if ([channel isEqual:@"positions"]) {
        [service requestPositionsForNoteUUID:uuid requestID:requestID owner:owner positionOwner:positionOwner completion:^(NVSearchPositions *positions, NSError *error) {
            Check(positions && !error && positions.sourceRanges.count, "successful positions retain the expected ranges"); delivered();
        }];
    } else {
        [service requestLiteralRangesInSource:@"road body" query:@"road" owner:owner completion:^(NSArray *ranges, NSString *source, NSError *error) {
            Check(!error && ranges.count == 1 && [source isEqual:@"road body"], "successful literal delivery retains its matching source"); delivered();
        }];
    }
    [capture release];
    return requestID;
}
static void CancelChannel(NVSearchService *service, NSString *channel, id owner, id positionOwner) {
    if ([channel isEqual:@"positions"]) [service cancelPositionRequestsForOwner:positionOwner];
    else if ([channel isEqual:@"literal"]) [service cancelLiteralRangesForOwner:owner];
    else [service cancelRequestsForOwner:owner];
}
static NSUInteger Seed(NVSearchService *service, id owner, NSString *query) {
    __block BOOL done = NO;
    NSUInteger requestID = [service requestForOwner:owner query:query completion:^(NVSearchResult *result, NSError *error) {
        Check(result && !error && result.distinctNoteCount == 1, "seed search completes successfully"); done = YES;
    }];
    Check(Spin(^BOOL { return done; }), "seed search callback arrives");
    return requestID;
}

static void SuccessfulReentry(NSString *channel) {
    @autoreleasepool {
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[Note(@"title", @"road body")]] autorelease];
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library);
        NSObject *owner = [[[NSObject alloc] init] autorelease];
        NSObject *positionOwner = [[[NSObject alloc] init] autorelease];
        NSObject *peer = [[[NSObject alloc] init] autorelease];
        NSData *uuid = UUID([[library allNotes] firstObject]);
        NSUInteger seeded = 0;
        if ([channel isEqual:@"positions"] || [channel isEqual:@"cached-search"]) seeded = Seed(service, owner, @"road");
        CaptureState first = {0}, abandoned = {0}, final = {0}, peerState = {0};
        CaptureState *a = &first, *b = &abandoned, *c = &final, *p = &peerState;
        __block NSUInteger finalID = 0;
        NSUInteger initialID = Submit(service, channel, owner, positionOwner, uuid, seeded, a, ^{
            CancelChannel(service, channel, owner, positionOwner);
            Check(!a->released, "self-cancellation cannot destroy the executing completion capture");
            Submit(service, channel, owner, positionOwner, uuid, seeded, b, nil, ^{
                Submit(service, @"search", peer, peer, uuid, 0, p, nil, nil);
            });
        }, ^{
            // Disposal of the successful callback replaces its queued successor.
            // Disposal of that successor starts independent work for another owner.
            finalID = Submit(service, channel, owner, positionOwner, uuid, seeded, c, nil, nil);
        });
        if ([channel isEqual:@"cached-search"]) Check(initialID == seeded, "completed query replay reuses the original request identity");
        Check(!a->calls && !a->released, "including cached results, callback delivery stays deferred until the caller returns");
        Check(Spin(^BOOL { return a->released && b->released && c->released && p->released; }),
              "successful disposal and nested replacement both reach their terminal captures");
        Check(a->calls == 1 && b->calls == 0 && c->calls == 1 && p->calls == 1,
              "only the first, newest replacement, and independent owner callbacks publish");
        Check(a->releasedOnMain && b->releasedOnMain && c->releasedOnMain && p->releasedOnMain,
              "success, nested cancellation, and independent delivery dispose on main");
        if ([channel isEqual:@"search"] || [channel isEqual:@"cached-search"])
            Check([service isRequestCurrent:finalID forOwner:owner], "successful old callback disposal preserves the newest search registry entry");
        else if ([channel isEqual:@"positions"]) Check([service isRequestCurrent:seeded forOwner:owner], "position reentry preserves the parent search identity");
        [service cancelRequestsForOwner:owner]; [service cancelRequestsForOwner:peer]; [service invalidate];
        printf("PASS successful callback reentry: %s\n", channel.UTF8String);
    }
}

/* Each production browser session has an independent disposal witness. */
typedef struct { _Atomic BOOL released, main; } OwnerState;
@interface WatchedSession : NVBrowserSession { @public OwnerState *state; }
@end
@implementation WatchedSession
- (void)dealloc {
    atomic_store(&state->main, [NSThread isMainThread]);
    atomic_store(&state->released, YES);
    [super dealloc];
}
@end
@interface WatchedOwner : NSObject { @public OwnerState *state; NVSearchService *service; }
@end
@implementation WatchedOwner
- (void)dealloc {
    atomic_store(&state->main, [NSThread isMainThread]);
    atomic_store(&state->released, YES);
    [service cancelRequestsForOwner:self];
    [super dealloc];
}
@end
static NSString *LongBody(void) {
    return [[@"" stringByPaddingToLength:20000 withString:@"e\u0301x " startingAtIndex:0] stringByAppendingString:@"z"];
}
static WatchedSession *Session(TestLibrary *library, NVSearchService *service, OwnerState *state) {
    WatchedSession *session = [[WatchedSession alloc] initWithLibrary:(id)library]; session->state = state;
    [session setSearchService:service]; [session setSearchMode:@"fuzzy"];
    Search(session, @"z");
    Check([[session matchKindAtIndex:0] isEqual:@"fuzzy"], "continuation fixture uses a source match and the production position channel");
    return session;
}
static void ContinuationTeardown(BOOL libraryReplacement) {
    @autoreleasepool {
        NSString *body = LongBody();
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[Note(@"title", body)]] autorelease];
        ContinuationService *service = [[[ContinuationService alloc] init] autorelease]; Capture(service, library);
        OwnerState oldState = {0}, peerState = {0}, replacementState = {0};
        WatchedSession *session = Session(library, service, &oldState);
        WatchedSession *peer = Session(library, service, &peerState);
        NSUInteger peerRequestID = [[peer searchResult] requestID];
        __block NSUInteger oldCallbacks = 0, peerCallbacks = 0, replacementCallbacks = 0;
        [service armSecondBatch];
        @autoreleasepool {
            [session requestSourceHighlightsForRow:0 completion:^(NSArray *ranges, NSString *source) { oldCallbacks++; }];
        }
        [service waitForSecondBatch];
        Check(service.batchCount == 2, "teardown begins after a real position mapping batch yielded");
        @autoreleasepool {
            if (libraryReplacement) [service invalidate];
            [session setDelegate:nil]; [session release]; session = nil;
            if (libraryReplacement) { [peer setDelegate:nil]; [peer release]; peer = nil; }
        }
        Check(atomic_load(&oldState.released) && atomic_load(&oldState.main), "canceled continuation releases the production browser on main before the worker resumes");
        if (libraryReplacement) {
            Check(atomic_load(&peerState.released) && atomic_load(&peerState.main), "library invalidation permits both old browsers to close before queued work finishes");
        } else {
            Check(!atomic_load(&peerState.released), "closing one owner does not dispose its peer browser");
            Check([service isRequestCurrent:peerRequestID forOwner:peer], "owner cancellation preserves the peer result identity");
            [peer requestSourceHighlightsForRow:0 completion:^(NSArray *ranges, NSString *source) {
                Check(ranges.count == 1 && [[ranges firstObject] rangeValue].location == body.length-1, "surviving peer receives its complete source position");
                peerCallbacks++;
            }];
        }
        // The old worker remains paused while a new library service works.
        TestLibrary *replacementLibrary = [[[TestLibrary alloc] initWithNotes:@[Note(@"replacement", @"z replacement")]] autorelease];
        NVSearchService *replacementService = [[[NVSearchService alloc] init] autorelease]; Capture(replacementService, replacementLibrary);
        WatchedSession *replacement = Session(replacementLibrary, replacementService, &replacementState);
        [replacement requestSourceHighlightsForRow:0 completion:^(NSArray *ranges, NSString *source) {
            Check(ranges.count == 1 && [source isEqual:@"z replacement"], "replacement library publishes only its own immutable source");
            replacementCallbacks++;
        }];
        Check(Spin(^BOOL { return replacementCallbacks == 1; }), "independent library publishes while the old continuation stays paused");
        Check(oldCallbacks == 0 && peerCallbacks == 0, "paused or canceled old work delivers no callback into the replacement library");
        [service resumeAndDrain];
        if (!libraryReplacement) Check(Spin(^BOOL { return peerCallbacks == 1; }), "peer position request completes after the closed owner's continuation resumes");
        Check(oldCallbacks == 0 && replacementCallbacks == 1, "old continuation never publishes after teardown or duplicates new-library delivery");
        if (peer) { [peer setDelegate:nil]; [peer release]; }
        [replacement setDelegate:nil]; [replacement release];
        Check(atomic_load(&replacementState.released) && atomic_load(&replacementState.main), "replacement browser closes on main independently");
        [service invalidate]; [replacementService invalidate];
        printf("PASS yielded continuation teardown: %s\n", libraryReplacement ? "library replacement" : "single owner close");
    }
}

static void SuccessfulContinuationOwner(void) {
    @autoreleasepool {
        NSString *body = LongBody();
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[Note(@"title", body)]] autorelease];
        ContinuationService *service = [[[ContinuationService alloc] init] autorelease]; Capture(service, library);
        OwnerState state = {0}; OwnerState *statePointer = &state;
        WatchedOwner *owner = [[WatchedOwner alloc] init]; owner->state = &state; owner->service = service;
        NSUInteger requestID = Seed(service, owner, @"z");
        NSData *uuid = UUID([[library allNotes] firstObject]);
        __block NSUInteger callbacks = 0;
        [service armSecondBatch];
        @autoreleasepool {
            [service requestPositionsForNoteUUID:uuid requestID:requestID owner:owner completion:^(NVSearchPositions *positions, NSError *error) {
                Check([NSThread isMainThread] && !error, "resumed position callback arrives successfully on main");
                Check(!atomic_load(&statePointer->released) && owner->state == statePointer, "successful mapping callback still owns its caller during invocation");
                Check(positions.sourceRanges.count == 1 && [[[positions sourceRanges] firstObject] rangeValue].location == body.length-1,
                      "resumed position work preserves the terminal source coordinate");
                callbacks++;
            }];
            [owner release]; owner = nil;
        }
        [service waitForSecondBatch];
        Check(!atomic_load(&state.released), "pending successful callback retains its captured owner between mapping batches");
        [service resumeAndDrain];
        Check(Spin(^BOOL { return atomic_load(&statePointer->released); }), "completed continuation releases its callback owner");
        Check(atomic_load(&state.main) && callbacks == 1, "successful continuation disposes its sole captured owner on main exactly once");
        Check(service.batchCount > 2, "successful mapping runs additional native continuations after the gate");
        [service invalidate];
        printf("PASS successful continuation ownership: %lu batches\n", (unsigned long)service.batchCount);
    }
}

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        for (NSString *channel in @[@"search", @"cached-search", @"positions", @"literal"]) SuccessfulReentry(channel);
        ContinuationTeardown(NO);
        ContinuationTeardown(YES);
        SuccessfulContinuationOwner();
        printf("PASS: %lu round-three ownership and API checks\n", (unsigned long)Checks);
    }
    return 0;
}
