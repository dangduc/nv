// Test-only wrappers call the original production methods.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <float.h>
#import "AppController.h"
#import "GlobalPrefs.h"
#import "PreviewController.h"
#import "LinkingEditor.h"

static NSUInteger CountCalls, LayoutCalls, PreferenceCalls, ClosedPreferenceCalls, DisplayCalls, JSCalls, BrowserDeallocs;
static double CountMilliseconds;
static NSMutableSet *ClosedBrowserAddresses;
static BOOL HasViewControls;
static BOOL TraceJS;

static NSArray *ViewSettingSelectors(void) {
    return @[@"setShowTitleInTopSection:sender:", @"setShowTagsInTopSection:sender:",
        @"setShowBodyControlsInTopSection:sender:", @"setShowNotesList:sender:", @"setShowWordCount:"];
}
static void ResetCounters(void) {
    CountCalls = LayoutCalls = PreferenceCalls = ClosedPreferenceCalls = DisplayCalls = JSCalls = 0;
    CountMilliseconds = 0;
}
static void ReviewSwap(Class cls, SEL original, SEL replacement) {
    Method method = class_getInstanceMethod(cls, original);
    if (method) method_exchangeImplementations(method, class_getInstanceMethod(cls, replacement));
}

@interface PreviewController (NVLifecycleCounters)
- (void)nv_r2Display:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier;
@end
@implementation PreviewController (NVLifecycleCounters)
- (void)nv_r2Display:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier {
    DisplayCalls++; [self nv_r2Display:snapshot viewerIdentifier:identifier];
}
@end
@interface WKWebView (NVLifecycleCounters)
- (void)nv_r2JS:(NSString *)script completionHandler:(void (^)(id, NSError *))completion;
@end
@implementation WKWebView (NVLifecycleCounters)
- (void)nv_r2JS:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {
    if (TraceJS) NSLog(@"JS TRACE script=%@ stack=%@", script, [[NSThread callStackSymbols] subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, [[NSThread callStackSymbols] count]))]);
    JSCalls++; [self nv_r2JS:script completionHandler:completion];
}
@end
@interface AppController (NVLifecycleCounters)
- (void)nv_r2Count:(BOOL)count;
- (void)nv_r2Layout;
- (void)nv_r2Preference:(NSString *)selector;
- (void)nv_r2Dealloc;
@end
@implementation AppController (NVLifecycleCounters)
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
    ClosedBrowserAddresses = [[NSMutableSet alloc] init];
    HasViewControls = class_getInstanceMethod(self, @selector(layoutNoteHeader)) != NULL;
    ReviewSwap(self, @selector(updateWordCount:), @selector(nv_r2Count:));
    ReviewSwap(self, @selector(layoutNoteHeader), @selector(nv_r2Layout));
    ReviewSwap(self, @selector(settingChangedForSelectorString:), @selector(nv_r2Preference:));
    ReviewSwap(self, @selector(dealloc), @selector(nv_r2Dealloc));
    ReviewSwap([PreviewController class], @selector(displaySnapshot:viewerIdentifier:), @selector(nv_r2Display:viewerIdentifier:));
    ReviewSwap([WKWebView class], @selector(evaluateJavaScript:completionHandler:), @selector(nv_r2JS:completionHandler:));
}
- (void)nv_r2Count:(BOOL)count {
    double start = [NSDate timeIntervalSinceReferenceDate];
    [self nv_r2Count:count];
    if (count) { CountCalls++; CountMilliseconds += ([NSDate timeIntervalSinceReferenceDate] - start) * 1000; }
}
- (void)nv_r2Layout { LayoutCalls++; [self nv_r2Layout]; }
- (void)nv_r2Preference:(NSString *)selector {
    if ([ViewSettingSelectors() containsObject:selector]) {
        PreferenceCalls++;
        if ([ClosedBrowserAddresses containsObject:[NSValue valueWithPointer:self]]) ClosedPreferenceCalls++;
    }
    [self nv_r2Preference:selector];
}
- (void)nv_r2Dealloc { BrowserDeallocs++; [self nv_r2Dealloc]; }
@end
