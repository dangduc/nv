// Reuse the Cocoa text-system and assertion helpers, not the earlier word-wrap matrix.
#define main UnusedEarlierReviewMain
#include "../../../WordWrapReview/round1/contrarian_ux/probe.m"
#undef main

static NSUInteger CollapsedCases,CommandChecks,PointChecks,RangeChecks,MarkedSteps;
static NSMutableArray *Records;
static SourceView *NativeReference(NSString *source,NSString *font,CGFloat width) {
    NegativeControl=YES;
    SourceView *native=[[[SourceView alloc] initWithText:source font:font width:width] autorelease];
    NegativeControl=NO;
    native->view.layoutManager.delegate=nil;
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode=NSLineBreakByWordWrapping;
    [native->view.textStorage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0,source.length)];
    [native snapshot];
    return native;
}
static NSArray *Boundaries(SourceView *system) {
    NSMutableArray *values=[NSMutableArray array];
    for(NSDictionary *row in [system snapshot]) [values addObject:@[row[@"start"],row[@"length"],row[@"rect"]]];
    return values;
}
static CGFloat Y(SourceView *system,NSUInteger index) {
    NSUInteger glyph=[system->view.layoutManager glyphIndexForCharacterAtIndex:index];
    return [system->view.layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL].origin.y;
}
static void AroundSeparator(NSString *prefix,NSString *suffix,NSString *font) {
    NSString *source=[NSString stringWithFormat:@"%@ %@",prefix,suffix];
    NSFont *face=[NSFont fontWithName:font size:18];
    CGFloat width=[prefix sizeWithAttributes:@{NSFontAttributeName:face}].width+10.25;
    NSUInteger separator=prefix.length;
    SourceView *system=[[[SourceView alloc] initWithText:source font:font width:width] autorelease];
    SourceView *native=NativeReference(source,font,width);
    NSArray *rows=[system snapshot];
    NSDictionary *context=@{@"font":font,@"source":source,@"width":@(width),@"separator":@(separator)};
    BOOL collapsed=Y(system,separator)==Y(system,separator-1) && Y(system,separator+1)>Y(system,separator);
    Check(collapsed,@"the fixture reaches a single separator collapsed at a wrap",context);
    if(collapsed) CollapsedCases++;
    BOOL sameRows=[Boundaries(system) isEqual:Boundaries(native)];
    Check(sameRows,@"single-separator fixture has the native word-wrap line ranges and rectangles",context);
    [Records addObject:@{@"context":context,@"productionRows":rows,@"nativeRows":[native snapshot]}];
    NSArray *selectors=@[@"moveRight:",@"moveLeft:",@"moveRightAndModifySelection:",@"moveLeftAndModifySelection:",
        @"moveWordRight:",@"moveWordLeft:",@"moveWordRightAndModifySelection:",@"moveWordLeftAndModifySelection:",
        @"moveToBeginningOfLine:",@"moveToEndOfLine:",@"moveToBeginningOfParagraph:",@"moveToEndOfParagraph:"];
    for(NSNumber *anchor in @[@(separator-1),@(separator),@(separator+1),@(separator+2)])
    for(NSString *name in selectors) {
        if(!sameRows && ([name containsString:@"Line:"])) continue;
        NSUInteger index=[source rangeOfComposedCharacterSequenceAtIndex:anchor.unsignedIntegerValue].location;
        [system->view setSelectedRange:NSMakeRange(index,0) affinity:NSSelectionAffinityDownstream stillSelecting:NO];
        [native->view setSelectedRange:NSMakeRange(index,0) affinity:NSSelectionAffinityDownstream stillSelecting:NO];
        for(NSUInteger step=0;step<2;step++) {
            [system->view performSelector:NSSelectorFromString(name) withObject:nil];
            [native->view performSelector:NSSelectorFromString(name) withObject:nil];
            NSMutableDictionary *detail=[NSMutableDictionary dictionaryWithDictionary:context];
            [detail addEntriesFromDictionary:@{@"command":name,@"anchor":@(index),@"step":@(step),
                @"actual":NSStringFromRange(system->view.selectedRange),@"native":NSStringFromRange(native->view.selectedRange),
                @"actualAffinity":@(system->view.selectionAffinity),@"nativeAffinity":@(native->view.selectionAffinity)}];
            Check(NSEqualRanges(system->view.selectedRange,native->view.selectedRange),@"commands around the collapsed separator preserve native source selection",detail);
            Check(system->view.selectionAffinity==native->view.selectionAffinity,@"commands preserve native insertion affinity at the wrap",detail);
            CommandChecks++;
        }
    }
    for(NSNumber *anchor in @[@(separator-1),@(separator),@(separator+1),@(separator+2)]) {
        NSUInteger index=[source rangeOfComposedCharacterSequenceAtIndex:anchor.unsignedIntegerValue].location;
        for(NSNumber *granularity in @[@(NSSelectByWord),@(NSSelectByParagraph)]) {
            NSRange proposed=NSMakeRange(index,0);
            Check(NSEqualRanges([system->view selectionRangeForProposedRange:proposed granularity:granularity.unsignedIntegerValue],
                [native->view selectionRangeForProposedRange:proposed granularity:granularity.unsignedIntegerValue]),
                @"word and paragraph selection preserve native source ranges near the separator",context);
            RangeChecks++;
        }
    }
    if(sameRows) for(NSUInteger row=0;row<MIN(rows.count,2UL);row++) {
        NSRect rect=NSRectFromString(rows[row][@"rect"]);
        NSArray *points=rows[row][@"insertions"];
        // Samples include each native insertion position, both sides of it, and the two line margins.
        NSMutableArray *xs=[NSMutableArray arrayWithObjects:@1,@(width-1),nil];
        for(NSArray *pair in points) {
            CGFloat x=[pair[1] doubleValue]+rect.origin.x;
            [xs addObjectsFromArray:@[@(x-0.2),@(x),@(x+0.2)]];
        }
        for(NSNumber *x in xs) {
            NSPoint point=NSMakePoint(x.doubleValue,NSMidY(rect));
            NSUInteger actual=[system->view characterIndexForInsertionAtPoint:point],expected=[native->view characterIndexForInsertionAtPoint:point];
            NSMutableDictionary *detail=[NSMutableDictionary dictionaryWithDictionary:context];
            [detail addEntriesFromDictionary:@{@"point":NSStringFromPoint(point),@"actual":@(actual),@"native":@(expected)}];
            Check(actual==expected,@"click placement around the collapsed separator agrees with native word wrapping",detail);PointChecks++;
        }
    }
    NSUInteger previous=[source rangeOfComposedCharacterSequenceAtIndex:separator-1].location;
    for(NSValue *value in @[[NSValue valueWithRange:NSMakeRange(separator,1)],
        [NSValue valueWithRange:NSMakeRange(previous,separator+2-previous)]]) {
        NSRange selected=value.rangeValue;
        NSUInteger aCount=0,bCount=0;
        NSRectArray a=[system->view.layoutManager rectArrayForCharacterRange:selected withinSelectedCharacterRange:selected inTextContainer:system->view.textContainer rectCount:&aCount];
        NSData *saved=[NSData dataWithBytes:a length:aCount*sizeof(NSRect)];
        NSRectArray b=[native->view.layoutManager rectArrayForCharacterRange:selected withinSelectedCharacterRange:selected inTextContainer:native->view.textContainer rectCount:&bCount];
        NSData *expected=[NSData dataWithBytes:b length:bCount*sizeof(NSRect)];
        Check([saved isEqual:expected],@"selection rectangles for the separator and surrounding text match native wrapping",context);
        RangeChecks++;
    }
    Check([system->view.string isEqual:source],@"navigation and selections preserve the exact source",context);
}
static void MarkedReplacement(NSString *font) {
    NSString *prefix=@"abcdefghij",*original=@"abcdefghij nextword";
    CGFloat width=[prefix sizeWithAttributes:@{NSFontAttributeName:[NSFont fontWithName:font size:18]}].width+10.25;
    SourceView *system=[[[SourceView alloc] initWithText:original font:font width:width] autorelease];
    [system snapshot];
    NSArray *marked=@[@"e",@"e\u0301",@"雪",@"👩🏽‍💻"];
    for(NSUInteger i=0;i<marked.count;i++) {
        NSString *replacement=marked[i];
        NSRange range=i?NSMakeRange(NSNotFound,0):NSMakeRange(11,8);
        [system->view setMarkedText:replacement selectedRange:NSMakeRange(replacement.length,0) replacementRange:range];
        NSString *expected=[@"abcdefghij " stringByAppendingString:replacement];
        NSDictionary *context=@{@"font":font,@"marked":replacement};
        Check([system->view.string isEqual:expected],@"marked replacement at the wrapped word preserves exact source",context);
        Check(NSEqualRanges(system->view.markedRange,NSMakeRange(11,replacement.length)),@"marked range stays attached to the following word",context);
        Check(NSEqualRanges(system->view.selectedRange,NSMakeRange(expected.length,0)),@"marked-text caret stays after the complete replacement",context);
        SourceView *fresh=[[[SourceView alloc] initWithText:expected font:font width:width] autorelease];
        [fresh->view.textStorage setAttributedString:system->view.textStorage];
        Check([[system snapshot] isEqual:[fresh snapshot]],@"marked replacement matches fresh layout and insertion positions",context);
        MarkedSteps++;
    }
    [system->view unmarkText];
    Check(!system->view.hasMarkedText,@"unmarking ends composition beside the separator",@{@"font":font});
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        [NSApplication sharedApplication]; Examples=[NSMutableArray array];FailureKinds=[NSMutableDictionary dictionary];FirstFailure=[NSMutableDictionary dictionary];Records=[NSMutableArray array];
        for(NSString *font in @[@"Menlo-Regular",@"Helvetica"]) {
            AroundSeparator(@"abcdefghij",@"nextword tail",font);
            AroundSeparator(@"alpha beta",@"gamma delta epsilon",font);
            AroundSeparator(@"café e\u0301 👩🏽‍💻",@"next word",font);
            MarkedReplacement(font);
        }
        NSDictionary *report=@{@"checks":@(Checks),@"failures":@(Failures),@"failureKinds":FailureKinds,@"firstFailure":FirstFailure,
            @"collapsedCases":@(CollapsedCases),@"commandComparisons":@(CommandChecks),@"pointComparisons":@(PointChecks),
            @"rangeComparisons":@(RangeChecks),@"markedSteps":@(MarkedSteps),@"records":Records};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        fprintf(stderr,"%lu checks; %lu failures\n",(unsigned long)Checks,(unsigned long)Failures);
    }return 0;
}
