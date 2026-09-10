#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { NSLog(@"FAIL: %@", message); exit(2); }
}
static NSArray *Canonical(NSArray *captures) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *capture in captures)
        [keys addObject:[NSString stringWithFormat:@"%@:%@", capture[@"range"], capture[@"kind"]]];
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}
static BOOL Has(NSArray *captures, NSString *source, NSString *kind, NSString *snippet) {
    for (NSDictionary *capture in captures)
        if ([capture[@"kind"] isEqual:kind] && [[source substringWithRange:[capture[@"range"] rangeValue]] isEqual:snippet]) return YES;
    return NO;
}
static NSArray *Parse(NVSourceParser *parser, NSString *source) {
    NSString *before = [[source copy] autorelease];
    NSArray *captures = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    Check(captures != nil, @"ordinary note completes analysis");
    Check([source isEqual:before], @"analysis preserves source characters");
    for (NSDictionary *capture in captures) {
        NSRange range = [capture[@"range"] rangeValue];
        Check(range.length && range.location <= [source length] && range.length <= [source length] - range.location, @"capture has a valid UTF-16 extent");
        Check(NSEqualRanges([source rangeOfComposedCharacterSequencesForRange:range], range), @"fixture capture does not split an emoji or combining sequence");
    }
    return captures;
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *directory = @(argv[1]);
    NSArray *fixtures = @[
        @[@"code control", @"Draft token then ~code~.\n", @"text.literal", @"~code~", @YES],
        @[@"unclosed verbatim before code", @"Draft =token then ~code~.\n", @"text.literal", @"~code~", @YES],
        @[@"unclosed code before verbatim", @"Draft ~token then =literal=.\n", @"text.literal", @"=literal=", @YES],
        @[@"unclosed verbatim before unicode code", @"Draft =token then ~Cafe\u0301 👩🏽‍💻 日本語~.\n", @"text.literal", @"~Cafe\u0301 👩🏽‍💻 日本語~", @YES],
        @[@"unclosed verbatim one newline", @"Draft =token\nthen ~code~.\n", @"text.literal", @"~code~", @YES],
        @[@"unclosed verbatim blank line", @"Draft =token\n\nthen ~code~.\n", @"text.literal", @"~code~", @YES],
        @[@"closed verbatim suppresses inner code", @"Draft =token ~code~ text=.\n", @"text.literal", @"~code~", @NO],
        @[@"closed code suppresses inner verbatim", @"Draft ~token =literal= text~.\n", @"text.literal", @"=literal=", @NO],
        @[@"closed verbatim remains one span", @"Draft =token ~code~ text=.\n", @"text.literal", @"=token ~code~ text=", @YES],
        @[@"adjacent literal types", @"Draft =token= then ~code~.\n", @"text.literal", @"~code~", @YES],
        @[@"unicode emphasis", @"Review *Cafe\u0301 👩🏽‍💻 日本語* today.\n", @"text.strong", @"*Cafe\u0301 👩🏽‍💻 日本語*", @YES],
        @[@"CRLF single newline", @"Review *first\r\nsecond* today.\r\n", @"text.strong", @"*first\r\nsecond*", @YES],
        @[@"LF single newline control", @"Review *first\nsecond* today.\n", @"text.strong", @"*first\nsecond*", @YES],
        @[@"CRLF multiline literal", @"Review ~first\r\nsecond~ today.\r\n", @"text.literal", @"~first\r\nsecond~", @YES],
        @[@"LF multiline literal control", @"Review ~first\nsecond~ today.\n", @"text.literal", @"~first\nsecond~", @YES],
        @[@"CRLF two newlines", @"Review *first\r\nsecond\r\nthird* today.\r\n", @"text.strong", @"*first\r\nsecond\r\nthird*", @NO],
        @[@"punctuation boundaries", @"Read (*word*), then /other/.\n", @"text.strong", @"*word*", @YES],
        @[@"Org explicit line break", @"Read *word*\\\\\nthen continue.\n", @"text.strong", @"*word*", @YES],
        @[@"Org explicit line break code", @"Read ~code~\\\\\nthen continue.\n", @"text.literal", @"~code~", @YES],
        @[@"word interior", @"Read prefix*word* and continue.\n", @"text.strong", @"*word*", @NO],
        @[@"markup in source block", @"#+BEGIN_SRC text\nDraft =token ~code~.\n#+END_SRC\n", @"text.literal", @"~code~", @NO],
        @[@"real comment", @"# Draft =token ~code~.\n", @"text.literal", @"~code~", @NO],
        @[@"hashtag prose", @"#draft =token then ~code~.\n", @"text.literal", @"~code~", @YES]
    ];
    NSUInteger mismatches = 0;
    NSMutableArray *results = [NSMutableArray array];
    NVSourceParser *incremental = [[NVSourceParser alloc] initWithQueryDirectory:directory];
    for (NSArray *fixture in fixtures) {
        NSString *source = fixture[1];
        NSArray *captures = Parse(incremental, source);
        NVSourceParser *fresh = [[NVSourceParser alloc] initWithQueryDirectory:directory];
        Check([Canonical(captures) isEqual:Canonical(Parse(fresh, source))], @"reused parser matches a fresh parser");
        [fresh release];
        BOOL actual = Has(captures, source, fixture[2], fixture[3]);
        if (actual != [fixture[4] boolValue]) mismatches++;
        NSMutableArray *display = [NSMutableArray array];
        for (NSDictionary *capture in captures)
            [display addObject:@{@"kind":capture[@"kind"], @"text":[source substringWithRange:[capture[@"range"] rangeValue]]}];
        [results addObject:@{@"fixture":fixture[0], @"source":source, @"kind":fixture[2], @"snippet":fixture[3], @"expected":fixture[4], @"actual":@(actual), @"captures":display}];
    }
    // Character-by-character editing remains stable after both delimiter kinds.
    // These equality checks exercise real incremental state but do not claim an
    // independent semantic oracle beyond the fixture expectations above.
    NSString *edited = @"Draft =token then ~Cafe\u0301 😀~.\n";
    for (NSUInteger end = 0; end <= [edited length]; end++) {
        if (end && CFStringIsSurrogateHighCharacter([edited characterAtIndex:end - 1])) continue;
        NSString *prefix = [edited substringToIndex:end];
        NVSourceParser *fresh = [[NVSourceParser alloc] initWithQueryDirectory:directory];
        Check([Canonical(Parse(incremental, prefix)) isEqual:Canonical(Parse(fresh, prefix))], @"typed prefix equals fresh analysis");
        [fresh release];
    }
    [incremental release];
    NSData *data = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
    fwrite([data bytes], 1, [data length], stdout);
    printf("\nFixtures=%lu semantic_mismatches=%lu mechanical_checks=%lu\n", (unsigned long)[fixtures count], (unsigned long)mismatches, (unsigned long)checks);
    return 0;
}}
