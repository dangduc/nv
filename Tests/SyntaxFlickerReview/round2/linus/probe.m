#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

static NSUInteger Checks, Writes, UnsafeWrites, Histories;
static void Check(BOOL ok, NSString *why) {
    Checks++;
    if (!ok) { NSLog(@"FAIL: %@", why); exit(1); }
}
static void Pump(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
}
@interface NVSourceHighlighter (Review)
- (void)analyze;
@end
@interface CheckedLayout : NSLayoutManager
@end
@implementation CheckedLayout
- (void)addTemporaryAttribute:(NSAttributedStringKey)key value:(id)value forCharacterRange:(NSRange)range {
    if ([key isEqual:NVSourceCaptureAttributeName]) {
        Writes++;
        if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeWrites++;
        Check(range.location <= [[self textStorage] length] && range.length <= [[self textStorage] length] - range.location, @"capture write is bounded");
    }
    [super addTemporaryAttribute:key value:value forCharacterRange:range];
}
- (void)removeTemporaryAttribute:(NSAttributedStringKey)key forCharacterRange:(NSRange)range {
    if ([key isEqual:NVSourceCaptureAttributeName]) {
        Writes++;
        if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeWrites++;
        Check(range.location <= [[self textStorage] length] && range.length <= [[self textStorage] length] - range.location, @"capture removal is bounded");
    }
    [super removeTemporaryAttribute:key forCharacterRange:range];
}
@end
static NSArray *Kinds(NSLayoutManager *layout) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i=0; i<[[layout textStorage] length]; i++)
        [result addObject:[layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:i effectiveRange:NULL] ?: [NSNull null]];
    return result;
}
static void CheckSource(NSTextStorage *storage, NSAttributedString *expected) {
    Check([storage isEqualToAttributedString:expected], @"exact source characters and persistent attributes survive highlighting");
    __block BOOL leaked = NO;
    [storage enumerateAttribute:NVSourceCaptureAttributeName inRange:NSMakeRange(0,[storage length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) leaked = YES; }];
    Check(!leaked, @"syntax capture never enters persistent source attributes");
}
static void Complete(NVSourceHighlighter *highlighter) {
    [NSObject cancelPreviousPerformRequestsWithTarget:highlighter selector:@selector(analyze) object:nil];
    [highlighter analyze];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while ([[highlighter valueForKey:@"analyzing"] boolValue] && [deadline timeIntervalSinceNow]>0) Pump(.005);
    Check(![[highlighter valueForKey:@"analyzing"] boolValue], @"worker completes within deadline");
}
static void Compare(NVSourceHighlighter *highlighter, NVSourceParser *oracle, NSTextStorage *storage, NSString *syntax) {
    NSAttributedString *expected=[[NSAttributedString alloc] initWithAttributedString:storage];
    Complete(highlighter);
    NSArray *captures=[oracle capturesForString:[storage string] syntaxIdentifier:syntax cancellationToken:NULL generation:0];
    Check(captures != nil && [captures count]>0, @"small fixture obtains nonempty independent captures");
    NSMutableArray *kinds=[NSMutableArray array];
    for(NSUInteger i=0;i<[storage length];i++) [kinds addObject:[NSNull null]];
    for(NSDictionary *capture in captures) {
        NSRange r=[capture[@"range"] rangeValue];
        Check(NSMaxRange(r)<=[storage length], @"oracle range bounded");
        for(NSUInteger i=r.location;i<NSMaxRange(r);i++) kinds[i]=capture[@"kind"];
    }
    for(NSLayoutManager *layout in [storage layoutManagers]) {
        [layout ensureLayoutForTextContainer:[[layout textContainers] firstObject]];
        Check(NVSourceCapturesAreCurrent(layout), @"completed short source is current");
        Check([Kinds(layout) isEqual:kinds], @"completed display equals independent parser including uncaptured gaps");
    }
    CheckSource(storage,expected); [expected release];
}
static void Plain(NVSourceHighlighter *highlighter, NSTextStorage *storage, NSString *label) {
    NSAttributedString *expected=[[NSAttributedString alloc] initWithAttributedString:storage];
    Complete(highlighter);
    for(NSLayoutManager *layout in [storage layoutManagers]) {
        Check(!NVSourceCapturesCanDisplay(layout) && !NVSourceCapturesAreCurrent(layout), [label stringByAppendingString:@": no display or semantics permission"]);
        // Enumerate runs, not half a million individual characters.
        for(NSUInteger i=0;i<[storage length];) {
            NSRange r; id value=[layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:i effectiveRange:&r];
            Check(value==nil, [label stringByAppendingString:@": no stale capture"]);
            Check(NSLocationInRange(i,r) && NSMaxRange(r)<=[storage length], @"plain display attribute range bounded");
            i=NSMaxRange(r);
        }
    }
    CheckSource(storage,expected); [expected release]; Histories++;
}
static void Attributes(NVSourceHighlighter *highlighter, NSTextStorage *storage, BOOL provisional) {
    NSArray *before=[Kinds([[storage layoutManagers] firstObject]) copy];
    NSUInteger writes=Writes; uint64_t generation=[highlighter generation];
    NSString *characters=[[storage string] copy];
    NSRange all=NSMakeRange(0,[storage length]);
    [storage beginEditing];
    [storage addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:21] range:all];
    [storage addAttribute:NSLinkAttributeName value:@"https://example.invalid/review" range:NSMakeRange(1,3)];
    [storage addAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] range:NSMakeRange(2,4)];
    [storage addAttribute:NSForegroundColorAttributeName value:[NSColor purpleColor] range:all];
    [storage endEditing];
    Check([highlighter generation]==generation, @"attribute-only changes do not obsolete source analysis");
    Check(Writes==writes, @"attribute-only transaction causes no highlighter display writes");
    Check([[storage string] isEqual:characters], @"attribute-only transaction preserves characters");
    for(NSLayoutManager *layout in [storage layoutManagers]) {
        [layout ensureLayoutForTextContainer:[[layout textContainers] firstObject]];
        Check([Kinds(layout) isEqual:before], @"attribute-only changes retain all adjusted capture positions");
        Check(NVSourceCapturesCanDisplay(layout), @"attribute-only changes retain display permission");
        Check(NVSourceCapturesAreCurrent(layout)==!provisional, @"attribute-only changes preserve current versus provisional status");
    }
    if(!provisional) {
        Pump(.09);
        Check([highlighter generation]==generation && Writes==writes, @"current attribute-only change does not schedule a later reparse");
    }
    [before release]; [characters release]; Histories++;
}
static void Run(NSString *directory, NSString *syntax, NSString *source) {
    NSTextStorage *storage=[[NSTextStorage alloc] initWithString:source attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13],@"review.persistent":@1}];
    for(NSNumber *width in @[@160,@500]) {
        CheckedLayout *layout=[[CheckedLayout alloc] init];
        NSTextContainer *container=[[NSTextContainer alloc] initWithContainerSize:NSMakeSize([width doubleValue],CGFLOAT_MAX)];
        [layout addTextContainer:container]; [storage addLayoutManager:layout]; [container release]; [layout release];
    }
    NVSourceHighlighter *highlighter=[[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:syntax queryDirectory:directory];
    NVSourceParser *oracle=[[NVSourceParser alloc] initWithQueryDirectory:directory];
    Compare(highlighter,oracle,storage,syntax);
    Attributes(highlighter,storage,NO);
    [storage replaceCharactersInRange:NSMakeRange([storage length],0) withString:@" "];
    Attributes(highlighter,storage,YES);
    Compare(highlighter,oracle,storage,syntax);

    NSAttributedString *replacement=[[NSAttributedString alloc] initWithString:[storage string] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSBackgroundColorAttributeName:[NSColor cyanColor],@"review.replacement":@2}];
    uint64_t generation=[highlighter generation]; NSUInteger writes=Writes;
    [storage setAttributedString:replacement];
    Check(Writes==writes, @"identical-character full attributed replacement does not mutate captures during character processing");
    NSLog(@"OBSERVE %@ identical-character attributed replacement: generation delta=%llu",syntax,(unsigned long long)([highlighter generation]-generation));
    Compare(highlighter,oracle,storage,syntax);
    CheckSource(storage,replacement); [replacement release]; Histories++;

    [storage replaceCharactersInRange:NSMakeRange([storage length],0) withString:@" "];
    for(NSLayoutManager *layout in [storage layoutManagers]) Check(NVSourceCapturesCanDisplay(layout) && !NVSourceCapturesAreCurrent(layout), @"pending edit has provisional captures before syntax change");
    [highlighter setSyntaxIdentifier:@"unsupported-review-format"];
    for(NSLayoutManager *layout in [storage layoutManagers]) Check(!NVSourceCapturesCanDisplay(layout), @"unsupported syntax immediately revokes provisional colors");
    Plain(highlighter,storage,@"unsupported syntax fallback");
    [highlighter setSyntaxIdentifier:syntax]; Compare(highlighter,oracle,storage,syntax); Histories++;

    NSMutableString *oversize=[NSMutableString stringWithString:source];
    while([oversize length]<524289) [oversize appendString:@"                                                                                                                                "];
    [storage replaceCharactersInRange:NSMakeRange(0,[storage length]) withString:oversize];
    Plain(highlighter,storage,@"source length budget fallback");
    [storage replaceCharactersInRange:NSMakeRange(0,[storage length]) withString:source];
    Compare(highlighter,oracle,storage,syntax); Histories++;

    // Cocoa permits constructing an unpaired surrogate. Check whether storage
    // preserves it; only assert rejection if lossless UTF-16 conversion fails.
    unichar invalidUnits[]={ 'x',0xD800,'y' };
    NSString *invalid=[[NSString alloc] initWithCharacters:invalidUnits length:3];
    [storage replaceCharactersInRange:NSMakeRange(0,[storage length]) withString:invalid];
    Check([[storage string] isEqual:invalid], @"native storage preserves the malformed UTF-16 fixture");
    NSData *encoded=[invalid dataUsingEncoding:NSUTF16LittleEndianStringEncoding allowLossyConversion:NO];
    NSLog(@"OBSERVE %@ isolated surrogate: length=%lu, lossless UTF-16 bytes=%lu",syntax,(unsigned long)[invalid length],(unsigned long)[encoded length]);
    NSArray *invalidCaptures=[oracle capturesForString:invalid syntaxIdentifier:syntax cancellationToken:NULL generation:0];
    if([encoded length]!=[invalid length]*2) Check(invalidCaptures==nil,@"lossless UTF-16 encoding failure rejects parse");
    else Check(invalidCaptures==nil || [invalidCaptures count]==0,@"accepted invalid UTF-16 fixture has no syntax captures");
    Plain(highlighter,storage,@"isolated surrogate fallback");
    [invalid release];
    [storage replaceCharactersInRange:NSMakeRange(0,[storage length]) withString:source];
    Compare(highlighter,oracle,storage,syntax); Histories++;
    Check(UnsafeWrites==0,@"all temporary capture writes occur outside character processing");
    NSLog(@"PASS %@: current/provisional attribute edits, identical-character replacement, unsupported and oversized and malformed source fallback/recovery",syntax);
    [highlighter close]; [highlighter release]; [oracle release]; [storage release];
}
static void DisplayBudget(NSString *directory) {
    NSString *source=@"{\"small\":true}";
    NSTextStorage *storage=[[NSTextStorage alloc] initWithString:source];
    for(NSUInteger i=0;i<2;i++) { CheckedLayout *layout=[[CheckedLayout alloc] init]; [storage addLayoutManager:layout]; [layout release]; }
    NVSourceHighlighter *highlighter=[[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory];
    NVSourceParser *oracle=[[NVSourceParser alloc] initWithQueryDirectory:directory];
    Complete(highlighter);
    NSMutableString *large=[NSMutableString stringWithString:@"["];
    for(NSUInteger i=0;i<3000;i++) [large appendFormat:@"%lu%@",(unsigned long)i,i==2999?@"]":@","];
    NSArray *captures=[oracle capturesForString:large syntaxIdentifier:@"json" cancellationToken:NULL generation:0];
    Check([captures count]>2048 && [captures count]<30000,@"fixture exceeds two-layout display operation budget but yields complete parser output");
    NSLog(@"OBSERVE display budget fixture: %lu parser captures across two layouts",(unsigned long)[captures count]);
    [storage replaceCharactersInRange:NSMakeRange(0,[storage length]) withString:large];
    Plain(highlighter,storage,@"display operation budget fallback");
    [storage replaceCharactersInRange:NSMakeRange(0,[storage length]) withString:source];
    Complete(highlighter);
    for(NSLayoutManager *layout in [storage layoutManagers]) Check(NVSourceCapturesAreCurrent(layout),@"small-source highlighting recovers after display budget fallback");
    Check([[storage string] isEqual:source],@"budget recovery preserves source"); Histories++;
    [highlighter close]; [highlighter release]; [oracle release]; [storage release];
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==2,@"query directory supplied"); NSString *directory=[NSString stringWithUTF8String:argv[1]];
        Run(directory,@"json",@"{\"key\":true,\"number\":123}");
        Run(directory,@"html",@"<b title=\"x\">text</b>");
        Run(directory,@"markdown",@"# Heading\n**bold** `code`\n");
        DisplayBudget(directory);
        Check(UnsafeWrites==0,@"zero unsafe capture mutations in all histories");
        NSLog(@"PASS: %lu assertions, %lu bounded histories, %lu unsafe capture writes",(unsigned long)Checks,(unsigned long)Histories,(unsigned long)UnsafeWrites);
    }
    return 0;
}
