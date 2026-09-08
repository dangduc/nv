#import <Foundation/Foundation.h>
#import "NVNoteContentSnapshot.h"
#import "NVMarkupRenderer.h"

static void Run(NSString *source, NSString *label) {
    NVMarkupRenderer *renderer = [[[NVMarkupRenderer alloc] init] autorelease];
    NVNoteContentSnapshot *snapshot = [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"review" noteIdentifier:label generation:1 title:label source:source contentType:@"html" assetRootURL:nil] autorelease];
    __block BOOL done = NO;
    [renderer renderSnapshot:snapshot viewerIdentifier:@"html" completion:^(NVMarkupRenderResult *result, NSError *error) {
        NSString *html = [result HTML];
        printf("%s input=%lu output=%lu start=%d end=%d error=%s\n", [label UTF8String], (unsigned long)[source length], (unsigned long)[html length], [html containsString:@"START_SENTINEL"], [html containsString:@"END_SENTINEL"], error ? [[error localizedDescription] UTF8String] : "none");
        done = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!done && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    if (!done) { fprintf(stderr, "callback timed out\n"); exit(2); }
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    for (NSNumber *size in @[@(9*1024*1024), @(11*1024*1024), @(15*1024*1024)]) {
        NSString *body = [@"x" stringByPaddingToLength:[size unsignedIntegerValue] withString:@"x" startingAtIndex:0];
        Run([NSString stringWithFormat:@"<p>START_SENTINEL%@END_SENTINEL</p>", body], [size stringValue]);
    }
    [pool drain];
    return 0;
}
