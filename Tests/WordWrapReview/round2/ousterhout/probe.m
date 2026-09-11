// Reuse the prior headless ownership harness, not its test entry point.
#define main RoundOneMain
#include "../../round1/ousterhout/probe.m"
#undef main
static BOOL OmitCompletionCleanup;
static NSUInteger CallbackEnds,PartialEnds,MeasuredEnds;
@interface NVSourceTypesetter (ReviewCleanupDeclaration)
- (void)clearParagraphAnalysis;
@end
@interface CallbackObserver : ObservedTypesetter {
    BOOL finishingParagraph;
    NSUInteger lastLineEnd;
}
@end
@implementation CallbackObserver
- (void)beginParagraph { [super beginParagraph]; lastLineEnd=0; }
- (void)endLineWithGlyphRange:(NSRange)range {
    [super endLineWithGlyphRange:range]; lastLineEnd=NSMaxRange(range);
}
- (void)clearParagraphAnalysis {
    // A negative control omits only the new completion cleanup; begin/dealloc cleanup still run.
    if(OmitCompletionCleanup && finishingParagraph) return;
    [super clearParagraphAnalysis];
}
- (void)endParagraph {
    BOOL hadMeasure=paragraphMeasure!=NULL;
    if(CallbackEnds<8) fprintf(stderr,"CALLBACK last=%lu paragraph=%s measure=%d\n",(unsigned long)lastLineEnd,NSStringFromRange(self.paragraphGlyphRange).UTF8String,hadMeasure);
    BOOL partial=lastLineEnd>self.paragraphGlyphRange.location && lastLineEnd<NSMaxRange(self.paragraphGlyphRange);
    finishingParagraph=YES; [super endParagraph]; finishingParagraph=NO;
    CallbackEnds++; if(partial) PartialEnds++; if(hadMeasure) MeasuredEnds++;
    Check(paragraphMeasure==NULL && lineBreaks==nil,@"paragraph completion releases analysis before returning to the native layout caller");
}
@end
static void InstallObserver(System *system) {
    [system->typesetter release];
    system->typesetter=[[CallbackObserver alloc]init];
    system->layout.typesetter=system->typesetter;
}
static void AddPages(System *system) {
    system->container.containerSize=NSMakeSize(240,45);
    for(NSNumber *height in @[@63,@1000000]) {
        NSTextContainer *next=[[[NSTextContainer alloc]initWithSize:NSMakeSize(height.doubleValue>1000?310:270,height.doubleValue)]autorelease];
        [system->layout addTextContainer:next];
    }
}
static NSArray *PagedSnapshot(System *system) {
    [system->layout ensureLayoutForTextContainer:system->layout.textContainers.lastObject];
    NSMutableArray *result=[NSMutableArray array];
    [system->layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,system->layout.numberOfGlyphs) usingBlock:^(NSRect rect,NSRect used,NSTextContainer *container,NSRange glyphs,BOOL *stop) {
        [result addObject:@[@([system->layout.textContainers indexOfObjectIdenticalTo:container]),NSStringFromRange(glyphs),NSStringFromRect(rect),NSStringFromRect(used)]];
    }];
    return result;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc<2)return 2;
        OmitCompletionCleanup=argc>2;
        for(NSUInteger pass=0;pass<6;pass++) {
            @autoreleasepool {
                NSString *paragraph=[@"" stringByPaddingToLength:1177+pass*11 withString:@"alpha beta gamma delta epsilon zeta " startingAtIndex:0];
                NSString *source=[paragraph stringByAppendingString:@"\nlast short paragraph\n"];
                NSTextStorage *storage=[[[NSTextStorage alloc]initWithString:source attributes:Attributes(pass)]autorelease];
                System *system=[[[System alloc]initWithStorage:storage width:240]autorelease];
                InstallObserver(system); system->container.containerSize=NSMakeSize(240,45);
                NSAttributedString *before=[storage copy];
                [system->layout ensureLayoutForTextContainer:system->container];
                NSRange first=[system->layout glyphRangeForTextContainer:system->container];
                Check(first.length>0 && NSMaxRange(first)<paragraph.length,@"the first finite container ends inside a source paragraph");
                Check(![[system->typesetter cacheState][@"hasMeasure"] boolValue],@"partial container layout has no completed measurement left attached");
                AddPages(system);
                NSArray *incremental=PagedSnapshot(system);
                System *fresh=[[[System alloc]initWithStorage:[[[NSTextStorage alloc]initWithAttributedString:storage]autorelease] width:240]autorelease];
                InstallObserver(fresh); AddPages(fresh);
                Check([incremental isEqual:PagedSnapshot(fresh)],@"resuming the partial paragraph matches a fresh paginated production layout");
                Check([storage isEqualToAttributedString:before],@"completion cleanup preserves source attributes during partial and resumed layout");
                [before release];
                for(NSUInteger reuse=0;reuse<4;reuse++) {
                    NSString *replacement=reuse%2?@"fresh words after blank paragraphs\r\n\r\nfinal reused words":@"\n\n";
                    [storage setAttributedString:[[[NSAttributedString alloc]initWithString:replacement attributes:Attributes(pass+reuse+1)]autorelease]];
                    NSArray *actual=PagedSnapshot(system);
                    System *reference=[[[System alloc]initWithStorage:[[[NSTextStorage alloc]initWithAttributedString:storage]autorelease] width:240]autorelease];
                    InstallObserver(reference); AddPages(reference);
                    Check([actual isEqual:PagedSnapshot(reference)],@"repeated blank and CRLF paragraph reuse matches fresh layout after font changes");
                    Check(![[system->typesetter cacheState][@"hasMeasure"] boolValue] && [[system->typesetter cacheState][@"breakBytes"] unsignedIntegerValue]==0,@"reused typesetter releases both completed analysis objects");
                }
            }
        }
        fprintf(stderr,"COUNTS partial=%lu measured=%lu ends=%lu\n",(unsigned long)PartialEnds,(unsigned long)MeasuredEnds,(unsigned long)CallbackEnds);
        Check(PartialEnds>0 && MeasuredEnds>0,@"observer witnessed measured completion and container exhaustion inside paragraphs");
        Check(Created==Destroyed,@"partial-layout and reuse systems release all typesetters");
        NSDictionary *result=@{@"checks":@(Checks),@"partialEnds":@(PartialEnds),@"paragraphCompletionCallbacks":@(CallbackEnds),@"measuredEnds":@(MeasuredEnds),@"typesettersCreated":@(Created),@"typesettersDestroyed":@(Destroyed),@"partialContainerCases":@6,@"reuseCycles":@24};
        [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL]writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES];
        fprintf(stderr,"PASS: %lu checks; %lu partial paragraph completions\n",(unsigned long)Checks,(unsigned long)PartialEnds);
    }
    return 0;
}
