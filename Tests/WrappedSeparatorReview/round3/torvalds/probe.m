#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include "production.inc"

static NSUInteger Checks, OraclePairs;
static void Check(BOOL condition, NSString *message) {
    Checks++;
    if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
static NSString *Scalar(UTF32Char scalar) {
    unichar text[2]; NSUInteger n = 1;
    if (scalar <= 0xffff) text[0] = (unichar)scalar;
    else { scalar -= 0x10000; text[0] = 0xd800 + (scalar >> 10); text[1] = 0xdc00 + (scalar & 0x3ff); n = 2; }
    return [NSString stringWithCharacters:text length:n];
}
static NSString *Triplet(unichar left, unichar right) {
    unichar chars[] = {left, ' ', right};
    return [NSString stringWithCharacters:chars length:3];
}
static NSDictionary *Snapshot(NSString *source, Class delegateClass) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source attributes:
        @{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18], @"Marker":@"source unchanged"}];
    NSLayoutManager *layout = [NSLayoutManager new];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(100,1000000)];
    id delegate = delegateClass ? [delegateClass new] : nil;
    [storage addLayoutManager:layout]; [layout addTextContainer:container]; layout.delegate = delegate;
    [layout ensureGlyphsForCharacterRange:NSMakeRange(0,source.length)];
    NSUInteger count = layout.numberOfGlyphs;
    NSMutableData *glyphs = [NSMutableData dataWithLength:count*sizeof(CGGlyph)];
    NSMutableData *properties = [NSMutableData dataWithLength:count*sizeof(NSGlyphProperty)];
    NSMutableData *indexes = [NSMutableData dataWithLength:count*sizeof(NSUInteger)];
    NSMutableData *bidi = [NSMutableData dataWithLength:count];
    Check([layout getGlyphsInRange:NSMakeRange(0,count) glyphs:glyphs.mutableBytes properties:properties.mutableBytes
        characterIndexes:indexes.mutableBytes bidiLevels:bidi.mutableBytes] == count, @"complete native glyph generation");
    Check([storage.string isEqual:source], @"production callback preserves source text");
    NSAttributedString *attributes = [[[NSAttributedString alloc] initWithAttributedString:storage] autorelease];
    NSDictionary *result = @{@"glyphs":glyphs,@"properties":properties,@"indexes":indexes,
        @"bidi":bidi,@"count":@(count),@"attributes":attributes};
    layout.delegate = nil; [delegate release]; [container release]; [layout release]; [storage release];
    return result;
}
static NSDictionary *Compare(NSString *name, NSString *source) {
    NSDictionary *before = Snapshot(source, [PreviousDelegate class]);
    NSDictionary *after = Snapshot(source, [CorrectedDelegate class]);
    NSDictionary *native = Snapshot(source, Nil);
    for (NSString *key in @[@"glyphs",@"properties",@"indexes",@"bidi",@"count",@"attributes"])
        Check([before[key] isEqual:after[key]], [NSString stringWithFormat:@"%@ pre/post %@ equality",name,key]);
    for (NSString *key in @[@"glyphs",@"indexes",@"bidi",@"count",@"attributes"])
        Check([native[key] isEqual:after[key]], [NSString stringWithFormat:@"%@ native %@ invariant",name,key]);
    const NSUInteger *indexes = [after[@"indexes"] bytes];
    const NSGlyphProperty *actual = [after[@"properties"] bytes], *raw = [native[@"properties"] bytes];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger eligible = 0, retained = 0, removed = 0;
    for (NSUInteger glyph = 0; glyph < [after[@"count"] unsignedIntegerValue]; glyph++) {
        NSUInteger index = indexes[glyph];
        Check(index < source.length, @"glyph index stays within UTF-16 source");
        Check((actual[glyph]|raw[glyph]) == raw[glyph] && ((actual[glyph]^raw[glyph])&~NSGlyphPropertyElastic) == 0,
            @"only native Elastic removal is permitted");
        BOOL candidate = [source characterAtIndex:index] == ' ' && (raw[glyph]&NSGlyphPropertyElastic) && !(raw[glyph]&NSGlyphPropertyControlCharacter);
        NSGlyphProperty expected = raw[glyph];
        if (candidate) {
            // Foundation always answers this independent oracle; there is no ASCII shortcut here.
            NSRange composed = [source rangeOfComposedCharacterSequenceAtIndex:index];
            BOOL singleton = NSEqualRanges(composed, NSMakeRange(index,1));
            BOOL interior = index > 0 && index + 1 < source.length;
            BOOL separator = interior && singleton &&
                ![whitespace characterIsMember:[source characterAtIndex:index-1]] &&
                ![whitespace characterIsMember:[source characterAtIndex:index+1]];
            if (!separator) expected &= ~NSGlyphPropertyElastic;
            eligible++; if (separator) retained++; else removed++;
        }
        Check(actual[glyph] == expected, @"corrected properties follow the unconditional Foundation oracle");
    }
    return @{@"batch":name,@"UTF16Length":@(source.length),@"glyphs":[after objectForKey:@"count"],
        @"eligibleSpaces":@(eligible),@"retainedElastic":@(retained),@"removedElastic":@(removed)};
}
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    NSArray *contexts = @[
        @{@"name":@"plain",@"prefix":@"",@"suffix":@""},
        @{@"name":@"prepend",@"prefix":@"\u0600\u0600",@"suffix":@""},
        @{@"name":@"combining",@"prefix":@"\u0301",@"suffix":@"\u0301\ufe0f"},
        @{@"name":@"ZWJ emoji",@"prefix":@"\U0001f469\u200d",@"suffix":@"\u200d\U0001f4bb"},
        @{@"name":@"bidi isolation",@"prefix":@"\u2067\u05d0",@"suffix":@"\u2069"},
        @{@"name":@"paragraph boundaries",@"prefix":@"\r\n",@"suffix":@"\u2028\u2029"},
        @{@"name":@"supplementary marks",@"prefix":@"\U0001f1fa\U0001f1f8",@"suffix":@"\U000e0100"}
    ];
    NSMutableString *ascii = [NSMutableString string], *surroundings = [NSMutableString string];
    NSMutableArray *oracleSummary = [NSMutableArray array], *nativeSummary = [NSMutableArray array];
    for (NSDictionary *context in contexts) {
        NSUInteger pairs = 0;
        for (unichar left = '!'; left <= '~'; left++) { @autoreleasepool {
            for (unichar right = '!'; right <= '~'; right++) {
                NSString *source = [NSString stringWithFormat:@"%@%@%@",context[@"prefix"],Triplet(left,right),context[@"suffix"]];
                NSUInteger target = [context[@"prefix"] length] + 1;
                Check(NSEqualRanges([source rangeOfComposedCharacterSequenceAtIndex:target],NSMakeRange(target,1)),
                    @"every printable ASCII pair yields a singleton space in Foundation");
                pairs++; OraclePairs++;
                if ([context[@"name"] isEqual:@"plain"]) [ascii appendFormat:@"%@\n",source];
                else if ((left=='!' || left=='A' || left=='\\' || left=='~') && (right=='!' || right=='A' || right=='\\' || right=='~'))
                    [surroundings appendFormat:@"%@\n",source];
            }
        }}
        [oracleSummary addObject:@{@"context":context[@"name"],@"pairs":@(pairs),@"singletonSpaces":@(pairs)}];
    }
    @autoreleasepool { [nativeSummary addObject:Compare(@"all 8836 printable ASCII pairs",ascii)]; }
    @autoreleasepool { [nativeSummary addObject:Compare(@"96 non-ASCII surroundings",surroundings)]; }
    NSMutableString *boundaries = [NSMutableString string];
    unichar edges[] = {0x20,0x21,0x7e,0x7f};
    for (NSUInteger left=0; left<4; left++) for (NSUInteger right=0; right<4; right++)
        [boundaries appendFormat:@"%@\n",Triplet(edges[left],edges[right])];
    [boundaries appendString:@" \nA \n A\n\n"]; // source and paragraph edges
    @autoreleasepool { [nativeSummary addObject:Compare(@"ASCII and paragraph boundaries",boundaries)]; }
    NSMutableString *fallback = [NSMutableString string]; NSUInteger whitespaceMembers = 0;
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (UTF32Char scalar=0; scalar<=0x10ffff; scalar++) {
        if (scalar>=0xd800 && scalar<=0xdfff) continue;
        if ([whitespace longCharacterIsMember:scalar]) {
            whitespaceMembers++; NSString *s=Scalar(scalar); [fallback appendFormat:@"%@ R\nL %@\n",s,s];
        }
    }
    UTF32Char selected[] = {0x200c,0x200d,0x2060,0xfeff,0x200e,0x200f,0x061c,0x2066,0x2067,0x2068,0x2069,0x0600,0x0301,0xfe0f,0xe0100,0x1f600};
    for (NSUInteger i=0; i<sizeof(selected)/sizeof(*selected); i++) {
        NSString *s=Scalar(selected[i]); [fallback appendFormat:@"%@ R\nL %@\n",s,s];
    }
    @autoreleasepool { [nativeSummary addObject:Compare(@"Unicode fallback and composed spaces",fallback)]; }
    Check(OraclePairs == 7*94*94,@"complete printable ASCII context matrix");
    NSDictionary *result = @{@"passed":@YES,@"checks":@(Checks+1),@"oraclePairs":@(OraclePairs),
        @"FoundationWhitespaceMembers":@(whitespaceMembers),@"oracleContexts":oracleSummary,@"nativeBatches":nativeSummary};
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    Check([json writeToFile:@(argv[1]) atomically:YES],@"write compact evidence");
    printf("PASS %lu checks, %lu Foundation pair/context observations, %lu native batches\n",
        (unsigned long)Checks,(unsigned long)OraclePairs,(unsigned long)nativeSummary.count);
} return 0; }
