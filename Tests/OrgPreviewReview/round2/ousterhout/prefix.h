#import "PreviewController.h"
#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
#import <math.h>

static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}
static BOOL Ready(PreviewController *preview, NSString *identifier) {
    return preview && ![preview loading] && ![preview renderError] && [[preview renderedHTML] length] &&
        [[preview viewerIdentifier] isEqual:identifier] && ![[preview webView] isHiddenOrHasHiddenAncestor];
}
static NSMenuItem *ViewerItem(NSString *identifier) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:identifier action:@selector(selectPreviewMode:) keyEquivalent:@""] autorelease];
    [item setRepresentedObject:identifier]; return item;
}
static void CollectViewerItems(NSMenu *menu, NSMutableArray *items) {
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == @selector(selectPreviewMode:)) [items addObject:item];
        if ([item submenu]) CollectViewerItems([item submenu], items);
    }
}
static id DOM(WKWebView *view, NSString *script) {
    __block BOOL done = NO;
    __block id result = nil;
    [view evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
        if (error) NSLog(@"DOM ERROR: %@", error);
        result = [value retain]; done = YES;
    }];
    return Await(^BOOL { return done; }, 5) ? [result autorelease] : nil;
}
