#import <Cocoa/Cocoa.h>
#import "LinkingEditor.h"

static NSUInteger WrapLineCount(NSTextView *view) {
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForTextContainer:view.textContainer];
    __block NSUInteger count = 0;
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *container, NSRange range, BOOL *stop) { count++; }];
    return count;
}
static NSRect WrapCaret(NSTextView *view) {
    NSRect rect = [view firstRectForCharacterRange:view.selectedRange actualRange:NULL];
    return [view convertRect:[view.window convertRectFromScreen:rect] fromView:nil];
}
