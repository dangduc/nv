// Reuse only the first-round Cocoa system and assertion helpers. Its matrix does not run.
#define main RoundOneUnusedMain
#include "../../round1/contrarian_ux/probe.m"
#undef main

static NSUInteger GranularityChecks, NavigationChecks, SelectionSamples, DifferentRows, SpaceOnlyRows;
static NSMutableArray *Observations;

static void SelectionCoverage(SourceView *system, NSRange selected, NSDictionary *context) {
    NSLayoutManager *layout=system->view.layoutManager;
    NSUInteger count=0;
    NSRectArray borrowed=[layout rectArrayForCharacterRange:selected withinSelectedCharacterRange:selected
        inTextContainer:system->view.textContainer rectCount:&count];
    NSData *copy=[NSData dataWithBytes:borrowed length:count*sizeof(NSRect)];
    const NSRect *rectangles=copy.bytes;
    for (NSDictionary *row in [system snapshot]) {
        NSRect line=NSRectFromString(row[@"rect"]);
        NSArray *points=row[@"insertions"];
        for(NSUInteger p=0;p+1<points.count;p++) {
            NSUInteger start=[points[p][0] unsignedIntegerValue],end=[points[p+1][0] unsignedIntegerValue];
            CGFloat a=[points[p][1] doubleValue],b=[points[p+1][1] doubleValue];
            if(end<=start || b-a<0.1 || [[NSCharacterSet newlineCharacterSet] characterIsMember:[system->view.string characterAtIndex:start]]) continue;
            BOOL chosen=start>=selected.location && end<=NSMaxRange(selected);
            if(!chosen && NSIntersectionRange(selected,NSMakeRange(start,end-start)).length) continue;
            NSPoint midpoint=NSMakePoint(line.origin.x+(a+b)*0.5,NSMidY(line));
            BOOL contains=NO;
            for(NSUInteger r=0;r<count;r++) if(NSPointInRect(midpoint,NSInsetRect(rectangles[r],-0.1,-0.1))) contains=YES;
            NSMutableDictionary *detail=[NSMutableDictionary dictionaryWithDictionary:context];
            [detail addEntriesFromDictionary:@{@"selected":NSStringFromRange(selected),@"index":@(start),@"chosen":@(chosen),@"covered":@(contains)}];
            Check(contains==chosen,@"multiline selection rectangles cover exactly the chosen insertion intervals",detail);
            SelectionSamples++;
        }
    }
}

