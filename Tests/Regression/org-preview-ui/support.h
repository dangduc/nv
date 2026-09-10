#import "AppController.h"
#import "PreviewController.h"
#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
#import "NotationPrefs.h"
#import "NSString_NV.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <math.h>

static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}
static id NativeJavaScript(WKWebView *view, NSString *script) {
    __block BOOL complete = NO;
    __block id output = nil;
    [view evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) NSLog(@"Org preview DOM inspection failed: %@", error);
        output = [result retain]; complete = YES;
    }];
    return Await(^BOOL { return complete; }, 5.0) ? [output autorelease] : nil;
}
static BOOL Ready(PreviewController *preview, NSString *format) {
    return preview && ![preview loading] && ![preview renderError] && [[preview renderedHTML] length] &&
        [[preview viewerIdentifier] isEqual:format] && ![[preview webView] isHiddenOrHasHiddenAncestor];
}
static void CollectPreviewItems(NSMenu *menu, NSMutableArray *items) {
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == @selector(selectPreviewMode:) && [[item representedObject] isEqual:@"org"]) [items addObject:item];
        if ([item submenu]) CollectPreviewItems([item submenu], items);
    }
}
static NSMenuItem *PreviewItem(NSString *identifier) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:identifier action:@selector(selectPreviewMode:) keyEquivalent:@""] autorelease];
    [item setRepresentedObject:identifier]; return item;
}
static BOOL CapturePreview(NSWindow *window, NSString *path) {
    [[window contentView] layoutSubtreeIfNeeded]; [window displayIfNeeded];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
    CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, (CGWindowID)[window windowNumber], kCGWindowImageDefault);
    if (!image) return NO;
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease]; CGImageRelease(image);
    return [[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
}

// Only the export destination/sheet response is supplied by the fixture. The
// production saveHTML: method captures the rendered result and writes the file.
@interface NVOrgTestExportPanel : NSObject {
@public
    NSURL *destination;
    NSString *proposedName;
    void (^response)(NSModalResponse);
}
@end
@implementation NVOrgTestExportPanel
- (void)setAllowedFileTypes:(NSArray *)types { }
- (void)setNameFieldStringValue:(NSString *)name { [proposedName release]; proposedName = [name copy]; }
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion { response = [completion copy]; }
- (NSURL *)URL { return destination; }
- (void)dealloc { [destination release]; [proposedName release]; [response release]; [super dealloc]; }
@end
static NVOrgTestExportPanel *OrgExportPanel;
@interface NSSavePanel (OrgPreviewExportTest)
+ (id)nv_orgExportPanel;
@end
@implementation NSSavePanel (OrgPreviewExportTest)
+ (id)nv_orgExportPanel { return OrgExportPanel; }
@end

static WKWebView *OrgFindView;
static NSUInteger OrgFindCalls, OrgFindCompletions;
static BOOL OrgFindMatch;
@interface WKWebView (OrgPreviewFindTest)
- (void)nv_orgFindString:(NSString *)string withConfiguration:(WKFindConfiguration *)configuration completionHandler:(void (^)(WKFindResult *))completion API_AVAILABLE(macos(11.0));
@end
@implementation WKWebView (OrgPreviewFindTest)
- (void)nv_orgFindString:(NSString *)string withConfiguration:(WKFindConfiguration *)configuration completionHandler:(void (^)(WKFindResult *))completion {
    if (self != OrgFindView) { [self nv_orgFindString:string withConfiguration:configuration completionHandler:completion]; return; }
    OrgFindCalls++;
    [self nv_orgFindString:string withConfiguration:configuration completionHandler:^(WKFindResult *result) {
        OrgFindMatch = [result matchFound]; OrgFindCompletions++;
        if (completion) completion(result);
    }];
}
@end

// Hold only the exact-document DOM reply. Production code owns capture identity,
// cached offsets, revision ordering, completion and timeout handling.
static WKWebView *OrgCaptureReplyView;
static NSMutableArray *OrgCaptureReplies;
@interface WKWebView (OrgFragmentCaptureTest)
- (void)nv_orgCaptureJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion;
@end
@implementation WKWebView (OrgFragmentCaptureTest)
- (void)nv_orgCaptureJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {
    if (self == OrgCaptureReplyView && [script isEqual:@"[document.baseURI,window.scrollX,window.scrollY]"]) {
        [OrgCaptureReplies addObject:[[completion copy] autorelease]];
        return;
    }
    [self nv_orgCaptureJavaScript:script completionHandler:completion];
}
@end
