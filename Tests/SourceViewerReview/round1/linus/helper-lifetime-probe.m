#import <Foundation/Foundation.h>
#import "NVNoteContentSnapshot.h"
#import "NVMarkupRenderer.h"
#import <signal.h>
#import <errno.h>

static void PumpUntil(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    if (!condition()) { fprintf(stderr,"deadline exceeded\n"); exit(2); }
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    if (argc != 3) return 2;
    NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
    NSString *PIDFile = [NSString stringWithUTF8String:argv[2]];
    NVMarkupRenderer *renderer = [[NVMarkupRenderer alloc] initWithResourceBundle:bundle];
    NVNoteContentSnapshot *snapshot = [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"review" noteIdentifier:@"note" generation:1 title:@"Note" source:@"# Note" contentType:@"markdown" assetRootURL:nil] autorelease];
    __block NSUInteger callbacks = 0;
    NSOperation *operation = [[renderer renderSnapshot:snapshot viewerIdentifier:@"markdown" completion:^(NVMarkupRenderResult *result, NSError *error) {
        if (result || [error code] != NVMarkupCancelled || ![NSThread isMainThread]) { fprintf(stderr,"unexpected callback\n"); exit(3); }
        callbacks++;
    }] retain];
    PumpUntil(^BOOL{ return [[NSFileManager defaultManager] fileExistsAtPath:PIDFile]; }, 3);
    pid_t PID = [[NSString stringWithContentsOfFile:PIDFile encoding:NSUTF8StringEncoding error:NULL] intValue];
    if (PID < 2) return 3;
    NSTimeInterval start = [[NSProcessInfo processInfo] systemUptime];
    [operation cancel];
    [renderer release];
    PumpUntil(^BOOL{ return [operation isFinished] && callbacks == 1; }, 3);
    PumpUntil(^BOOL{ return kill(PID,0) == -1 && errno == ESRCH; }, 3);
    printf("PASS: SIGTERM-ignoring helper PID %d stopped/reaped in %.3fs; exactly %lu main-thread cancellation callback after renderer release\n", PID, [[NSProcessInfo processInfo] systemUptime]-start,(unsigned long)callbacks);
    [operation release];
    [pool drain];
    return 0;
}
