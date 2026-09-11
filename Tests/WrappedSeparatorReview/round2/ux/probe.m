// The runner supplies only the round-one Cocoa setup, native reference, and row helpers.
#include "round1-ux-helper.h"
static NSUInteger EditCases,NativeGeometryComparisons,FreshGeometryComparisons,TrailingTransitions;
static NSMutableArray *EditRecords;

static void PrepareNativeTyping(SourceView *native) {
    NSParagraphStyle *style=[native->view.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    native->view.defaultParagraphStyle=style;
    NSMutableDictionary *attrs=[NSMutableDictionary dictionaryWithDictionary:native->view.typingAttributes];
    attrs[NSParagraphStyleAttributeName]=style;native->view.typingAttributes=attrs;
}
static void ObserveEdit(SourceView *system,SourceView *native,NSString *font,NSString *expected,NSRange selection,BOOL trailing,NSDictionary *context) {
    Check([system->view.string isEqual:expected],@"production edit has the exact intended source",context);
    Check([native->view.string isEqual:expected],@"native reference edit has the exact intended source",context);
    Check(NSEqualRanges(system->view.selectedRange,selection),@"production edit leaves the intended logical selection",context);
    Check(NSEqualRanges(system->view.selectedRange,native->view.selectedRange),@"edit selection agrees with native word wrapping",context);
    Check(system->view.selectionAffinity==native->view.selectionAffinity,@"edit caret affinity agrees with native word wrapping",context);
    SourceView *fresh=[[[SourceView alloc] initWithText:expected font:font width:system->view.frame.size.width] autorelease];
    [fresh->view.textStorage setAttributedString:system->view.textStorage];
    NSArray *snapshot=[system snapshot];
    Check([snapshot isEqual:[fresh snapshot]],@"edited layout and insertion positions match a fresh production layout",context);
    FreshGeometryComparisons++;
    if(trailing) {
        NSUInteger space=expected.length-1;
        NSUInteger glyph=[system->view.layoutManager glyphIndexForCharacterAtIndex:space];
        Check(!([system->view.layoutManager propertyForGlyphAtIndex:glyph]&NSGlyphPropertyElastic),@"deleting the following word restores literal trailing-space advancement",context);
        Check(Y(system,space)>Y(system,space-1),@"trailing space occupies the following visual line",context);
        NSDictionary *last=snapshot.lastObject;
        NSArray *points=last[@"insertions"];
        CGFloat advance=[@" " sizeWithAttributes:@{NSFontAttributeName:[NSFont fontWithName:font size:18]}].width;
        CGFloat actual=[points.lastObject[1] doubleValue]-[points.firstObject[1] doubleValue];
        Check(fabs(actual-advance)<0.05,@"the trailing-space caret advances by the font's ordinary space width",context);
    } else {
        Check([snapshot isEqual:[native snapshot]],@"post-edit line and insertion positions agree with native word wrapping",context);
        NativeGeometryComparisons++;
    }
    [EditRecords addObject:@{@"case":context,@"source":expected,@"selection":NSStringFromRange(system->view.selectedRange),
        @"affinity":@(system->view.selectionAffinity),@"literalTrailingSpace":@(trailing),@"lineRanges":Boundaries(system)}];
}
static void RunEdits(NSString *font) {
    NSString *source=@"abcdefghij nextword";
    CGFloat width=[@"abcdefghij" sizeWithAttributes:@{NSFontAttributeName:[NSFont fontWithName:font size:18]}].width+10.25;
    NSArray *cases=@[
        @{@"name":@"Backspace on collapsed separator",@"command":@"deleteBackward:",@"selection":@"{11, 0}",@"erase":@"{10, 1}"},
        @{@"name":@"Forward Delete on collapsed separator",@"command":@"deleteForward:",@"selection":@"{10, 0}",@"erase":@"{10, 1}"},
        @{@"name":@"Backspace before collapsed separator",@"command":@"deleteBackward:",@"selection":@"{10, 0}",@"erase":@"{9, 1}"},
        @{@"name":@"Forward Delete at wrapped word start",@"command":@"deleteForward:",@"selection":@"{11, 0}",@"erase":@"{11, 1}"},
        @{@"name":@"Delete selection spanning the separator",@"command":@"deleteBackward:",@"selection":@"{9, 3}",@"erase":@"{9, 3}"},
        @{@"name":@"Delete following word then type again",@"command":@"deleteWordBackward:",@"selection":@"{19, 0}",@"erase":@"{11, 8}",@"trailing":@YES},
        @{@"name":@"Delete previous word from wrapped word start",@"command":@"deleteWordBackward:",@"selection":@"{11, 0}",@"erase":@"{0, 11}"},
        @{@"name":@"Replace selection across soft wrap",@"selection":@"{9, 3}",@"erase":@"{9, 3}",@"replacement":@"J K"},
        @{@"name":@"Replace separator and first letter with Unicode",@"selection":@"{10, 2}",@"erase":@"{10, 2}",@"replacement":@" 雪"}];
    for(NSDictionary *fixture in cases) {
        @autoreleasepool {
            SourceView *system=[[[SourceView alloc] initWithText:source font:font width:width] autorelease];
            SourceView *native=NativeReference(source,font,width);PrepareNativeTyping(native);[system snapshot];
            NSDictionary *context=@{@"font":font,@"width":@(width),@"operation":fixture[@"name"]};
            Check(Y(system,10)==Y(system,9)&&Y(system,11)>Y(system,10),@"every edit begins at an actually collapsed separator",context);
            NSRange selected=NSRangeFromString(fixture[@"selection"]),erase=NSRangeFromString(fixture[@"erase"]);
            [system->view setSelectedRange:selected affinity:NSSelectionAffinityDownstream stillSelecting:NO];
            [native->view setSelectedRange:selected affinity:NSSelectionAffinityDownstream stillSelecting:NO];
            NSString *replacement=fixture[@"replacement"]?:@"";
            NSMutableString *expected=[NSMutableString stringWithString:source];[expected replaceCharactersInRange:erase withString:replacement];
            if(fixture[@"command"]) {
                SEL selector=NSSelectorFromString(fixture[@"command"]);
                [system->view performSelector:selector withObject:nil];[native->view performSelector:selector withObject:nil];
            } else {
                [system->view insertText:replacement replacementRange:selected];[native->view insertText:replacement replacementRange:selected];
            }
            BOOL trailing=[fixture[@"trailing"] boolValue];
            ObserveEdit(system,native,font,expected,NSMakeRange(erase.location+replacement.length,0),trailing,context);EditCases++;
            if(trailing) {
                [system->view insertText:@"newword" replacementRange:system->view.selectedRange];
                [native->view insertText:@"newword" replacementRange:native->view.selectedRange];
                [expected appendString:@"newword"];
                ObserveEdit(system,native,font,expected,NSMakeRange(expected.length,0),NO,@{@"font":font,@"operation":@"trailing space becomes separator after insertion"});
                Check(Y(system,10)==Y(system,9)&&Y(system,11)>Y(system,10),@"typing after the literal trailing space collapses the separator again",context);
                TrailingTransitions++;
            }
        }
    }
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;[NSApplication sharedApplication];
        Examples=[NSMutableArray array];FailureKinds=[NSMutableDictionary dictionary];FirstFailure=[NSMutableDictionary dictionary];EditRecords=[NSMutableArray array];
        for(NSString *font in @[@"Menlo-Regular",@"Helvetica"])RunEdits(font);
        NSDictionary *result=@{@"checks":@(Checks),@"failures":@(Failures),@"failureKinds":FailureKinds,@"firstFailure":FirstFailure,
            @"editCases":@(EditCases),@"nativeGeometryComparisons":@(NativeGeometryComparisons),@"freshGeometryComparisons":@(FreshGeometryComparisons),
            @"trailingToSeparatorTransitions":@(TrailingTransitions),@"records":EditRecords};
        [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:@(argv[1]) atomically:YES];
        fprintf(stderr,"%lu checks; %lu failures\n",(unsigned long)Checks,(unsigned long)Failures);
    }return 0;
}
