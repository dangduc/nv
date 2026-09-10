#import <Foundation/Foundation.h>
#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
#include <libproc.h>
#include <sys/resource.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(2); }
}
static double Now(void) { return [[NSProcessInfo processInfo] systemUptime] * 1000.0; }
static void Pump(BOOL (^done)(void), double limit) {
    double deadline = Now() + limit;
    while (!done() && Now() < deadline)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    Check(done(), @"request reaches the expected state before the probe deadline");
}
@interface Ticker : NSObject { @public double last, largestGap; NSUInteger ticks; }
@end
@implementation Ticker
- (void)tick:(NSTimer *)timer { double now = Now(); if (last) largestGap = MAX(largestGap, now - last); last = now; ticks++; }
@end
static pid_t HelperPID(void) {
    pid_t pids[32] = {0};
    int bytes = proc_listpids(PROC_PPID_ONLY, getpid(), pids, sizeof(pids));
    for (int i = 0; i < bytes / (int)sizeof(pid_t); i++) {
        char name[128] = {0};
        if (pids[i] > 0 && proc_name(pids[i], name, sizeof(name)) > 0 && !strcmp(name, "nv-org-preview")) return pids[i];
    }
    return 0;
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSBundle *bundle = [NSBundle bundleWithPath:@(argv[1])];
    NSString *mode = @(argv[3]);
    NSMutableString *source = [NSMutableString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:NULL];
    Check(bundle && source, @"read the app resource bundle and disposable Org journal");
    if ([mode isEqual:@"input-limit"]) [source setString:[@"" stringByPaddingToLength:16 * 1024 * 1024 + 1 withString:@"ordinary prose " startingAtIndex:0]];
    NVMarkupRenderer *renderer = [[NVMarkupRenderer alloc] initWithResourceBundle:bundle];
    if ([mode isEqual:@"timeout"]) [renderer setTimeLimit:.05];
    NSUInteger trials = [mode isEqual:@"render"] ? 3 : 1;
    for (NSUInteger trial = 0; trial < trials; trial++) { @autoreleasepool {
        Ticker *ticker = [[Ticker alloc] init];
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:.005 target:ticker selector:@selector(tick:) userInfo:nil repeats:YES];
        __block NSUInteger callbacks = 0;
        __block NSError *failure = nil;
        __block NVMarkupRenderResult *result = nil;
        __block double callbackAt = 0;
        double started = Now();
        NVNoteContentSnapshot *snapshot = [[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"luu-review" noteIdentifier:@"journal" generation:trial title:@"Org journal" source:source contentType:@"public.plain-text" assetRootURL:nil];
        double copied = Now();
        NSOperation *operation = [[renderer renderSnapshot:snapshot viewerIdentifier:@"org" completion:^(NVMarkupRenderResult *value, NSError *error) {
            Check([NSThread isMainThread], @"completion runs on the main thread");
            callbacks++; result = [value retain]; failure = [error retain]; callbackAt = Now();
        }] retain];
        double submitted = Now();
        __block pid_t child = 0; double cancelledAt = 0;
        if ([mode isEqual:@"cancel"]) {
            Pump(^BOOL{ child = HelperPID(); return child != 0 || callbacks > 0; }, 3000);
            Check(child > 0 && callbacks == 0 && [operation isExecuting], @"an actual converter child is active before cancellation");
            cancelledAt = Now(); [operation cancel];
        }
        Pump(^BOOL{ return callbacks > 0 && [operation isFinished]; }, 15000);
        if ([mode isEqual:@"render"]) {
            Check(result && !failure, @"ordinary journal renders successfully");
            Check([[result HTML] containsString:@"END_OF_NOTE_SENTINEL"] && [[result HTML] containsString:@"Café 日本語 👩‍💻"], @"complete output retains its final text and Unicode");
            Check([[snapshot source] isEqual:source], @"preview preserves the source snapshot");
        } else {
            NVMarkupRendererErrorCode expected = [mode isEqual:@"cancel"] ? NVMarkupCancelled : [mode isEqual:@"timeout"] ? NVMarkupTimedOut : NVMarkupLimitExceeded;
            Check(!result && [failure code] == expected, @"cancellation or limit returns the matching structured error");
        }
        if (child > 0) {
            Pump(^BOOL{ errno = 0; return kill(child, 0) < 0 && errno == ESRCH; }, 2000);
        }
        double finished = Now();
        // Drain the main queue after worker completion to reject duplicate callbacks.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:.025];
        while ([until timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
        Check(callbacks == 1, @"each request produces exactly one completion");
        [timer invalidate];
        struct rusage usage; getrusage(RUSAGE_SELF, &usage);
        printf("mode=%s trial=%lu input_bytes=%lu snapshot_ms=%.3f submit_ms=%.3f callback_ms=%.3f worker_finished_ms=%.3f timer_ticks=%lu largest_timer_gap_ms=%.3f parent_max_rss_bytes=%ld output_utf8_bytes=%lu error=%ld",
            [mode UTF8String], trial, [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding], copied - started, submitted - copied,
            callbackAt - started, finished - started, ticker->ticks, ticker->largestGap, usage.ru_maxrss,
            [[result HTML] lengthOfBytesUsingEncoding:NSUTF8StringEncoding], (long)[failure code]);
        if (cancelledAt) printf(" cancel_callback_ms=%.3f cancel_cleanup_ms=%.3f child_pid=%d", callbackAt - cancelledAt, finished - cancelledAt, child);
        printf("\n"); fflush(stdout);
        [operation release]; [snapshot release]; [result release]; [failure release]; [ticker release];
    } }
    [renderer release];
    printf("PASS: %lu focused renderer checks\n", (unsigned long)checks);
} return 0; }
