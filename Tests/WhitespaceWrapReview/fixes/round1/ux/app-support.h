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

static void SendSpace(NSTextView *view, BOOL repeat) {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil
        characters:@" " charactersIgnoringModifiers:@" " isARepeat:repeat keyCode:49];
    [NSApp sendEvent:event];
}
