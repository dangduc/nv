#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "PreviewController.h"
#import "NVMarkupRenderer.h"

static NSUInteger ProviderInitializations, ProviderDeallocations, ProviderFirstCloses;
static NSUInteger RenderSubmissions, TimerEntries, ScrollJavaScriptCalls;
static void MinimalSwap(Class cls, SEL a, SEL b) {
    method_exchangeImplementations(class_getInstanceMethod(cls, a), class_getInstanceMethod(cls, b));
}
@interface PreviewController (NVMinimalRoundThree)
- (id)nv_minimal_init;
- (void)nv_minimal_close;
- (void)nv_minimal_dealloc;
- (void)nv_minimal_captureDisplayState:(NSTimer *)timer;
@end
@implementation PreviewController (NVMinimalRoundThree)
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
    MinimalSwap(self, @selector(init), @selector(nv_minimal_init));
    MinimalSwap(self, @selector(close), @selector(nv_minimal_close));
    MinimalSwap(self, @selector(dealloc), @selector(nv_minimal_dealloc));
    MinimalSwap(self, @selector(captureDisplayState:), @selector(nv_minimal_captureDisplayState:));
}
- (id)nv_minimal_init { ProviderInitializations++; return [self nv_minimal_init]; }
- (void)nv_minimal_close {
    if (![[self valueForKey:@"closed"] boolValue]) ProviderFirstCloses++;
    [self nv_minimal_close];
}
- (void)nv_minimal_dealloc { ProviderDeallocations++; [self nv_minimal_dealloc]; }
- (void)nv_minimal_captureDisplayState:(NSTimer *)timer {
    TimerEntries++;
    // Optional fault injection proves the hidden-poll assertion observes an
    // actual WebKit submission. The production method still runs unchanged.
    if (getenv("NV_MINIMAL_FORCE_HIDDEN_POLL") && [[self webView] isHiddenOrHasHiddenAncestor])
        [[self webView] evaluateJavaScript:@"[window.scrollX,window.scrollY]" completionHandler:nil];
    [self nv_minimal_captureDisplayState:timer];
}
@end
@interface NVMarkupRenderer (NVMinimalRoundThree)
- (NSOperation *)nv_minimal_renderSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier completion:(NVMarkupRenderCompletion)completion;
@end
@implementation NVMarkupRenderer (NVMinimalRoundThree)
+ (void)load {
    if (getenv("NV_WINDOW_TEST_DIRECTORY"))
        MinimalSwap(self, @selector(renderSnapshot:viewerIdentifier:completion:), @selector(nv_minimal_renderSnapshot:viewerIdentifier:completion:));
}
- (NSOperation *)nv_minimal_renderSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier completion:(NVMarkupRenderCompletion)completion {
    RenderSubmissions++;
    return [self nv_minimal_renderSnapshot:snapshot viewerIdentifier:identifier completion:completion];
}
@end
@interface WKWebView (NVMinimalRoundThree)
- (void)nv_minimal_evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion;
@end
@implementation WKWebView (NVMinimalRoundThree)
+ (void)load {
    if (getenv("NV_WINDOW_TEST_DIRECTORY"))
        MinimalSwap(self, @selector(evaluateJavaScript:completionHandler:), @selector(nv_minimal_evaluateJavaScript:completionHandler:));
}
- (void)nv_minimal_evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {
    if ([script isEqualToString:@"[window.scrollX,window.scrollY]"]) ScrollJavaScriptCalls++;
    [self nv_minimal_evaluateJavaScript:script completionHandler:completion];
}
@end
