// Import the actual implementation to measure its static supplemental pass.
#import "Sources/Editor/NVSourceHighlighter.m"
static NSUInteger checks = 0;
static void Require(BOOL value, const char *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(2); }
}
static double Now(void) { return NVClock() / 1000000.0; }
static double Median(double *values, NSUInteger n) {
    for (NSUInteger i = 0; i < n; i++) for (NSUInteger j = i + 1; j < n; j++)
        if (values[i] > values[j]) { double t = values[i]; values[i] = values[j]; values[j] = t; }
    return values[n / 2];
}
static NSString *Notebook(NSUInteger sections) {
    NSMutableString *s = [NSMutableString stringWithString:@"#+TITLE: Release journal\n#+AUTHOR: Engineering\n\n"];
    for (NSUInteger i = 0; i < sections; i++) {
        [s appendFormat:@"* TODO [#B] Release %lu :work:notes:\nSCHEDULED: <2026-09-10 Thu>\n:PROPERTIES:\n:ID: release-%lu\n:END:\n", (unsigned long)i, (unsigned long)i];
        [s appendString:@"Discuss the *source editor* with /reviewers/. Keep =literal *markers*= unchanged.\n"
            "Café 😀 日本語: the _next step_ needs +old wording+ removed and ~code~ retained.\n"
            "See [[https://example.com/release][release notes]] and [[file:agenda.org][local agenda]].\n"
            "- [ ] Collect comments\n  - [X] Read the report\n  - [ ] Record the measurements\n"
            "- [X] Keep temporary notes separate\n"
            "| Area | Status |\n|------+--------|\n| Source | *ready* |\n| Preview | TODO |\n"
            "#+BEGIN_SRC json\n{\"enabled\": true, \"text\": \"*literal*\"}\n#+END_SRC\n"
            "#+TITLE: Appendix\n# This comment excludes *emphasis*.\n#tag remains *prose*.\n"
            "** DONE Discussion\nPlain text records the choice and its reason.\n\n"];
    }
    return s;
}
static NSArray *Canonical(NSArray *captures) {
    if (!captures) return nil;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *capture in captures) {
        NSRange r = [capture[@"range"] rangeValue];
        [result addObject:[NSString stringWithFormat:@"%lu:%lu:%@", (unsigned long)r.location, (unsigned long)r.length, capture[@"kind"]]];
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}
@interface CountingLayout : NSLayoutManager { @public NSUInteger writes; }
@end
@implementation CountingLayout
- (void)addTemporaryAttribute:(NSAttributedStringKey)key value:(id)value forCharacterRange:(NSRange)range {
    if ([key isEqual:NVSourceCaptureAttributeName]) writes++;
    [super addTemporaryAttribute:key value:value forCharacterRange:range];
}
@end
static void Bounds(NSArray *captures, NSUInteger length) {
    Require([captures count] <= 30000, "capture count stays within limit");
    for (NSDictionary *capture in captures) {
        NSRange r = [capture[@"range"] rangeValue];
        Require(r.length && r.location <= length && r.length <= length - r.location, "UTF-16 capture bounds");
    }
}
static void CheckEdit(NVSourceParser *parser, NSString *source, NSString *directory, const char *label) {
    double start = Now();
    NSArray *incremental = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    double elapsed = Now() - start;
    NVSourceParser *fresh = [[NVSourceParser alloc] initWithQueryDirectory:directory];
    NSArray *expected = [fresh capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    Require(incremental != nil && expected != nil, "ordinary edit completes inside budget");
    Require([Canonical(incremental) isEqual:Canonical(expected)], "incremental captures match fresh captures");
    Bounds(incremental, [source length]);
    printf("edit=%s utf16=%lu captures=%lu incremental_ms=%.3f\n", label, (unsigned long)[source length], (unsigned long)[incremental count], elapsed);
    [fresh release];
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *directory = @(argv[1]);
    for (NSNumber *size in @[@1, @8, @32, @128, @384]) { @autoreleasepool {
        NSString *source = Notebook([size unsignedIntegerValue]);
        double times[5]; NSUInteger fallback = 0, captureCount = 0;
        for (NSUInteger trial = 0; trial < 5; trial++) { @autoreleasepool {
            NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
            double start = Now();
            NSArray *result = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
            times[trial] = Now() - start;
            if (!result) fallback++; else { Bounds(result, [source length]); captureCount = [result count]; }
            NSArray *recovery = [parser capturesForString:Notebook(1) syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
            Require([recovery count] > 0, "small note recovers after notebook or fallback");
            [parser release];
        } }
        double median = Median(times, 5);
        printf("notebook sections=%lu utf16=%lu median_ms=%.3f max_ms=%.3f fallbacks=%lu captures=%lu\n",
            [size unsignedLongValue], (unsigned long)[source length], median, times[4], (unsigned long)fallback, (unsigned long)captureCount);

        if ([size unsignedIntegerValue] <= 32) {
            TSParser *raw = ts_parser_new(); Require(ts_parser_set_language(raw, tree_sitter_org()), "raw Org language");
            NSData *bytes = [source dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
            nv_org_scanner_begin_parse();
            TSTree *tree = ts_parser_parse_string_encoding(raw, NULL, [bytes bytes], (uint32_t)[bytes length], TSInputEncodingUTF16LE);
            Require(tree && !nv_org_scanner_did_fail(), "ordinary raw notebook parse succeeds");
            double supplemental[5]; NSUInteger count = 0;
            for (NSUInteger trial = 0; trial < 5; trial++) { @autoreleasepool {
                NSMutableArray *captures = [NSMutableArray array];
                NVSourceBudget budget = {NULL, 0, NVClock() + 120000000ULL, NO};
                double start = Now();
                Require(NVOrgCaptures(tree, source, captures, &budget), "supplemental pass completes");
                supplemental[trial] = Now() - start; count = [captures count]; Bounds(captures, [source length]);
            } }
            double med = Median(supplemental, 5);
            printf("supplemental sections=%lu median_ms=%.3f max_ms=%.3f added_captures=%lu\n", [size unsignedLongValue], med, supplemental[4], (unsigned long)count);
            ts_tree_delete(tree); ts_parser_delete(raw);
        }
        fflush(stdout);
    } }

    NSMutableString *edit = [NSMutableString stringWithString:Notebook(8)];
    NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
    CheckEdit(parser, edit, directory, "initial");
    NSArray *edits = @[@[@"source editor", @"source edito"], @[@"source edito*", @"source editor*"],
        @[@"*source editor*", @"*source editor"], @[@"*source editor with", @"*source editor* with"],
        @[@"TODO [#B]", @"DONE [#B]"], @[@"#tag remains", @"# tag remains"],
        @[@"# tag remains", @"#tag remains"], @[@"release notes]]", @"release notes]"],
        @[@"release notes] and", @"release notes]] and"], @[@"Café 😀 日本語", @"Café 👩‍💻 日本語"],
        @[@"#+END_SRC", @"#+END_SR"], @[@"#+END_SR\n", @"#+END_SRC\n"]];
    NSUInteger index = 0;
    for (NSArray *change in edits) {
        NSRange range = [edit rangeOfString:change[0]];
        Require(range.location != NSNotFound, "typo fixture target exists");
        [edit replaceCharactersInRange:range withString:change[1]];
        CheckEdit(parser, edit, directory, [[NSString stringWithFormat:@"typo-%lu", (unsigned long)++index] UTF8String]);
    }
    uint64_t token = 9;
    double start = Now();
    Require([parser capturesForString:edit syntaxIdentifier:@"org" cancellationToken:&token generation:8] == nil, "cancelled request returns no stale captures");
    printf("pre_cancelled_ms=%.3f\n", Now() - start);
    CheckEdit(parser, edit, directory, "after-cancellation");
    NSString *overLimit = [@"" stringByPaddingToLength:512 * 1024 + 1 withString:@"text " startingAtIndex:0];
    Require([[parser capturesForString:overLimit syntaxIdentifier:@"org" cancellationToken:NULL generation:0] count] == 0, "length guard chooses plain source");
    CheckEdit(parser, Notebook(1), directory, "after-length-fallback");

    NSString *displaySource = Notebook(32);
    NSArray *displayCaptures = [parser capturesForString:displaySource syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    Require([displayCaptures count] > 1024 && [displayCaptures count] <= 4096 / 3, "display fixture crosses four-layout budget");
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:displaySource];
    NSMutableArray *layouts = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        CountingLayout *layout = [[CountingLayout alloc] init];
        [storage addLayoutManager:layout]; [layouts addObject:layout]; [layout release];
    }
    NVSourceHighlighter *highlighter = [[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"org" queryDirectory:directory];
    [highlighter setValue:displayCaptures forKey:@"captures"];
    [highlighter applyCaptures];
    for (CountingLayout *layout in layouts) {
        Require(NVSourceCapturesAreCurrent(layout), "three layouts display the complete revision");
        Require(layout->writes == [displayCaptures count], "every capture is applied exactly once per layout");
        layout->writes = 0;
    }
    CountingLayout *fourth = [[CountingLayout alloc] init];
    [storage addLayoutManager:fourth]; [layouts addObject:fourth];
    [highlighter layoutsChanged];
    for (CountingLayout *layout in layouts) {
        Require(!NVSourceCapturesCanDisplay(layout), "four layouts fall back together");
        Require(layout->writes == 0, "over-budget display performs no capture writes");
    }
    [storage removeLayoutManager:fourth]; [layouts removeLastObject]; [fourth release];
    [highlighter layoutsChanged];
    for (CountingLayout *layout in layouts) Require(NVSourceCapturesAreCurrent(layout), "removing the fourth layout restores the cached revision");
    Require([storage attribute:NVSourceCaptureAttributeName atIndex:0 effectiveRange:NULL] == nil, "captures stay out of note text attributes");
    printf("display_budget captures=%lu layouts=3:complete layouts=4:plain layouts=3:restored\n", (unsigned long)[displayCaptures count]);
    [highlighter close]; [highlighter release]; [storage release];
    [parser release];
    printf("PASS: %lu bounds, completion, fresh-edit equivalence, and recovery checks\n", (unsigned long)checks);
} return 0; }
