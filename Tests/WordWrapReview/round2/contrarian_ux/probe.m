// Reuse the round-one text-system, hit-testing, and selection helpers, not its matrix.
#define main RoundOneUnusedMain
#include "../../round1/contrarian_ux/probe.m"
#undef main

static NSUInteger CompletedParagraphs, RetainedAnalysis, EmptyStates, SeparatorMoves;
static NSMutableArray *Transcript;
@interface CompletionObserver : NVSourceTypesetter
@end
@implementation CompletionObserver
- (void)endParagraph {
    [super endParagraph];
    CompletedParagraphs++;
    if (paragraphMeasure || lineBreaks) RetainedAnalysis++;
}
@end

static SourceView *Make(NSString *source, NSString *font, CGFloat width) {
    SourceView *system=[[[SourceView alloc] initWithText:source font:font width:width] autorelease];
    system->view.layoutManager.typesetter=[[[CompletionObserver alloc] init] autorelease];
    return system;
}
static void Record(SourceView *system, NSString *font, NSString *stage) {
    NSRange selected=system->view.selectedRange;
    NSDictionary *context=@{@"stage":stage,@"font":font};
    Fresh(system,font,context);
    [Transcript addObject:@{@"stage":stage,@"font":font,@"source":system->view.string,
        @"selection":NSStringFromRange(selected),@"rows":[system snapshot]}];
    system->view.selectedRange=selected;
}
static void EmptyAndRestore(NSString *font) {
    NSString *source=@"alpha beta gamma delta epsilon\n\nreallyLongIdentifierWithManyCharacters0123456789     omega\n";
    SourceView *system=Make(source,font,160.1);
    Record(system,font,@"initial wrapped source");
    for (NSUInteger cycle=0;cycle<3;cycle++) {
        NSDictionary *context=@{@"sequence":@"empty and restore",@"font":font,@"cycle":@(cycle)};
        [system->view selectAll:nil];
        [system->view deleteBackward:nil];
        Check(system->view.string.length==0 && NSEqualRanges(system->view.selectedRange,NSMakeRange(0,0)),
            @"delete all leaves an empty source and insertion at zero",context);
        Record(system,font,@"empty source");
        NSRect extra=system->view.layoutManager.extraLineFragmentRect;
        Check(extra.size.height>0 && isfinite(extra.origin.x) && isfinite(extra.origin.y),
            @"empty source retains finite native insertion-line geometry",context);
        Check([system->view characterIndexForInsertionAtPoint:NSMakePoint(8,NSMidY(extra))]==0,
            @"empty-source mouse placement selects zero",context);
        [system->view moveRight:nil]; [system->view moveLeft:nil];
        Check(NSEqualRanges(system->view.selectedRange,NSMakeRange(0,0)),@"empty-source arrows retain zero",context);
        EmptyStates++;
        NSString *replacement=cycle==1 ? @"\n\n" : source;
        [system->view insertText:replacement replacementRange:system->view.selectedRange];
        Check([system->view.string isEqual:replacement] &&
            NSEqualRanges(system->view.selectedRange,NSMakeRange(replacement.length,0)),
            @"restore preserves exact source and final insertion",context);
        [system->view setFrameSize:NSMakeSize(cycle%2 ? 239.9 : 160.1,100000)];
        Record(system,font,@"restored and resized source");
    }
}
static void SeparatorsAndLongToken(NSString *font) {
    NSString *source=@"alpha beta gamma\r\n\r\nidentifierWithManyCharacters0123456789\u2028delta epsilon\u2029zeta eta theta\nlast words";
    SourceView *system=Make(source,font,160.1);
    Record(system,font,@"mixed separators");
    NegativeControl=YES;
    SourceView *native=[[[SourceView alloc] initWithText:source font:font width:160.1] autorelease];
    NegativeControl=NO;
    [native snapshot];
    NSCharacterSet *separators=[NSCharacterSet newlineCharacterSet];
    for (NSUInteger i=0;i<source.length;) {
        NSRange cluster=[source rangeOfComposedCharacterSequenceAtIndex:i];
        // Cocoa navigation treats CRLF as one separator even when NSString reports separate sequences.
        if ([source characterAtIndex:i]=='\r' && i+1<source.length && [source characterAtIndex:i+1]=='\n') cluster.length=2;
        if ([separators characterIsMember:[source characterAtIndex:i]]) {
            NSDictionary *context=@{@"sequence":@"separator navigation",@"font":font,@"index":@(i),@"cluster":NSStringFromRange(cluster)};
            system->view.selectedRange=NSMakeRange(i,0);
            [system->view moveRight:nil];
            Check(NSEqualRanges(system->view.selectedRange,NSMakeRange(NSMaxRange(cluster),0)),
                @"Right crosses the complete separator",context);
            [system->view moveLeft:nil];
            Check(NSEqualRanges(system->view.selectedRange,NSMakeRange(i,0)),@"Left returns across the complete separator",context);
            [system->view moveRightAndModifySelection:nil];
            native->view.selectedRange=NSMakeRange(i,0);
            [native->view moveRight:nil]; [native->view moveLeft:nil]; [native->view moveRightAndModifySelection:nil];
            Check(NSEqualRanges(system->view.selectedRange,native->view.selectedRange),
                @"Shift-Right preserves native separator selection semantics",context);
            [Transcript addObject:@{@"stage":@"separator selection",@"font":font,@"selection":NSStringFromRange(system->view.selectedRange)}];
            SeparatorMoves+=3;
        }
        i=NSMaxRange(cluster);
    }
    NSRange token=[source rangeOfString:@"identifierWithManyCharacters0123456789"];
    for (NSUInteger step=0;step<4;step++) {
        NSUInteger position=token.location+[@[@0,@9,@18,@35][step] unsignedIntegerValue];
        NSString *insert=@[@" ",@"\n",@"\r\n",@"👩🏽‍💻"][step];
        NSDictionary *context=@{@"sequence":@"wrapped token edit",@"font":font,@"step":@(step)};
        system->view.selectedRange=NSMakeRange(position,0);
        [system->view insertText:insert replacementRange:system->view.selectedRange];
        NSMutableString *expected=[NSMutableString stringWithString:source];
        [expected insertString:insert atIndex:position];
        Check([system->view.string isEqual:expected] && NSEqualRanges(system->view.selectedRange,NSMakeRange(position+insert.length,0)),
            @"wrapped-token insertion preserves source and insertion",context);
        Record(system,font,@"wrapped token after insertion");
        [system->view deleteBackward:nil];
        Check([system->view.string isEqual:source] && NSEqualRanges(system->view.selectedRange,NSMakeRange(position,0)),
            @"Backspace restores the token and insertion across a separator or composed emoji",context);
        Record(system,font,@"wrapped token after Backspace");
    }
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2) return 2;
        [NSApplication sharedApplication];
        Examples=[NSMutableArray array]; FailureKinds=[NSMutableDictionary dictionary];
        FirstFailure=[NSMutableDictionary dictionary]; Transcript=[NSMutableArray array];
        for(NSString *font in @[@"Menlo-Regular",@"Helvetica"]) {
            EmptyAndRestore(font); SeparatorsAndLongToken(font);
        }
        Check(CompletedParagraphs>0,@"observer exercised paragraph completion",@{});
        NSDictionary *result=@{@"checks":@(Checks),@"failures":@(Failures),@"failureKinds":FailureKinds,@"examples":Examples,
            @"completedParagraphCallbacks":@(CompletedParagraphs),@"retainedAnalysisCallbacks":@(RetainedAnalysis),
            @"emptyStates":@(EmptyStates),@"separatorCommands":@(SeparatorMoves),@"snapshots":@(Edits),
            @"pointSamples":@(HitPairs),@"blankRemainderClicks":@(GapHits),@"selectionCommands":@(NativeSelections),
            @"transcript":Transcript};
        [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        fprintf(stderr,"%lu checks; %lu failures; %lu completed paragraphs; %lu retained analysis callbacks\n",
            (unsigned long)Checks,(unsigned long)Failures,(unsigned long)CompletedParagraphs,(unsigned long)RetainedAnalysis);
    }
    return 0;
}
