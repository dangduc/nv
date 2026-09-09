#import <Foundation/Foundation.h>
#import "NVSearchService.h"
#include <stdatomic.h>

static NSUInteger checks;
static void Check(BOOL value, const char *label) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    return condition();
}
static NSData *UUID(unsigned char number) {
    unsigned char bytes[16] = {0}; bytes[15] = number;
    return [NSData dataWithBytes:bytes length:16];
}
static NVSearchNoteSnapshot *Snapshot(unsigned char number, NSString *title, NSString *tags, NSString *source) {
    return [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(number) title:title tags:tags source:source revision:1] autorelease];
}
static NVSearchResult *Run(NVSearchService *service, id owner, NSString *query) {
    __block BOOL done = NO;
    __block NVSearchResult *result = nil;
    [service requestForOwner:owner query:query completion:^(NVSearchResult *r, NSError *error) {
        Check(error == nil && r != nil, "production service returns a complete result");
        Check([NSThread isMainThread], "completion belongs to the main thread");
        result = [r retain]; done = YES;
    }];
    Check(!done, "completion is deferred");
    Check(Await(^BOOL { return done; }), "completion arrives within five seconds");
    return [result autorelease];
}

static _Atomic unsigned releasedTokens, releasedServices, releasedSnapshots;
@interface LifetimeToken : NSObject @end
@implementation LifetimeToken
- (void)dealloc { atomic_fetch_add(&releasedTokens, 1); [super dealloc]; }
@end
@interface TrackedService : NVSearchService @end
@implementation TrackedService
- (void)dealloc { [super dealloc]; atomic_fetch_add(&releasedServices, 1); }
@end
@interface TrackedSnapshot : NVSearchNoteSnapshot @end
@implementation TrackedSnapshot
- (void)dealloc { [super dealloc]; atomic_fetch_add(&releasedSnapshots, 1); }
@end

