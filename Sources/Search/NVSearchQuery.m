#import "NVSearchQuery.h"

@implementation NVSearchTerm
@synthesize text = _text, phrase = _phrase;
- (id)initWithText:(NSString *)text phrase:(BOOL)phrase {
    if ((self = [super init])) { _text = [text copy]; _phrase = phrase; }
    return self;
}
- (void)dealloc { [_text release]; [super dealloc]; }
@end

@implementation NVSearchQuery
@synthesize string = _string, terms = _terms;
- (id)initWithString:(NSString *)string {
    if ((self = [super init])) {
        _string = [(string ?: @"") copy];
        NSMutableArray *terms = [NSMutableArray array];
        NSMutableString *text = [NSMutableString string];
        NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" :\t\r\n"];
        BOOL quoted = NO;
        for (NSUInteger i = 0; i < [_string length]; ++i) {
            unichar c = [_string characterAtIndex:i];
            if (c == '"' || (!quoted && [separators characterIsMember:c])) {
                if ([text length]) {
                    [terms addObject:[[[NVSearchTerm alloc] initWithText:text phrase:quoted] autorelease]];
                    [text setString:@""];
                }
                if (c == '"') quoted = !quoted;
            } else [text appendFormat:@"%C", c];
        }
        if ([text length]) [terms addObject:[[[NVSearchTerm alloc] initWithText:text phrase:quoted] autorelease]];
        _terms = [terms copy];
    }
    return self;
}
- (void)dealloc { [_string release]; [_terms release]; [super dealloc]; }
- (BOOL)hasTerms { return [_terms count] != 0; }
- (BOOL)matchesTitle:(NSString *)title {
    for (NVSearchTerm *term in _terms)
        if ([title rangeOfString:[term text] options:NSCaseInsensitiveSearch].location == NSNotFound) return NO;
    return YES;
}
- (NSArray *)literalRangesInString:(NSString *)string {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NVSearchTerm *term in _terms) {
        NSRange remaining = NSMakeRange(0, [string length]);
        while (remaining.length) {
            NSRange range = [string rangeOfString:[term text] options:NSCaseInsensitiveSearch range:remaining];
            if (range.location == NSNotFound || !range.length) break;
            [indexes addIndexesInRange:[string rangeOfComposedCharacterSequencesForRange:range]];
            remaining = NSMakeRange(NSMaxRange(range), [string length] - NSMaxRange(range));
        }
    }
    NSMutableArray *ranges = [NSMutableArray array];
    [indexes enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        [ranges addObject:[NSValue valueWithRange:range]];
    }];
    return ranges;
}
@end
