#import <Cocoa/Cocoa.h>
#import "LinkingEditor.h"

static NSArray *NativeLineRecords(NSTextView *view) {
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForTextContainer:view.textContainer];
    NSMutableArray *records = [NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *container, NSRange glyphRange, BOOL *stop) {
            NSRange range = [layout characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
            [records addObject:@{@"location":@(range.location), @"length":@(range.length), @"y":@(rect.origin.y),
                @"width":@(used.size.width), @"text":[view.string substringWithRange:range]}];
        }];
    return records;
}
static NSDictionary *MarkerPoint(NSTextView *view, NSUInteger index) {
    NSLayoutManager *layout = view.layoutManager;
    NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:index];
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    NSPoint location = [layout locationForGlyphAtIndex:glyph];
    return @{@"x":@(location.x), @"y":@(fragment.origin.y)};
}

static NSDictionary *NativeCaretPoint(NSTextView *view) {
    NSRect screen = [view firstRectForCharacterRange:view.selectedRange actualRange:NULL];
    NSRect local = [view convertRect:[view.window convertRectFromScreen:screen] fromView:nil];
    return @{@"x":@(local.origin.x),@"y":@(local.origin.y)};
}

static void NavigationKey(NSTextView *view,unichar character,unsigned short keyCode,NSEventModifierFlags flags) {
    NSString *characters=[NSString stringWithCharacters:&character length:1];
    NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil
        characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:keyCode];
    [NSApp sendEvent:event];
}
static BOOL CaretInHorizontalBounds(NSTextView *view,NSDictionary *point) {
    double x=[point[@"x"] doubleValue];
    return isfinite(x) && x >= view.textContainerInset.width-1 && x <= NSWidth(view.bounds)-view.textContainerInset.width+2;
}
static BOOL MovesForward(NSDictionary *before,NSDictionary *after) {
    double dy=[after[@"y"] doubleValue]-[before[@"y"] doubleValue];
    return dy >= -0.01 && (fabs(dy)>0.01 || [after[@"x"] doubleValue]+0.01 >= [before[@"x"] doubleValue]);
}