// This snapshot pauses only at the production service's preparation boundary.
// The superclass still constructs all bytes, and production fzf scores them.
@interface PausedSnapshot : NVSearchNoteSnapshot {
@public dispatch_semaphore_t entered, proceed; BOOL paused;
}
@end
@implementation PausedSnapshot
- (id)initWithNoteUUID:(NSData *)uuid title:(NSString *)title tags:(NSString *)tags source:(NSString *)source revision:(NSUInteger)revision {
    if ((self = [super initWithNoteUUID:uuid title:title tags:tags source:source revision:revision])) {
        entered = dispatch_semaphore_create(0); proceed = dispatch_semaphore_create(0);
    }
    return self;
}
- (NSData *)preparedUTF8WithCancellation:(NVFZFCancel *)cancel status:(NVFZFStatus *)status {
    if (!paused) {
        paused = YES; dispatch_semaphore_signal(entered);
        if (dispatch_semaphore_wait(proceed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) abort();
    }
    return [super preparedUTF8WithCancellation:cancel status:status];
}
- (void)dealloc { dispatch_release(entered); dispatch_release(proceed); [super dealloc]; }
@end

@interface ReentrantOwner : NSObject {
@public NVSearchService *service; NSUInteger callbacks, firstRequest; BOOL failed, invoking;
}
- (void)submit;
@end
@implementation ReentrantOwner
- (void)submit {
    invoking = YES;
    NSUInteger request = [service requestForOwner:self query:@"road" completion:^(NVSearchResult *result, NSError *error) {
        failed |= invoking || error != nil || [result requestID] != firstRequest;
        callbacks++;
        if (callbacks < 50) [self submit];
    }];
    if (!firstRequest) firstRequest = request;
    failed |= firstRequest != request;
    invoking = NO;
}
@end

static void TestReuseAndReentrancy(void) {
    NVSearchService *service = [[NVSearchService alloc] init];
    NSObject *owner = [[NSObject alloc] init];
    PausedSnapshot *snapshot = [[PausedSnapshot alloc] initWithNoteUUID:UUID(1) title:@"road" tags:@"" source:@"body road" revision:1];
    [service synchronizeWithSnapshots:@[snapshot]];
    __block NSUInteger firstCallbacks = 0, replacementCallbacks = 0;
    NSUInteger first = [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *r, NSError *e) { firstCallbacks++; }];
    Check(dispatch_semaphore_wait(snapshot->entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, "worker reaches controlled preparation boundary");
    NSUInteger replacement = [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *r, NSError *e) {
        Check(r != nil && !e, "replacement completion receives a complete native result"); replacementCallbacks++;
    }];
    Check(first == replacement, "identical pending work reuses request identity");
    dispatch_semaphore_signal(snapshot->proceed);
    Check(Await(^BOOL { return replacementCallbacks == 1; }), "replacement callback completes");
    Check(firstCallbacks == 0, "replaced pending callback never runs");
    NVSearchResult *cached = Run(service, owner, @"road");
    Check(cached.requestID == first, "completed work retains request identity");
    Check(cached.titleNoteUUIDs.count == 1 && cached.fuzzyNoteUUIDs.count == 1, "reused work preserves both overlapping groups");
    ReentrantOwner *reentrant = [[ReentrantOwner alloc] init]; reentrant->service = service;
    [reentrant submit];
    Check(Await(^BOOL { return reentrant->callbacks == 50; }), "fifty callback-originated requests all complete");
    Check(!reentrant->failed, "callback reentrancy stays deferred and reuses identity");
    [service cancelRequestsForOwner:reentrant]; [reentrant release];
    __block BOOL revised = NO;
    [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *r, NSError *e) {
        NSUInteger old = r.requestID;
        [service updateSnapshot:Snapshot(1, @"changed", @"", @"fresh")];
        Check(![service isRequestCurrent:old forOwner:owner], "callback mutation invalidates its request synchronously");
        [service requestForOwner:owner query:@"fresh" completion:^(NVSearchResult *newResult, NSError *error) {
            Check(!error && [newResult.fuzzyNoteUUIDs isEqual:@[UUID(1)]], "callback mutation publishes fresh source"); revised = YES;
        }];
    }];
    Check(Await(^BOOL { return revised; }), "request submitted inside mutation callback completes");
    [service cancelRequestsForOwner:owner]; [service invalidate];
    [snapshot release]; [owner release]; [service release];
}

