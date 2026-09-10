#include <time.h>
static double Now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000.0 + t.tv_nsec / 1000000.0; }
static double Median(double *values) {
    for (NSUInteger i = 0; i < 5; i++) for (NSUInteger j = i + 1; j < 5; j++)
        if (values[j] < values[i]) { double t = values[i]; values[i] = values[j]; values[j] = t; }
    return values[2];
}
static NSUInteger checks;
static void CheckLinks(NSAttributedString *text, NSUInteger expected) {
    __block NSUInteger count = 0;
    [text enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [text length]) options:0 usingBlock:^(id value, NSRange r, BOOL *stop) {
        if (value) {
            NSString *url = [value absoluteString];
            NSString *label = [[text string] substringWithRange:r];
            if (!([url isEqual:@"https://example.com/guide"] && [label isEqual:@"Guide 😀"]) &&
                !([url isEqual:@"https://example.org"] && [label isEqual:@"https://example.org"])) exit(2);
            count++;
        }
    }];
    checks++;
    if (count != expected) { fprintf(stderr, "links expected=%lu actual=%lu\n", expected, count); exit(3); }
}
int main(void) { @autoreleasepool {
    for (NSNumber *n in @[@128, @512, @2048]) {
        for (NSNumber *wrapped in @[@NO, @YES]) { @autoreleasepool {
            NSMutableString *source = [NSMutableString string];
            for (NSUInteger i = 0; i < [n unsignedIntegerValue]; i++) {
                [source appendString:@"Café notes [[https://example.com/guide][Guide 😀]], [[file:local.org][local]] and https://example.org. "];
                if ([wrapped boolValue] && i % 4 == 3) [source appendString:@"\r\n"];
            }
            double full[5], insert[5], remove[5];
            for (NSUInteger trial = 0; trial < 5; trial++) { @autoreleasepool {
                NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:source];
                double start = Now();
                [text addLinkAttributesForRange:NSMakeRange(0, [text length]) syntaxIdentifier:@"org"];
                full[trial] = Now() - start; CheckLinks(text, 2 * [n unsignedIntegerValue]);
                [text replaceCharactersInRange:NSMakeRange(2, 0) withString:@"x"];
                start = Now(); [text addLinkAttributesForRange:NSMakeRange(2, 1) syntaxIdentifier:@"org"];
                insert[trial] = Now() - start; CheckLinks(text, 2 * [n unsignedIntegerValue]);
                [text replaceCharactersInRange:NSMakeRange(2, 1) withString:@""];
                start = Now(); [text addLinkAttributesForRange:NSMakeRange(2, 0) syntaxIdentifier:@"org"];
                remove[trial] = Now() - start; CheckLinks(text, 2 * [n unsignedIntegerValue]);
                checks++; if (![[text string] isEqual:source]) return 4;
                [text release];
            } }
            double f = Median(full), i = Median(insert), r = Median(remove);
            printf("mixed-links units=%lu wrapped=%s utf16=%lu full_median_ms=%.3f insert_median_ms=%.3f delete_median_ms=%.3f edit_max_ms=%.3f\n",
                [n unsignedLongValue], [wrapped boolValue] ? "yes" : "no", [source length], f, i, r, MAX(insert[4], remove[4])); fflush(stdout);
        } }
    }
    printf("PASS: %lu exact-link-count, label, destination, and source checks\n", (unsigned long)checks);
} return 0; }
