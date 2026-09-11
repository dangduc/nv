#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "space-delegate.h"

static NSUInteger Checks, Narrowed;
static BOOL NegativeControl;
static NSMutableArray *Failures;
static void Check(BOOL ok, NSString *message) {
    Checks++;
    if (!ok) { [Failures addObject:message]; fprintf(stderr,"FAIL: %s\n",message.UTF8String); }
}
@interface ObservedTypesetter:NVSourceTypesetter
@end
@implementation ObservedTypesetter
- (void)getLineFragmentRect:(NSRect *)rect usedRect:(NSRect *)used remainingRect:(NSRect *)remaining
    forStartingGlyphAtIndex:(NSUInteger)start proposedRect:(NSRect)proposed lineSpacing:(CGFloat)spacing
    paragraphSpacingBefore:(CGFloat)before paragraphSpacingAfter:(CGFloat)after {
    [super getLineFragmentRect:rect usedRect:used remainingRect:remaining forStartingGlyphAtIndex:start
        proposedRect:proposed lineSpacing:spacing paragraphSpacingBefore:before paragraphSpacingAfter:after];
    if (limitedLineWidth) Narrowed++;
}
@end
@interface TextSystem:NSObject {
@public NSTextStorage *storage; NSLayoutManager *layout; NSTextContainer *container; SpaceDelegate *delegate;
}
- (id)initWithText:(NSAttributedString *)text width:(CGFloat)width mode:(NSUInteger)mode;
- (NSDictionary *)snapshot;
@end
@implementation TextSystem
- (id)initWithText:(NSAttributedString *)text width:(CGFloat)width mode:(NSUInteger)mode {
    if ((self=[super init])) {
        storage=[[NSTextStorage alloc]initWithAttributedString:text];
        layout=[[NSLayoutManager alloc]init];
        container=[[NSTextContainer alloc]initWithSize:NSMakeSize(width,100000)];
        delegate=[[SpaceDelegate alloc]init];
        [storage addLayoutManager:layout]; [layout addTextContainer:container];
        layout.delegate=delegate;
        if(mode==1)layout.typesetter=[[[ObservedTypesetter alloc]init]autorelease];
        if(mode==2) {
            NSMutableParagraphStyle *p=[[[storage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL]mutableCopy]autorelease];
            p.lineBreakMode=NSLineBreakByWordWrapping;
            [storage addAttribute:NSParagraphStyleAttributeName value:p range:NSMakeRange(0,storage.length)];
        }
    }
    return self;
}
- (NSDictionary *)snapshot {
    [layout ensureLayoutForTextContainer:container];
    NSUInteger n=layout.numberOfGlyphs;
    NSMutableData *glyphs=[NSMutableData dataWithLength:n*sizeof(CGGlyph)];
    NSMutableData *properties=[NSMutableData dataWithLength:n*sizeof(NSGlyphProperty)];
    NSMutableData *indexes=[NSMutableData dataWithLength:n*sizeof(NSUInteger)];
    NSMutableData *levels=[NSMutableData dataWithLength:n];
    Check([layout getGlyphsInRange:NSMakeRange(0,n) glyphs:glyphs.mutableBytes properties:properties.mutableBytes
        characterIndexes:indexes.mutableBytes bidiLevels:levels.mutableBytes]==n,@"complete glyph snapshot");
    NSMutableArray *lines=[NSMutableArray array],*points=[NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,n) usingBlock:^(NSRect r,NSRect used,NSTextContainer *c,NSRange g,BOOL *stop){
        NSRange chars=[layout characterRangeForGlyphRange:g actualGlyphRange:NULL];
        [lines addObject:@[@(chars.location),@(chars.length),@(r.origin.x),@(r.origin.y),@(r.size.width),@(used.origin.x),@(used.size.width)]];
    }];
    for(NSUInteger i=0;i<storage.length;i++) {
        NSUInteger g=[layout glyphIndexForCharacterAtIndex:i];
        NSRect r=[layout lineFragmentRectForGlyphAtIndex:g effectiveRange:NULL];
        NSPoint p=[layout locationForGlyphAtIndex:g];
        [points addObject:@[@(r.origin.x+p.x),@(r.origin.y+p.y)]];
    }
    return @{ @"glyphs":glyphs,@"properties":properties,@"indexes":indexes,@"levels":levels,@"lines":lines,@"points":points };
}
- (void)dealloc {
    layout.delegate=nil; [delegate release]; [container release]; [layout release]; [storage release]; [super dealloc];
}
@end
static NSAttributedString *Text(NSString *source,NSFont *font,CGFloat tabs) {
    NSMutableParagraphStyle *p=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];
    p.lineBreakMode=NSLineBreakByCharWrapping;
    if(tabs>0) { p.tabStops=@[]; p.defaultTabInterval=tabs; }
    return [[[NSAttributedString alloc]initWithString:source attributes:@{NSFontAttributeName:font,NSParagraphStyleAttributeName:p,@"ReviewMarker":@"unchanged"}]autorelease];
}
static TextSystem *System(NSAttributedString *text,CGFloat width,NSUInteger mode) {
    return [[[TextSystem alloc]initWithText:text width:width mode:(NegativeControl&&mode==1?0:mode)]autorelease];
}
static NSArray *FontNames(void) { return @[@"Menlo-Regular",@"Helvetica",@"TimesNewRomanPS-ItalicMT",@"Baskerville",@"Cochin",@"AmericanTypewriter",@"Herculanum",@"Zapfino"]; }
static BOOL Whole(NSDictionary *snapshot,NSRange word) {
    for(NSArray *line in snapshot[@"lines"]) {
        NSUInteger start=[line[0]unsignedIntegerValue];
        if(start>word.location && start<NSMaxRange(word))return NO;
    }
    return YES;
}
static NSDictionary *Unicode(void) {
    NSArray *texts=@[@"ab e\u0301 a\u0308 o\u0302 cd ef",@"ab 👩🏽‍💻 👨‍👩‍👧‍👦 🇻🇳 1\ufe0f\u20e3 cd",
        @"ab क्‍षि क्षि नमस्ते cd",@"אבג مرحبا A12 שלום 👩‍💻",@"ab\tcd\u00a0ef\u202fgh\u2060ij\u2011kl",
        @"office affine fi fl ffi ffl words",@"ab  \u2002\u2003\u2009cd ef",@"a\u200bhello\u00adworld other text"];
    NSUInteger cases=0, splits=0; NSMutableArray *splitRows=[NSMutableArray array],*shapeDifferences=[NSMutableArray array];
    for(NSString *name in FontNames())for(NSNumber *width in @[@18,@35,@62,@120,@220])for(NSString *source in texts)@autoreleasepool {
        NSFont *font=[NSFont fontWithName:name size:18]; Check(font!=nil,@"fixture font exists"); if(!font)continue;
        NSAttributedString *text=Text(source,font,0);
        TextSystem *native=System(text,width.doubleValue,0),*candidate=System(text,width.doubleValue,1);
        NSDictionary *before=[native snapshot],*after=[candidate snapshot];
        for(NSString *key in @[@"indexes",@"levels"])
            Check([before[key]isEqual:after[key]],[NSString stringWithFormat:@"glyph equality %@ %@ %@",name,width,key]);
        if(![before[@"glyphs"]isEqual:after[@"glyphs"]]||![before[@"properties"]isEqual:after[@"properties"]])
            [shapeDifferences addObject:@{@"font":name,@"width":width,@"source":source}];
        Check([candidate->storage.string isEqual:source],@"layout preserves source characters");
        Check([candidate->storage isEqualToAttributedString:native->storage],@"storage attributes match native fallback normalization");
        for(NSArray *line in after[@"lines"]) {
            NSUInteger start=[line[0]unsignedIntegerValue];
            BOOL boundary=start==source.length || [source rangeOfComposedCharacterSequenceAtIndex:start].location==start;
            Check(boundary,[NSString stringWithFormat:@"cluster boundary %@ %@ %lu",name,width,(unsigned long)start]);
            if(!boundary) { splits++; [splitRows addObject:@{ @"font":name,@"width":width,@"source":source,@"start":@(start) }]; }
        }
        cases++;
    }
    return @{ @"cases":@(cases),@"clusterSplits":@(splits),@"splitRows":splitRows,@"postLayoutShapeDifferences":shapeDifferences };
}
static NSDictionary *Words(void) {
    NSArray *tokens=@[@"affinity",@"office",@"ligatures",@"éclair",@"e\u0301clair",@"alpha\u00a0beta",@"alpha\u202fbeta",@"alpha\u2060beta",@"alpha\u2011beta"];
    NSUInteger cases=0,fitting=0; NSMutableArray *splits=[NSMutableArray array];
    for(NSString *name in FontNames())for(NSNumber *width in @[@60,@100,@160,@240])for(NSNumber *tabs in @[@0,@40,@73])for(NSString *token in tokens)@autoreleasepool {
        NSFont *font=[NSFont fontWithName:name size:18]; if(!font)continue;
        TextSystem *alone=System(Text(token,font,tabs.doubleValue),width.doubleValue,0);
        NSDictionary *isolated=[alone snapshot];
        if(!Whole(isolated,NSMakeRange(0,token.length)))continue;
        fitting++;
        for(NSString *prefix in @[@"aaa ",@"aa\t",@"aa bb "]) {
            NSString *source=[NSString stringWithFormat:@"%@%@ ending",prefix,token];
            NSAttributedString *text=Text(source,font,tabs.doubleValue);
            NSDictionary *candidate=[System(text,width.doubleValue,1)snapshot];
            NSDictionary *native=[System(text,width.doubleValue,2)snapshot];
            NSRange range=NSMakeRange(prefix.length,token.length);
            BOOL nativeWhole=Whole(native,range), actualWhole=Whole(candidate,range);
            if(nativeWhole&&!actualWhole)[splits addObject:@{ @"font":name,@"width":width,@"tabs":tabs,@"source":source,
                @"token":token,@"candidateLines":candidate[@"lines"],@"nativeLines":native[@"lines"],@"isolatedLines":isolated[@"lines"] }];
            cases++;
        }
    }
    Check(NegativeControl?splits.count>0:splits.count==0,NegativeControl?@"previous character policy is rejected by whole-token comparison":@"fitting tokens remain whole whenever native word layout keeps them whole");
    return @{ @"cases":@(cases),@"fittingConfigurations":@(fitting),@"nativeWholeCandidateSplit":splits };
}
static void Fresh(TextSystem *system,NSString *label) {
    TextSystem *fresh=System(system->storage,system->container.containerSize.width,1);
    NSDictionary *a=[system snapshot],*b=[fresh snapshot];
    for(NSString *key in @[@"lines",@"points",@"glyphs",@"properties",@"indexes",@"levels"])
        Check([a[key]isEqual:b[key]],[NSString stringWithFormat:@"fresh equality %@ %@",label,key]);
}
static NSDictionary *Invalidation(void) {
    NSUInteger phases=0;
    NSString *source=@"office affinity e\u0301clair 👩🏽‍💻 नमस्ते \talpha\u00a0beta rest of this paragraph. ";
    for(NSNumber *width in @[@90,@180,@300])@autoreleasepool {
        TextSystem *system=System(Text([source stringByAppendingString:source],[NSFont fontWithName:@"Menlo-Regular" size:18],0),width.doubleValue,1);
        Fresh(system,@"initial"); phases++;
        for(NSString *font in FontNames()) {
            [system->storage addAttribute:NSFontAttributeName value:[NSFont fontWithName:font size:18]range:NSMakeRange(0,system->storage.length)];
            Fresh(system,font); phases++;
            NSDictionary *before=[system snapshot];
            [system->layout addTemporaryAttributes:@{NSForegroundColorAttributeName:[NSColor redColor],NSBackgroundColorAttributeName:[NSColor yellowColor]} forCharacterRange:NSMakeRange(3,system->storage.length-6)];
            Check([[system snapshot]isEqual:before],@"temporary source colors preserve all layout geometry"); phases++;
            [system->layout removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(0,system->storage.length)];
            [system->layout removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0,system->storage.length)];
            [system->storage replaceCharactersInRange:NSMakeRange(7,0)withString:@"extra "];
            Fresh(system,@"interior insertion after font change"); phases++;
            [system->storage replaceCharactersInRange:NSMakeRange(7,6)withString:@""];
            [system->container setContainerSize:NSMakeSize(width.doubleValue+17,100000)];
            Fresh(system,@"resize after deletion"); phases++;
            [system->container setContainerSize:NSMakeSize(width.doubleValue,100000)];
        }
    }
    return @{ @"phases":@(phases) };
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=3&&argc!=4)return 2;
    NegativeControl=argc==4;
    Failures=[NSMutableArray new];
    NSString *suite=[NSString stringWithUTF8String:argv[1]];
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:[suite isEqual:@"unicode"]?Unicode():([suite isEqual:@"words"]?Words():Invalidation())];
    result[@"checks"]=@(Checks); result[@"narrowedLines"]=@(Narrowed); result[@"failures"]=Failures;
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    if(![data writeToFile:[NSString stringWithUTF8String:argv[2]]atomically:YES])return 2;
    fprintf(stderr,"%s: %lu checks, %lu narrowed lines, %lu assertion failures\n",suite.UTF8String,(unsigned long)Checks,(unsigned long)Narrowed,(unsigned long)Failures.count);
    return Failures.count?1:0;
} }
