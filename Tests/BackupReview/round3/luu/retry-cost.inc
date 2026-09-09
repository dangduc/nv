
#include <libproc.h>
#include <sys/resource.h>
#include <time.h>

static NVApplicationController *activeApp;
static const NSUInteger retryLimit = 256;
static NSUInteger firstPanelFDs, opensAtFirstPanel, checkpointsAtFirstPanel;
static NSUInteger blockedReturnChecks;
static long firstPanelRSS, lastPanelRSS;

static NSUInteger OpenFDCount(void) {
    struct proc_fdinfo entries[256];
    int bytes = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, entries, sizeof(entries));
    Check(bytes > 0 && bytes < sizeof(entries), @"descriptor fixture has a bounded complete inventory");
    return (NSUInteger)bytes / sizeof(entries[0]);
}
static long PeakRSS(void) {
    struct rusage usage;
    Check(getrusage(RUSAGE_SELF, &usage) == 0, @"process memory counter is available");
    return usage.ru_maxrss;
}
static double ThreadSeconds(void) {
    struct timespec value;
    Check(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value) == 0, @"thread CPU clock is available");
    return value.tv_sec + value.tv_nsec / 1e9;
}

@interface NVApplicationController (CostControl)
- (BOOL)fixtureInactiveGuard:(NSInvocation *)invocation;
@end
@implementation NVApplicationController (CostControl)
- (BOOL)fixtureInactiveGuard:(NSInvocation *)invocation { return NO; }
@end

static void CheckReturnShapes(void) {
    // Void, object, BOOL, integer, floating-point, NSRange, and a larger struct.
    const char *types[] = {"v@:", "@@:", "B@:", "Q@:", "d@:", "{_NSRange=QQ}@:", "{ReviewValue=QQQQQQQQ}@:"};
    for (NSUInteger index = 0; index < sizeof(types) / sizeof(types[0]); index++) {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:types[index]];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        unsigned char bytes[64];
        NSUInteger length = [signature methodReturnLength];
        Check(length <= sizeof(bytes), @"fixture return storage is bounded");
        memset(bytes, 0xA5, sizeof(bytes));
        if (length) [invocation setReturnValue:bytes];
        Check([activeApp rejectInvocationDuringBackupRestore:invocation], @"paused guard handles each return shape");
        if (length) [invocation getReturnValue:bytes];
        for (NSUInteger byte = 0; byte < length; byte++) Check(bytes[byte] == 0, @"paused return contains no stale result bytes");
        blockedReturnChecks++;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[activeApp activeBrowser] methodSignatureForSelector:@selector(fixtureMutation)]];
    [invocation setSelector:@selector(fixtureMutation)];
    [activeApp forwardInvocation:invocation];
    [activeApp performLibraryInvocation:invocation fromBrowser:[activeApp activeBrowser]];
    Check(forwardedCalls == 0, @"repeated paused invocation batches never reach mutable collaborators");
}

@interface ReviewApplication : NSObject
- (void)terminate:(id)sender;
@end
@implementation ReviewApplication
- (void)terminate:(id)sender {
    terminationCalls++;
    Check(activeApp->backupRestoreInProgress && activeApp->restoring, @"canceled quit stays inside the recovery boundary");
    // Return without lifecycle callbacks, as a canceled Quit would do.
}
@end
static void ReviewTerminationCallback(void) { Check(NO, @"this fixture cancels quit before termination starts"); }

static NSInteger ReviewRecoveryPanel(NSString *title, NSString *message, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...) {
    panelVisits++;
    Check(panelVisits <= retryLimit, @"recovery has a bounded fixture response budget");
    Check(activeApp->backupRestoreInProgress && activeApp->restoring && activeApp->library->backupRestorePrepared,
          @"every retry remains inside the prepared library boundary");
    Check(activeApp->library->walWriter == nil && recoveryReads == 0, @"failed retry does not own or recover a competing journal");
    if (panelVisits == 1) {
        firstPanelFDs = OpenFDCount();
        opensAtFirstPanel = journalOpens;
        checkpointsAtFirstPanel = checkpointWrites;
        firstPanelRSS = PeakRSS();
    }
    Check(journalOpens == opensAtFirstPanel + panelVisits - 1, @"each response permits exactly one exclusive journal open attempt");
    Check(checkpointWrites == checkpointsAtFirstPanel && archiveWrites == 1 && replacementAttempts == 1,
          @"retry does not repeat checkpoint capture, restore archive publication, or replacement initialization");
    Check(OpenFDCount() == firstPanelFDs, @"repeated exclusive-open failure does not accumulate file descriptors");
    CheckReturnShapes();
    Check([[NSData dataWithContentsOfFile:JournalPath()] isEqual:Bytes(@"competing library journal")],
          @"repeated retry preserves the competing journal bytes");
    if (panelVisits == retryLimit) {
        lastPanelRSS = PeakRSS();
        Check(unlink([JournalPath() fileSystemRepresentation]) == 0, @"final fixture response releases the competing writer");
        return NSAlertDefaultReturn;
    }
    return panelVisits % 4 == 0 ? NSAlertAlternateReturn : NSAlertDefaultReturn;
}

