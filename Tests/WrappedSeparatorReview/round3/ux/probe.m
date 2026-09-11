// The runner reuses the earlier Cocoa setup, native reference, and typing setup only.
#include "reused-ux-helper.h"
#include "original-literal-delegate.h"
static NSUInteger Histories,Stages,NativePositions,FreshPositions,ProtectedAdvances;
static NSMutableArray *Transcript,*ProtectedWidths;

static void Observe(SourceView *system,SourceView *native,NSString *font,CGFloat offset,NSString *replacement,BOOL protected,NSString *stage) {
    NSString *expected=[@"abcdefghij " stringByAppendingString:replacement];
    NSDictionary *context=@{@"font":font,@"widthOffset":@(offset),@"replacement":replacement,@"stage":stage};
    Check([system->view.string isEqual:expected] && [native->view.string isEqual:expected],@"marked replacement preserves the exact intended source in both editors",context);
    Check(NSEqualRanges(system->view.selectedRange,NSMakeRange(expected.length,0)),@"production selection follows the complete marked replacement",context);
    Check(NSEqualRanges(system->view.selectedRange,native->view.selectedRange),@"marked replacement retains native logical selection",context);
    Check(system->view.selectionAffinity==native->view.selectionAffinity,@"marked replacement retains native caret affinity",context);
    NSArray *snapshot=[system snapshot];
    NSUInteger glyph=[system->view.layoutManager glyphIndexForCharacterAtIndex:10];
    BOOL elastic=([system->view.layoutManager propertyForGlyphAtIndex:glyph]&NSGlyphPropertyElastic)!=0;
    Check(elastic!=protected,@"space elasticity follows the explicit ordinary/protected fixture state",context);
    SourceView *fresh=[[[SourceView alloc] initWithText:expected font:font width:system->view.frame.size.width] autorelease];
    [fresh->view.textStorage setAttributedString:system->view.textStorage];
    Check([snapshot isEqual:[fresh snapshot]],@"width and marked-text history retain fresh production insertion positions",context);FreshPositions++;
    if(!protected) {
        Check([snapshot isEqual:[native snapshot]],@"ordinary separators retain native word-wrap insertion positions at this width",context);NativePositions++;
    } else {
        SourceView *literal=[[[SourceView alloc] initWithText:expected font:font width:system->view.frame.size.width] autorelease];
        literal->view.layoutManager.delegate=[[[LiteralSpaceDelegate alloc] init] autorelease];
        [literal->view.textStorage setAttributedString:system->view.textStorage];
        [literal->view.layoutManager invalidateGlyphsForCharacterRange:NSMakeRange(0,expected.length) changeInLength:0 actualCharacterRange:NULL];
        Check([snapshot isEqual:[literal snapshot]],@"protected space retains the original literal-policy layout and insertion positions",context);
        BOOL measured=NO;
        CGFloat expectedAdvance=[@" " sizeWithAttributes:@{NSFontAttributeName:[NSFont fontWithName:font size:18]}].width;
        for(NSDictionary *row in snapshot) {
            NSArray *points=row[@"insertions"];
            for(NSUInteger i=0;i+1<points.count;i++) {
                if([points[i][0] unsignedIntegerValue]==10 && [points[i+1][0] unsignedIntegerValue]==12) {
                    CGFloat advance=[points[i+1][1] doubleValue]-[points[i][1] doubleValue];
                    NSMutableDictionary *detail=[NSMutableDictionary dictionaryWithDictionary:context];
                    [detail addEntriesFromDictionary:@{@"advance":@(advance),@"ordinaryUnmarkedSpaceWidth":@(expectedAdvance)}];
                    Check(advance>0.05,@"protected space retains a visible native insertion interval",detail);
                    [ProtectedWidths addObject:detail];
                    measured=YES;ProtectedAdvances++;
                }
            }
        }
        Check(measured,@"protected-space insertion interval is present and measurable",context);
    }
    [Transcript addObject:@{@"case":context,@"source":expected,@"selection":NSStringFromRange(system->view.selectedRange),
        @"markedRange":NSStringFromRange(system->view.markedRange),@"affinity":@(system->view.selectionAffinity),@"elastic":@(elastic),@"positions":snapshot}];Stages++;
}
static void History(NSString *font,CGFloat offset) {
    CGFloat width=[@"abcdefghij" sizeWithAttributes:@{NSFontAttributeName:[NSFont fontWithName:font size:18]}].width+10+offset;
    SourceView *system=[[[SourceView alloc] initWithText:@"abcdefghij xray" font:font width:width] autorelease];
    SourceView *native=NativeReference(@"abcdefghij xray",font,width);PrepareNativeTyping(native);
    [system snapshot];
    NSArray *replacements=@[@"x",@"e\u0301",@"\u0301x",@"雪",@"x"];
    for(NSUInteger i=0;i<replacements.count;i++) {
        NSString *replacement=replacements[i];
        NSRange replace=i?NSMakeRange(NSNotFound,0):NSMakeRange(11,4);
        [system->view setMarkedText:replacement selectedRange:NSMakeRange(replacement.length,0) replacementRange:replace];
        [native->view setMarkedText:replacement selectedRange:NSMakeRange(replacement.length,0) replacementRange:replace];
        Observe(system,native,font,offset,replacement,i==2,@"marked");
        Check(NSEqualRanges(system->view.markedRange,NSMakeRange(11,replacement.length)),@"composition range continues to identify the replacement beside the separator",@{@"font":font,@"widthOffset":@(offset),@"replacement":replacement});
    }
    [system->view unmarkText];[native->view unmarkText];
    Observe(system,native,font,offset,@"x",NO,@"committed");
    Check(!system->view.hasMarkedText && !native->view.hasMarkedText,@"composition commits without leaving a marked range",@{@"font":font,@"widthOffset":@(offset)});
    Histories++;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;[NSApplication sharedApplication];
        Examples=[NSMutableArray array];FailureKinds=[NSMutableDictionary dictionary];FirstFailure=[NSMutableDictionary dictionary];Transcript=[NSMutableArray array];ProtectedWidths=[NSMutableArray array];
        for(NSString *font in @[@"Menlo-Regular",@"Helvetica"])for(NSNumber *offset in @[@(-0.25),@0,@0.25])History(font,offset.doubleValue);
        NSDictionary *result=@{@"checks":@(Checks),@"failures":@(Failures),@"failureKinds":FailureKinds,@"firstFailure":FirstFailure,
            @"widthCompositionHistories":@(Histories),@"stages":@(Stages),@"nativeInsertionComparisons":@(NativePositions),
            @"freshInsertionComparisons":@(FreshPositions),@"protectedSpaceAdvances":@(ProtectedAdvances),@"protectedWidths":ProtectedWidths,@"transcript":Transcript};
        [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:@(argv[1]) atomically:YES];
        fprintf(stderr,"%lu checks; %lu failures\n",(unsigned long)Checks,(unsigned long)Failures);
    }return 0;
}
