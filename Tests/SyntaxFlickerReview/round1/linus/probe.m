#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

// A TextKit integration probe. Syntax output is used as an oracle only after
// edits; the test is about display attributes and retained revision ownership.
static NSUInteger Checks, UnsafeChanges, AttributeWrites, Histories;
static void Check(BOOL ok, NSString *why) {
    Checks++;
    if (!ok) { NSLog(@"FAIL: %@", why); exit(1); }
}
static void Pump(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}
@interface NVSourceHighlighter (Review)
- (void)analyze;
@end
@interface BoundaryLayout : NSLayoutManager
@end
@implementation BoundaryLayout
- (void)addTemporaryAttribute:(NSAttributedStringKey)key value:(id)value forCharacterRange:(NSRange)range {
    if ([key isEqual:NVSourceCaptureAttributeName]) {
        AttributeWrites++;
        if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeChanges++;
        Check(range.location <= [[self textStorage] length] && range.length <= [[self textStorage] length] - range.location, @"syntax write remains inside current UTF-16 storage");
    }
    [super addTemporaryAttribute:key value:value forCharacterRange:range];
}
- (void)removeTemporaryAttribute:(NSAttributedStringKey)key forCharacterRange:(NSRange)range {
    if ([key isEqual:NVSourceCaptureAttributeName]) {
        AttributeWrites++;
        if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeChanges++;
    }
    [super removeTemporaryAttribute:key forCharacterRange:range];
}
@end
static NSArray *Kinds(NSLayoutManager *layout) {
    NSMutableArray *answer = [NSMutableArray array];
    for (NSUInteger i = 0; i < [[layout textStorage] length]; i++) {
        NSRange range;
        id kind = [layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:i effectiveRange:&range];
        Check(NSLocationInRange(i, range) && NSMaxRange(range) <= [[layout textStorage] length], @"temporary capture enumeration remains bounded after native layout");
        [answer addObject:kind ?: [NSNull null]];
    }
    return answer;
}
static void Layout(NSTextStorage *storage) {
    for (NSLayoutManager *layout in [storage layoutManagers]) {
        NSTextContainer *container = [[layout textContainers] firstObject];
        [layout ensureLayoutForTextContainer:container];
        NSUInteger glyphs = [layout numberOfGlyphs];
        if (glyphs) {
            NSRange chars = [layout characterRangeForGlyphRange:NSMakeRange(0, glyphs) actualGlyphRange:NULL];
            Check(NSMaxRange(chars) <= [storage length], @"cached glyph mapping remains inside shortened or replaced source");
            NSRect box = [layout boundingRectForGlyphRange:NSMakeRange(0, glyphs) inTextContainer:container];
            Check(isfinite(NSWidth(box)) && isfinite(NSHeight(box)), @"native laid-out bounds remain finite");
        }
    }
}
static NSArray *FreshKinds(NVSourceParser *oracle, NSString *source, NSString *syntax) {
    NSArray *captures = [oracle capturesForString:source syntaxIdentifier:syntax cancellationToken:NULL generation:0];
    Check(captures != nil, @"small fixture obtains a complete independent parse");
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < [source length]; i++) [result addObject:[NSNull null]];
    for (NSDictionary *capture in captures) {
        NSRange range = [capture[@"range"] rangeValue];
        Check(NSMaxRange(range) <= [source length], @"oracle capture bounds valid");
        for (NSUInteger i = range.location; i < NSMaxRange(range); i++) result[i] = capture[@"kind"];
    }
    return result;
}
static void Settle(NVSourceHighlighter *highlighter, NVSourceParser *oracle, NSTextStorage *storage, NSString *syntax) {
    [NSObject cancelPreviousPerformRequestsWithTarget:highlighter selector:@selector(analyze) object:nil];
    [highlighter analyze];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ([[highlighter valueForKey:@"analyzing"] boolValue] && [deadline timeIntervalSinceNow] > 0) Pump(.005);
    Check(![[highlighter valueForKey:@"analyzing"] boolValue], @"replacement worker completes within deadline");
    Layout(storage);
    NSArray *fresh = FreshKinds(oracle, [storage string], syntax);
    BOOL hasCaptures = NO;
    for (id kind in fresh) if (kind != [NSNull null]) hasCaptures = YES;
    for (NSLayoutManager *layout in [storage layoutManagers]) {
        Check(NVSourceCapturesAreCurrent(layout) == hasCaptures, @"current revision follows completed nonempty capture result");
        Check([Kinds(layout) isEqual:fresh], @"completed display equals an independent full parse at every UTF-16 position");
    }
    __block BOOL persistedSyntax = NO;
    [storage enumerateAttribute:NVSourceCaptureAttributeName inRange:NSMakeRange(0, [storage length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) persistedSyntax = YES; }];
    Check(!persistedSyntax, @"syntax stays out of persisted source attributes");
}
static void Edit(NVSourceHighlighter *highlighter, NSTextStorage *storage, NSRange range, NSString *replacement, NSString *label) {
    NSMutableArray *models = [NSMutableArray array];
    for (NSLayoutManager *layout in [storage layoutManagers]) {
        NSMutableArray *expected = [Kinds(layout) mutableCopy];
        NSMutableArray *inserted = [NSMutableArray array];
        for (NSUInteger i = 0; i < [replacement length]; i++) [inserted addObject:[NSNull null]];
        [expected replaceObjectsInRange:range withObjectsFromArray:inserted];
        [models addObject:expected]; [expected release];
    }
    NSMutableString *expectedSource = [[storage string] mutableCopy];
    [expectedSource replaceCharactersInRange:range withString:replacement];
    NSUInteger writesBefore = AttributeWrites;
    uint64_t generation = [highlighter generation];
    [storage replaceCharactersInRange:range withString:replacement];
    Check([highlighter generation] > generation, [label stringByAppendingString:@": edit advances generation"]);
    Check(AttributeWrites == writesBefore, [label stringByAppendingString:@": edit performs no highlighter temporary-attribute mutation"]);
    Check([[storage string] isEqual:expectedSource], [label stringByAppendingString:@": exact edited source survives"]);
    [expectedSource release];
    Layout(storage);
    NSUInteger i = 0;
    for (NSLayoutManager *layout in [storage layoutManagers]) {
        Check(!NVSourceCapturesAreCurrent(layout), [label stringByAppendingString:@": semantics obsolete before debounce"]);
        Check(NVSourceCapturesCanDisplay(layout), [label stringByAppendingString:@": preceding revision remains displayable"]);
        Check([Kinds(layout) isEqual:models[i++]], [label stringByAppendingString:@": surviving character colors shift exactly with TextKit"]);
    }
    Histories++;
}
static void Run(NSString *directory, NSString *syntax, NSString *line, NSString *shortSource) {
    NSMutableString *source = [NSMutableString string];
    for (NSUInteger i = 0; i < 24; i++) [source appendString:line];
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13], @"fixture.persisted":@YES}];
    NSMutableArray *layouts = [NSMutableArray array];
    for (NSNumber *width in @[@150, @600]) {
        BoundaryLayout *layout = [[[BoundaryLayout alloc] init] autorelease];
        NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize([width doubleValue], CGFLOAT_MAX)] autorelease];
        [layout addTextContainer:container]; [storage addLayoutManager:layout]; [layouts addObject:layout];
    }
    NVSourceParser *oracle = [[NVSourceParser alloc] initWithQueryDirectory:directory];
    NVSourceHighlighter *highlighter = [[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:syntax queryDirectory:directory];
    Settle(highlighter, oracle, storage, syntax);
    for (NSUInteger round = 0; round < 4; round++) {
        Edit(highlighter, storage, NSMakeRange(0,0), @"😀\r\ne\u0301\n", @"Unicode prefix insertion");
        Edit(highlighter, storage, NSMakeRange(0,2), @"", @"surrogate pair deletion");
        NSRange combining = [[storage string] rangeOfString:@"e\u0301"];
        Edit(highlighter, storage, combining, @"é👩‍💻", @"combining sequence to emoji ZWJ replacement");
        NSRange emoji = [[storage string] rangeOfString:@"👩‍💻"];
        Edit(highlighter, storage, emoji, @"e\u0301", @"ZWJ cluster to combining sequence replacement");
        Edit(highlighter, storage, NSMakeRange(0, 6), @"", @"cached multiline prefix shortening");
        Settle(highlighter, oracle, storage, syntax);
    }
    // Coalesced character edits: TextKit may discard attributes inside its
    // aggregate edited span. Verify stable suffix and eventual full equivalence.
    NSArray *before = [Kinds(layouts[0]) copy];
    NSUInteger tail = [storage length] - 1;
    while (tail && before[tail] == [NSNull null]) tail--;
    id suffixKind = [[before objectAtIndex:tail] retain];
    NSUInteger writes = AttributeWrites;
    [storage beginEditing];
    [storage replaceCharactersInRange:NSMakeRange(0, 2) withString:@"\n"];
    [storage replaceCharactersInRange:NSMakeRange(4, 3) withString:@"😀"];
    [storage endEditing];
    Check(AttributeWrites == writes, @"coalesced replace/delete does not mutate temporary attributes during processing");
    Layout(storage);
    for (NSLayoutManager *layout in layouts) {
        Check(NVSourceCapturesCanDisplay(layout) && !NVSourceCapturesAreCurrent(layout), @"coalesced edit retains display-only revision");
        Check([[layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:tail-2 effectiveRange:NULL] isEqual:suffixKind], @"coalesced edit retains untouched suffix capture at adjusted index");
    }
    [before release]; [suffixKind release]; Histories++;
    Settle(highlighter, oracle, storage, syntax);
    Edit(highlighter, storage, NSMakeRange(0, [storage length]), shortSource, @"whole-document short replacement");
    Settle(highlighter, oracle, storage, syntax);
    Edit(highlighter, storage, NSMakeRange(0, [storage length]), @"", @"whole-document deletion");
    Settle(highlighter, oracle, storage, syntax);
    [storage replaceCharactersInRange:NSMakeRange(0,0) withString:shortSource];
    Layout(storage);
    for (NSLayoutManager *layout in layouts) Check(!NVSourceCapturesCanDisplay(layout), @"empty-to-source insertion cannot display a revision cleared by empty result");
    Settle(highlighter, oracle, storage, syntax); Histories++;
    Check(UnsafeChanges == 0, @"all syntax writes and removals occur outside character processing");
    NSLog(@"PASS %@: 24 native edit histories, two fully laid-out containers, UTF-16 exact display and independent final parse comparisons", syntax);
    [highlighter close]; [highlighter release];
    for (NSLayoutManager *layout in layouts) [storage removeLayoutManager:layout];
    [oracle release]; [storage release];
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"query directory supplied");
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        Run(directory, @"json", @"{\"emoji😀\":\"é👩‍💻\",\"number\":123,\"flag\":true}\r\n", @"{\"é😀\":false}\n");
        Run(directory, @"html", @"<p data-value=\"😀é👩‍💻\"><strong>Unicode</strong></p>\r\n", @"<b title=\"é😀\">new</b>\n");
        Run(directory, @"markdown", @"## Heading 😀\r\n**bold é👩‍💻** and `code`\n\n", @"# é😀\n**new** `code`\n");
        Check(UnsafeChanges == 0, @"zero temporary syntax mutations during character processing");
        NSLog(@"PASS: %lu assertions across %lu edit histories; unsafe mutations=%lu", (unsigned long)Checks, (unsigned long)Histories, (unsigned long)UnsafeChanges);
    }
    return 0;
}