static void MeasureInactiveGuard(void) {
    const NSUInteger iterations = 1000000;
    double controlBest = 1e9, guardBest = 1e9;
    for (NSUInteger sample = 0; sample < 5; sample++) {
        double start = ThreadSeconds();
        for (NSUInteger index = 0; index < iterations; index++)
            if ([activeApp fixtureInactiveGuard:nil]) exit(2);
        double control = ThreadSeconds() - start;
        start = ThreadSeconds();
        for (NSUInteger index = 0; index < iterations; index++)
            if ([activeApp rejectInvocationDuringBackupRestore:nil]) exit(2);
        double guard = ThreadSeconds() - start;
        controlBest = MIN(controlBest, control);
        guardBest = MIN(guardBest, guard);
    }
    // A broad tripwire, not a cross-machine latency guarantee.
    Check(guardBest < 0.150, @"inactive guard stays below 150 ns per call in this native fixture");
    printf("INACTIVE_GUARD iterations_per_sample=%lu samples=5 control_ns=%.2f guard_ns=%.2f best_thread_cpu_seconds=%.6f\n",
           (unsigned long)iterations, controlBest * 1e9 / iterations, guardBest * 1e9 / iterations, guardBest);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc == 2, @"temporary root supplied");
        exitMode = "bounded";
        fixtureDirectory = [NSString stringWithUTF8String:argv[1]];
        sourceDirectory = [NSURL fileURLWithPath:[fixtureDirectory stringByAppendingPathComponent:@"original"]];
        NSURL *target = [NSURL fileURLWithPath:[fixtureDirectory stringByAppendingPathComponent:@"replacement"]];
        for (NSURL *directory in @[sourceDirectory, target])
            Check([[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:NULL], @"create disposable folder");
        activeApp = [NVApplicationController new];
        fixtureApplication = [ReviewApplication new];
        NotationController *original = activeApp->library;
        Check([original initializeJournaling] && [original flushAllNoteChanges], @"initialize original durable fixture");
        Check([CheckpointData() isEqual:Bytes(@"before restore")], @"original checkpoint contains the expected fixture bytes");
        introduceCollision = YES;
        NSError *error = nil;
        Check(![activeApp restoreBackupArchive:@{@"data":Bytes(@"restored text")} toDirectory:target error:&error], @"restore failure completes after successful journal recovery");
        Check(activeApp->library == original && !activeApp->restoring && !activeApp->backupRestoreInProgress && !original->backupRestorePrepared,
              @"successful resume clears both guards and preserves the original library");
        Check(panelVisits == retryLimit && terminationCalls == 63 && restarts == 1 && original->walWriter != nil,
              @"256 responses including 63 canceled quits cause exactly one successful restart");
        Check(journalOpens == opensAtFirstPanel + retryLimit && recoveryReads == 0, @"final response causes one successful exclusive journal open");
        Check(OpenFDCount() == firstPanelFDs + 1, @"successful recovery owns exactly one additional journal descriptor");
        Check(lastPanelRSS - firstPanelRSS < 16 * 1024 * 1024, @"256 recovery choices add less than 16 MiB in this fixture");
        printf("RETRY_COST panels=%lu canceled_quits=%lu original_reopen_attempts=%lu checkpoint_repeats=0 restore_archive_writes=%lu replacement_attempts=%lu fd_growth_during_failures=0 resumed_fd_growth=1 rss_growth_bytes=%ld return_shape_checks=%lu\n",
               (unsigned long)panelVisits, (unsigned long)terminationCalls, (unsigned long)(retryLimit + 1),
               (unsigned long)archiveWrites, (unsigned long)replacementAttempts, lastPanelRSS - firstPanelRSS, (unsigned long)blockedReturnChecks);
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[activeApp activeBrowser] methodSignatureForSelector:@selector(fixtureMutation)]];
        [invocation setSelector:@selector(fixtureMutation)];
        [activeApp forwardInvocation:invocation];
        NSUInteger result = 0;
        [invocation getReturnValue:&result];
        Check(result == 91 && forwardedCalls == 1, @"the normal forwarded command resumes after journal recovery");
        MeasureInactiveGuard();
        printf("PASS: %lu assertions; current extracted production methods, fixture UI/model/archive, real exclusive journal opens\n", (unsigned long)checks);
        [activeApp release]; [fixtureApplication release];
    }
    return 0;
}
