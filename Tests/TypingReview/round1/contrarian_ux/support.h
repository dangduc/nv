#import "NVSourceAnalysis.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"

static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}

static NSUInteger LinkClicks;
static IMP OriginalClick;
static NSUInteger NativeActivations;
static void RecordNativeActivation(id editor, SEL selector, id url, NSUInteger index) {
    NativeActivations++;
}
static void RecordClick(id editor, SEL selector, id url, NSUInteger index) {
    LinkClicks++;
    ((void (*)(id, SEL, id, NSUInteger))OriginalClick)(editor, selector, url, index);
}

static NSEvent *MouseEvent(LinkingEditor *editor, NSEventType type, NSUInteger index) {
    NSLayoutManager *layout = editor.layoutManager;
    [layout ensureLayoutForTextContainer:editor.textContainer];
    NSRange glyphs = [layout glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL];
    NSRect rect = [layout boundingRectForGlyphRange:glyphs inTextContainer:editor.textContainer];
    NSPoint point = NSMakePoint(NSMinX(rect) + 1 + editor.textContainerOrigin.x,
                               NSMidY(rect) + editor.textContainerOrigin.y);
    point = [editor convertPoint:point toView:nil];
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0
        timestamp:[NSProcessInfo processInfo].systemUptime windowNumber:editor.window.windowNumber
        context:nil eventNumber:1 clickCount:1 pressure:1];
}
static void Click(LinkingEditor *editor, NSUInteger index) {
    NSEvent *up = MouseEvent(editor, NSLeftMouseUp, index);
    NSEvent *down = MouseEvent(editor, NSLeftMouseDown, index);
    [NSApp postEvent:up atStart:YES];
    [NSApp sendEvent:down];
}
