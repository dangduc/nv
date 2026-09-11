#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "production-space-delegate.h"

static NSUInteger Checks, Failures, HitPairs, GapHits, Edits, Fits, LongSplits, NativeSelections;
static NSMutableArray *Examples;
static NSMutableDictionary *FailureKinds;
static NSMutableDictionary *FirstFailure;
static BOOL NegativeControl;
static void Check(BOOL condition, NSString *kind, NSDictionary *context) {
    Checks++;
    if (!condition) {
        Failures++;
        FailureKinds[kind]=@([FailureKinds[kind] unsignedIntegerValue]+1);
        if (!FirstFailure[kind]) FirstFailure[kind]=context;
        if (Examples.count < 24) [Examples addObject:@{@"kind":kind, @"context":context}];
    }
}

@interface SourceView : NSObject {
@public
    NSTextView *view;
    SpaceDelegate *delegate;
}
- (id)initWithText:(NSString *)source font:(NSString *)font width:(CGFloat)width;
- (NSArray *)snapshot;
@end
@implementation SourceView
- (id)initWithText:(NSString *)source font:(NSString *)font width:(CGFloat)width {
    if ((self = [super init])) {
        view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, width, 100000)];
        view.richText = NO;
        view.horizontallyResizable = NO;
        view.verticallyResizable = YES;
        view.textContainerInset = NSZeroSize;
        view.textContainer.widthTracksTextView = YES;
        delegate = [[SpaceDelegate alloc] init];
        view.layoutManager.delegate = delegate;
        if (!NegativeControl) view.layoutManager.typesetter = [[[NVSourceTypesetter alloc] init] autorelease];
        NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
        style.lineBreakMode = NSLineBreakByCharWrapping;
        NSDictionary *attrs = @{NSFontAttributeName:[NSFont fontWithName:font size:18], NSParagraphStyleAttributeName:style};
        view.defaultParagraphStyle = style;
        view.typingAttributes = attrs;
        [view.textStorage setAttributedString:[[[NSAttributedString alloc] initWithString:source attributes:attrs] autorelease]];
    }
    return self;
}
- (NSArray *)snapshot {
    NSLayoutManager *lm = view.layoutManager;
    [lm ensureLayoutForTextContainer:view.textContainer];
    NSMutableArray *rows = [NSMutableArray array];
    [lm enumerateLineFragmentsForGlyphRange:NSMakeRange(0, lm.numberOfGlyphs) usingBlock:
        ^(NSRect rect, NSRect used, NSTextContainer *container, NSRange glyphs, BOOL *stop) {
        NSRange chars = [lm characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
        CGFloat *positions = calloc(view.string.length + 1, sizeof(CGFloat));
        NSUInteger *indexes = calloc(view.string.length + 1, sizeof(NSUInteger));
        NSUInteger count = [lm getLineFragmentInsertionPointsForCharacterAtIndex:chars.location alternatePositions:NO
            inDisplayOrder:YES positions:positions characterIndexes:indexes];
        NSMutableArray *insertions = [NSMutableArray array];
        for (NSUInteger i=0; i<count; i++) [insertions addObject:@[@(indexes[i]), @(positions[i])]];
        free(positions); free(indexes);
        [rows addObject:@{@"start":@(chars.location), @"length":@(chars.length), @"rect":NSStringFromRect(rect),
            @"used":NSStringFromRect(used), @"insertions":insertions}];
    }];
    return rows;
}
- (void)dealloc { view.layoutManager.delegate=nil; [view release]; [delegate release]; [super dealloc]; }
@end

static void Interaction(SourceView *system, NSDictionary *context) {
    NSTextView *view = system->view;
    NSLayoutManager *lm = view.layoutManager;
    NSArray *rows = [system snapshot];
    for (NSDictionary *row in rows) {
        NSRect rect = NSRectFromString(row[@"rect"]);
        Check(fabs(rect.size.width-view.textContainer.size.width)<0.01,
            @"restored line rectangle retains full source width", context);
        NSArray *points = row[@"insertions"];
        for (NSUInteger p=0; p+1<points.count; p++) {
            NSUInteger start = [points[p][0] unsignedIntegerValue], end = [points[p+1][0] unsignedIntegerValue];
            CGFloat x = [points[p][1] doubleValue], next = [points[p+1][1] doubleValue];
            if (end <= start || next-x < 0.1) continue;
            if ([[NSCharacterSet newlineCharacterSet] characterIsMember:[view.string characterAtIndex:start]]) continue;
            for (NSNumber *part in @[@0.25, @0.75]) {
                NSPoint target=NSMakePoint(rect.origin.x+x+(next-x)*part.doubleValue, NSMidY(rect));
                CGFloat fraction=0;
                NSUInteger hit=[lm characterIndexForPoint:target inTextContainer:view.textContainer
                    fractionOfDistanceBetweenInsertionPoints:&fraction];
                NSUInteger insertion=[view characterIndexForInsertionAtPoint:target];
                NSUInteger expected=part.doubleValue<0.5 ? start : end;
                NSMutableDictionary *e=[NSMutableDictionary dictionaryWithDictionary:context];
                [e addEntriesFromDictionary:@{@"start":@(start), @"end":@(end), @"point":NSStringFromPoint(target),
                    @"hit":@(hit), @"insertion":@(insertion), @"expected":@(expected), @"fraction":@(fraction), @"row":row}];
                Check(hit==start, @"character hit within insertion interval", e);
                Check(insertion==expected, @"mouse insertion chooses nearest boundary", e);
                HitPairs++;
            }
            if (end==start+1 && [view.string characterAtIndex:start]!='\t') {
                NSRange chosen=NSMakeRange(start, 1);
                NSUInteger count=0;
                NSRectArray selection=[lm rectArrayForCharacterRange:chosen withinSelectedCharacterRange:chosen
                    inTextContainer:view.textContainer rectCount:&count];
                NSPoint midpoint=NSMakePoint(rect.origin.x+(x+next)*0.5, NSMidY(rect));
                BOOL contains=NO;
                for (NSUInteger i=0;i<count;i++) if (NSPointInRect(midpoint, NSInsetRect(selection[i], -0.1, -0.1))) contains=YES;
                Check(contains, @"single-character selection covers its insertion interval", context);
            }
            if (end==start+1 && [view.string characterAtIndex:start]<128) {
                view.selectedRange=NSMakeRange(start,0);
                [view moveRight:nil];
                Check(NSEqualRanges(view.selectedRange,NSMakeRange(end,0)), @"native Right crosses character boundary", context);
                [view moveLeft:nil];
                Check(NSEqualRanges(view.selectedRange,NSMakeRange(start,0)), @"native Left returns to character boundary", context);
                [view moveRightAndModifySelection:nil];
                Check(NSEqualRanges(view.selectedRange,NSMakeRange(start,1)), @"native Shift-Right selects the source character", context);
                NativeSelections+=3;
            }
        }
        if (points.count) {
            CGFloat lastX=[points.lastObject[1] doubleValue]+rect.origin.x;
            NSUInteger lastIndex=[points.lastObject[0] unsignedIntegerValue];
            NSUInteger start=[row[@"start"] unsignedIntegerValue], end=start+[row[@"length"] unsignedIntegerValue];
            BOOL soft=end<view.string.length && ![[NSCharacterSet newlineCharacterSet] characterIsMember:[view.string characterAtIndex:end-1]];
            // This oracle concerns moved whole words, not a split inside an oversized token or ligature.
            BOOL boundary=[[NSCharacterSet characterSetWithCharactersInString:@" \t/-"] characterIsMember:[view.string characterAtIndex:end-1]];
            if (soft && boundary && NSMaxX(rect)-lastX>8) {
                NSPoint gap=NSMakePoint((lastX+NSMaxX(rect))*0.5, NSMidY(rect));
                NSUInteger hit=[view characterIndexForInsertionAtPoint:gap];
                NSMutableDictionary *e=[NSMutableDictionary dictionaryWithDictionary:context];
                [e addEntriesFromDictionary:@{@"hit":@(hit), @"expected":@(lastIndex), @"point":NSStringFromPoint(gap), @"row":row}];
                Check(hit==lastIndex, @"word-wrap blank remainder targets visual line end", e);
                GapHits++;
            }
        }
    }
}

static void Fresh(SourceView *system, NSString *font, NSDictionary *context) {
    NSArray *before = [system snapshot];
    SourceView *fresh=[[[SourceView alloc] initWithText:system->view.string font:font width:system->view.frame.size.width] autorelease];
    [fresh->view.textStorage setAttributedString:system->view.textStorage];
    Check([before isEqual:[fresh snapshot]], @"incremental rows and caret positions equal fresh layout", context);
    Interaction(system, context);
    Edits++;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2 && argc != 3) return 2;
        [NSApplication sharedApplication];
        NegativeControl=argc==3;
        Examples = [NSMutableArray array];
        FailureKinds = [NSMutableDictionary dictionary];
        FirstFailure = [NSMutableDictionary dictionary];
        NSArray *fixtures=@[@"alpha beta gamma delta epsilon zeta eta theta",
            @"alpha       beta\t gamma   delta\n  epsilon zeta ",
            @"let reallyLongIdentifierWithManyCharacters0123456789 = source/path-with-hyphens/file.txt; done ",
            @"office affine efficient five AVATAR WAVE alpha beta gamma"];
        NSRegularExpression *words=[NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9]+" options:0 error:NULL];
        NSUInteger cases=0;
        for (NSString *font in @[@"Menlo-Regular", @"Helvetica", @"TimesNewRomanPSMT"])
        for (NSNumber *width in @[@73.9, @74.1, @95.9, @96.1, @119.9, @120.1, @159.9, @160.1, @239.9])
        for (NSString *source in fixtures) {
            @autoreleasepool {
                SourceView *system=[[[SourceView alloc] initWithText:source font:font width:width.doubleValue] autorelease];
                NSDictionary *context=@{@"font":font, @"width":width, @"source":source};
                Interaction(system, context);
                Check([system->view.string isEqual:source], @"interaction preserves exact source", context);
                for (NSTextCheckingResult *word in [words matchesInString:source options:0 range:NSMakeRange(0,source.length)]) {
                    NSString *token=[source substringWithRange:word.range];
                    CGFloat measured=[token sizeWithAttributes:@{NSFontAttributeName:[NSFont fontWithName:font size:18]}].width;
                    NSCharacterSet *spaces=[NSCharacterSet whitespaceAndNewlineCharacterSet];
                    BOOL standalone=(word.range.location==0 || [spaces characterIsMember:[source characterAtIndex:word.range.location-1]]) &&
                        (NSMaxRange(word.range)==source.length || [spaces characterIsMember:[source characterAtIndex:NSMaxRange(word.range)]]);
                    NSUInteger first=[system->view.layoutManager glyphIndexForCharacterAtIndex:word.range.location];
                    NSUInteger last=[system->view.layoutManager glyphIndexForCharacterAtIndex:NSMaxRange(word.range)-1];
                    NSRect a=[system->view.layoutManager lineFragmentRectForGlyphAtIndex:first effectiveRange:NULL];
                    NSRect b=[system->view.layoutManager lineFragmentRectForGlyphAtIndex:last effectiveRange:NULL];
                    if (standalone && measured < width.doubleValue-10.1) {
                        NSMutableDictionary *e=[NSMutableDictionary dictionaryWithDictionary:context]; e[@"word"]=token;
                        Check(a.origin.y==b.origin.y, @"fitting ordinary word remains whole", e); Fits++;
                    } else if (measured > width.doubleValue-10 && a.origin.y!=b.origin.y) LongSplits++;
                }
                cases++;
            }
        }
        for (NSString *font in @[@"Menlo-Regular", @"Helvetica"])
        for (NSNumber *width in @[@96.1, @160.1, @239.9]) {
            @autoreleasepool {
                NSString *source=@"alpha beta    gamma\tidentifierWithManyCharacters0123456789\n  delta epsilon";
                SourceView *system=[[[SourceView alloc] initWithText:source font:font width:width.doubleValue] autorelease];
                for (NSUInteger step=0;step<18;step++) {
                    NSDictionary *context=@{@"font":font, @"width":width, @"step":@(step)};
                    NSUInteger index=step%3==0 ? 6 : step%3==1 ? 14 : system->view.string.length-3;
                    NSMutableString *expected=[NSMutableString stringWithString:system->view.string];
                    NSString *insert=@[@" ", @"alpha ", @"\t", @"X", @"\n", @"👩🏽‍💻"][step%6];
                    [expected insertString:insert atIndex:index];
                    system->view.selectedRange=NSMakeRange(index,0);
                    [system->view insertText:insert replacementRange:system->view.selectedRange];
                    Check([system->view.string isEqual:expected], @"native insertion preserves exact intended source", context);
                    Check(NSEqualRanges(system->view.selectedRange,NSMakeRange(index+insert.length,0)), @"native insertion retains intended caret", context);
                    NSRange afterInsert=system->view.selectedRange;
                    Fresh(system,font,context);
                    system->view.selectedRange=afterInsert;
                    NSRange deletion=[expected rangeOfComposedCharacterSequenceAtIndex:afterInsert.location-1];
                    [expected deleteCharactersInRange:deletion];
                    [system->view deleteBackward:nil];
                    Check([system->view.string isEqual:expected], @"native Backspace preserves exact intended source", context);
                    Check(NSEqualRanges(system->view.selectedRange,NSMakeRange(deletion.location,0)), @"native Backspace retains intended caret", context);
                    Fresh(system,font,context);
                    [system->view setFrameSize:NSMakeSize(width.doubleValue+(step%2 ? -19.7 : 13.3),100000)];
                    Fresh(system,font,context);
                }
            }
        }
        NSDictionary *report=@{@"checks":@(Checks), @"failures":@(Failures), @"examples":Examples, @"failureKinds":FailureKinds,
            @"firstFailure":FirstFailure,
            @"initialCases":@(cases), @"hitPairs":@(HitPairs), @"blankRemainderHits":@(GapHits),
            @"editedSnapshots":@(Edits), @"fittingWords":@(Fits), @"longTokenSplits":@(LongSplits),
            @"nativeSelectionCommands":@(NativeSelections)};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        fprintf(stderr,"%lu checks; %lu observed assertion failures\n",(unsigned long)Checks,(unsigned long)Failures);
    }
    return 0;
}
