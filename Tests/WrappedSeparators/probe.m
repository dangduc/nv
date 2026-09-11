#define main PreviousProbeMain
#include "../WordWrapping/probe.m"
#undef main

static BOOL Separator(NSString *source, NSUInteger index) {
    if (!index || index + 1 >= source.length || [source characterAtIndex:index] != ' ') return NO;
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    return ![space characterIsMember:[source characterAtIndex:index-1]] &&
        ![space characterIsMember:[source characterAtIndex:index+1]] &&
        [source rangeOfComposedCharacterSequenceAtIndex:index].length == 1;
}

static NSDictionary *Separators(void) {
    NSUInteger cases = 0, wraps = 0;
    NSArray *sources = @[@"abcdefghij word next", @"abc defghi jklm", @"alpha beta gamma delta epsilon",
        @"line\n    abc defghij next", @"café e\u0302 👩🏽‍💻 zeta eta theta", @"中文 中文 hello world"];
    for (NSString *fontName in @[@"Menlo-Regular", @"Helvetica", @"TimesNewRomanPSMT"])
    for (NSUInteger width = 55; width < 321; width += 7)
    for (NSString *source in sources) { @autoreleasepool {
        TextSystem *system = [[[TextSystem alloc] initWithWidth:width refined:YES] autorelease];
        [system setSource:source font:[NSFont fontWithName:fontName size:18] style:ParagraphStyle(@"plain")];
        NSDictionary *snapshot = [system snapshot];
        Check([system->storage.string isEqual:source], @"wrapping preserves the exact source");
        for (NSDictionary *row in snapshot[@"lines"]) {
            NSUInteger start = [row[@"start"] unsignedIntegerValue];
            Check(!Separator(source, start), @"word separator does not indent a wrapped line");
            if (start) wraps++;
        }
        cases++;
    }}
    Check(wraps > 500, @"fixture covers automatic line boundaries");
    return @{@"cases":@(cases), @"wrappedLines":@(wraps)};
}

static BOOL Elastic(TextSystem *system, NSUInteger index) {
    [system snapshot];
    return ([system->layout propertyForGlyphAtIndex:[system->layout glyphIndexForCharacterAtIndex:index]] & NSGlyphPropertyElastic) != 0;
}

static NSDictionary *Transitions(void) {
    NSUInteger histories = 0;
    for (NSUInteger width = 80; width <= 320; width += 40)
    for (NSUInteger styled = 0; styled < 2; styled++) { @autoreleasepool {
        TextSystem *system = [[[TextSystem alloc] initWithWidth:width refined:YES] autorelease];
        [system setSource:@"abcdefghij next" font:[NSFont fontWithName:@"Menlo-Regular" size:18] style:ParagraphStyle(@"plain")];
        if (styled) [system->storage addAttribute:NSForegroundColorAttributeName value:NSColor.redColor range:NSMakeRange(10,1)];
        TextSystem *peer = [[[TextSystem alloc] initWithWidth:width+60 refined:YES] autorelease];
        [peer->storage removeLayoutManager:peer->layout];
        [peer->storage release]; peer->storage = [system->storage retain];
        [peer->storage addLayoutManager:peer->layout];
        for (NSUInteger cycle = 0; cycle < 4; cycle++) {
            Check(Elastic(system,10) && Elastic(peer,10), @"single separator is elastic in both layouts");
            [system->storage replaceCharactersInRange:NSMakeRange(11,0) withString:@" "];
            Check(!Elastic(system,10) && !Elastic(peer,10), @"existing separator becomes literal when a second space is inserted");
            CheckFreshLayout(system); CheckFreshLayout(peer);
            [system->storage replaceCharactersInRange:NSMakeRange(11,1) withString:@""];
            Check(Elastic(system,10) && Elastic(peer,10), @"deleting the second space restores separator elasticity");
            CheckFreshLayout(system); CheckFreshLayout(peer);
            [system->storage replaceCharactersInRange:NSMakeRange(11,4) withString:@""];
            Check(!Elastic(system,10) && !Elastic(peer,10), @"deleting the following word makes the space visibly advancing");
            CheckFreshLayout(system); CheckFreshLayout(peer);
            [system->storage replaceCharactersInRange:NSMakeRange(11,0) withString:@"next"];
            Check(Elastic(system,10) && Elastic(peer,10), @"typing after a trailing space restores separator elasticity");
            CheckFreshLayout(system); CheckFreshLayout(peer);
        }
        [system->storage beginEditing];
        [system->storage replaceCharactersInRange:NSMakeRange(10,1) withString:@"\n "];
        [system->storage replaceCharactersInRange:NSMakeRange(0,3) withString:@"ê"];
        [system->storage endEditing];
        CheckFreshLayout(system); CheckFreshLayout(peer);
        [system->container setContainerSize:NSMakeSize(width+100,1000000)];
        CheckFreshLayout(system); CheckFreshLayout(peer);
        histories++;
    }}
    return @{@"sharedHistories":@(histories)};
}

static NSDictionary *Preservation(void) {
    NSArray *sources = @[@"", @" ", @"               ", @"abcdefghij   next", @"line\n    next",
        @"\tword\tword", @"a\u00a0b", @"a\u202fb", @"a\u2003b", @"word  ", @"word\r\n word", @"word\u2028 word",
        @"abcdefghij \u0301word", @"abcdefghij \ufe0fword", @"abcdefghij \u200dword"];
    for (NSString *source in sources) { @autoreleasepool {
        TextSystem *system = [[[TextSystem alloc] initWithWidth:80 refined:YES] autorelease];
        [system setSource:source font:[NSFont fontWithName:@"Menlo-Regular" size:18] style:ParagraphStyle(@"plain")];
        [system snapshot];
        for (NSUInteger i = 0; i < source.length; i++)
            if ([source characterAtIndex:i] == ' ') Check(!Elastic(system,i), @"intentional spaces retain fixed advancement");
        Check([system->storage.string isEqual:source], @"layout leaves intentional whitespace intact");
        CheckFreshLayout(system);
    }}
    return @{@"cases":@(sources.count)};
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 3) return 2;
    [NSApplication sharedApplication];
    NSString *suite = [NSString stringWithUTF8String:argv[1]];
    NSDictionary *evidence = [suite isEqual:@"separators"] ? Separators() :
        ([suite isEqual:@"transitions"] ? Transitions() : Preservation());
    NSMutableDictionary *report = [NSMutableDictionary dictionaryWithDictionary:evidence];
    report[@"checks"] = @(Checks);
    Check([[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
        writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES], @"write result JSON");
    fprintf(stderr,"PASS %s: %lu checks\n", suite.UTF8String, (unsigned long)Checks-1);
    return 0;
}}
