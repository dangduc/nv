#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#import "LinkingEditor.h"
static BOOL CQWait(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}
static NSDictionary *CQDraw(LinkingEditor *editor, NSUInteger index) {
    NSLayoutManager *layout = [editor layoutManager];
    NSRange range;
    NSDictionary *attributes = [layout temporaryAttributesAtCharacterIndex:index effectiveRange:&range];
    return [[layout delegate] layoutManager:layout shouldUseTemporaryAttributes:attributes
        forDrawingToScreen:YES atCharacterIndex:index effectiveRange:&range];
}
static NSIndexSet *CQBackgrounds(LinkingEditor *editor) {
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    for (NSUInteger index = 0; index < [[editor string] length]; index++)
        if (CQDraw(editor, index)[NSBackgroundColorAttributeName]) [result addIndex:index];
    return result;
}
static NSIndexSet *CQMatches(NSString *source, NSString *query) {
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    if (![query length]) return result;
    NSRange remaining = NSMakeRange(0, [source length]);
    while (remaining.length) {
        NSRange match = [source rangeOfString:query options:NSCaseInsensitiveSearch range:remaining];
        if (match.location == NSNotFound) break;
        [result addIndexesInRange:match];
        remaining = NSMakeRange(NSMaxRange(match), [source length] - NSMaxRange(match));
    }
    return result;
}
