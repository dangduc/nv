static NSUInteger checks;
static void Check(BOOL success, NSString *message) {
    checks++;
    if (!success) { fprintf(stderr, "FAIL %s\n", [message UTF8String]); exit(1); }
}
static NSArray *Links(NSMutableAttributedString *text) {
    NSMutableArray *result = [NSMutableArray array];
    [text enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [text length]) options:0
        usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value) [result addObject:@[[[text string] substringWithRange:range], [value absoluteString]]];
        }];
    return result;
}
int main(void) { @autoreleasepool {
    NSArray *cases = @[
        @[@"Read [[https://example.com/manual][the manual]].", @[@[@"the manual", @"https://example.com/manual"]]],
        @[@"[[https://example.com?q=x#section][Café 😀]]", @[@[@"Café 😀", @"https://example.com?q=x#section"]]],
        @[@"[[https://example.com]] and [[http://example.org][other]].", @[@[@"https://example.com", @"https://example.com"], @[@"other", @"http://example.org"]]],
        @[@"[[file:notes.org][Notes]]", @[]],
        @[@"[[id:week-one][Week one]]", @[]],
        @[@"[[#goals][Goals]]", @[]],
        @[@"[[Another note]]", @[]],
        @[@"[[file:notes.org][https://example.com]]", @[]],
        @[@"[[https://example.com\n][Manual]]", @[]]
    ];
    for (NSArray *item in cases) {
        NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:item[0]] autorelease];
        [text addLinkAttributesForRange:NSMakeRange(0, [text length]) syntaxIdentifier:@"org"];
        Check([Links(text) isEqual:item[1]], [@"web link semantics: " stringByAppendingString:item[0]]);
        Check([[text string] isEqual:item[0]], @"link decorations preserve exact source characters");
    }
    // LinkingEditor computes the old logical-line range before an edit. For
    // this one-line source, that range covers the full new source afterward.
    NSMutableAttributedString *edited = [[[NSMutableAttributedString alloc] initWithString:@"[[https://example.com][Manual]]"] autorelease];
    [edited addLinkAttributesForRange:NSMakeRange(0, [edited length]) syntaxIdentifier:@"org"];
    NSUInteger position = [[edited string] rangeOfString:@"Manual"].location + 3;
    [edited replaceCharactersInRange:NSMakeRange(position, 0) withString:@"\n"];
    [edited addLinkAttributesForRange:NSMakeRange(0, [edited length]) syntaxIdentifier:@"org"];
    Check([Links(edited) count] == 0, @"pressing Return within a label clears both split lines");
    [edited deleteCharactersInRange:NSMakeRange(position, 1)];
    [edited addLinkAttributesForRange:NSMakeRange(0, [edited length]) syntaxIdentifier:@"org"];
    Check([Links(edited) isEqual:@[@[@"Manual", @"https://example.com"]]], @"joining the label restores its web link");
    NSLog(@"PASS: %lu ordinary source-link checks", (unsigned long)checks);
    return 0;
}}
