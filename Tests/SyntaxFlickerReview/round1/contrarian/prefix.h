#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#import "LinkingEditor.h"
static BOOL CRWait(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}
static NSDictionary *CRDraw(LinkingEditor *editor, NSUInteger index, NSRange *effective) {
    NSLayoutManager *layout = [editor layoutManager];
    NSRange range = NSMakeRange(index, 1);
    NSDictionary *attributes = [layout temporaryAttributesAtCharacterIndex:index effectiveRange:&range];
    NSDictionary *result = [[layout delegate] layoutManager:layout shouldUseTemporaryAttributes:attributes
        forDrawingToScreen:YES atCharacterIndex:index effectiveRange:&range];
    if (effective) *effective = range;
    return result;
}
static NSColor *CRColor(LinkingEditor *editor, NSUInteger index) { return CRDraw(editor,index,NULL)[NSForegroundColorAttributeName]; }
