// Reuse the observed production subclass and source-attribute helper, not the old tests.
#define main RoundOneMain
#include "../../round1/ousterhout/probe.m"
#undef main
static NSLayoutManager *NewOwnedLayout(NSTextStorage *storage,SpaceDelegate *delegate,CGFloat width) {
    NSLayoutManager *layout=[[NSLayoutManager alloc]init];
    NSTextContainer *container=[[[NSTextContainer alloc]initWithSize:NSMakeSize(width,1000000)]autorelease];
    [layout addTextContainer:container]; [storage addLayoutManager:layout]; layout.delegate=delegate;
    // Match LinkingEditor.awakeFromNib: only the layout manager retains this typesetter after pool drain.
    NSAutoreleasePool *installationPool=[[NSAutoreleasePool alloc]init];
    [layout setTypesetter:[[[ObservedTypesetter alloc]init]autorelease]];
    [installationPool drain];
    return layout;
}
static NSArray *DeferredSnapshot(NSLayoutManager *layout) {
    NSTextContainer *container=layout.textContainers[0];
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *result=[NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs) usingBlock:^(NSRect rect,NSRect used,NSTextContainer *text,NSRange glyphs,BOOL *stop) {
        NSRange characters=[layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
        [result addObject:@[NSStringFromRange(characters),NSStringFromRect(rect),NSStringFromRect(used),NSStringFromPoint([layout locationForGlyphAtIndex:glyphs.location])]];
    }];
    return result;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        NSTextStorage *storage=[[NSTextStorage alloc]init];
        NSAutoreleasePool *sourcePool=[[NSAutoreleasePool alloc]init];
        NSString *source=@"alpha beta gamma delta epsilon zeta eta theta.\nsecond paragraph with Helvetica and several ordinary words.\nlast paragraph has       many trailing spaces                     ";
        [storage setAttributedString:[[[NSAttributedString alloc]initWithString:source attributes:Attributes(0)]autorelease]];
        NSRange second=[source paragraphRangeForRange:NSMakeRange([source rangeOfString:@"second"].location,0)];
        NSRange third=[source paragraphRangeForRange:NSMakeRange([source rangeOfString:@"last"].location,0)];
        [storage addAttributes:Attributes(1) range:second];
        [storage addAttributes:Attributes(2) range:third];
        [sourcePool drain];
        NSAttributedString *unchanged=[storage copy];
        SpaceDelegate *delegate=[[SpaceDelegate alloc]init];
        NSAutoreleasePool *layoutPool=[[NSAutoreleasePool alloc]init];
        NSLayoutManager *a=NewOwnedLayout(storage,delegate,245),*b=NewOwnedLayout(storage,delegate,337);
        Check(Created==2 && Destroyed==0,@"each layout retains its autoreleased production typesetter after the installation pool drains");
        Check(a.typesetter!=b.typesetter && a.textStorage==b.textStorage,@"the two sole-owner layouts keep distinct typesetters over shared source");
        NSArray *beforeA=[DeferredSnapshot(a)copy],*beforeB=[DeferredSnapshot(b)copy];
        Check([storage isEqualToAttributedString:unchanged],@"deferred layout preserves mixed paragraph font and source attributes after their creation pool drains");
        Check(![[((ObservedTypesetter *)a.typesetter)cacheState][@"hasMeasure"]boolValue],@"deferred multi-paragraph layout releases its final measurement");
        for(NSUInteger replacement=0;replacement<4;replacement++) {
            NSUInteger destroyedBefore=Destroyed;
            NSAutoreleasePool *replacementPool=[[NSAutoreleasePool alloc]init];
            [a setTypesetter:[[[ObservedTypesetter alloc]init]autorelease]];
            [replacementPool drain];
            Check(Destroyed==destroyedBefore+1 && Created-Destroyed==2,@"replacement releases the old sole-owned typesetter and retains exactly its successor");
            Check([beforeA isEqual:DeferredSnapshot(a)],@"typesetter replacement preserves deferred line geometry on the same layout");
            [a invalidateGlyphsForCharacterRange:NSMakeRange(0,storage.length) changeInLength:0 actualCharacterRange:NULL];
            Check([beforeA isEqual:DeferredSnapshot(a)],@"replacement also reproduces geometry after complete glyph regeneration");
            Check([beforeB isEqual:DeferredSnapshot(b)] && b.textStorage==storage,@"replacement and regeneration cannot affect the peer layout");
            Check([storage isEqualToAttributedString:unchanged],@"typesetter ownership transitions never rewrite shared source attributes");
        }
        NSUInteger beforeRemoval=Destroyed;
        [storage removeLayoutManager:a]; a.delegate=nil; [a release];
        [layoutPool drain];
        NSAutoreleasePool *peerPool=[[NSAutoreleasePool alloc]init];
        Check(Destroyed==beforeRemoval+1 && Created-Destroyed==1,@"removing one layout and draining native temporaries destroys its sole-owned typesetter");
        Check([beforeB isEqual:DeferredSnapshot(b)] && [storage isEqualToAttributedString:unchanged],@"surviving layout remains correct after its peer and peer typesetter are destroyed");
        [storage removeLayoutManager:b]; b.delegate=nil; [b release];
        [peerPool drain];
        Check(Created==Destroyed,@"all six autoreleased production instances are destroyed by their layout owners");
        [beforeA release]; [beforeB release]; [unchanged release]; [delegate release]; [storage release];
        NSDictionary *result=@{@"checks":@(Checks),@"typesettersCreated":@(Created),@"typesettersDestroyed":@(Destroyed),@"soleOwnerLayouts":@2,@"replacements":@4,@"paragraphs":@3,@"narrowedLines":@(NarrowedLines)};
        [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL]writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES];
        fprintf(stderr,"PASS: %lu checks; %lu/%lu typesetters destroyed\n",(unsigned long)Checks,(unsigned long)Destroyed,(unsigned long)Created);
    }
    return 0;
}
