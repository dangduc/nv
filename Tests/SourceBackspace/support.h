#import "AppController.h"
#import "LinkingEditor.h"
#import "NVSourceHighlighter.h"

static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}
static NSDictionary *DrawingAttributes(LinkingEditor *editor, NSDictionary *attributes, NSUInteger index) {
    NSRange range = NSMakeRange(index, 1);
    return [[editor layoutManager] delegate] ? [[[editor layoutManager] delegate]
        layoutManager:[editor layoutManager] shouldUseTemporaryAttributes:attributes
        forDrawingToScreen:YES atCharacterIndex:index effectiveRange:&range] : attributes;
}
static BOOL HasBackground(LinkingEditor *editor) {
    NSLayoutManager *layout = [editor layoutManager];
    for (NSUInteger index = 0; index < [[editor string] length];) {
        NSRange range;
        if ([layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:index effectiveRange:&range]) return YES;
        index = MAX(index + 1, NSMaxRange(range));
    }
    return NO;
}
static BOOL HasCurrentCapture(LinkingEditor *editor, NSUInteger index, NSString *capture) {
    return NVSourceCapturesAreCurrent([editor layoutManager]) &&
        [[[[editor layoutManager] temporaryAttributesAtCharacterIndex:index effectiveRange:NULL]
            objectForKey:NVSourceCaptureAttributeName] isEqual:capture];
}
static NSBitmapImageRep *Render(LinkingEditor *editor) {
    [[editor layoutManager] ensureLayoutForTextContainer:[editor textContainer]];
    NSRect rect = [editor visibleRect];
    NSBitmapImageRep *bitmap = [editor bitmapImageRepForCachingDisplayInRect:rect];
    if (bitmap) [editor cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    return bitmap;
}
static void InstallBackground(LinkingEditor *editor) {
    [editor setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, [[editor string] length])]]];
}
