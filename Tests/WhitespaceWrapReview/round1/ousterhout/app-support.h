#import <Cocoa/Cocoa.h>
#import "LinkingEditor.h"

@interface WrapStorageObserver : NSObject { @public NSUInteger edits; NSUInteger characterEdits; }
- (void)observe:(NSNotification *)notification;
@end
@implementation WrapStorageObserver
- (void)observe:(NSNotification *)notification {
    edits++;
    if ([(NSTextStorage *)notification.object editedMask] & NSTextStorageEditedCharacters) characterEdits++;
}
@end

static NSUInteger SpaceLineCount(NSTextView *editor) {
    NSLayoutManager *layout = editor.layoutManager;
    [layout ensureLayoutForTextContainer:editor.textContainer];
    __block NSUInteger count = 0;
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *container, NSRange range, BOOL *stop) { count++; }];
    return count;
}
