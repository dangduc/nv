#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "production-space-delegate.h"

static BOOL NegativeControl;

static NSDictionary *Snapshot(NSString *source, NSParagraphStyle *style, CGFloat width, BOOL refined) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source attributes:@{
        NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18],
        NSParagraphStyleAttributeName:style}];
    NSLayoutManager *layout = [[NSLayoutManager alloc] init];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(width, 1000000)];
    SpaceDelegate *delegate = [[SpaceDelegate alloc] init];
    [storage addLayoutManager:layout];
    [layout addTextContainer:container];
    layout.delegate = delegate;
    if (refined) layout.typesetter = [[[NVSourceTypesetter alloc] init] autorelease];
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *lines = [NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *textContainer, NSRange glyphs, BOOL *stop) {
        NSRange characters = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
        NSMutableArray *points = [NSMutableArray array];
        for (NSUInteger i=characters.location; i<NSMaxRange(characters); i++) {
            NSUInteger g=[layout glyphIndexForCharacterAtIndex:i];
            NSPoint p=[layout locationForGlyphAtIndex:g];
            [points addObject:@[@(p.x+rect.origin.x), @(p.y+rect.origin.y)]];
        }
        [lines addObject:@{@"start":@(characters.location), @"length":@(characters.length),
            @"text":[source substringWithRange:characters], @"rect":NSStringFromRect(rect),
            @"used":NSStringFromRect(used), @"points":points}];
    }];
    NSDictionary *result = [[@{@"lines":lines, @"unchanged":@([storage.string isEqual:source])} retain] autorelease];
    layout.delegate=nil;
    [delegate release];
    [container release];
    [layout release];
    [storage release];
    return result;
}

static void NativeActions(NSString *output) {
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,160,600)];
    view.richText=NO;
    view.usesRuler=NO;
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode=NSLineBreakByCharWrapping;
    NSDictionary *attrs=@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18], NSParagraphStyleAttributeName:style};
    [view.textStorage setAttributedString:[[[NSAttributedString alloc] initWithString:@"שלום עולם שלום עולם שלום עולם" attributes:attrs] autorelease]];
    view.selectedRange=NSMakeRange(0,view.string.length);
    [view makeBaseWritingDirectionRightToLeft:nil];
    NSParagraphStyle *rtl=[view.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"richText":@(view.richText),
        @"rtlDirection":@(rtl.baseWritingDirection), @"rtlAlignment":@(rtl.alignment),
        @"rtlLineBreakMode":@(rtl.lineBreakMode), @"source":view.string}];
    [view alignJustified:nil];
    NSParagraphStyle *justified=[view.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    result[@"justifiedAlignment"]=@(justified.alignment);
    result[@"justifiedLineBreakMode"]=@(justified.lineBreakMode);
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:output atomically:YES];
    [view release];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc<2 || argc>3) return 2;
        NegativeControl=argc==3;
        [NSApplication sharedApplication];
        NativeActions([[NSString stringWithUTF8String:argv[1]] stringByAppendingString:@".actions.json"]);
        NSMutableArray *results=[NSMutableArray array];
        for (NSNumber *width in @[@160, @240, @320])
        for (NSString *geometry in @[@"plain", @"positive-tail", @"negative-tail", @"first-indent", @"hanging-indent", @"tabs", @"explicit-rtl"])
        for (NSNumber *alignment in @[@(NSTextAlignmentNatural), @(NSTextAlignmentLeft), @(NSTextAlignmentRight), @(NSTextAlignmentCenter), @(NSTextAlignmentJustified)])
        for (NSString *source in @[@"alpha beta gamma delta epsilon zeta eta theta",
            @"שלום עולם שלום עולם שלום עולם שלום עולם", @"alpha\tbeta gamma delta epsilon zeta eta theta"]) {
            @autoreleasepool {
                NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
                style.lineBreakMode=NSLineBreakByCharWrapping;
                style.alignment=alignment.integerValue;
                if ([geometry isEqual:@"positive-tail"]) style.tailIndent=width.doubleValue-30;
                if ([geometry isEqual:@"negative-tail"]) style.tailIndent=-30;
                if ([geometry isEqual:@"first-indent"]) style.firstLineHeadIndent=30;
                if ([geometry isEqual:@"hanging-indent"]) style.headIndent=30;
                if ([geometry isEqual:@"tabs"]) { style.tabStops=@[]; style.defaultTabInterval=40; }
                if ([geometry isEqual:@"explicit-rtl"]) style.baseWritingDirection=NSWritingDirectionRightToLeft;
                NSDictionary *candidate=Snapshot(source, style, width.doubleValue, !NegativeControl);
                NSDictionary *previous=Snapshot(source, style, width.doubleValue, NO);
                style.lineBreakMode=NSLineBreakByWordWrapping;
                NSDictionary *reference=Snapshot(source, style, width.doubleValue, NO);
                [results addObject:@{@"source":source, @"width":width, @"geometry":geometry,
                    @"alignment":alignment, @"candidate":candidate, @"reference":reference, @"previous":previous}];
            }
        }
        NSData *json=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
        return [json writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}
