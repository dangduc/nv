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

static NSMutableArray *Activations;
static BOOL CaptureOpenURL(id object, SEL selector, NSURL *url) { [Activations addObject:[url absoluteString] ?: @"nil"]; return YES; }
static void CaptureModernOpen(id object, SEL selector, NSArray *urls, NSURL *application, id config, id completion) {
    for (NSURL *url in urls) [Activations addObject:[url absoluteString] ?: @"nil"];
}
static BOOL CaptureLegacyOpen(id object, SEL selector, NSArray *urls, id bundle, NSUInteger options, id descriptor, id *identifiers) {
    for (NSURL *url in urls) [Activations addObject:[url absoluteString] ?: @"nil"]; return YES;
}
static void DescribeMenu(NSMenu *menu, NSString *label) {
    for (NSMenuItem *item in menu.itemArray)
        NSLog(@"MENU %@ title=%@ action=%@ target=%@ enabled=%d represented=%@", label, item.title, NSStringFromSelector(item.action), NSStringFromClass([item.target class]), item.enabled, item.representedObject);
}
static NSMenuItem *OpenItem(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) if ([item.title isEqual:@"Open Link"]) return item;
    return nil;
}

#import <dlfcn.h>
static BOOL HasAnalysis(void) { return dlsym(RTLD_DEFAULT, "NVSourceLinksAreCurrent") != NULL; }
static BOOL LinksCurrent(NSTextStorage *storage) {
    BOOL (*function)(NSTextStorage *) = dlsym(RTLD_DEFAULT, "NVSourceLinksAreCurrent");
    return function ? function(storage) : YES;
}
