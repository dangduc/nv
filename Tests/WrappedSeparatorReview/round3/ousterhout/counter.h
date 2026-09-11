#import <objc/runtime.h>

// Instrument only this disposable process's concrete storage-string class.
// The frozen production callback itself is inserted unchanged.
static IMP OriginalCharacter,OriginalComposed;
static Class ObservedStringClass;
static NSString *ObservedSource;
static BOOL InProductionCallback;
static NSUInteger QueryDepth,DirectReads,ComposedQueries,BudgetCallbacks;
static unichar CountCharacter(id object,SEL selector,NSUInteger index) {
    if(InProductionCallback && object==ObservedSource && !QueryDepth) DirectReads++;
    return ((unichar (*)(id,SEL,NSUInteger))OriginalCharacter)(object,selector,index);
}
static NSRange CountComposed(id object,SEL selector,NSUInteger index) {
    BOOL count=InProductionCallback && object==ObservedSource;
    if(count) { ComposedQueries++; QueryDepth++; }
    NSRange range=((NSRange (*)(id,SEL,NSUInteger))OriginalComposed)(object,selector,index);
    if(count) QueryDepth--;
    return range;
}
static void InstallCounters(NSString *source) {
    ObservedStringClass=object_getClass(source);
    SEL character=@selector(characterAtIndex:),composed=@selector(rangeOfComposedCharacterSequenceAtIndex:);
    OriginalCharacter=class_getMethodImplementation(ObservedStringClass,character);
    OriginalComposed=class_getMethodImplementation(ObservedStringClass,composed);
    Check(OriginalCharacter && OriginalComposed,@"native source primitives exist");
    class_replaceMethod(ObservedStringClass,character,(IMP)CountCharacter,
                        method_getTypeEncoding(class_getInstanceMethod(ObservedStringClass,character)));
    class_replaceMethod(ObservedStringClass,composed,(IMP)CountComposed,
                        method_getTypeEncoding(class_getInstanceMethod(ObservedStringClass,composed)));
}
static void RemoveCounters(void) {
    class_replaceMethod(ObservedStringClass,@selector(characterAtIndex:),OriginalCharacter,
                        method_getTypeEncoding(class_getInstanceMethod(ObservedStringClass,@selector(characterAtIndex:))));
    class_replaceMethod(ObservedStringClass,@selector(rangeOfComposedCharacterSequenceAtIndex:),OriginalComposed,
                        method_getTypeEncoding(class_getInstanceMethod(ObservedStringClass,@selector(rangeOfComposedCharacterSequenceAtIndex:))));
}
@interface CountingDelegate : ProductionDelegate {
@public NSUInteger generated,reads,queries,asciiCandidates,fallbackCandidates,callbacks;
}
@end
@implementation CountingDelegate
- (NSUInteger)layoutManager:(NSLayoutManager *)layout shouldGenerateGlyphs:(const CGGlyph *)glyphs
    properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes
    font:(NSFont *)font forGlyphRange:(NSRange)range {
    Check(!InProductionCallback,@"native callback is not recursively entered in this history");
    NSString *source=layout.textStorage.string;
    Check(object_getClass(source)==ObservedStringClass,@"the callback source uses the instrumented concrete string class");
    NSUInteger expectedReads=0,expectedQueries=0,ascii=0;
    NSCharacterSet *whitespace=[NSCharacterSet whitespaceAndNewlineCharacterSet];
    // Compute the expected budget from native input glyph candidates before
    // counters are active. No source or glyph state changes occur here.
    for(NSUInteger i=0;i<range.length;i++) {
        NSUInteger index=indexes[i];
        if(!(properties[i]&NSGlyphPropertyElastic) || (properties[i]&NSGlyphPropertyControlCharacter) || index>=source.length) continue;
        expectedReads++;
        if([source characterAtIndex:index]!=' ' || !index || index+1>=source.length) continue;
        expectedReads+=2;
        unichar left=[source characterAtIndex:index-1],right=[source characterAtIndex:index+1];
        if([whitespace characterIsMember:left] || [whitespace characterIsMember:right]) continue;
        if(left>=0x21 && left<=0x7e && right>=0x21 && right<=0x7e) ascii++;
        else expectedQueries++;
    }
    NSUInteger beforeReads=DirectReads,beforeQueries=ComposedQueries;
    ObservedSource=source; InProductionCallback=YES;
    NSUInteger result=[super layoutManager:layout shouldGenerateGlyphs:glyphs properties:properties
                            characterIndexes:indexes font:font forGlyphRange:range];
    InProductionCallback=NO; ObservedSource=nil;
    NSUInteger actualReads=DirectReads-beforeReads,actualQueries=ComposedQueries-beforeQueries;
    Check(actualReads==expectedReads,@"callback reads each candidate and each bounded neighbor only once");
    Check(actualQueries==expectedQueries,@"only eligible non-ASCII contexts query a composed range");
    Check(QueryDepth==0 && ObservedSource==nil,@"callback query instrumentation retains no context");
    generated+=range.length; reads+=actualReads; queries+=actualQueries;
    asciiCandidates+=ascii; fallbackCandidates+=expectedQueries; callbacks++; BudgetCallbacks++;
    return result;
}
@end
