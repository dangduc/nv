// Exercise the extracted production methods with ordinary attributed strings.
// No view, event loop, file data, or network operation participates in this probe.
#include <time.h>
static double Milliseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec * 1000.0 + (double)now.tv_nsec / 1000000.0;
}
static double Median(double *times, NSUInteger count) {
    for (NSUInteger i = 0; i < count; i++) for (NSUInteger j = i + 1; j < count; j++)
        if (times[j] < times[i]) { double value = times[i]; times[i] = times[j]; times[j] = value; }
    return times[count / 2];
}
static NSUInteger CountLinks(NSAttributedString *source) {
    __block NSUInteger count = 0;
    __block BOOL valid = YES;
    [source enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [source length]) options:0
        usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) {
            count++;
            if (![[[source string] substringWithRange:range] isEqual:@"label"] ||
                ![[value absoluteString] isEqual:@"https://example.com"]) valid = NO;
        }
    }];
    return valid ? count : NSNotFound;
}
int main(void) { @autoreleasepool {
    NSString *unit = @"[[https://example.com][label]] ";
    for (NSNumber *number in @[@250, @500, @1000, @2000, @4000, @8000]) {
        NSUInteger count = [number unsignedIntegerValue];
        NSMutableString *source = [NSMutableString string];
        for (NSUInteger i = 0; i < count; i++) [source appendString:unit];
        for (NSString *shape in @[@"single-line", @"one-per-line"]) {
            NSString *text = [shape isEqual:@"single-line"] ? source : [source stringByReplacingOccurrencesOfString:@"]] " withString:@"]]\n"];
            double times[5], editingTimes[5];
            NSUInteger found = 0;
            for (NSUInteger trial = 0; trial < 5; trial++) { @autoreleasepool {
                NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text];
                double start = Milliseconds();
                [attributed addLinkAttributesForRange:NSMakeRange(0, [attributed length]) syntaxIdentifier:@"org"];
                times[trial] = Milliseconds() - start;
                found = CountLinks(attributed);
                if (found != count || ![[attributed string] isEqual:text]) return 3;
                start = Milliseconds();
                [attributed addLinkAttributesForRange:NSMakeRange([attributed length] / 2, 1) syntaxIdentifier:@"org"];
                editingTimes[trial] = Milliseconds() - start;
                if (CountLinks(attributed) != count) return 4;
                [attributed release];
            } }
            double wholeMedian = Median(times, 5), editMedian = Median(editingTimes, 5);
            printf("shape=%s links=%lu utf16=%lu whole_median_ms=%.3f whole_max_ms=%.3f edit_median_ms=%.3f edit_max_ms=%.3f\n",
                [shape UTF8String], (unsigned long)count, (unsigned long)[text length], wholeMedian, times[4], editMedian, editingTimes[4]);
            fflush(stdout);
        }
    }
    puts("PASS: both full-note and one-character refreshes preserve every expected link and source character");
} return 0; }