static void Affordances(NSString *font,CGFloat width) {
    NSString *spaces=[@"" stringByPaddingToLength:36 withString:@" " startingAtIndex:0];
    NSString *source=[NSString stringWithFormat:@"alpha beta gamma delta %@identifierWithManyCharacters0123456789  omega\n\nnext paragraph: café e\u0301 👩🏽‍💻 zeta eta theta\r\nlast line words.",spaces];
    SourceView *system=[[[SourceView alloc] initWithText:source font:font width:width] autorelease];
    NegativeControl=YES;
    SourceView *native=[[[SourceView alloc] initWithText:source font:font width:width] autorelease];
    NegativeControl=NO;
    NSArray *rows=[system snapshot]; [native snapshot];
    for(NSDictionary *row in rows) {
        NSString *text=[source substringWithRange:NSMakeRange([row[@"start"] unsignedIntegerValue],[row[@"length"] unsignedIntegerValue])];
        if([text stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" "]].length==0) SpaceOnlyRows++;
    }
    for(NSUInteger i=0;i<source.length;i++) {
        NSUInteger a=[system->view.layoutManager glyphIndexForCharacterAtIndex:i],b=[native->view.layoutManager glyphIndexForCharacterAtIndex:i];
        CGFloat y=[system->view.layoutManager lineFragmentRectForGlyphAtIndex:a effectiveRange:NULL].origin.y;
        CGFloat other=[native->view.layoutManager lineFragmentRectForGlyphAtIndex:b effectiveRange:NULL].origin.y;
        if(y!=other) DifferentRows++;
    }
    NSRange token=[source rangeOfString:@"identifierWithManyCharacters0123456789"];
    NSUInteger newline=[source rangeOfString:@"\n"].location;
    NSArray *anchors=@[@0,@6,@12,@25,@45,@(token.location+10),@(NSMaxRange(token)),@(newline),@(newline+1),
        @([source rangeOfString:@"paragraph"].location+3),@([source rangeOfString:@"café"].location+1),
        @([source rangeOfString:@"👩🏽‍💻"].location),@(source.length-3)];
    NSMutableArray *ranges=[NSMutableArray array];
    for(NSNumber *anchor in anchors) [ranges addObject:[NSValue valueWithRange:[source rangeOfComposedCharacterSequenceAtIndex:anchor.unsignedIntegerValue]]];
    [ranges addObject:[NSValue valueWithRange:NSMakeRange(12,token.location+10-12)]];
    for(NSValue *rangeValue in ranges) {
        NSRange proposed=rangeValue.rangeValue;
        for(NSNumber *mode in @[@(NSSelectByWord),@(NSSelectByParagraph)]) {
            NSRange selected=[system->view selectionRangeForProposedRange:proposed granularity:mode.unsignedIntegerValue];
            NSRange expected=[native->view selectionRangeForProposedRange:proposed granularity:mode.unsignedIntegerValue];
            NSDictionary *context=@{@"font":font,@"width":@(width),@"proposed":NSStringFromRange(proposed),@"granularity":mode,
                @"actual":NSStringFromRange(selected),@"native":NSStringFromRange(expected)};
            Check(NSEqualRanges(selected,expected),@"word and paragraph selection preserve native source ranges",context);
            Check(NSMaxRange(selected)<=source.length,@"selection remains inside source",context);
            [Observations addObject:context]; GranularityChecks++;
        }
    }
    NSArray *commands=@[@"moveWordRight:",@"moveWordLeft:",@"moveWordRightAndModifySelection:",@"moveWordLeftAndModifySelection:"];
    for(NSNumber *anchor in @[@6,@25,@(token.location+10),@(newline+3)])
    for(NSString *command in commands) {
        system->view.selectedRange=native->view.selectedRange=NSMakeRange(anchor.unsignedIntegerValue,0);
        for(NSUInteger step=0;step<3;step++) {
            [system->view performSelector:NSSelectorFromString(command) withObject:nil];
            [native->view performSelector:NSSelectorFromString(command) withObject:nil];
            NSDictionary *context=@{@"font":font,@"width":@(width),@"anchor":anchor,@"command":command,@"step":@(step),
                @"actual":NSStringFromRange(system->view.selectedRange),@"native":NSStringFromRange(native->view.selectedRange)};
            Check(NSEqualRanges(system->view.selectedRange,native->view.selectedRange),@"word navigation and extension preserve native source indexes",context);
            [Observations addObject:context]; NavigationChecks++;
        }
    }
    NSDictionary *context=@{@"font":font,@"width":@(width)};
    SelectionCoverage(system,NSMakeRange(12,token.location+10-12),context);
    SelectionCoverage(system,NSMakeRange(NSMaxRange(token)-3,newline+12-(NSMaxRange(token)-3)),context);
    Check([system->view.string isEqual:source] && [native->view.string isEqual:source],@"selection and navigation preserve the exact source",context);
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2) return 2;
        [NSApplication sharedApplication]; Examples=[NSMutableArray array]; FailureKinds=[NSMutableDictionary dictionary];
        FirstFailure=[NSMutableDictionary dictionary]; Observations=[NSMutableArray array];
        for(NSString *font in @[@"Menlo-Regular",@"Helvetica"]) for(NSNumber *width in @[@160.1,@239.9]) Affordances(font,width.doubleValue);
        Check(DifferentRows>0,@"reference comparison includes different visual wrapping",@{});
        Check(SpaceOnlyRows>0,@"fixture includes complete visual rows of overflowing ordinary spaces",@{});
        NSDictionary *result=@{@"checks":@(Checks),@"failures":@(Failures),@"failureKinds":FailureKinds,@"examples":Examples,
            @"cases":@4,@"granularityComparisons":@(GranularityChecks),@"navigationComparisons":@(NavigationChecks),
            @"selectionIntervalSamples":@(SelectionSamples),@"charactersOnDifferentRows":@(DifferentRows),
            @"spaceOnlyRows":@(SpaceOnlyRows),@"observations":Observations};
        [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        fprintf(stderr,"%lu checks; %lu failures\n",(unsigned long)Checks,(unsigned long)Failures);
    }
    return 0;
}
