#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "delegates.h"

static NSUInteger Checks, Comparisons, ShapingControls, CallbackBatches, SingletonSpaceBatches;
static NSMutableArray *Failures, *Records;
static NSMutableSet *CallbackFonts;
static void Check(BOOL result, NSString *label) { Checks++; if(!result) [Failures addObject:label]; }
@interface ObservedCurrent : CurrentDelegate
@end
@implementation ObservedCurrent
- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:(const CGGlyph *)glyphs
    properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes
    font:(NSFont *)font forGlyphRange:(NSRange)range {
    CallbackBatches++; if(font.fontName) [CallbackFonts addObject:font.fontName];
    if(range.length==1 && indexes[0]<manager.textStorage.length && [manager.textStorage.string characterAtIndex:indexes[0]]==' ')
        SingletonSpaceBatches++;
    return [super layoutManager:manager shouldGenerateGlyphs:glyphs properties:properties
        characterIndexes:indexes font:font forGlyphRange:range];
}
@end

static NSDictionary *Snapshot(NSAttributedString *text, CGFloat width, BOOL current) {
    NSTextStorage *storage=[[[NSTextStorage alloc] initWithAttributedString:text] autorelease];
    NSLayoutManager *layout=[[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container=[[[NSTextContainer alloc] initWithSize:NSMakeSize(width,10000)] autorelease];
    id delegate=current?(id)[[[ObservedCurrent alloc] init] autorelease]:(id)[[[BaseDelegate alloc] init] autorelease];
    [storage addLayoutManager:layout]; [layout addTextContainer:container];
    layout.delegate=delegate; layout.typesetter=[[[NVSourceTypesetter alloc] init] autorelease];
    [layout ensureLayoutForTextContainer:container];
    NSUInteger count=layout.numberOfGlyphs;
    NSMutableData *glyphs=[NSMutableData dataWithLength:count*sizeof(CGGlyph)], *properties=[NSMutableData dataWithLength:count*sizeof(NSGlyphProperty)];
    NSMutableData *indexes=[NSMutableData dataWithLength:count*sizeof(NSUInteger)], *levels=[NSMutableData dataWithLength:count];
    Check([layout getGlyphsInRange:NSMakeRange(0,count) glyphs:glyphs.mutableBytes properties:properties.mutableBytes
        characterIndexes:indexes.mutableBytes bidiLevels:levels.mutableBytes]==count,@"native glyph snapshot is complete");
    NSMutableArray *rows=[NSMutableArray array], *points=[NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,count)
        usingBlock:^(NSRect rect,NSRect used,NSTextContainer *unused,NSRange range,BOOL *stop) {
        NSRange chars=[layout characterRangeForGlyphRange:range actualGlyphRange:NULL];
        [rows addObject:@[@(chars.location),@(chars.length),NSStringFromRect(rect),NSStringFromRect(used)]];
    }];
    for(NSUInteger index=0;index<count;index++) [points addObject:NSStringFromPoint([layout locationForGlyphAtIndex:index])];
    Check([storage.string isEqual:text.string],@"layout preserves exact source code units");
    NSAttributedString *normalized=[[storage copy] autorelease];
    layout.delegate=nil;
    return @{@"glyphs":glyphs,@"properties":properties,@"indexes":indexes,@"levels":levels,
             @"rows":rows,@"points":points,@"normalized":normalized,@"glyphCount":@(count)};
}
static NSAttributedString *Text(NSString *plain, BOOL shaped) {
    NSFont *word=[NSFont fontWithName:@"TimesNewRomanPSMT" size:18];
    NSFont *alternate=[NSFont fontWithName:@"Helvetica" size:20];
    NSFont *space=[NSFont fontWithName:@"Menlo-Regular" size:13];
    Check(word && alternate && space,@"all three split-run fonts exist");
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode=NSLineBreakByCharWrapping;
    NSMutableAttributedString *text=[[[NSMutableAttributedString alloc] initWithString:plain attributes:@{
        NSFontAttributeName:word,NSParagraphStyleAttributeName:style,NSLigatureAttributeName:shaped?@2:@0,
        NSKernAttributeName:shaped?@1.25:@0,NSBaselineOffsetAttributeName:shaped?@2:@0,@"RunMarker":@"word"}] autorelease];
    BOOL alternateWord=NO;
    for(NSUInteger index=0;index<plain.length;index++) if([plain characterAtIndex:index]==' ') {
        [text addAttributes:@{NSFontAttributeName:space,NSForegroundColorAttributeName:[NSColor redColor],
            NSKernAttributeName:shaped?@(-0.5):@0,NSBaselineOffsetAttributeName:shaped?@(-1):@0,@"RunMarker":@"separator"}
            range:NSMakeRange(index,1)];
        alternateWord=!alternateWord;
        if(alternateWord && index+1<plain.length) {
            NSRange next=[plain rangeOfString:@" " options:0 range:NSMakeRange(index+1,plain.length-index-1)];
            NSUInteger end=next.location==NSNotFound?plain.length:next.location;
            [text addAttribute:NSFontAttributeName value:alternate range:NSMakeRange(index+1,end-index-1)];
        }
    }
    return text;
}
static void Fixture(NSString *plain, NSString *name) {
    for(NSNumber *width in @[@86,@440]) {
        NSDictionary *unshaped=nil;
        for(NSNumber *shaped in @[@NO,@YES]) {
            NSAttributedString *text=Text(plain,shaped.boolValue);
            NSDictionary *current=Snapshot(text,width.doubleValue,YES), *baseline=Snapshot(text,width.doubleValue,NO);
            NSString *label=[NSString stringWithFormat:@"%@ width%@ shaping%@",name,width,shaped];
            for(NSString *key in @[@"glyphs",@"properties",@"indexes",@"levels",@"rows",@"points",@"normalized"])
                Check([current[key] isEqual:baseline[key]],[NSString stringWithFormat:@"%@: exact pre-fix equality for %@",label,key]);
            if(!shaped.boolValue) unshaped=current;
            else if(![current[@"points"] isEqual:unshaped[@"points"]] || ![current[@"glyphs"] isEqual:unshaped[@"glyphs"]]) ShapingControls++;
            [Records addObject:@{@"case":label,@"utf16Length":@(plain.length),@"glyphCount":current[@"glyphCount"],
                @"lineCount":@([current[@"rows"] count]),@"exactEqual":@([current isEqual:baseline])}]; Comparisons++;
        }
    }
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2) return 2;
        Failures=[NSMutableArray array]; Records=[NSMutableArray array]; CallbackFonts=[NSMutableSet set];
        Fixture(@"office affine ! ~ fi fl ffi",@"ASCII-shortcut");
        Fixture(@"café 雪 fi e\u0301 office 👩🏽‍💻",@"Unicode-fallback");
        Fixture(@"a \u0301b fi \u00A0office  tail",@"composed-and-repeated-space");
        Check(SingletonSpaceBatches>0,@"split fonts produce actual one-glyph separator callbacks");
        Check(CallbackFonts.count>=3,@"actual callback traffic includes the split font runs");
        Check(ShapingControls==6,@"all six width/source pairs exercise changed shaping geometry or glyphs");
        Check(NSApp==nil,@"the probe creates no GUI application");
        NSDictionary *report=@{@"checks":@(Checks),@"comparisons":@(Comparisons),@"shapingControls":@(ShapingControls),
            @"callbackBatches":@(CallbackBatches),@"singletonSpaceBatches":@(SingletonSpaceBatches),
            @"callbackFonts":[[CallbackFonts allObjects] sortedArrayUsingSelector:@selector(compare:)],@"failures":Failures,@"records":Records};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        printf("%lu checks; %lu exact layout comparisons; %lu single-space batches; %lu shaping controls; %lu failures\n",
            (unsigned long)Checks,(unsigned long)Comparisons,(unsigned long)SingletonSpaceBatches,(unsigned long)ShapingControls,(unsigned long)Failures.count);
        for(NSString *failure in Failures) fprintf(stderr,"FAIL: %s\n",failure.UTF8String);
        return Failures.count?1:0;
    }
}
