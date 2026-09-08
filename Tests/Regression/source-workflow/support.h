#import "AppController.h"
#import "PreviewController.h"
#import "NVMarkupRenderer.h"
#import "NVSourceHighlighter.h"
#import "SyncResponseFetcher.h"
#import "NotationPrefs.h"
#import <math.h>

static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return condition();
}
static NSMenuItem *SourceItem(NSString *identifier, SEL action) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:identifier action:action keyEquivalent:@""] autorelease];
    [item setRepresentedObject:identifier];
    return item;
}
static BOOL PreviewShows(AppController *browser, NSString *marker) {
    PreviewController *preview = [browser valueForKey:@"previewController"];
    if ([preview renderError]) return NO;
    return [browser isViewingNote] && ![preview loading] && [[preview renderedHTML] rangeOfString:marker].location != NSNotFound &&
        [[preview renderedHTML] length] > 0 && ![[preview webView] isHiddenOrHasHiddenAncestor];
}
static void ChangeMode(AppController *browser, BOOL preview) {
    NSSegmentedControl *mode = [browser valueForKey:@"bodyModeControl"];
    [mode setSelectedSegment:preview ? 1 : 0];
    [NSApp sendAction:[mode action] to:[mode target] from:mode];
}
static NSPoint SourceOrigin(AppController *browser) {
    NSScrollView *scroll = [browser valueForKey:@"textScrollView"];
    return [[scroll contentView] bounds].origin;
}
static id NativeJavaScript(WKWebView *view, NSString *script) {
    __block BOOL complete = NO;
    __block id output = nil;
    __block NSError *failure = nil;
    [view evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        output = [result retain]; failure = [error retain]; complete = YES;
    }];
    BOOL finished = Await(^BOOL { return complete; }, 5.0);
    if (!finished || failure) NSLog(@"Native preview inspection failed: %@", failure);
    [failure release];
    return finished ? [output autorelease] : nil;
}
static BOOL CaptureBrowser(NSWindow *window, NSString *path) {
    // View state can be ready before WindowServer presents its next frame.
    // Let native layout and the compositor finish before capturing the artifact.
    [[window contentView] layoutSubtreeIfNeeded];
    [window displayIfNeeded];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
    CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
    if (!image) return NO;
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
    NSData *data = [bitmap representationUsingType:NSPNGFileType properties:@{}];
    CGImageRelease(image);
    return [data writeToFile:path atomically:YES];
}
