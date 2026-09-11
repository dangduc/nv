#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "LinkingEditor.h"
#import "NVNoteEditingSession.h"
@interface NVNoteEditingSession (PolicyReviewPrivate)
- (BOOL)hasPendingTextChanges;
@end
// Forward the real production callback unchanged; observe which buffer paths execute.
typedef NSUInteger (*ProductionGlyphMethod)(id,SEL,NSLayoutManager *,const CGGlyph *,const NSGlyphProperty *,const NSUInteger *,NSFont *,NSRange);
static ProductionGlyphMethod OriginalGlyphMethod;
static NSUInteger SmallChangedBatches,LargeChangedBatches,UnchangedBatches;
static NSUInteger ReviewGlyphMethod(id receiver,SEL selector,NSLayoutManager *layout,const CGGlyph *glyphs,const NSGlyphProperty *properties,const NSUInteger *indexes,NSFont *font,NSRange range) {
    NSUInteger result=OriginalGlyphMethod(receiver,selector,layout,glyphs,properties,indexes,font,range);
    if (!result) UnchangedBatches++;
    else if (range.length<=64) SmallChangedBatches++;
    else LargeChangedBatches++;
    return result;
}
static NSArray *GlyphSnapshot(NSTextView *view,BOOL regenerate) {
    NSLayoutManager *layout=view.layoutManager;
    if (regenerate) [layout invalidateGlyphsForCharacterRange:NSMakeRange(0,view.string.length) changeInLength:0 actualCharacterRange:NULL];
    [layout ensureLayoutForTextContainer:view.textContainer];
    NSUInteger length=layout.numberOfGlyphs;
    NSMutableData *glyphs=[NSMutableData dataWithLength:length*sizeof(CGGlyph)];
    NSMutableData *properties=[NSMutableData dataWithLength:length*sizeof(NSGlyphProperty)];
    NSMutableData *indexes=[NSMutableData dataWithLength:length*sizeof(NSUInteger)];
    NSUInteger copied=[layout getGlyphsInRange:NSMakeRange(0,length) glyphs:glyphs.mutableBytes properties:properties.mutableBytes characterIndexes:indexes.mutableBytes bidiLevels:NULL];
    return @[@(copied),glyphs,properties,indexes];
}
static BOOL HasSharedPolicy(NSTextView *view,NSParagraphStyle *style) {
    __block BOOL valid=YES;
    [view.textStorage enumerateAttribute:NSParagraphStyleAttributeName inRange:NSMakeRange(0,view.string.length) options:0 usingBlock:^(id value,NSRange range,BOOL *stop) {
        if(value!=style || [value lineBreakMode]!=NSLineBreakByCharWrapping) valid=NO;
    }];
    return valid;
}
