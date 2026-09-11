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
@interface CountingDelegate : ProductionDelegate { @public NSUInteger generated; }
@end
@implementation CountingDelegate
- (NSUInteger)layoutManager:(NSLayoutManager *)layout shouldGenerateGlyphs:(const CGGlyph *)glyphs
    properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes
    font:(NSFont *)font forGlyphRange:(NSRange)range {
    generated += range.length;
    return [super layoutManager:layout shouldGenerateGlyphs:glyphs properties:properties
               characterIndexes:indexes font:font forGlyphRange:range];
}
@end

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
static void Record(NSString *name, NSArray *layouts, NSArray *delegates) {
    for(NSUInteger i=0;i<layouts.count;i++) {
        NSLayoutManager *layout=layouts[i]; CountingDelegate *delegate=delegates[i];
        NSDictionary *actual=Snapshot(layout),*expected=Fresh(layout);
        BOOL equal=[actual isEqual:expected];
        if(!equal) fprintf(stderr,"Mismatch %s layout %lu:\nactual %s\nexpected %s\n",name.UTF8String,
                           (unsigned long)i,actual.description.UTF8String,expected.description.UTF8String);
        Check(equal,[name stringByAppendingString:@" cached glyphs and geometry match fresh production layout"]);
        CheckPolicy(layout);
        if (([name isEqual:@"edit-note-A-with-peer-on-note-B"] && i==0) ||
            ([name isEqual:@"edit-composed-space-in-note-B"] && i==1))
            Check(delegate->generated==0,@"editing one note does not regenerate the other note's layout");
        [Rows addObject:@{@"case":name,@"layout":@(i),@"length":@(layout.textStorage.length),
                         @"glyphs":@([actual[@"glyphs"] count]),@"lines":@([actual[@"lines"] count]),
                         @"generated":@(delegate->generated),@"freshMatch":@(equal)}];
        delegate->generated=0;
    }
}

int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==2,@"expected output path");
        Rows=[NSMutableArray array];
        NSTextStorage *noteA=[[[NSTextStorage alloc] initWithAttributedString:Attributed(@"abcdefghij next alpha beta\nend word ")] autorelease];
        NSTextStorage *noteB=[[[NSTextStorage alloc] initWithAttributedString:Attributed(@"note  B \u0301word\n    indent next")] autorelease];
        CountingDelegate *d1=[[[CountingDelegate alloc] init] autorelease];
        CountingDelegate *d2=[[[CountingDelegate alloc] init] autorelease];
        NSLayoutManager *l1=NewLayout(noteA,d1,91,NO),*l2=NewLayout(noteA,d2,173,YES);
        NSArray *layouts=@[l1,l2],*delegates=@[d1,d2];
        Check(l1.typesetter!=l2.typesetter,@"shared storage keeps distinct production typesetters");
        Record(@"initial-distinct-font-runs",layouts,delegates);
        for(NSString *mark in @[@"\u0301",@"\ufe0f",@"\u200d"]) {
            NSString *name=[NSString stringWithFormat:@"mark-U%04X",[mark characterAtIndex:0]];
            [noteA replaceCharactersInRange:NSMakeRange(11,0) withString:mark];
            Record([name stringByAppendingString:@"-insert"],layouts,delegates);
            [noteA replaceCharactersInRange:NSMakeRange(11,mark.length) withString:@""];
            Record([name stringByAppendingString:@"-delete"],layouts,delegates);
        }
        [noteA replaceCharactersInRange:NSMakeRange(11,1) withString:@"\u00a0"];
        Record(@"nonbreaking-neighbor-insert",layouts,delegates);
        [noteA replaceCharactersInRange:NSMakeRange(11,1) withString:@"n"];
        Record(@"nonbreaking-neighbor-remove",layouts,delegates);
        [noteA beginEditing];
        [noteA replaceCharactersInRange:NSMakeRange(11,0) withString:@"\u0301"];
        [noteA replaceCharactersInRange:[noteA.string rangeOfString:@"beta"] withString:@""];
        [noteA addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Menlo-Italic" size:17] range:NSMakeRange(0,5)];
        [noteA endEditing];
        Record(@"disjoint-composition-deletion-attributes-batch",layouts,delegates);
        [noteA setAttributedString:Attributed(@"one two three\nlast word ")];
        Record(@"replace-shared-note-contents",layouts,delegates);
        [noteA addAttributes:@{NSFontAttributeName:[NSFont fontWithName:@"Helvetica" size:19],
                             NSBaselineOffsetAttributeName:@2} range:NSMakeRange(3,1)];
        Record(@"attribute-only-separator-change",layouts,delegates);

        // Move only one browser's layout. replaceTextStorage: moves all layouts.
        [noteA removeLayoutManager:l1]; [noteB addLayoutManager:l1];
        Check(l1.textStorage==noteB && l2.textStorage==noteA && noteA.layoutManagers.count==1 && noteB.layoutManagers.count==1,
              @"one layout changes notes without moving its shared peer");
        Record(@"split-layouts-across-notes",layouts,delegates);
        [noteA replaceCharactersInRange:NSMakeRange(4,0) withString:@" "];
        Record(@"edit-note-A-with-peer-on-note-B",layouts,delegates);
        [noteB replaceCharactersInRange:[noteB.string rangeOfString:@"\u0301"] withString:@""];
        Record(@"edit-composed-space-in-note-B",layouts,delegates);
        [noteB removeLayoutManager:l1]; [noteA addLayoutManager:l1];
        Record(@"reattach-layout-to-shared-note",layouts,delegates);
        [noteA setAttributedString:Attributed(@"")];
        Record(@"reuse-with-empty-note",layouts,delegates);
        [noteA setAttributedString:Attributed(@"\t  start one two\u00a0three\ntrailing  ")];
        Record(@"reuse-after-empty-note",layouts,delegates);
        Check(NSApp==nil,@"no application or GUI session was created");
        NSDictionary *report=@{@"checks":@(Checks),@"layoutComparisons":@(Rows.count),@"rows":Rows};
        Check([[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
               writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"save bounded results");
        printf("PASS: %lu checks, %lu production-layout comparisons\n",(unsigned long)Checks,(unsigned long)Rows.count);
        for(NSLayoutManager *layout in layouts) { layout.delegate=nil; [layout.textStorage removeLayoutManager:layout]; }
    }
    return 0;
}
