#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "space-delegate.h"
static NSUInteger Checks,Created,Destroyed,ParagraphBegins,ParagraphEnds,NarrowedLines;
static BOOL ReleaseAfterParagraph;
static void Check(BOOL condition,NSString *message) {
    Checks++;
    if(!condition) { fprintf(stderr,"FAIL %lu: %s\n",(unsigned long)Checks,message.UTF8String); exit(1); }
}
// Observe lifecycle while preserving every call to the production implementation.
@interface ObservedTypesetter : NVSourceTypesetter
- (NSDictionary *)cacheState;
@end
@implementation ObservedTypesetter
- (id)init { if((self=[super init])) Created++; return self; }
- (void)beginParagraph { [super beginParagraph]; ParagraphBegins++; }
- (void)endParagraph {
    [super endParagraph]; ParagraphEnds++;
    // Optional experiment only: release the actual production cache after its paragraph completes.
    if(ReleaseAfterParagraph) {
        if(paragraphMeasure) CFRelease(paragraphMeasure);
        paragraphMeasure=NULL;
        [lineBreaks release]; lineBreaks=nil;
    }
}
- (void)getLineFragmentRect:(NSRect *)rect usedRect:(NSRect *)used remainingRect:(NSRect *)remaining forStartingGlyphAtIndex:(NSUInteger)start proposedRect:(NSRect)proposed lineSpacing:(CGFloat)spacing paragraphSpacingBefore:(CGFloat)before paragraphSpacingAfter:(CGFloat)after {
    [super getLineFragmentRect:rect usedRect:used remainingRect:remaining forStartingGlyphAtIndex:start proposedRect:proposed lineSpacing:spacing paragraphSpacingBefore:before paragraphSpacingAfter:after];
    if(limitedLineWidth) NarrowedLines++;
}
- (NSDictionary *)cacheState {
    CTLineRef line=paragraphMeasure?CTTypesetterCreateLine(paragraphMeasure,CFRangeMake(0,0)):NULL;
    CFIndex glyphCount=line?CTLineGetGlyphCount(line):0;
    if(line) CFRelease(line);
    return @{@"hasMeasure":@(paragraphMeasure!=NULL),@"cachedGlyphCount":@(glyphCount),@"breakBytes":@(lineBreaks.length),@"paragraph":NSStringFromRange(paragraphRange)};
}
- (void)dealloc { Destroyed++; [super dealloc]; }
@end
@interface System : NSObject {
@public NSTextStorage *storage; NSLayoutManager *layout; NSTextContainer *container; SpaceDelegate *delegate; ObservedTypesetter *typesetter;
}
- (id)initWithStorage:(NSTextStorage *)text width:(CGFloat)width;
- (void)attach:(NSTextStorage *)text;
- (NSArray *)snapshot;
@end
@implementation System
- (id)initWithStorage:(NSTextStorage *)text width:(CGFloat)width {
    if((self=[super init])) {
        layout=[[NSLayoutManager alloc]init]; container=[[NSTextContainer alloc]initWithSize:NSMakeSize(width,1000000)];
        delegate=[[SpaceDelegate alloc]init]; typesetter=[[ObservedTypesetter alloc]init];
        layout.delegate=delegate; layout.typesetter=typesetter; [layout addTextContainer:container];
        [self attach:text];
    } return self;
}
- (void)attach:(NSTextStorage *)text {
    [storage removeLayoutManager:layout]; [storage release]; storage=[text retain]; [storage addLayoutManager:layout];
}
- (NSArray *)snapshot {
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *lines=[NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs) usingBlock:^(NSRect rect,NSRect used,NSTextContainer *text,NSRange glyphs,BOOL *stop) {
        NSRange chars=[layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
        [lines addObject:@[NSStringFromRange(chars),NSStringFromRect(rect),NSStringFromRect(used),NSStringFromPoint([layout locationForGlyphAtIndex:glyphs.location])]];
    }];
    return lines;
}
- (void)dealloc {
    [storage removeLayoutManager:layout]; layout.delegate=nil;
    [storage release]; [layout release]; [container release]; [delegate release]; [typesetter release]; [super dealloc];
}
@end
static NSDictionary *Attributes(NSUInteger pass) {
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];
    style.lineBreakMode=NSLineBreakByCharWrapping;
    style.alignment=(pass%3==0)?NSTextAlignmentLeft:((pass%3==1)?NSTextAlignmentRight:NSTextAlignmentCenter);
    return @{NSFontAttributeName:[NSFont fontWithName:pass%2?@"Helvetica":@"Menlo-Regular" size:pass%2?16:18],NSParagraphStyleAttributeName:style};
}
static void FreshEqual(System *system,NSString *label) {
    NSTextStorage *freshStorage=[[[NSTextStorage alloc]initWithAttributedString:system->storage]autorelease];
    System *fresh=[[[System alloc]initWithStorage:freshStorage width:system->container.size.width]autorelease];
    fresh->container.lineFragmentPadding=system->container.lineFragmentPadding;
    NSArray *actual=[system snapshot],*expected=[fresh snapshot];
    if(![actual isEqual:expected]) fprintf(stderr,"GEOMETRY %s\nactual %s\nexpected %s\n",label.UTF8String,actual.description.UTF8String,expected.description.UTF8String);
    Check([actual isEqual:expected],label);
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc>=2,@"result path provided");
        ReleaseAfterParagraph=argc>2;
        NSMutableArray *caches=[NSMutableArray array];
        for(NSUInteger pass=0;pass<12;pass++) {
            @autoreleasepool {
                NSString *paragraph=@"alpha beta gamma delta epsilon zeta eta theta iota kappa. ";
                NSString *source=[[@"" stringByPaddingToLength:paragraph.length*12 withString:paragraph startingAtIndex:0] stringByAppendingString:@"\nsecond paragraph with a different terminal word\nthird final paragraph"];
                NSTextStorage *text=[[[NSTextStorage alloc]initWithString:source attributes:Attributes(pass)]autorelease];
                System *a=[[[System alloc]initWithStorage:text width:245+pass*7]autorelease];
                System *b=[[[System alloc]initWithStorage:text width:397-pass*5]autorelease];
                Check(a->typesetter!=b->typesetter && a->layout.textStorage==b->layout.textStorage,@"shared source uses separate production typesetter instances");
                NSAttributedString *original=[text copy];
                [a->layout ensureLayoutForBoundingRect:NSMakeRect(0,0,200,32) inTextContainer:a->container];
                [b->layout ensureLayoutForBoundingRect:NSMakeRect(0,0,350,60) inTextContainer:b->container];
                Check([text isEqualToAttributedString:original],@"partial layout leaves all shared source attributes unchanged");
                [text replaceCharactersInRange:NSMakeRange(0,5) withString:@"zzzzq"];
                [text addAttributes:Attributes(pass+1) range:NSMakeRange(0,NSMaxRange([text.string paragraphRangeForRange:NSMakeRange(0,0)]))];
                FreshEqual(a,@"first partial layout refreshes text and font caches after same-length edit");
                FreshEqual(b,@"second partial layout independently refreshes text and font caches");
                [a->container setContainerSize:NSMakeSize(210+pass*4,1000000)];
                a->container.lineFragmentPadding=pass%2?11:5;
                FreshEqual(a,@"resized container and padding match a new production layout");
                NSAttributedString *beforeDetach=[text copy];
                NSArray *peerBefore=[[b snapshot]copy];
                NSTextStorage *empty=[[[NSTextStorage alloc]init]autorelease];
                [a attach:empty]; [a snapshot];
                [caches addObject:@{@"afterEmptySwitch":[a->typesetter cacheState]}];
                Check([peerBefore isEqual:[b snapshot]] && [text isEqualToAttributedString:beforeDetach],@"detaching one layout leaves its peer and old source unchanged");
                [empty setAttributedString:[[[NSAttributedString alloc]initWithString:@"new source short words then trailing       " attributes:Attributes(pass+2)]autorelease]];
                FreshEqual(a,@"reused typesetter resets paragraph state when an empty note receives new source");
                [a attach:text];
                FreshEqual(a,@"reattached original note matches a fresh production typesetter");
                [text addAttribute:NSForegroundColorAttributeName value:[NSColor purpleColor] range:NSMakeRange(0,text.length)];
                FreshEqual(a,@"color regeneration does not alter measured source geometry");
                FreshEqual(b,@"peer color regeneration keeps independent geometry correct");
                Check([text.string isEqual:[source stringByReplacingCharactersInRange:NSMakeRange(0,5) withString:@"zzzzq"]],@"only the explicit source edit changes characters");
                [peerBefore release]; [beforeDetach release]; [original release];
            }
            Check(Created==Destroyed,@"all layout-local typesetters release after their text systems leave scope");
        }
        Check(NarrowedLines>100,@"lifecycle fixtures exercise actual production word-boundary narrowing");
        NSAutoreleasePool *retentionPool=[[NSAutoreleasePool alloc]init];
        NSString *large=[@"" stringByPaddingToLength:65536 withString:@"alpha beta gamma delta epsilon " startingAtIndex:0];
        NSTextStorage *largeStorage=[[NSTextStorage alloc]initWithString:large attributes:Attributes(0)];
        System *retentionSystem=[[System alloc]initWithStorage:largeStorage width:544];
        [retentionSystem snapshot];
        NSTextStorage *emptyStorage=[[NSTextStorage alloc]init];
        [retentionSystem attach:emptyStorage]; [retentionSystem snapshot];
        [largeStorage setAttributedString:[[[NSAttributedString alloc]initWithString:@""]autorelease]];
        NSDictionary *retainedState=[[retentionSystem->typesetter cacheState]copy];
        [retentionPool drain];
        NSUInteger retainedGlyphCount=[retainedState[@"cachedGlyphCount"] unsignedIntegerValue];
        Check(ReleaseAfterParagraph ? retainedGlyphCount==0 : retainedGlyphCount==65536,@"cached typesetter data remains readable after empty switch unless the paragraph-completion experiment releases it");
        NSAutoreleasePool *cleanupPool=[[NSAutoreleasePool alloc]init];
        [retentionSystem release]; [emptyStorage release]; [largeStorage release];
        [cleanupPool drain];
        Check(Created==Destroyed,@"large-paragraph probe releases its typesetter");
        NSDictionary *retention=@{@"paragraphLength":@65536,@"cachedGlyphsAfterEmptySwitchAndSourceClear":@(retainedGlyphCount),@"cacheAfterEmptySwitch":retainedState};
        [retainedState release];
        NSDictionary *result=@{@"endParagraphCleanupExperiment":@(ReleaseAfterParagraph),@"retention":retention,@"narrowedLines":@(NarrowedLines),@"checks":@(Checks),@"cases":@12,@"typesettersCreated":@(Created),@"typesettersDestroyed":@(Destroyed),@"paragraphBegins":@(ParagraphBegins),@"paragraphEnds":@(ParagraphEnds),@"cacheObservations":caches};
        Check([[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL]writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES],@"write results");
        fprintf(stderr,"PASS: %lu checks, %lu typesetters destroyed\n",(unsigned long)Checks-1,(unsigned long)Destroyed);
    }
    return 0;
}
