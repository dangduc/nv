#import <Foundation/Foundation.h>
#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
static NSUInteger checks;
static void Check(BOOL value, NSString *name) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", [name UTF8String]); exit(2); }
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSBundle *bundle = [NSBundle bundleWithPath:@(argv[1])];
    NSString *directory = @(argv[2]);
    NVMarkupRenderer *renderer = [[NVMarkupRenderer alloc] initWithResourceBundle:bundle];
    for (NSString *name in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        if (![[name pathExtension] isEqual:@"org"]) continue;
        NSString *source = [NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
        NVNoteContentSnapshot *snapshot = [[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"contrarian-review" noteIdentifier:name generation:1 title:name source:source contentType:@"public.plain-text" assetRootURL:nil];
        __block NSUInteger callbacks = 0;
        __block NVMarkupRenderResult *result = nil;
        __block NSError *error = nil;
        NSOperation *operation = [[renderer renderSnapshot:snapshot viewerIdentifier:@"org" completion:^(NVMarkupRenderResult *value, NSError *failure) {
            Check([NSThread isMainThread], @"completion uses the main thread"); callbacks++;
            result = [value retain]; error = [failure retain];
        }] retain];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while ((!callbacks || ![operation isFinished]) && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
        Check(callbacks == 1 && result && !error, @"ordinary fixture has one successful render");
        Check([[snapshot source] isEqual:source] && [result snapshot] == snapshot, @"source text and request identity remain unchanged");
        NSString *output = [directory stringByAppendingPathComponent:[[name stringByDeletingPathExtension] stringByAppendingString:@"-renderer.html"]];
        Check([[result HTML] writeToFile:output atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"save actual renderer output for semantic assertions");
        [operation release]; [snapshot release]; [result release]; [error release];
    }
    [renderer release];
    printf("PASS: %lu native renderer/source-preservation checks\n", (unsigned long)checks);
} return 0; }
