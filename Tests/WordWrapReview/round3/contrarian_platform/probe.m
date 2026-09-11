#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "space-delegate.h"

static NSUInteger Checks, NativeEdits, BoundaryStarts, NarrowedLines;
static NSMutableArray *Records;
static void Check(BOOL ok,NSString *message) {
    Checks++; if(!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
@interface ObservedTypesetter:NVSourceTypesetter
@end
@implementation ObservedTypesetter
- (void)getLineFragmentRect:(NSRect *)rect usedRect:(NSRect *)used remainingRect:(NSRect *)remaining
    forStartingGlyphAtIndex:(NSUInteger)start proposedRect:(NSRect)proposed lineSpacing:(CGFloat)spacing
    paragraphSpacingBefore:(CGFloat)before paragraphSpacingAfter:(CGFloat)after {
    [super getLineFragmentRect:rect usedRect:used remainingRect:remaining forStartingGlyphAtIndex:start
        proposedRect:proposed lineSpacing:spacing paragraphSpacingBefore:before paragraphSpacingAfter:after];
    if(limitedLineWidth)NarrowedLines++;
}
@end
@interface Editor:NSObject {
@public NSTextStorage *storage; NSLayoutManager *layout; NSTextContainer *container; NSTextView *view; SpaceDelegate *delegate;
}
- (id)initWithText:(NSAttributedString *)text width:(CGFloat)width refined:(BOOL)refined;
- (NSDictionary *)snapshot;
- (void)font:(NSString *)font size:(CGFloat)size;
@end
@implementation Editor
- (id)initWithText:(NSAttributedString *)text width:(CGFloat)width refined:(BOOL)refined {
    if((self=[super init])) {
        storage=[[NSTextStorage alloc]initWithAttributedString:text]; layout=[NSLayoutManager new];
        container=[[NSTextContainer alloc]initWithSize:NSMakeSize(width,100000)]; delegate=[SpaceDelegate new];
        [storage addLayoutManager:layout]; [layout addTextContainer:container]; layout.delegate=delegate;
        if(refined)layout.typesetter=[[[ObservedTypesetter alloc]init]autorelease];
        view=[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,width,500)textContainer:container];
        view.richText=NO; view.allowsUndo=NO; view.horizontallyResizable=NO;
        container.widthTracksTextView=NO;
        view.typingAttributes=[storage attributesAtIndex:0 effectiveRange:NULL];
    }
    return self;
}
- (void)font:(NSString *)name size:(CGFloat)size {
    NSFont *font=[NSFont fontWithName:name size:size]; Check(font!=nil,@"fixture font exists");
    [storage addAttribute:NSFontAttributeName value:font range:NSMakeRange(0,storage.length)];
    NSMutableDictionary *attributes=[[view.typingAttributes mutableCopy]autorelease];
    attributes[NSFontAttributeName]=font; view.typingAttributes=attributes;
}
- (NSDictionary *)snapshot {
    [layout ensureLayoutForTextContainer:container];
    NSUInteger count=layout.numberOfGlyphs;
    NSMutableArray *lines=[NSMutableArray array],*points=[NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,count)usingBlock:^(NSRect rect,NSRect used,NSTextContainer *c,NSRange g,BOOL *stop) {
        NSRange chars=[layout characterRangeForGlyphRange:g actualGlyphRange:NULL];
        Check(chars.location==storage.length || [storage.string rangeOfComposedCharacterSequenceAtIndex:chars.location].location==chars.location,@"line preserves composed sequence");
        [lines addObject:@[@(chars.location),@(chars.length),@(rect.origin.x),@(rect.origin.y),@(rect.size.width),@(rect.size.height),@(used.origin.x),@(used.size.width)]];
    }];
    NSMutableData *glyphs=[NSMutableData dataWithLength:count*sizeof(CGGlyph)],*properties=[NSMutableData dataWithLength:count*sizeof(NSGlyphProperty)];
    NSMutableData *indexes=[NSMutableData dataWithLength:count*sizeof(NSUInteger)],*bidi=[NSMutableData dataWithLength:count];
    Check([layout getGlyphsInRange:NSMakeRange(0,count)glyphs:glyphs.mutableBytes properties:properties.mutableBytes characterIndexes:indexes.mutableBytes bidiLevels:bidi.mutableBytes]==count,@"complete native glyph mapping");
    for(NSUInteger g=0;g<count;g++) { NSPoint p=[layout locationForGlyphAtIndex:g]; [points addObject:@[@(p.x),@(p.y)]]; }
    return @{@"lines":lines,@"points":points,@"glyphs":glyphs,@"properties":properties,@"indexes":indexes,@"bidi":bidi};
}
- (void)dealloc {
    layout.delegate=nil; [view release]; [delegate release]; [container release]; [layout release]; [storage release]; [super dealloc];
}
@end
static NSAttributedString *Text(NSString *source) {
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];
    style.lineBreakMode=NSLineBreakByCharWrapping;
    return [[[NSAttributedString alloc]initWithString:source attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18],NSParagraphStyleAttributeName:style}]autorelease];
}
static Editor *New(NSAttributedString *text,CGFloat width,BOOL refined) {
    return [[[Editor alloc]initWithText:text width:width refined:refined]autorelease];
}
static void Observe(Editor *candidate,Editor *native,NSString *phase,NSRange target) {
    NSString *expected=[[candidate->storage.string copy]autorelease];
    NSDictionary *actual=[candidate snapshot],*reference=[native snapshot];
    Check([candidate->storage.string isEqual:native->storage.string]&&[candidate->storage.string isEqual:expected],@"layout preserves source and native edit equivalence");
    Check([candidate->storage isEqualToAttributedString:native->storage],@"native and candidate storage attributes match");
    Check(NSEqualRanges(candidate->view.selectedRange,native->view.selectedRange),@"native selection matches after edits and layout changes");
    Check(NSMaxRange(candidate->view.selectedRange)<=candidate->storage.length,@"native selection remains in bounds");
    for(NSString *key in @[@"indexes",@"bidi"])Check([actual[key]isEqual:reference[key]],@"native UTF-16 mapping and bidi levels match");
    Editor *fresh=New(candidate->storage,candidate->container.containerSize.width,YES);
    NSDictionary *freshLayout=[fresh snapshot];
    for(NSString *key in @[@"lines",@"points",@"glyphs",@"properties",@"indexes",@"bidi"])
        Check([actual[key]isEqual:freshLayout[key]],[NSString stringWithFormat:@"fresh layout equality %@ %@",phase,key]);
    BOOL targetStartsLine=NO;
    for(NSArray *line in actual[@"lines"])if([line[0]unsignedIntegerValue]==target.location)targetStartsLine=YES;
    if(targetStartsLine)BoundaryStarts++;
    [Records addObject:@{@"phase":phase,@"source":candidate->storage.string,@"targetRange":NSStringFromRange(target),@"selection":NSStringFromRange(candidate->view.selectedRange),@"width":@(candidate->container.containerSize.width),@"targetStartsLine":@(targetStartsLine),@"lines":actual[@"lines"]}];
}
static void Edit(Editor *candidate,Editor *native,NSRange range,NSString *replacement) {
    NSString *expected=[candidate->storage.string stringByReplacingCharactersInRange:range withString:replacement];
    for(Editor *editor in @[candidate,native]) {
        [editor->view insertText:replacement replacementRange:range]; NativeEdits++;
        Check([editor->storage.string isEqual:expected],@"native scalar edit preserves exact requested source");
    }
}
static void Fixture(NSString *name,NSString *initial,NSArray *edits) {
    NSString *prefix=@"one two ",*suffix=@" tail words";
    NSString *source=[NSString stringWithFormat:@"%@%@%@",prefix,initial,suffix];
    Editor *candidate=New(Text(source),104,YES),*native=New(Text(source),104,NO);
    NSRange target=NSMakeRange(prefix.length,initial.length);
    Observe(candidate,native,[name stringByAppendingString:@" initial"],target);
    Check([Records.lastObject[@"targetStartsLine"]boolValue],@"initial target starts at an actual wrap boundary");
    NSUInteger index=0;
    for(NSArray *edit in edits) {
        NSRange range=NSMakeRange(target.location+[edit[0]unsignedIntegerValue],[edit[1]unsignedIntegerValue]);
        NSString *replacement=edit[2];
        Edit(candidate,native,range,replacement);
        target.length=target.length-range.length+replacement.length;
        Observe(candidate,native,[NSString stringWithFormat:@"%@ edit %lu",name,(unsigned long)++index],target);
    }
    for(Editor *editor in @[candidate,native])[editor->container setContainerSize:NSMakeSize(76,100000)];
    Observe(candidate,native,[name stringByAppendingString:@" narrow"],target);
    for(Editor *editor in @[candidate,native]) { [editor font:@"Helvetica" size:22]; [editor->container setContainerSize:NSMakeSize(137,100000)]; }
    Observe(candidate,native,[name stringByAppendingString:@" font and widen"],target);
    for(Editor *editor in @[candidate,native]) { editor->view.selectedRange=target; [editor->view deleteBackward:nil]; NativeEdits++; }
    NSString *deleted=[prefix stringByAppendingString:suffix];
    Check([candidate->storage.string isEqual:deleted]&&[native->storage.string isEqual:deleted],@"native deletion removes the final complete target");
    target.length=0;
    Observe(candidate,native,[name stringByAppendingString:@" delete target"],target);
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=2)return 2; Records=[NSMutableArray new];
    Fixture(@"combining",@"e",@[@[@1,@0,@"\u0301"],@[@1,@1,@"\u0302"],@[@2,@0,@"\u0323"],@[@1,@1,@""],@[@0,@2,@"ẹ"]]);
    Fixture(@"variation",@"❤",@[@[@1,@0,@"\ufe0e"],@[@1,@1,@"\ufe0f"],@[@1,@1,@""],@[@1,@0,@"\ufe0f"]]);
    Fixture(@"emoji",@"👩",@[@[@2,@0,@"🏽"],@[@2,@2,@"🏿"],@[@4,@0,@"\u200d💻"],@[@4,@1,@""],@[@4,@0,@"\u200d"]]);
    Check(BoundaryStarts>=3&&NarrowedLines>0,@"fixtures exercise real wrapping and production narrowing");
    NSDictionary *result=@{@"checks":@(Checks),@"nativeEdits":@(NativeEdits),@"phases":@(Records.count),@"targetAtLineStartPhases":@(BoundaryStarts),@"narrowedLines":@(NarrowedLines),@"records":Records,@"passed":@YES};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    if(![data writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES])return 2;
    fprintf(stderr,"PASS: %lu checks, %lu phases, %lu native edits, %lu target-boundary phases\n",(unsigned long)Checks,(unsigned long)Records.count,(unsigned long)NativeEdits,(unsigned long)BoundaryStarts);
}return 0; }
