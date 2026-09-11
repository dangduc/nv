#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "space-delegate.h"

static NSUInteger Checks, ParagraphBegins, ParagraphEnds, ActiveAnalysisEnds, NarrowedLines;
static void Check(BOOL ok,NSString *message) {
    Checks++;
    if(!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
@interface ObservedTypesetter:NVSourceTypesetter
- (BOOL)hasAnalysis;
@end
@implementation ObservedTypesetter
- (BOOL)hasAnalysis { return paragraphMeasure!=NULL || lineBreaks!=nil; }
- (void)beginParagraph { ParagraphBegins++; [super beginParagraph]; }
- (void)endParagraph {
    if([self hasAnalysis])ActiveAnalysisEnds++;
    [super endParagraph]; ParagraphEnds++;
    Check(![self hasAnalysis],@"native paragraph completion clears analysis");
}
- (void)getLineFragmentRect:(NSRect *)rect usedRect:(NSRect *)used remainingRect:(NSRect *)remaining
    forStartingGlyphAtIndex:(NSUInteger)start proposedRect:(NSRect)proposed lineSpacing:(CGFloat)spacing
    paragraphSpacingBefore:(CGFloat)before paragraphSpacingAfter:(CGFloat)after {
    [super getLineFragmentRect:rect usedRect:used remainingRect:remaining forStartingGlyphAtIndex:start
        proposedRect:proposed lineSpacing:spacing paragraphSpacingBefore:before paragraphSpacingAfter:after];
    if(limitedLineWidth)NarrowedLines++;
}
@end
@interface Context:NSObject {
@public NSTextStorage *storage; NSLayoutManager *layout; NSTextContainer *container; SpaceDelegate *delegate;
}
- (id)initWithStorage:(NSTextStorage *)text width:(CGFloat)width native:(BOOL)native;
- (NSDictionary *)snapshot;
@end
@implementation Context
- (id)initWithStorage:(NSTextStorage *)text width:(CGFloat)width native:(BOOL)native {
    if((self=[super init])) {
        storage=[text retain]; layout=[NSLayoutManager new];
        container=[[NSTextContainer alloc]initWithSize:NSMakeSize(width,100000)];
        delegate=[SpaceDelegate new]; [storage addLayoutManager:layout]; [layout addTextContainer:container];
        layout.delegate=delegate;
        if(!native)layout.typesetter=[[[ObservedTypesetter alloc]init]autorelease];
    }
    return self;
}
- (NSDictionary *)snapshot {
    [layout ensureLayoutForTextContainer:container];
    NSUInteger count=layout.numberOfGlyphs;
    NSMutableArray *lines=[NSMutableArray array],*points=[NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,count) usingBlock:^(NSRect rect,NSRect used,NSTextContainer *c,NSRange g,BOOL *stop) {
        NSRange chars=[layout characterRangeForGlyphRange:g actualGlyphRange:NULL];
        Check(chars.location==storage.length || [storage.string rangeOfComposedCharacterSequenceAtIndex:chars.location].location==chars.location,@"line starts at composed character boundary");
        [lines addObject:@[@(chars.location),@(chars.length),@(rect.origin.x),@(rect.origin.y),@(rect.size.width),@(rect.size.height),@(used.origin.x),@(used.size.width)]];
    }];
    NSMutableData *glyphs=[NSMutableData dataWithLength:count*sizeof(CGGlyph)];
    NSMutableData *properties=[NSMutableData dataWithLength:count*sizeof(NSGlyphProperty)];
    NSMutableData *indexes=[NSMutableData dataWithLength:count*sizeof(NSUInteger)];
    NSMutableData *levels=[NSMutableData dataWithLength:count];
    Check([layout getGlyphsInRange:NSMakeRange(0,count)glyphs:glyphs.mutableBytes properties:properties.mutableBytes characterIndexes:indexes.mutableBytes bidiLevels:levels.mutableBytes]==count,@"complete glyph mapping");
    for(NSUInteger i=0;i<count;i++) {
        NSPoint point=[layout locationForGlyphAtIndex:i];
        [points addObject:@[@(point.x),@(point.y)]];
    }
    return @{@"lines":lines,@"points":points,@"glyphs":glyphs,@"properties":properties,@"indexes":indexes,@"bidi":levels};
}
- (void)dealloc {
    layout.delegate=nil; [storage removeLayoutManager:layout];
    [delegate release]; [container release]; [layout release]; [storage release]; [super dealloc];
}
@end
static NSAttributedString *Text(NSString *source,NSString *fontName,CGFloat size) {
    NSFont *font=[NSFont fontWithName:fontName size:size]; Check(font!=nil,@"fixture font exists");
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];
    style.lineBreakMode=NSLineBreakByCharWrapping;
    return [[[NSAttributedString alloc]initWithString:source attributes:@{NSFontAttributeName:font,NSParagraphStyleAttributeName:style,@"Marker":@"preserved"}]autorelease];
}
static Context *NewContext(NSAttributedString *text,CGFloat width,BOOL native) {
    NSTextStorage *storage=[[[NSTextStorage alloc]initWithAttributedString:text]autorelease];
    return [[[Context alloc]initWithStorage:storage width:width native:native]autorelease];
}
static void Fresh(Context *live,NSString *label) {
    NSAttributedString *before=[[[NSAttributedString alloc]initWithAttributedString:live->storage]autorelease];
    NSDictionary *actual=[live snapshot];
    Context *fresh=NewContext(before,live->container.containerSize.width,NO);
    NSDictionary *expected=[fresh snapshot];
    for(NSString *key in @[@"lines",@"points",@"glyphs",@"properties",@"indexes",@"bidi"])
        Check([actual[key]isEqual:expected[key]],[NSString stringWithFormat:@"fresh equality %@ %@",label,key]);
    Context *native=NewContext(before,live->container.containerSize.width,YES);
    NSDictionary *reference=[native snapshot];
    for(NSString *key in @[@"indexes",@"bidi"])
        Check([actual[key]isEqual:reference[key]],@"native UTF-16 and bidi mappings remain intact");
    Check([live->storage.string isEqual:before.string],@"layout preserves exact source");
    Check([live->storage isEqualToAttributedString:native->storage],@"storage attributes match native font normalization");
    Check(![(ObservedTypesetter *)live->layout.typesetter hasAnalysis],@"completed layout retains no paragraph analysis");
}
static NSDictionary *Interrupted(void) {
    NSMutableArray *records=[NSMutableArray array];
    NSArray *separators=@[@"\n",@"\r\n",@"\r",@"\302\205",@"\u2028",@"\u2029"];
    NSString *phrase=@"one e\u0301clair 👩🏽‍💻 two affinity नमस्ते three ";
    for(NSNumber *width in @[@100,@190])for(NSString *separator in separators)@autoreleasepool {
        NSString *paragraph=[@""stringByPaddingToLength:phrase.length*4 withString:phrase startingAtIndex:0];
        NSString *source=[NSString stringWithFormat:@"%@%@%@%@אבג مرحبا end%@",paragraph,separator,paragraph,separator,separator];
        Context *context=NewContext(Text(source,@"Helvetica",18),width.doubleValue,NO);
        [context->layout ensureGlyphsForCharacterRange:NSMakeRange(0,source.length)];
        NSUInteger count=context->layout.numberOfGlyphs,cursor=0,batches=0,resumed=0,partialReturns=0;
        NSMutableArray *returns=[NSMutableArray array];
        while(cursor<count) {
            NSUInteger next=NSNotFound;
            if(cursor)resumed++;
            [context->layout.typesetter layoutGlyphsInLayoutManager:context->layout startingAtGlyphIndex:cursor maxNumberOfLineFragments:2 nextGlyphIndex:&next];
            Check(next>cursor && next<=count,@"bounded native layout makes valid forward progress");
            Check(next==count || [source rangeOfComposedCharacterSequenceAtIndex:[context->layout characterIndexForGlyphAtIndex:next]].location==[context->layout characterIndexForGlyphAtIndex:next],@"resume index preserves composed character boundary");
            if(next<count)partialReturns++;
            [returns addObject:@(next)]; cursor=next; batches++;
            Check(batches<200,@"bounded fixture finishes within 200 batches");
        }
        Check(partialReturns>0 && resumed>0,@"fixture actually interrupts and resumes native layout");
        Fresh(context,@"interrupted Unicode layout");
        [records addObject:@{@"width":width,@"separatorUTF16":@([separator characterAtIndex:0]),@"sourceLength":@(source.length),@"batches":@(batches),@"resumes":@(resumed),@"partialReturns":@(partialReturns),@"glyphReturnIndexes":returns}];
    }
    return @{@"cases":records};
}
static NSDictionary *EmptyTransitions(void) {
    NSUInteger phases=0;
    NSMutableArray *records=[NSMutableArray array];
    NSArray *sources=@[@"first e\u0301clair 👩🏽‍💻 affinity\r\nsecond नमस्ते line",@"אבג مرحبا hello\u2029office e\u0301clair\u2028tail",@"alpha\u00a0beta\302\205👨‍👩‍👧‍👦 tail\rlast line"];
    NSArray *fonts=@[@"Menlo-Regular",@"TimesNewRomanPS-ItalicMT",@"Cochin"];
    NSTextStorage *storage=[[[NSTextStorage alloc]initWithAttributedString:Text(sources[0],fonts[0],18)]autorelease];
    Context *a=[[[Context alloc]initWithStorage:storage width:96 native:NO]autorelease];
    Context *b=[[[Context alloc]initWithStorage:storage width:181 native:NO]autorelease];
    Fresh(a,@"initial peer A");Fresh(b,@"initial peer B");phases+=2;
    for(NSUInteger cycle=0;cycle<3;cycle++) {
        [storage setAttributedString:Text(@"",fonts[cycle],14+cycle*3)];
        Fresh(a,@"empty peer A");Fresh(b,@"empty peer B");phases+=2;
        Check(a->layout.numberOfGlyphs==0&&b->layout.numberOfGlyphs==0,@"empty shared source has no glyphs");
        NSString *source=sources[(cycle+1)%3],*font=fonts[(cycle+1)%3];
        [storage setAttributedString:Text(source,font,15+cycle*4)];
        Fresh(b,@"replacement peer B first");Fresh(a,@"replacement peer A second");phases+=2;
        NSRange emoji=[storage.string rangeOfString:@"👩🏽‍💻"];
        if(emoji.location==NSNotFound)emoji=[storage.string rangeOfComposedCharacterSequenceAtIndex:0];
        [storage replaceCharactersInRange:emoji withString:@"e\u0302"];
        [storage addAttribute:NSFontAttributeName value:[NSFont fontWithName:fonts[cycle]size:22]range:NSMakeRange(0,storage.length)];
        [a->container setContainerSize:NSMakeSize(110+cycle*11,100000)];
        Fresh(a,@"cluster replacement and font A");Fresh(b,@"cluster replacement and font B");phases+=2;
        [records addObject:@{@"cycle":@(cycle),@"replacementFont":font,@"replacementSource":source}];
    }
    return @{@"phases":@(phases),@"cycles":records};
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=2)return 2;
    NSDictionary *interrupted=Interrupted(),*transitions=EmptyTransitions();
    Check(ActiveAnalysisEnds>0&&NarrowedLines>0,@"fixtures exercise live paragraph analysis and narrowed lines");
    Check(ParagraphBegins==ParagraphEnds,@"all observed paragraphs complete");
    NSDictionary *result=@{@"interrupted":interrupted,@"emptyTransitions":transitions,@"checks":@(Checks),@"paragraphBegins":@(ParagraphBegins),@"paragraphEnds":@(ParagraphEnds),@"activeAnalysisEnds":@(ActiveAnalysisEnds),@"narrowedLines":@(NarrowedLines),@"passed":@YES};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    if(![data writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES])return 2;
    fprintf(stderr,"PASS: %lu checks, %lu paragraph endings, %lu narrowed lines\n",(unsigned long)Checks,(unsigned long)ParagraphEnds,(unsigned long)NarrowedLines);
}return 0; }
