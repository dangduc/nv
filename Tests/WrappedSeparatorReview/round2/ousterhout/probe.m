#include "support.h"
#import <objc/runtime.h>

static NSMutableDictionary *OrderBaselines;
static NSUInteger Comparisons, CacheChecks;
static void CheckReleasedAnalysis(NSLayoutManager *layout) {
    void *measure=NULL,*breaks=NULL;
    Check(object_getInstanceVariable(layout.typesetter,"paragraphMeasure",&measure)!=NULL,
          @"the frozen production typesetter exposes its expected measurement ivar");
    Check(object_getInstanceVariable(layout.typesetter,"lineBreaks",&breaks)!=NULL,
          @"the frozen production typesetter exposes its expected break-table ivar");
    Check(measure==NULL && breaks==NULL,@"completed layout retains no paragraph measurement or break table");
    CacheChecks++;
}
static void CompareInOrder(NSString *stage,NSArray *layouts,NSArray *delegates,NSArray *order,NSUInteger permutation) {
    for(NSNumber *number in order) {
        NSUInteger index=number.unsignedIntegerValue;
        NSLayoutManager *layout=layouts[index]; CountingDelegate *delegate=delegates[index];
        NSDictionary *actual=Snapshot(layout),*fresh=Fresh(layout);
        Check([actual isEqual:fresh],[stage stringByAppendingString:@" matches fresh production glyphs and geometry"]);
        NSString *key=[NSString stringWithFormat:@"%@:%lu",stage,(unsigned long)index];
        NSDictionary *baseline=OrderBaselines[key];
        if(baseline) Check([baseline isEqual:actual],[stage stringByAppendingString:@" is independent of layout request order"]);
        else OrderBaselines[key]=actual;
        CheckPolicy(layout);
        CheckReleasedAnalysis(layout);
        [Rows addObject:@{@"stage":stage,@"permutation":@(permutation),@"layout":@(index),
                         @"glyphs":@([actual[@"glyphs"] count]),@"lines":@([actual[@"lines"] count]),
                         @"generated":@(delegate->generated)}];
        delegate->generated=0;
        Comparisons++;
    }
}
static void Invalidate(NSLayoutManager *layout,NSRange range) {
    NSRange actual=NSMakeRange(NSNotFound,0);
    Check(range.location<=layout.textStorage.length && range.length<=layout.textStorage.length-range.location,
          @"targeted invalidation stays within current source");
    [layout invalidateGlyphsForCharacterRange:range changeInLength:0 actualCharacterRange:&actual];
    Check(actual.location!=NSNotFound && actual.location<=layout.textStorage.length &&
          actual.length<=layout.textStorage.length-actual.location,@"AppKit returns a bounded expanded invalidation range");
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==2,@"expected result path");
        Rows=[NSMutableArray array]; OrderBaselines=[NSMutableDictionary dictionary];
        NSArray *orders=@[@[@0,@1,@2],@[@0,@2,@1],@[@1,@0,@2],@[@1,@2,@0],@[@2,@0,@1],@[@2,@1,@0]];
        NSUInteger permutation=0;
        for(NSArray *order in orders) { @autoreleasepool {
            NSTextStorage *shared=[[[NSTextStorage alloc] initWithAttributedString:
                Attributed(@"prefix alpha beta\n  gamma \u0301delta epsilon\nlast word tail ")] autorelease];
            NSTextStorage *other=[[[NSTextStorage alloc] initWithAttributedString:
                Attributed(@"other  note\nword \ufe0fnext end ")] autorelease];
            CountingDelegate *d0=[[[CountingDelegate alloc] init] autorelease];
            CountingDelegate *d1=[[[CountingDelegate alloc] init] autorelease];
            CountingDelegate *d2=[[[CountingDelegate alloc] init] autorelease];
            NSArray *delegates=@[d0,d1,d2];
            NSArray *layouts=@[NewLayout(shared,d0,82,NO),NewLayout(shared,d1,119,YES),NewLayout(shared,d2,207,YES)];
            Check(shared.layoutManagers.count==3,@"three native layout managers share one storage owner");
            NSSet *typesetters=[NSSet setWithObjects:[layouts[0] typesetter],[layouts[1] typesetter],[layouts[2] typesetter],nil];
            Check(typesetters.count==3,@"each layout owns a separate production typesetter");
            CompareInOrder(@"initial",layouts,delegates,order,permutation);

            NSUInteger separator=NSMaxRange([shared.string rangeOfString:@"alpha"]);
            NSRange mark=[shared.string rangeOfString:@"\u0301"];
            NSRange newline=[shared.string rangeOfString:@"\n"];
            Invalidate(layouts[0],NSMakeRange(separator,1));
            Invalidate(layouts[1],mark);
            Invalidate(layouts[2],NSMakeRange(newline.location-1,3));
            CompareInOrder(@"split-attribute-and-paragraph-invalidations",layouts,delegates,order,permutation);

            [shared beginEditing];
            [shared addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Helvetica" size:20]
                           range:[shared.string rangeOfString:@"alpha"]];
            [shared addAttribute:NSBaselineOffsetAttributeName value:@2 range:NSMakeRange(separator,1)];
            [shared endEditing];
            Invalidate(layouts[1],NSMakeRange(separator-1,2));
            CompareInOrder(@"font-boundary-change",layouts,delegates,order,permutation);

            [shared replaceCharactersInRange:newline withString:@""];
            Invalidate(layouts[0],NSMakeRange(newline.location-1,3));
            Invalidate(layouts[2],NSMakeRange(newline.location,1));
            CompareInOrder(@"joined-paragraph-boundary",layouts,delegates,order,permutation);

            [shared beginEditing];
            [shared replaceCharactersInRange:[shared.string rangeOfString:@"\u0301"] withString:@""];
            [shared replaceCharactersInRange:NSMakeRange(separator+1,0) withString:@"\ufe0f"];
            [shared addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor]
                           range:NSMakeRange(separator,2)];
            [shared endEditing];
            Invalidate(layouts[2],NSMakeRange(separator+1,1));
            CompareInOrder(@"disjoint-composed-context-batch",layouts,delegates,order,permutation);

            NSLayoutManager *middle=layouts[1];
            [shared removeLayoutManager:middle]; [other addLayoutManager:middle];
            Invalidate(middle,NSMakeRange(6,1));
            CompareInOrder(@"middle-layout-other-note",layouts,delegates,order,permutation);
            [other replaceCharactersInRange:[other.string rangeOfString:@"\ufe0f"] withString:@""];
            [shared replaceCharactersInRange:NSMakeRange(shared.length,0) withString:@"next"];
            Invalidate(layouts[0],NSMakeRange(shared.length-5,1));
            CompareInOrder(@"two-note-independent-edits",layouts,delegates,order,permutation);

            [other removeLayoutManager:middle]; [shared addLayoutManager:middle];
            Invalidate(middle,NSMakeRange(separator,2));
            CompareInOrder(@"middle-layout-returns",layouts,delegates,order,permutation);
            for(NSLayoutManager *layout in layouts) {
                NSTextContainer *container=layout.textContainers.firstObject;
                container.containerSize=NSMakeSize(container.containerSize.width+13,1000000);
            }
            CompareInOrder(@"independent-width-change",layouts,delegates,order,permutation);
            for(NSLayoutManager *layout in layouts) { layout.delegate=nil; [layout.textStorage removeLayoutManager:layout]; }
            Check(shared.layoutManagers.count==0 && other.layoutManagers.count==0,@"fixture releases both storage-to-layout attachments");
            permutation++;
        }}
        Check(NSApp==nil,@"no application or GUI session exists");
        NSDictionary *report=@{@"checks":@(Checks+1),@"requestOrders":@(orders.count),
                              @"layoutComparisons":@(Comparisons),@"releasedAnalysisChecks":@(CacheChecks),@"rows":Rows};
        Check([[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
               writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"write compact evidence");
        printf("PASS: %lu checks; %lu comparisons across six request orders\n",(unsigned long)Checks,(unsigned long)Comparisons);
    }
    return 0;
}
