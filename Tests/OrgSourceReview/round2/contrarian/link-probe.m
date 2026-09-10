static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { NSLog(@"FAIL: %@", message); exit(2); }
}
static NSArray *Links(NSAttributedString *text) {
    NSMutableArray *result = [NSMutableArray array];
    [text enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [text length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) [result addObject:@[[[text string] substringWithRange:range], [value absoluteString], @(range.location), @(range.length)]];
    }];
    return result;
}
int main(void) { @autoreleasepool {
    NSString *initial = @"Intro 👩🏽‍💻\r\n[[https://example.com/path?q=a#part][Cafe\u0301 😀]] and [[id:abc][https://ignored.example]]\r\nNext https://example.org/end.\r\n";
    NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:initial] autorelease];
    [text addAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] range:NSMakeRange(0, [text length])];
    [text addLinkAttributesForRange:NSMakeRange(0, [text length]) syntaxIdentifier:@"org"];
    Check([Links(text) count] == 2, @"Unicode CRLF note exposes the explicit label and ordinary URL only");
    Check([Links(text)[0][0] isEqual:@"Cafe\u0301 😀"], @"combining and emoji label is complete");
    Check([Links(text)[0][1] isEqual:@"https://example.com/path?q=a#part"], @"URL query and fragment are preserved");
    Check([[text string] isEqual:initial], @"decoration preserves CRLF source characters");
    NSArray *edits = @[
        @[@"Cafe\u0301 😀", @"Cafe\u0301 日本語 😀"],
        @[@"q=a", @"q=b"],
        @[@"日本語", @"日\n本語"],
        @[@"日\n本語", @"日本語"],
        @[@"https://example.com", @"file:example.com"],
        @[@"file:example.com", @"https://example.net"],
        @[@" 😀]]", @" 😀]"],
        @[@" 😀] and", @" 😀]] and"]
    ];
    for (NSArray *edit in edits) {
        NSRange range = [[text string] rangeOfString:edit[0]];
        Check(range.location != NSNotFound, @"edit target exists");
        [text replaceCharactersInRange:range withString:edit[1]];
        NSString *before = [[[text string] copy] autorelease];
        // Whole-note refresh is the syntax-switch/session API contract. This
        // review does not substitute a partial range for LinkingEditor's range.
        [text addLinkAttributesForRange:NSMakeRange(0, [text length]) syntaxIdentifier:@"org"];
        NSMutableAttributedString *fresh = [[[NSMutableAttributedString alloc] initWithString:before] autorelease];
        [fresh addLinkAttributesForRange:NSMakeRange(0, [fresh length]) syntaxIdentifier:@"org"];
        Check([Links(text) isEqual:Links(fresh)], @"retained attributes after edit equal fresh decoration");
        Check([[text string] isEqual:before], @"link refresh preserves edited text");
        Check([[text attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:[NSColor yellowColor]], @"link refresh preserves unrelated background attributes");
    }
    Check([Links(text) count] == 2, @"restoring delimiter recovers the label link");
    Check([Links(text)[0][1] isEqual:@"https://example.net/path?q=b#part"], @"restored label uses current destination");
    printf("PASS: %lu Unicode and edited-link checks\n", (unsigned long)checks);
    return 0;
}}
