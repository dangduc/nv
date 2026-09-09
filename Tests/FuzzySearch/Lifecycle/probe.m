#include <stdatomic.h>
static _Atomic BOOL SessionReleased, SessionReleasedOnMain;
@interface TrackedBrowserSession : NVBrowserSession @end
@implementation TrackedBrowserSession
- (void)dealloc {
    atomic_store(&SessionReleasedOnMain, [NSThread isMainThread]);
    atomic_store(&SessionReleased, YES);
    [super dealloc];
}
@end
@interface GatedSearchService : NVSearchService { dispatch_semaphore_t entered, proceed; }
- (void)pauseWorker;
- (void)resumeAndDrain;
@end
@implementation GatedSearchService
- (id)init { if ((self = [super init])) { entered = dispatch_semaphore_create(0); proceed = dispatch_semaphore_create(0); } return self; }
- (void)pauseWorker {
    dispatch_async(_worker, ^{
        dispatch_semaphore_signal(entered);
        if (dispatch_semaphore_wait(proceed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) abort();
    });
    Check(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, "worker gate entered");
}
- (void)resumeAndDrain {
    __block BOOL drained = NO;
    dispatch_semaphore_signal(proceed);
    dispatch_async(_worker, ^{ dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; }); });
    Check(Spin(^BOOL { return drained; }), "worker queue drained");
}
- (void)dealloc { dispatch_release(entered); dispatch_release(proceed); [super dealloc]; }
@end

typedef struct { BOOL released, releasedOnMain; NSUInteger callbacks; } LifetimeState;
@interface CallbackCapture : NSObject { @public LifetimeState *state; void (^onRelease)(void); }
@end
@implementation CallbackCapture
- (void)dealloc {
    state->released = YES; state->releasedOnMain = [NSThread isMainThread];
    if (onRelease) onRelease();
    [onRelease release]; [super dealloc];
}
@end

static void SessionTeardown(NSString *channel) {
    atomic_store(&SessionReleased, NO); atomic_store(&SessionReleasedOnMain, NO);
    @autoreleasepool {
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[Note(@"title", @"road body")]] autorelease];
        GatedSearchService *service = [[[GatedSearchService alloc] init] autorelease]; Capture(service, library);
        @autoreleasepool {
            TrackedBrowserSession *session = [[TrackedBrowserSession alloc] initWithLibrary:(id)library];
            [session setSearchService:service]; [session setSearchMode:@"fuzzy"];
            if ([channel isEqual:@"positions"]) Search(session, @"road");
            [service pauseWorker];
            @autoreleasepool {
                if ([channel isEqual:@"search"]) [session filterNotesFromString:@"road"];
                else if ([channel isEqual:@"positions"]) [session requestSourceHighlightsForRow:0 completion:^(NSArray *ranges, NSString *source) { Check(NO, "closed position owner must not receive a callback"); }];
                else [service requestLiteralRangesInSource:@"road body" query:@"road" owner:session completion:^(NSArray *ranges, NSString *source, NSError *error) { (void)[session description]; Check(NO, "closed literal owner must not receive a callback"); }];
                [session setDelegate:nil]; [session release];
            }
        }
        Check(atomic_load(&SessionReleased), "production session is disposed before worker resumes");
        Check(atomic_load(&SessionReleasedOnMain), "production session is disposed on main");
        [service resumeAndDrain]; [service invalidate];
        printf("PASS production session teardown: %s\n", channel.UTF8String);
    }
}

