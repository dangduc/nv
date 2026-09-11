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

static void TypingKey(NSTextView *view,unichar character,unsigned short keyCode,BOOL repeat) {
    NSString *characters=[NSString stringWithCharacters:&character length:1];
    NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil
        characters:characters charactersIgnoringModifiers:characters isARepeat:repeat keyCode:keyCode];
    [NSApp sendEvent:event];
}
static BOOL SamePoint(NSDictionary *a,NSDictionary *b) {
    return fabs([a[@"x"] doubleValue]-[b[@"x"] doubleValue])<0.02 && fabs([a[@"y"] doubleValue]-[b[@"y"] doubleValue])<0.02;
}
static void NativeMouseClick(NSTextView *view,NSUInteger index) {
    NSRect screen=[view firstRectForCharacterRange:NSMakeRange(index,0) actualRange:NULL];
    NSPoint window=[view.window convertPointFromScreen:NSMakePoint(NSMinX(screen)+0.1,NSMidY(screen))];
    NSTimeInterval stamp=NSProcessInfo.processInfo.systemUptime;
    NSEvent *down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:window modifierFlags:0 timestamp:stamp windowNumber:view.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSEvent *up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:window modifierFlags:0 timestamp:stamp+0.01 windowNumber:view.window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
    [NSApp postEvent:up atStart:YES];
    [NSApp sendEvent:down];
}
