#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#include <time.h>
static double Milliseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec * 1000.0 + (double)now.tv_nsec / 1000000.0;
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSDictionary *fixtures = @{
        @"prose": @"Ordinary prose Café 😀 日本語 and words that do not need highlighting.\n",
        @"emphasis": @"*bold* /italic/ _underlined_ +strike+ =literal *inside*= ~code~.\n",
        @"links": @"[[https://example.com][label]] ",
        @"tasks": @"* TODO Task\n:PROPERTIES:\n:ID: example\n:END:\nBody text.\n",
    };
    NSUInteger checks = 0;
    for (NSString *name in [[fixtures allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        for (NSNumber *number in @[@16384, @65536, @262144, @524288]) { @autoreleasepool {
            NSUInteger target = [number unsignedIntegerValue];
            NSString *source = [@"" stringByPaddingToLength:target withString:fixtures[name] startingAtIndex:0];
            double sum = 0, maximum = 0;
            NSUInteger completed = 0, fallback = 0, maximumCaptures = 0;
            for (NSUInteger trial = 0; trial < 3; trial++) { @autoreleasepool {
                NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:@(argv[1])];
                double start = Milliseconds();
                NSArray *captures = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
                double elapsed = Milliseconds() - start;
                sum += elapsed; maximum = MAX(maximum, elapsed);
                if (!captures) fallback++;
                else {
                    completed++; maximumCaptures = MAX(maximumCaptures, [captures count]);
                    for (NSDictionary *capture in captures) {
                        NSRange range = [capture[@"range"] rangeValue];
                        if (!range.length || range.location > [source length] || range.length > [source length] - range.location) return 3;
                        checks++;
                    }
                    if ([captures count] > 30000) return 4;
                    checks++;
                }
                // Recovery after a budget fallback must return usable captures.
                NSArray *recovered = [parser capturesForString:@"* TODO Small\nBody *bold*.\n" syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
                if (!recovered || ![recovered count]) return 5;
                checks++;
                [parser release];
            } }
            printf("fixture=%s utf16=%lu trials=3 completed=%lu fallback=%lu mean_ms=%.3f max_ms=%.3f max_captures=%lu\n",
                [name UTF8String], (unsigned long)[source length], (unsigned long)completed, (unsigned long)fallback, sum / 3.0, maximum, (unsigned long)maximumCaptures);
            fflush(stdout);
        } }
    }
    printf("PASS: %lu independent bounds, capture-count, and recovery checks\n", (unsigned long)checks);
} return 0; }
