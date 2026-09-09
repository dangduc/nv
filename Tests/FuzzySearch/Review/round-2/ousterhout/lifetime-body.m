#include <stdatomic.h>
static _Atomic BOOL SessionReleased, SessionReleasedOnMain;
@interface TrackedBrowserSession : NVBrowserSession @end
@implementation TrackedBrowserSession
- (void)dealloc {
    atomic_store(&SessionReleasedOnMain, [NSThread isMainThread]);
    atomic_store(&SessionReleased, YES);
    fprintf(stdout, "SESSION DEALLOC: main=%d\n", [NSThread isMainThread]);
    [super dealloc];
}
@end
@interface GatedSearchService : NVSearchService {
    dispatch_semaphore_t entered, proceed;
}
- (void)pauseWorker;
- (void)resumeWorker;
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
- (void)resumeWorker { dispatch_semaphore_signal(proceed); }
- (void)dealloc { dispatch_release(entered); dispatch_release(proceed); [super dealloc]; }
@end
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"search";
        NoteObject *note = Note(@"title", @"road body");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[note]] autorelease];
        GatedSearchService *service = [[[GatedSearchService alloc] init] autorelease]; Capture(service, library);
        @autoreleasepool {
            TrackedBrowserSession *session = [[TrackedBrowserSession alloc] initWithLibrary:(id)library];
            [session setSearchService:service]; [session setSearchMode:@"fuzzy"];
            if ([mode isEqual:@"positions"]) Search(session, @"road");
            [service pauseWorker];
            @autoreleasepool {
                if ([mode isEqual:@"search"]) [session filterNotesFromString:@"road"];
                else if ([mode isEqual:@"positions"]) [session requestSourceHighlightsForRow:0 completion:^(NSArray *ranges, NSString *source) { Check(NO, "closed position owner must not receive a callback"); }];
                else [service requestLiteralRangesInSource:@"road body" query:@"road" owner:session completion:^(NSArray *ranges, NSString *source, NSError *error) { (void)[session description]; Check(NO, "closed literal owner must not receive a callback"); }];
                // AppController dealloc uses these same session teardown calls.
                [session setDelegate:nil];
                [session release];
            }
        }
        fprintf(stdout, "CANCELLED %s: released_before_worker=%d\n", mode.UTF8String, atomic_load(&SessionReleased));
        [service resumeWorker];
        Check(Spin(^BOOL { return atomic_load(&SessionReleased); }), "cancelled session is released");
        Check(atomic_load(&SessionReleasedOnMain), "cancelled browser session must be destroyed on main");
        [service invalidate];
        printf("LIFETIME CHECK PASSED: %s\n", mode.UTF8String);
    }
    return 0;
}
