#import <Foundation/Foundation.h>
#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
#include <libproc.h>
#include <sys/resource.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
static NSUInteger checks;
static double Now(void) { return [[NSProcessInfo processInfo] systemUptime] * 1000; }
static void Check(BOOL result, NSString *message) { checks++; if (!result) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(2); } }
static void Pump(BOOL (^done)(void)) {
    double until = Now() + 10000;
    while (!done() && Now() < until) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    Check(done(), @"operation reaches its expected state");
}
static pid_t Child(void) {
    pid_t pids[32] = {0}; int count = proc_listpids(PROC_PPID_ONLY, getpid(), pids, sizeof(pids));
    for (int i = 0; i < count / sizeof(pid_t); i++) {
        char name[128] = {0};
        if (pids[i] > 0 && proc_name(pids[i], name, sizeof(name)) > 0 && !strcmp(name, "nv-org-preview")) return pids[i];
    }
    return 0;
}
static NVNoteContentSnapshot *Snapshot(NSString *source, NSUInteger generation) {
    return [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"luu-r2" noteIdentifier:@"same-note" generation:generation title:@"Heading references" source:source contentType:@"public.plain-text" assetRootURL:nil] autorelease];
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *source = [NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:NULL];
    NVMarkupRenderer *renderer = [[NVMarkupRenderer alloc] initWithResourceBundle:[NSBundle bundleWithPath:@(argv[1])]];
    BOOL replace = [@(argv[4]) isEqual:@"replace"];
    NVNoteContentSnapshot *snapshot = Snapshot(source, 1);
    __block NSUInteger callbacks = 0, newerCallbacks = 0;
    __block NVMarkupRenderResult *result = nil;
    __block NSError *error = nil;
    __block double callbackTime = 0;
    double started = Now();
    NSOperation *old = [[renderer renderSnapshot:snapshot viewerIdentifier:@"org" completion:^(NVMarkupRenderResult *value, NSError *failure) {
        Check([NSThread isMainThread], @"completion uses main thread"); callbacks++; callbackTime = Now();
        result = [value retain]; error = [failure retain];
    }] retain];
    double submitted = Now();
    __block pid_t child = 0;
    double cancelledAt = 0;
    NSOperation *newer = nil;
    NVNoteContentSnapshot *newSnapshot = nil;
    if (replace) {
        Pump(^BOOL{ child = Child(); return child > 0 || callbacks > 0; });
        Check(child > 0 && callbacks == 0, @"cancel only after the old converter is active");
        cancelledAt = Now(); [old cancel];
        newSnapshot = Snapshot(@"* TODO New revision\n:PROPERTIES:\n:CUSTOM_ID: newest\n:END:\n[[*New revision][newest-link]]\nEND_OF_NOTE_SENTINEL\n", 2);
        newer = [[renderer renderSnapshot:newSnapshot viewerIdentifier:@"org" completion:^(NVMarkupRenderResult *value, NSError *failure) {
            Check([NSThread isMainThread], @"newer completion uses main thread"); newerCallbacks++;
            Check(value && !failure && [value snapshot] == newSnapshot && [[[value snapshot] source] isEqual:[newSnapshot source]], @"newer result retains its own source and request identity");
            Check([[[value snapshot] source] containsString:@"New revision"] && ![[value HTML] containsString:@"ref-"], @"newer preview contains no stale reference labels");
            Check([[value HTML] writeToFile:@(argv[3]) atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"save newer output for independent link oracle");
        }] retain];
    }
    Pump(^BOOL{ return callbacks > 0 && [old isFinished] && (!replace || (newerCallbacks > 0 && [newer isFinished])); });
    if (replace) {
        Check(!result && [error code] == NVMarkupCancelled, @"old request returns cancellation without HTML");
        Pump(^BOOL{ errno = 0; return kill(child, 0) < 0 && errno == ESRCH; });
    } else {
        Check(result && !error && [result snapshot] == snapshot, @"ordinary indexed document renders with matching identity");
        Check([[result HTML] writeToFile:@(argv[3]) atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"save actual renderer output for independent link oracle");
    }
    double finished = Now();
    NSDate *drain = [NSDate dateWithTimeIntervalSinceNow:.03];
    while ([drain timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:drain];
    Check(callbacks == 1 && (!replace || newerCallbacks == 1), @"each request completes exactly once");
    Check([[snapshot source] isEqual:source], @"source snapshot remains unchanged");
    struct rusage usage; getrusage(RUSAGE_SELF, &usage);
    printf("mode=%s input_bytes=%lu submit_ms=%.3f callback_ms=%.3f completion_ms=%.3f parent_max_rss_bytes=%ld",
        replace ? "replace" : "render", [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding], submitted - started, callbackTime - started, finished - started, usage.ru_maxrss);
    if (replace) printf(" cancel_callback_ms=%.3f replacement_and_cleanup_ms=%.3f", callbackTime - cancelledAt, finished - cancelledAt);
    printf("\nPASS: %lu actual renderer and cancellation checks\n", checks);
    [newer release]; [old release]; [result release]; [error release]; [renderer release];
} return 0; }