static void TestInvalidationAndPositions(void) {
    NVSearchService *service = [[NVSearchService alloc] init];
    NSObject *owner = [[NSObject alloc] init], *peer = [[NSObject alloc] init];
    NSObject *source = [[NSObject alloc] init], *excerpt = [[NSObject alloc] init];
    [service synchronizeWithSnapshots:@[Snapshot(1, @"road", @"blue", @"body road"), Snapshot(2, @"other", @"", @"road")]];
    for (NSUInteger dimension = 0; dimension < 3; dimension++) {
        NVSearchResult *result = Run(service, owner, @"road");
        NVSearchNoteSnapshot *current = [service snapshotForUUID:UUID(1)];
        NSUInteger revision = service.corpusRevision;
        NVSearchNoteSnapshot *same = [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(1) title:current.title tags:current.tags source:current.source revision:999] autorelease];
        Check(![service updateSnapshot:same] && service.corpusRevision == revision, "equal committed strings preserve corpus identity");
        Check([service isRequestCurrent:result.requestID forOwner:owner], "equal committed strings preserve displayed work");
        NVSearchNoteSnapshot *changed = Snapshot(1, dimension == 0 ? @"road renamed" : current.title,
            dimension == 1 ? @"green" : current.tags, dimension == 2 ? @"road changed body" : current.source);
        Check([service updateSnapshot:changed], "title, tags, or source mutation changes corpus identity");
        Check(![service isRequestCurrent:result.requestID forOwner:owner], "each searchable dimension cancels old identity synchronously");
    }
    NVSearchResult *result = Run(service, owner, @"road");
    NVSearchResult *peerResult = Run(service, peer, @"road");
    __block BOOL oldSource = NO, currentSource = NO, excerptDone = NO, peerDone = NO;
    [service requestPositionsForNoteUUID:UUID(1) requestID:result.requestID owner:owner positionOwner:source completion:^(NVSearchPositions *p, NSError *e) { oldSource = YES; }];
    [service requestPositionsForNoteUUID:UUID(2) requestID:result.requestID owner:owner positionOwner:source completion:^(NVSearchPositions *p, NSError *e) { currentSource = p != nil && !e && [p.snapshot.noteUUID isEqual:UUID(2)]; }];
    [service requestPositionsForNoteUUID:UUID(1) requestID:result.requestID owner:owner positionOwner:excerpt completion:^(NVSearchPositions *p, NSError *e) { excerptDone = p != nil && !e; }];
    [service requestPositionsForNoteUUID:UUID(2) requestID:peerResult.requestID owner:peer completion:^(NVSearchPositions *p, NSError *e) { peerDone = p != nil && !e; }];
    Check(Await(^BOOL { return currentSource && excerptDone && peerDone; }), "replacement positions and independent owners complete");
    Check(!oldSource, "position replacement suppresses old callback");
    __block BOOL removedSource = NO, removedExcerpt = NO;
    [service requestPositionsForNoteUUID:UUID(1) requestID:result.requestID owner:owner positionOwner:source completion:^(NVSearchPositions *p, NSError *e) { removedSource = YES; }];
    [service requestPositionsForNoteUUID:UUID(1) requestID:result.requestID owner:owner positionOwner:excerpt completion:^(NVSearchPositions *p, NSError *e) { removedExcerpt = YES; }];
    [service cancelRequestsForOwner:owner];
    Check([service isRequestCurrent:peerResult.requestID forOwner:peer], "browser cancellation preserves peer request identity");
    Run(service, peer, @"other");
    Check(!removedSource && !removedExcerpt, "browser cancellation also suppresses both position channels");
    [service cancelRequestsForOwner:peer]; [service invalidate];
    [source release]; [excerpt release]; [peer release]; [owner release]; [service release];
}

static void TestReplacementAndRelease(void) {
    unsigned tokensBefore = atomic_load(&releasedTokens), servicesBefore = atomic_load(&releasedServices), snapshotsBefore = atomic_load(&releasedSnapshots);
    @autoreleasepool {
        TrackedService *oldService = [[TrackedService alloc] init];
        NSObject *owner = [[NSObject alloc] init];
        TrackedSnapshot *snapshot = [[TrackedSnapshot alloc] initWithNoteUUID:UUID(7) title:@"old road" tags:@"" source:@"old source" revision:1];
        [oldService synchronizeWithSnapshots:@[snapshot]]; [snapshot release];
        LifetimeToken *token = [[LifetimeToken alloc] init];
        [oldService requestForOwner:owner query:@"road" completion:^(NVSearchResult *r, NSError *e) {
            (void)[token description]; Check(NO, "replaced library must never publish");
        }];
        [token release];
        [oldService invalidate]; [oldService release];
        NVSearchService *newService = [[NVSearchService alloc] init];
        [newService synchronizeWithSnapshots:@[Snapshot(7, @"new road", @"", @"new source")]];
        NVSearchResult *result = Run(newService, owner, @"road");
        Check([[result snapshotForUUID:UUID(7)].source isEqual:@"new source"], "reused UUID in new library resolves its new immutable version");
        [newService cancelRequestsForOwner:owner]; [newService invalidate]; [newService release]; [owner release];
    }
    Check(Await(^BOOL { return atomic_load(&releasedServices) == servicesBefore + 1; }), "cancelled service releases without a worker join");
    Check(atomic_load(&releasedTokens) == tokensBefore + 1, "cancelled work releases its captured callback owner");
    Check(atomic_load(&releasedSnapshots) == snapshotsBefore + 1, "cancelled library releases obsolete immutable snapshots");
}

int main(void) {
    @autoreleasepool {
        TestReuseAndReentrancy();
        TestInvalidationAndPositions();
        TestReplacementAndRelease();
        printf("OWNERSHIP REVIEW: %lu checks passed\n", (unsigned long)checks);
    }
    return 0;
}
