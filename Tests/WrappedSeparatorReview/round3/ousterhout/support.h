#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"

static NSUInteger Checks;
static NSMutableArray *Rows;
static void Check(BOOL condition, NSString *message) {
    Checks++;
    if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
@interface ProductionDelegate : NSObject <NSLayoutManagerDelegate>
@end
@implementation ProductionDelegate
@PRODUCTION_HOOK@
@end
@COUNTER_DELEGATE@

static NSAttributedString *Attributed(NSString *text) {
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode=NSLineBreakByCharWrapping;
    NSFont *font=[NSFont fontWithName:@"Menlo-Regular" size:17];
    NSFont *spaceFont=[NSFont fontWithName:@"Menlo-Bold" size:17];
    Check(font && spaceFont,@"fixture fonts exist");
    NSMutableAttributedString *value=[[[NSMutableAttributedString alloc] initWithString:text
                       attributes:@{NSFontAttributeName:font,NSParagraphStyleAttributeName:style}] autorelease];
    for(NSUInteger i=0;i<text.length;i++) if([text characterAtIndex:i]==' ')
        [value addAttributes:@{NSFontAttributeName:spaceFont,NSForegroundColorAttributeName:[NSColor redColor]}
                       range:NSMakeRange(i,1)];
    return value;
}
static NSLayoutManager *NewLayout(NSTextStorage *storage, CountingDelegate *delegate, CGFloat width, BOOL noncontiguous) {
    NSLayoutManager *layout=[[[NSLayoutManager alloc] init] autorelease];
    [storage addLayoutManager:layout];
    NSTextContainer *container=[[[NSTextContainer alloc] initWithSize:NSMakeSize(width,1000000)] autorelease];
    [layout addTextContainer:container];
    layout.delegate=delegate;
    layout.allowsNonContiguousLayout=noncontiguous;
    layout.typesetter=[[[NVSourceTypesetter alloc] init] autorelease];
    return layout;
}
static NSDictionary *Snapshot(NSLayoutManager *layout) {
    NSTextStorage *storage=layout.textStorage;
    NSAttributedString *before=[[storage copy] autorelease];
    [layout ensureLayoutForTextContainer:[layout.textContainers firstObject]];
    NSMutableArray *glyphs=[NSMutableArray array],*lines=[NSMutableArray array];
    for(NSUInteger i=0;i<layout.numberOfGlyphs;i++) {
        NSRect line=[layout lineFragmentRectForGlyphAtIndex:i effectiveRange:NULL];
        NSPoint point=[layout locationForGlyphAtIndex:i];
        [glyphs addObject:@[@([layout characterIndexForGlyphAtIndex:i]),@([layout glyphAtIndex:i]),
                           @([layout propertyForGlyphAtIndex:i]),@(line.origin.x+point.x),@(line.origin.y+point.y)]];
    }
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs)
        usingBlock:^(NSRect rect,NSRect used,NSTextContainer *container,NSRange range,BOOL *stop){
            [lines addObject:@{ @"characters":NSStringFromRange([layout characterRangeForGlyphRange:range actualGlyphRange:NULL]),
                               @"rect":NSStringFromRect(rect),@"used":NSStringFromRect(used)}];
        }];
    Check([storage isEqualToAttributedString:before],@"glyph generation and typesetting do not mutate source attributes or characters");
    return @{@"glyphs":glyphs,@"lines":lines};
}
static NSDictionary *Fresh(NSLayoutManager *layout) {
    NSTextStorage *copy=[[[NSTextStorage alloc] initWithAttributedString:layout.textStorage] autorelease];
    CountingDelegate *delegate=[[[CountingDelegate alloc] init] autorelease];
    NSLayoutManager *fresh=NewLayout(copy,delegate,[(NSTextContainer *)layout.textContainers.firstObject containerSize].width,
                                    layout.allowsNonContiguousLayout);
    NSDictionary *result=Snapshot(fresh);
    fresh.delegate=nil;
    return result;
}
static void CheckPolicy(NSLayoutManager *layout) {
    NSString *text=layout.textStorage.string;
    NSCharacterSet *whitespace=[NSCharacterSet whitespaceAndNewlineCharacterSet];
    for(NSUInteger i=0;i<text.length;i++) if([text characterAtIndex:i]==' ') {
        BOOL expected=i>0 && i+1<text.length &&
            ![whitespace characterIsMember:[text characterAtIndex:i-1]] &&
            ![whitespace characterIsMember:[text characterAtIndex:i+1]] &&
            [text rangeOfComposedCharacterSequenceAtIndex:i].length==1;
        NSUInteger glyph=[layout glyphIndexForCharacterAtIndex:i];
        BOOL elastic=([layout propertyForGlyphAtIndex:glyph]&NSGlyphPropertyElastic)!=0;
        Check(elastic==expected,[NSString stringWithFormat:@"separator policy at %lu in %@",(unsigned long)i,text]);
    }
}
