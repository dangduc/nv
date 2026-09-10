#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

static BOOL Has(NSArray *captures, NSString *source, NSString *kind, NSString *snippet) {
    for (NSDictionary *capture in captures) {
        if ([capture[@"kind"] isEqual:kind] &&
            [[source substringWithRange:[capture[@"range"] rangeValue]] isEqual:snippet]) return YES;
    }
    return NO;
}
static BOOL HasKind(NSArray *captures, NSString *kind) {
    for (NSDictionary *capture in captures) if ([capture[@"kind"] isEqual:kind]) return YES;
    return NO;
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSArray *fixtures = @[
        @[@"hashtag", @"#travel *book tickets*\n", @"text.strong", @"*book tickets*", @YES],
        @[@"hashtag after title", @"#+TITLE: Trip\n#travel *book tickets*\n", @"text.strong", @"*book tickets*", @YES],
        @[@"indented hashtag", @"  #travel *book tickets*\n", @"text.strong", @"*book tickets*", @YES],
        @[@"hashtag after comment", @"# A comment\n#travel *book tickets*\n", @"text.strong", @"*book tickets*", @YES],
        @[@"hashtag after blank line", @"A trip.\n\n#travel *book tickets*\n", @"text.strong", @"*book tickets*", @YES],
        @[@"ordinary comment", @"# travel *book tickets*\n", @"text.strong", @"*book tickets*", @NO],
        @[@"comment after title", @"#+TITLE: Trip\n# travel *book tickets*\n", @"text.strong", @"*book tickets*", @NO],
        @[@"prose", @"Travel *book tickets*.\n", @"text.strong", @"*book tickets*", @YES],
        @[@"task", @"* TODO Book tickets\n", @"keyword.todo", @"TODO", @YES],
        @[@"done", @"* DONE Book tickets\n", @"constant.done", @"DONE", @YES],
        @[@"task word in prose", @"TODO Book tickets\n", @"keyword.todo", @"TODO", @NO],
        @[@"task word in list", @"- TODO Book tickets\n", @"keyword.todo", @"TODO", @NO],
        @[@"source block", @"#+BEGIN_SRC text\n* TODO Book tickets\n*book tickets*\n#+END_SRC\n", @"text.strong", @"*book tickets*", @NO],
        @[@"example block", @"#+BEGIN_EXAMPLE\n*book tickets*\n#+END_EXAMPLE\n", @"text.strong", @"*book tickets*", @NO],
        @[@"quoted prose known limit", @"#+BEGIN_QUOTE\n*book tickets*\n#+END_QUOTE\n", @"text.strong", @"*book tickets*", @NO],
        @[@"verse prose known limit", @"#+BEGIN_VERSE\n*book tickets*\n#+END_VERSE\n", @"text.strong", @"*book tickets*", @NO],
        @[@"literal", @"Use =*book tickets*= as text.\n", @"text.strong", @"*book tickets*", @NO],
        @[@"unicode emphasis", @"Travel *Café 😀 日本語*.\n", @"text.strong", @"*Café 😀 日本語*", @YES]
    ];
    NSMutableArray *results = [NSMutableArray array];
    NSUInteger mismatch = 0, bounds = 0;
    for (NSArray *fixture in fixtures) {
        NSString *source = fixture[1];
        NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:@(argv[1])];
        NSArray *captures = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
        if (!captures) return 2;
        NSMutableArray *display = [NSMutableArray array];
        for (NSDictionary *capture in captures) {
            NSRange r = [capture[@"range"] rangeValue];
            if (r.location > [source length] || r.length > [source length] - r.location) return 3;
            bounds++;
            [display addObject:@{@"kind":capture[@"kind"], @"text":[source substringWithRange:r]}];
        }
        BOOL actual = Has(captures, source, fixture[2], fixture[3]);
        BOOL expected = [fixture[4] boolValue];
        if (actual != expected) mismatch++;
        [results addObject:@{@"fixture":fixture[0], @"source":source, @"expected_capture":fixture[2], @"expected":@(expected), @"actual":@(actual), @"comment":@(HasKind(captures,@"comment")), @"captures":display}];
        [parser release];
    }
    NSData *JSON = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
    fwrite([JSON bytes], 1, [JSON length], stdout);
    printf("\nFixtures=%lu semantic_mismatches=%lu bounds_checks=%lu\n", (unsigned long)[fixtures count], (unsigned long)mismatch, (unsigned long)bounds);
    return 0;
}}