static void CallbackLifetime(NSString *channel, NSString *action) {
    @autoreleasepool {
        NoteObject *note = Note(@"title", @"road body");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[note]] autorelease];
        GatedSearchService *service = [[[GatedSearchService alloc] init] autorelease]; Capture(service, library);
        NSObject *owner = [[[NSObject alloc] init] autorelease], *positionOwner = [[[NSObject alloc] init] autorelease];
        NSData *uuid = [NSData dataWithBytes:[note uniqueNoteIDBytes] length:16];
        __block NSUInteger requestID = 0; __block BOOL seeded = NO, replacementCompleted = NO;
        if ([channel isEqual:@"positions"]) {
            requestID = [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *result, NSError *error) { Check(result && !error, "position source search succeeds"); seeded = YES; }];
            Check(Spin(^BOOL { return seeded; }), "position source search completes");
        }
        [service pauseWorker];
        LifetimeState state = {0}; LifetimeState *statePointer = &state;
        @autoreleasepool {
            CallbackCapture *capture = [[CallbackCapture alloc] init]; capture->state = &state;
            if ([action hasPrefix:@"reentrant"]) capture->onRelease = [^{
                requestID = [service requestForOwner:owner query:@"body" completion:^(NVSearchResult *result, NSError *error) { Check(result && !error, "reentrant replacement succeeds"); replacementCompleted = YES; }];
            } copy];
            if ([channel isEqual:@"search"]) requestID = [service requestForOwner:owner query:@"road" completion:^(NVSearchResult *result, NSError *error) { Check([NSThread isMainThread] && result && !error, "search success is on main"); capture->state->callbacks++; }];
            else if ([channel isEqual:@"positions"]) [service requestPositionsForNoteUUID:uuid requestID:requestID owner:owner positionOwner:positionOwner completion:^(NVSearchPositions *positions, NSError *error) { Check([NSThread isMainThread] && positions && !error, "position success is on main"); capture->state->callbacks++; }];
            else [service requestLiteralRangesInSource:@"road body" query:@"road" owner:owner completion:^(NSArray *ranges, NSString *source, NSError *error) { Check([NSThread isMainThread] && [ranges count] && !error, "literal success is on main"); capture->state->callbacks++; }];
            [capture release];
            if ([action isEqual:@"all"] || [action isEqual:@"reentrant-all"]) [service invalidate];
            else if ([action isEqual:@"update"]) {
                [note setTitleString:@"changed"]; Capture(service, library);
            } else if ([action isEqual:@"upsert"]) {
                [service updateSnapshot:[[[NVSearchNoteSnapshot alloc] initWithNoteUUID:uuid title:@"changed" tags:@"" source:@"road body" revision:100] autorelease]];
            } else if ([action isEqual:@"remove"]) [service removeUUID:uuid];
            else if ([action isEqual:@"replace"] || [action isEqual:@"same"] || [action isEqual:@"reentrant-replace"] || [action isEqual:@"reentrant-same"]) {
                if ([channel isEqual:@"search"]) [service requestForOwner:owner query:([action hasSuffix:@"same"] ? @"road" : @"body") completion:nil];
                else if ([channel isEqual:@"positions"]) [service requestPositionsForNoteUUID:uuid requestID:requestID owner:owner positionOwner:positionOwner completion:nil];
                else [service requestLiteralRangesInSource:@"body" query:@"body" owner:owner completion:nil];
            } else if ([action isEqual:@"channel"]) {
                if ([channel isEqual:@"positions"]) [service cancelPositionRequestsForOwner:positionOwner];
                else [service cancelLiteralRangesForOwner:owner];
            } else if (![action isEqual:@"success"]) [service cancelRequestsForOwner:owner];
        }
        BOOL success = [action isEqual:@"success"];
        if (!success) {
            Check(state.released, "cancel or replacement disposes callback capture before worker resumes");
            Check(state.releasedOnMain, "cancel or replacement disposes callback capture on main");
        }
        if ([action hasPrefix:@"reentrant"]) Check([service isRequestCurrent:requestID forOwner:owner], "reentrant submission survives outer cancellation");
        [service resumeAndDrain];
        if (success) {
            Check(Spin(^BOOL { return statePointer->released; }), "successful completion disposes callback capture");
            Check(state.releasedOnMain && state.callbacks == 1, "successful callback and capture disposal stay on main");
        } else Check(state.callbacks == 0, "cancelled callback never fires");
        if ([action hasPrefix:@"reentrant"]) Check(Spin(^BOOL { return replacementCompleted; }), "reentrant replacement publishes");
        [service invalidate];
        printf("PASS callback lifetime: %s / %s\n", channel.UTF8String, action.UTF8String);
    }
}
int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        for (NSString *channel in @[@"search", @"positions", @"literal"]) {
            SessionTeardown(channel);
            for (NSString *action in @[@"owner", @"all", @"update", @"upsert", @"remove", @"replace", @"reentrant", @"reentrant-all", @"reentrant-replace", @"success"]) CallbackLifetime(channel, action);
            CallbackLifetime(channel, [channel isEqual:@"search"] ? @"same" : @"channel");
            if ([channel isEqual:@"search"]) CallbackLifetime(channel, @"reentrant-same");
        }
        printf("PASS: %lu lifecycle checks\n", (unsigned long)Checks);
    }
    return 0;
}
