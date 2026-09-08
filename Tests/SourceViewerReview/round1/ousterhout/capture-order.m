#import <Cocoa/Cocoa.h>
#import "PreviewController.h"
#import "NVMarkupRenderer.h"

@interface ControlledWebView : NSView { NSMutableArray *_replies; }
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion;
- (void)reply:(NSUInteger)index value:(id)value;
@end
@implementation ControlledWebView
- (id)init { if ((self = [super init])) _replies = [[NSMutableArray alloc] init]; return self; }
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {
    if ([script isEqual:@"[document.baseURI,window.scrollX,window.scrollY]"] && completion) [_replies addObject:[[completion copy] autorelease]];
}
- (void)reply:(NSUInteger)index value:(id)value { void (^reply)(id, NSError *) = [_replies objectAtIndex:index]; reply(value, nil); }
- (void)stopLoading {}
- (void)setNavigationDelegate:(id)delegate {}
- (void)setUIDelegate:(id)delegate {}
- (id)configuration { return nil; }
- (void)dealloc { [_replies release]; [super dealloc]; }
@end

@interface ControlledViewer : PreviewController
- (void)prepare;
@end
@implementation ControlledViewer
- (void)loadView { [self setView:[[[NSView alloc] init] autorelease]]; }
- (void)prepare {
    _webView = (WKWebView *)[[ControlledWebView alloc] init];
    _snapshot = [[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"library" noteIdentifier:@"note" generation:1 title:@"Note" source:@"Source" contentType:@"html" assetRootURL:nil];
    _renderResult = [[NVMarkupRenderResult alloc] initWithSnapshot:_snapshot viewerIdentifier:@"html" HTML:@"<p>Source</p>"];
    [_viewerIdentifier release]; _viewerIdentifier = [@"html" copy];
    _documentBaseURL = [[NSURL URLWithString:@"nvalt-asset://fixture/"] retain];
}
@end

static double Scenario(BOOL reverse) {
    ControlledViewer *viewer = [[ControlledViewer alloc] init];
    [viewer prepare];
    __block NSDictionary *browserState = nil;
    NVReadonlyViewerStateCompletion consumer = ^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
        [browserState release]; browserState = [state copy];
    };
    [viewer restoreViewerState:@{@"scrollY": @100}];
    [viewer captureViewerStateWithCompletion:consumer];
    [viewer restoreViewerState:@{@"scrollY": @200}];
    [viewer captureViewerStateWithCompletion:consumer];
    ControlledWebView *web = (id)[viewer webView];
    // A missing first DOM reply takes its cached fallback. The second reply succeeds.
    if (reverse) {
        [web reply:1 value:@[@"nvalt-asset://fixture/", @0, @200]];
        // Leave reply 0 unanswered; the production 0.5-second timer supplies its fallback.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:.7];
        while ([until timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
    }
    else { [web reply:0 value:nil]; [web reply:1 value:@[@"nvalt-asset://fixture/", @0, @200]]; }
    double providerY = [[[viewer viewerState] objectForKey:@"scrollY"] doubleValue];
    double browserY = [[browserState objectForKey:@"scrollY"] doubleValue];
    printf("%s: provider scroll %.0f, browser callback state %.0f (latest captured scroll 200)\n", reverse ? "New reply then old fallback" : "Ordered replies control", providerY, browserY);
    [browserState release]; browserState = nil;
    [viewer close]; [viewer release];
    return providerY;
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    double control = Scenario(NO), outOfOrder = Scenario(YES);
    BOOL confirms = control == 200 && outOfOrder == 100;
    printf("%s: an older state capture overwrites a completed newer capture\n", confirms ? "CONFIRMED" : "NOT REPRODUCED");
    [pool drain]; return confirms ? 0 : 1;
}
