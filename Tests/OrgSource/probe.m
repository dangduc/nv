#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
static NSUInteger checks;
static void Check(BOOL value, NSString *label) {
    checks++;
    if (!value) { NSLog(@"FAIL: %@", label); exit(1); }
}
static NSArray *Parse(NVSourceParser *parser, NSString *source) {
    NSArray *captures = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    Check(captures != nil, @"Org analysis completed within budget");
    for (NSDictionary *capture in captures) {
        NSRange range = [capture[@"range"] rangeValue];
        Check(range.length && range.location <= [source length] && range.length <= [source length] - range.location, @"capture stays within UTF-16 source bounds");
    }
    return captures;
}
static BOOL Has(NSArray *captures, NSString *source, NSString *kind, NSString *text) {
    for (NSDictionary *capture in captures)
        if ([capture[@"kind"] isEqual:kind] && [[source substringWithRange:[capture[@"range"] rangeValue]] isEqual:text]) return YES;
    return NO;
}
static NSArray *Canonical(NSArray *captures) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *capture in captures) [keys addObject:[NSString stringWithFormat:@"%@:%@", capture[@"range"], capture[@"kind"]]];
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
static BOOL Wait(NSLayoutManager *layout, NSString *kind, NSUInteger index) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ([deadline timeIntervalSinceNow] > 0) {
        if (NVSourceCapturesAreCurrent(layout) && [[layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:NULL] isEqual:kind]) return YES;
        Pump();
    }
    return NO;
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *directory = @(argv[1]);
    NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
    NSString *source = @"#+TITLE: Café 😀 日本語\n# adjacent comment *not emphasis*\n\n* TODO [#A] Heading :work:\nSCHEDULED: <2026-09-09 Wed>\n:PROPERTIES:\n:ID: sample\n:END:\n*bold* /italic/ _underline_ +strike+ =literal *plain*= ~code~.\n*outer =literal= text* and *one\nline*.\n[[file:sample.org][Org note]] src_json{true}\n- [ ] Task\n- [X] Done\n| Name | Value |\n|------+-------|\n| Café | 42 |\n#+BEGIN_SRC json\n{\"text\": \"*not bold*\"}\n#+END_SRC\n** DONE Child 😀\nBody";
    NSArray *captures = Parse(parser, source);
    NSArray *expected = @[@[@"keyword", @"TITLE"], @[@"comment", @"# adjacent comment *not emphasis*"], @[@"keyword.todo", @"TODO"], @[@"constant.done", @"DONE"], @[@"constant", @"[#A]"], @[@"attribute", @"work"], @[@"attribute", @"ID"], @[@"string.special", @"<2026-09-09 Wed>"], @[@"text.strong", @"*bold*"], @[@"text.emphasis", @"/italic/"], @[@"text.underline", @"_underline_"], @[@"text.strike", @"+strike+"], @[@"text.literal", @"=literal *plain*="], @[@"text.literal", @"~code~"], @[@"text.literal", @"=literal="], @[@"text.strong", @"*outer =literal= text*"], @[@"text.strong", @"*one\nline*"], @[@"text.uri", @"[[file:sample.org][Org note]]"], @[@"text.literal", @"src_json{true}"], @[@"constant", @"[ ]"], @[@"constant", @"[X]"]];
    for (NSArray *item in expected) Check(Has(captures, source, item[0], item[1]), [NSString stringWithFormat:@"captures %@ as %@", item[1], item[0]]);
    Check(!Has(captures, source, @"text.strong", @"*plain*") && !Has(captures, source, @"text.strong", @"*not bold*") && !Has(captures, source, @"text.strong", @"*not emphasis*"), @"literal spans, source blocks, and comments suppress emphasis");
    NSString *edges = @"* TODOISH is not a task\nDONE in prose; x*word* x/word/ * space* *space * \\*escaped*\n*two\nlines\ninvalid* and /single line/ and *Café 😀 日本語*\n#+BEGIN_EXAMPLE\n* TODO not a heading\n*ignored*\n#+END_EXAMPLE\n";
    NSArray *edgeCaptures = Parse(parser, edges);
    Check(!Has(edgeCaptures, edges, @"keyword.todo", @"TODO") && !Has(edgeCaptures, edges, @"constant.done", @"DONE"), @"only whole default task words at heading start are task captures");
    for (NSString *invalid in @[@"*word*", @"* space*", @"*space *", @"*escaped*", @"*two\nlines\ninvalid*", @"*ignored*"]) Check(!Has(edgeCaptures, edges, @"text.strong", invalid), @"invalid boundaries and protected block text stay plain");
    Check(Has(edgeCaptures, edges, @"text.strong", @"*Café 😀 日本語*"), @"Unicode emphasis retains UTF-16 extent");
    Check(Has(edgeCaptures, edges, @"text.emphasis", @"/single line/"), @"valid emphasis after rejected spans still works");
    NSArray *hashtagFixtures = @[@"#travel *book tickets*\n", @"  #travel *book tickets*\n",
        @"# A comment\n#travel *book tickets*\n", @"A trip.\n\n#travel *book tickets*\n",
        @"#+TITLE: Trip\n#travel *book tickets*\n", @"#travel *book tickets*\n# A comment\n",
        @"# First comment\n#travel *book tickets*\n# Last comment\n"];
    for (NSString *fixture in hashtagFixtures) {
        NSArray *result = Parse(parser, fixture);
        Check(Has(result, fixture, @"text.strong", @"*book tickets*"), @"hashtag prose keeps emphasis regardless of neighboring lines");
        NSRange hashtag = [fixture rangeOfString:@"#travel"];
        for (NSDictionary *capture in result) {
            if ([capture[@"kind"] isEqual:@"comment"])
                Check(!NSIntersectionRange(hashtag, [capture[@"range"] rangeValue]).length, @"comment captures cannot include hashtag prose");
        }
    }
    for (NSString *fixture in @[@"# travel *book tickets*\n", @"#+TITLE: Trip\n# travel *book tickets*\n",
                                @"  # travel *book tickets*\n#travel *visible*\n", @"#\n#travel *visible*\n"]) {
        NSArray *result = Parse(parser, fixture);
        Check(!Has(result, fixture, @"text.strong", @"*book tickets*"), @"real Org comment lines suppress emphasis");
        NSString *comment = [fixture containsString:@"# travel"] ? @"# travel *book tickets*" : @"#";
        Check(Has(result, fixture, @"comment", comment), @"whitespace or end of line identifies a comment prefix");
    }
    NSArray *edits = @[[source stringByReplacingOccurrencesOfString:@"TODO" withString:@"DONE"], [source stringByReplacingOccurrencesOfString:@"*bold*" withString:@"*Café 😀 日本語*"], [source stringByReplacingOccurrencesOfString:@"=literal *plain*=" withString:@"literal *plain*"], [source stringByReplacingOccurrencesOfString:@"#+END_SRC" withString:@""], [source stringByAppendingString:@"\n* TODO new heading"], [source stringByReplacingOccurrencesOfString:@"- [ ] Task" withString:@"  - [X] Task"], source];
    for (NSString *edit in edits) {
        NSArray *incremental = Parse(parser, edit);
        NVSourceParser *fresh = [[NVSourceParser alloc] initWithQueryDirectory:directory];
        Check([Canonical(incremental) isEqual:Canonical(Parse(fresh, edit))], @"incremental Org captures equal fresh analysis");
        [fresh release];
    }
    uint64_t token = 7;
    Check([parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:&token generation:6] == nil, @"cancelled Org analysis returns no result");
    NSString *large = [@"x" stringByPaddingToLength:512 * 1024 + 1 withString:@"x" startingAtIndex:0];
    Check([[parser capturesForString:large syntaxIdentifier:@"org" cancellationToken:NULL generation:0] count] == 0, @"large notes retain existing plain-source fallback");
    Parse(parser, source);
    NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:temporary withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"((headline) @text.title (#match? @text.title \"TODO\"))" writeToFile:[temporary stringByAppendingPathComponent:@"org.scm"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NVSourceParser *predicates = [[NVSourceParser alloc] initWithQueryDirectory:temporary];
    Check([predicates capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0] == nil, @"Org extension does not permit generic query predicates");
    [predicates release];
    [[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL];

    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:@"* TODO Heading\nBody *bold*.\n"];
    NSLayoutManager *first = [[NSLayoutManager alloc] init], *second = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:first]; [storage addLayoutManager:second];
    NVSourceHighlighter *analysis = [[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"org" queryDirectory:directory];
    [analysis layoutsChanged];
    Check(Wait(first, @"keyword.todo", 2) && Wait(second, @"keyword.todo", 2), @"Org task captures reach both attached layouts");
    NSUInteger bold = [[storage string] rangeOfString:@"*bold*"].location;
    Check(Wait(first, @"text.strong", bold), @"supplemental emphasis reaches temporary display attributes");
    [first addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(bold, 6)];
    [storage replaceCharactersInRange:NSMakeRange(bold + 1, 0) withString:@"new "];
    Check(!NVSourceCapturesAreCurrent(first) && NVSourceCapturesCanDisplay(first) && NVSourceCapturesCanDisplay(second), @"typing preserves provisional colors in both Org layouts");
    Check(Wait(first, @"text.strong", bold + 2) && Wait(second, @"text.strong", bold + 2), @"latest Org result colors inserted source in both layouts");
    Check([[first temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:bold effectiveRange:NULL] isEqual:[NSColor yellowColor]], @"syntax retains window-local search background");
    [analysis setSyntaxIdentifier:@"plain"];
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(second), @"switch to Plain Text clears Org syntax display");
    Check([[storage string] isEqual:@"* TODO Heading\nBody *new bold*.\n"], @"source highlighting preserves exact edited characters");
    Check([storage attribute:NVSourceCaptureAttributeName atIndex:2 effectiveRange:NULL] == nil, @"syntax attributes never enter shared note storage");
    [analysis close]; [analysis release];
    [storage removeLayoutManager:first]; [storage removeLayoutManager:second]; [first release]; [second release]; [storage release];
    [parser release];
    NSLog(@"PASS: %lu Org source checks", (unsigned long)checks);
}}
