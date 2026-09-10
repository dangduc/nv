#import <Foundation/Foundation.h>
#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
static NSUInteger checks;
static void Check(BOOL value, NSString *label) {
    checks++;
    if (!value) { NSLog(@"FAIL: %@", label); exit(2); }
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *directory = @(argv[2]);
    NVMarkupRenderer *renderer = [[NVMarkupRenderer alloc] initWithResourceBundle:[NSBundle bundleWithPath:@(argv[1])]];
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger generation = 0;
    for (NSString *name in names) {
        if (![[name pathExtension] isEqual:@"org"]) continue;
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSData *before = [NSData dataWithContentsOfFile:path];
        NSString *source = [[[NSString alloc] initWithData:before encoding:NSUTF8StringEncoding] autorelease];
        Check(source != nil, @"fixture is valid UTF-8");
        NVNoteContentSnapshot *snapshot = [[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"org-preview-r2-contrarian" noteIdentifier:name generation:++generation title:name source:source contentType:@"public.plain-text" assetRootURL:nil];
        __block NSUInteger callbacks = 0;
        __block NVMarkupRenderResult *result = nil;
        __block NSError *error = nil;
        NSOperation *operation = [[renderer renderSnapshot:snapshot viewerIdentifier:@"org" completion:^(NVMarkupRenderResult *value, NSError *failure) {
            Check([NSThread isMainThread], @"completion uses the main thread");
            callbacks++;
            result = [value retain]; error = [failure retain];
        }] retain];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while ((!callbacks || ![operation isFinished]) && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
        Check(callbacks == 1 && result && !error, @"ordinary fixture completes successfully exactly once");
        Check([result snapshot] == snapshot, @"result retains the original snapshot identity");
        Check([[[snapshot source] dataUsingEncoding:NSUTF8StringEncoding] isEqual:before], @"snapshot retains exact UTF-8 source including CRLF");
        Check([[NSData dataWithContentsOfFile:path] isEqual:before], @"renderer leaves the fixture file unchanged");
        NSString *output = [directory stringByAppendingPathComponent:[[name stringByDeletingPathExtension] stringByAppendingString:@"-renderer.html"]];
        Check([[result HTML] writeToFile:output atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"record renderer output for the independent semantic oracle");
        [operation release]; [snapshot release]; [result release]; [error release];
    }
    [renderer release];
    printf("PASS: %lu native renderer and source-preservation checks\n", (unsigned long)checks);
    return 0;
}}
