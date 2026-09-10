static NSUInteger checks = 0;
static void Check(BOOL success, NSString *message) {
    checks++;
    if (!success) { fprintf(stderr, "FAIL %s\n", [message UTF8String]); exit(1); }
}
static NSArray *Links(NSAttributedString *source) {
    NSMutableArray *links = [NSMutableArray array];
    [source enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [source length]) options:0
        usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) [links addObject:@[[[source string] substringWithRange:range], [value absoluteString]]];
    }];
    return links;
}
static NSMutableAttributedString *Org(NSString *text) {
    NSMutableAttributedString *source = [[[NSMutableAttributedString alloc] initWithString:text] autorelease];
    [source addLinkAttributesForRange:NSMakeRange(0, [source length]) syntaxIdentifier:@"org"];
    Check([[source string] isEqualToString:text], @"decoration preserves source characters");
    return source;
}
int main(void) { @autoreleasepool {
    for (NSString *target in @[@"file:agenda.org", @"id:example-id", @"#heading", @"Another note", @"agenda.org", @"", @" https://example.com", @"https://example.com path", @"javascript:alert(1)"]) {
        for (NSString *suffix in @[@"]]", @"][Label]]"]) {
            NSString *text = [NSString stringWithFormat:@"[[%@%@", target, suffix];
            Check([Links(Org(text)) count] == 0, [@"unresolved or malformed Org target stays inert: " stringByAppendingString:text]);
        }
    }
    Check([Links(Org(@"[[https://example.com]]")) isEqual:@[@[@"https://example.com", @"https://example.com"]]], @"bare web target");
    Check([Links(Org(@"[[https://example.com/path?q=1#part][Résumé 😀 中文]]")) isEqual:@[@[@"Résumé 😀 中文", @"https://example.com/path?q=1#part"]]], @"described Unicode link");
    Check([Links(Org(@"[[http://example.com][One]] [[https://example.net][Two]]")) count] == 2, @"adjacent described links");
    Check([Links(Org(@"https://example.org\n[[file:agenda.org][http://example.net]]\nhttps://example.com")) count] == 2, @"outside URLs survive while link labels stay inert");
    Check([Links(Org(@"[[file:agenda.org\nhttps://example.com")) count] == 1, @"unfinished bracket suppresses only its line");
    NSMutableAttributedString *editing = Org(@"prefix [[https://example.com][Label]] suffix");
    NSRange closing = [[editing string] rangeOfString:@"]]"];
    [editing deleteCharactersInRange:closing];
    [editing addLinkAttributesForRange:NSMakeRange(closing.location, 0) syntaxIdentifier:@"org"];
    Check([Links(editing) count] == 0, @"deleting closer clears inherited label link");
    [editing insertAttributedString:[[[NSAttributedString alloc] initWithString:@"]]"] autorelease] atIndex:closing.location];
    [editing addLinkAttributesForRange:NSMakeRange(closing.location, 2) syntaxIdentifier:@"org"];
    Check([Links(editing) isEqual:@[@[@"Label", @"https://example.com"]]], @"restoring closer restores correct URL");
    NSMutableAttributedString *switching = Org(@"[[Another note]]");
    [switching removeAttribute:NSLinkAttributeName range:NSMakeRange(0,[switching length])];
    [switching addLinkAttributesForRange:NSMakeRange(0,[switching length]) syntaxIdentifier:@"plain"];
    Check([Links(switching) isEqual:@[@[@"Another note", @"nvalt://find/Another%20note"]]], @"plain syntax keeps nv wiki links");
    [switching addLinkAttributesForRange:NSMakeRange(0,[switching length]) syntaxIdentifier:@"org"];
    Check([Links(switching) count] == 0, @"switch to Org removes nv link");
    Check([Links(Org(@"")) count] == 0, @"empty source");
    [editing addLinkAttributesForRange:NSMakeRange(NSNotFound, 2) syntaxIdentifier:@"org"];
    Check([Links(editing) count] == 1, @"stale out-of-bounds range is ignored");
    printf("PASS %lu Org link checks\n", (unsigned long)checks);
} return 0; }
