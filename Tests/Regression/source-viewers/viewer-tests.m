#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "PreviewController.h"
#import "NVNoteContentSnapshot.h"
#import "NVMarkupRenderer.h"
static NSUInteger Checks = 0;
static void Check(BOOL value, NSString *message) {
    Checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
}
static void PumpUntil(BOOL (^condition)(void), NSTimeInterval limit) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:limit];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(condition(), @"viewer callback completes before its deadline");
}
static void Pump(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static id Evaluate(WKWebView *view, NSString *script) {
    __block BOOL done = NO;
    __block id result = nil;
    [view evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
        if (error) fprintf(stderr, "Evaluation failed: %s\n", [[error description] UTF8String]);
        Check(error == nil, @"host read-only document queries work with content scripts disabled");
        result = [value retain]; done = YES;
    }];
    PumpUntil(^BOOL{ return done; }, 5);
    return [result autorelease];
}
static NVNoteContentSnapshot *Snapshot(NSString *source, NSString *note, NSUInteger generation, NSURL *assets) {
    return [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"isolated-library" noteIdentifier:note generation:generation title:note source:source contentType:@"public.plain-text" assetRootURL:assets] autorelease];
}

// Delay only the WebKit boundary, keeping production capture completion,
// timeout, restoration, and timer ordering in control of the provider.
@interface ControlledCaptureWebView : NSView {
@public
    NSMutableArray *captures;
    NSMutableArray *timers;
}
@end
@implementation ControlledCaptureWebView
- (id)init {
    if ((self = [super init])) { captures = [[NSMutableArray alloc] init]; timers = [[NSMutableArray alloc] init]; }
    return self;
}
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {
    if (!completion) return;
    if ([script isEqual:@"[document.baseURI,window.scrollX,window.scrollY]"]) [captures addObject:[[completion copy] autorelease]];
    else if ([script isEqual:@"[window.scrollX,window.scrollY]"]) [timers addObject:[[completion copy] autorelease]];
}
- (BOOL)isHiddenOrHasHiddenAncestor { return NO; }
- (void)stopLoading {}
- (void)setNavigationDelegate:(id)delegate {}
- (void)setUIDelegate:(id)delegate {}
- (id)configuration { return nil; }
- (void)dealloc { [captures release]; [timers release]; [super dealloc]; }
@end

@interface ControlledCaptureViewer : PreviewController
- (void)prepare;
@end
@implementation ControlledCaptureViewer
- (void)loadView { [self setView:[[[NSView alloc] init] autorelease]]; }
- (void)prepare {
    _webView = (WKWebView *)[[ControlledCaptureWebView alloc] init];
    _snapshot = [Snapshot(@"Source", @"Ordered capture", 1, nil) retain];
    _renderResult = [[NVMarkupRenderResult alloc] initWithSnapshot:_snapshot viewerIdentifier:@"html" HTML:@"<p>Source</p>"];
    [_viewerIdentifier release]; _viewerIdentifier = [@"html" copy];
    _documentBaseURL = [[NSURL URLWithString:@"nvalt-asset://controlled/"] retain];
}
@end
static void Reply(NSArray *replies, NSUInteger index, id result) {
    Check(index < [replies count], @"controlled WebKit received the expected request");
    void (^reply)(id, NSError *) = [replies objectAtIndex:index]; reply(result, nil);
}
static NSArray *DocumentScroll(NSNumber *y) { return @[@"nvalt-asset://controlled/", @0, y]; }
static double CachedScroll(PreviewController *viewer) { return [[[viewer viewerState] objectForKey:@"scrollY"] doubleValue]; }
static void CaptureOrderingChecks(NSWindow *window) {
    for (NSUInteger order = 0; order < 3; order++) {
        ControlledCaptureViewer *viewer = [[ControlledCaptureViewer alloc] init]; [viewer prepare];
        ControlledCaptureWebView *web = (id)[viewer webView];
        [[window contentView] addSubview:web];
        __block NSUInteger firstCalls = 0, secondCalls = 0;
        [viewer restoreViewerState:@{@"scrollY": @100}];
        [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
            Check([[snapshot noteIdentifier] isEqual:@"Ordered capture"] && [identifier isEqual:@"html"] && [NSThread isMainThread], @"superseded capture retains call-time identity on the main thread");
            Check([[state objectForKey:@"scrollY"] doubleValue] == 100, @"older capture delivers its own immutable result even when superseded"); firstCalls++;
        }];
        [viewer restoreViewerState:@{@"scrollY": @200}];
        [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
            Check([[state objectForKey:@"scrollY"] doubleValue] == 200, @"newer capture delivers its exact DOM result"); secondCalls++;
        }];
        if (order == 0) {
            Reply(web->captures, 0, DocumentScroll(@100));
            Check(CachedScroll(viewer) == 200, @"older completion cannot replace state while the newer capture is still pending");
            Reply(web->captures, 1, DocumentScroll(@200));
        } else {
            Reply(web->captures, 1, DocumentScroll(@200));
            if (order == 1) Reply(web->captures, 0, DocumentScroll(@100));
            else PumpUntil(^BOOL { return firstCalls == 1; }, 2);
        }
        Check(CachedScroll(viewer) == 200 && firstCalls == 1 && secondCalls == 1, @"ordered, reversed, and older-timeout completions preserve the latest capture exactly once");
        Reply(web->captures, 0, DocumentScroll(@999));
        Check(CachedScroll(viewer) == 200 && firstCalls == 1, @"late repeated WebKit reply cannot change canonical state or repeat completion");
        [viewer close]; [viewer release];
    }
    ControlledCaptureViewer *viewer = [[ControlledCaptureViewer alloc] init]; [viewer prepare];
    ControlledCaptureWebView *web = (id)[viewer webView];
    [[window contentView] addSubview:web];
    [viewer restoreViewerState:@{@"scrollY": @100}];
    __block NSUInteger restoredCalls = 0;
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) { restoredCalls++; }];
    Check([viewer hasPendingViewerStateCaptureForSnapshot:[viewer snapshot] viewerIdentifier:@"html"], @"latest pending capture is available for a rapid presentation return");
    [viewer restoreViewerState:@{@"scrollY": @300}];
    Check(![viewer hasPendingViewerStateCaptureForSnapshot:[viewer snapshot] viewerIdentifier:@"html"], @"explicit restoration supersedes an older pending capture");
    Reply(web->captures, 0, DocumentScroll(@100));
    Check(restoredCalls == 1 && CachedScroll(viewer) == 300, @"older DOM reply cannot overwrite explicit restored state");
    [viewer performSelector:NSSelectorFromString(@"captureDisplayState:") withObject:nil];
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {}];
    Reply(web->captures, 1, DocumentScroll(@400));
    Reply(web->timers, 0, @[@0, @100]);
    Check(CachedScroll(viewer) == 400, @"older timer reply cannot overwrite a newer explicit capture");
    [viewer performSelector:NSSelectorFromString(@"captureDisplayState:") withObject:nil];
    [viewer restoreViewerState:@{@"scrollY": @500}];
    Reply(web->timers, 1, @[@0, @100]);
    Check(CachedScroll(viewer) == 500, @"older timer reply cannot overwrite explicit restoration");
    [viewer performSelector:NSSelectorFromString(@"captureDisplayState:") withObject:nil];
    [viewer performSelector:NSSelectorFromString(@"captureDisplayState:") withObject:nil];
    Reply(web->timers, 3, @[@0, @600]);
    Reply(web->timers, 2, @[@0, @100]);
    Check(CachedScroll(viewer) == 600, @"timer callbacks also preserve request order when replies reverse");
    [viewer close]; [viewer release];
}
@interface ViewerTests : NSObject <NSApplicationDelegate>
@end
@implementation ViewerTests
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp activateIgnoringOtherApps:YES];
    [self performSelector:@selector(runTests) withObject:nil afterDelay:.3];
}
- (void)runTests {
    NSURL *assets = [NSURL fileURLWithPath:[[[NSProcessInfo processInfo] environment] objectForKey:@"NV_VIEWER_ASSET_ROOT"] isDirectory:YES];
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 680, 480) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO] autorelease];
    [window setReleasedWhenClosed:NO];
    PreviewController *viewer = [[PreviewController alloc] init];
    [window setContentView:[viewer view]];
    [window makeKeyAndOrderFront:nil];
    CaptureOrderingChecks(window);
    [window setContentSize:NSMakeSize(420, 180)];
    [[viewer view] layoutSubtreeIfNeeded];
    Check(NSContainsRect([[viewer view] bounds], [[viewer valueForKey:@"_statusField"] frame]), @"loading and error status remains visible in a compact body");
    [window setContentSize:NSMakeSize(680, 480)];
    Check([viewer isKindOfClass:[NSViewController class]] && ![viewer isKindOfClass:[NSWindowController class]], @"viewer embeds without a detached window controller");
    if (@available(macOS 11.0, *)) Check(![[[[viewer webView] configuration] defaultWebpagePreferences] allowsContentJavaScript], @"document JavaScript is disabled separately from native evaluation");
    Check(![[[[viewer webView] configuration] websiteDataStore] isPersistent], @"viewer uses a nonpersistent website data store");
    NSMutableString *HTML = [NSMutableString stringWithString:@"<h1 id='first'>Read-only source viewer</h1><script>document.body.dataset.executed='yes'</script><p contenteditable='true'>Visible Unicode 日本語 😀</p><form><input value='locked'><textarea>fixed</textarea><button>Submit</button></form><img id='local' src='pixel.png'><img id='escape' src='../outside.png'><img id='remote' src='http://127.0.0.1:9/never'><a href='#last'>Last section</a>"];
    [HTML replaceOccurrencesOfString:@"http://127.0.0.1:9/never" withString:[[[NSProcessInfo processInfo] environment] objectForKey:@"NV_VIEWER_REMOTE_URL"] options:0 range:NSMakeRange(0, [HTML length])];
    for (NSUInteger index = 0; index < 150; index++) [HTML appendFormat:@"<p>Line %lu — Find target.</p>", (unsigned long)index];
    [HTML appendString:@"<h2 id='last'>Last section</h2>"];
    NVNoteContentSnapshot *snapshot = Snapshot(HTML, @"HTML fixture", 1, assets);
    [viewer displaySnapshot:snapshot viewerIdentifier:@"html"];
    PumpUntil(^BOOL{ return ![viewer loading]; }, 15);
    if ([viewer renderError]) fprintf(stderr, "Viewer error: %s\n", [[[viewer renderError] description] UTF8String]);
    Check([viewer renderError] == nil && [[viewer renderedHTML] containsString:@"Read-only source viewer"], @"HTML renders through the inline WK provider");
    Pump(.3);
    Check([Evaluate([viewer webView], @"document.body.innerText") containsString:@"Visible Unicode 日本語 😀"], @"rendered text preserves Unicode in WebKit");
    Check([Evaluate([viewer webView], @"document.querySelectorAll('script,[contenteditable]').length") integerValue] == 0, @"document script and editing nodes are inert");
    Check([Evaluate([viewer webView], @"Array.from(document.querySelectorAll('input,textarea,button')).every(x=>x.disabled)") boolValue], @"form controls cannot receive edits");
    Check([Evaluate([viewer webView], @"document.getElementById('local').naturalWidth") integerValue] == 1, @"scoped local image loads");
    Check([Evaluate([viewer webView], @"document.getElementById('escape').naturalWidth") integerValue] == 0, @"parent traversal cannot escape the asset scope");
    Check([Evaluate([viewer webView], @"document.getElementById('remote').naturalWidth") integerValue] == 0, @"remote resource stays blocked");
    Check([[viewer capabilities] containsObject:@"copy"] && [[viewer capabilities] containsObject:@"find"] && [[viewer capabilities] containsObject:@"html-export"], @"provider declares readonly capabilities");
    Evaluate([viewer webView], @"window.scrollTo(0,900)");
    Pump(.4);
    NSDictionary *state = [[viewer viewerState] retain];
    Check([[state objectForKey:@"scrollY"] doubleValue] > 800, @"viewer captures native display scroll state");
    Evaluate([viewer webView], @"window.scrollTo(0,0)");
    [viewer restoreViewerState:state];
    Pump(.2);
    Check([Evaluate([viewer webView], @"window.scrollY") doubleValue] > 800, @"viewer restores scroll without note edits");
    [state release];
    NSMenuItem *find = [[[NSMenuItem alloc] initWithTitle:@"Find" action:@selector(performFindPanelAction:) keyEquivalent:@""] autorelease];
    [find setTag:NSFindPanelActionShowFindPanel];
    Check([viewer validateMenuItem:find], @"Find is enabled in a ready viewer");
    [viewer performFindPanelAction:find];
    NSSearchField *field = [viewer valueForKey:@"_findField"];
    [field setStringValue:@"Find target"];
    [NSApp sendAction:[field action] to:[field target] from:field];
    Pump(.25);
    Check([Evaluate([viewer webView], @"window.getSelection().toString()") containsString:@"Find target"], @"Find selects rendered text");
    NSString *firstMatch = Evaluate([viewer webView], @"window.getSelection().anchorNode.parentElement.innerText");
    [find setTag:NSFindPanelActionNext]; [viewer performFindPanelAction:find]; Pump(.2);
    NSString *nextMatch = Evaluate([viewer webView], @"window.getSelection().anchorNode.parentElement.innerText");
    Check(![nextMatch isEqual:firstMatch], @"Find Next advances to another rendered occurrence");
    [find setTag:NSFindPanelActionPrevious]; [viewer performFindPanelAction:find]; Pump(.2);
    Check([Evaluate([viewer webView], @"window.getSelection().anchorNode.parentElement.innerText") isEqual:firstMatch], @"Find Previous returns to the preceding rendered occurrence");
    for (NSNumber *tag in @[@4, @5, @6, @8, @12, @99]) {
        [find setTag:[tag integerValue]];
        Check(![viewer validateMenuItem:find], @"read-only viewer disables replacement and unknown Find actions");
        [viewer performFindPanelAction:find];
        Check([[field stringValue] isEqual:@"Find target"], @"disabled Find actions leave the viewer query unchanged");
    }
    Evaluate([viewer webView], @"(()=>{let r=document.createRange();r.selectNodeContents(document.querySelector('p'));let s=window.getSelection();s.removeAllRanges();s.addRange(r);return true})()");
    [find setTag:NSFindPanelActionSetFindString];
    Check([viewer validateMenuItem:find], @"Use Selection for Find remains available in read-only mode");
    [viewer performFindPanelAction:find]; Pump(.2);
    Check([[field stringValue] containsString:@"Visible Unicode 日本語 😀"], @"Use Selection for Find copies the rendered selection into the native query field");
    Check([[snapshot source] isEqual:HTML], @"Find and scrolling leave source untouched");
    // No timer pump follows this scroll: transition capture must read the DOM.
    Evaluate([viewer webView], @"window.scrollTo(0,1234)");
    __block BOOL preciseCapture = NO;
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *captured, NSString *identifier, NSDictionary *capturedState) {
        Check([[captured noteIdentifier] isEqual:@"HTML fixture"] && [identifier isEqual:@"html"], @"asynchronous capture keeps its call-time note and viewer identity");
        Check([[capturedState objectForKey:@"scrollY"] doubleValue] >= 1230, @"immediate transition captures the latest DOM scroll without waiting for the timer");
        Check([viewer valueForKey:@"_navigation"] == nil, @"replacement navigation waits until the old DOM capture callback");
        preciseCapture = YES;
    }];
    [viewer displaySnapshot:Snapshot(@"# Loading B", @"Intermediate B", 2, assets) viewerIdentifier:@"markdown"];
    __block BOOL loadingCapture = NO;
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *captured, NSString *identifier, NSDictionary *capturedState) {
        Check([[captured noteIdentifier] isEqual:@"Intermediate B"] && [identifier isEqual:@"markdown"], @"loading capture reports the requested B identity");
        Check([[capturedState objectForKey:@"scrollY"] doubleValue] == 0, @"loading B cannot inherit offsets from the old A document");
        loadingCapture = YES;
    }];
    [viewer displaySnapshot:snapshot viewerIdentifier:@"html"];
    Check([viewer hasPendingViewerStateCaptureForSnapshot:snapshot viewerIdentifier:@"html"], @"rapid A to B to A keeps the pending A capture despite the B fallback");
    PumpUntil(^BOOL{ return preciseCapture && loadingCapture && ![viewer loading]; }, 15);
    Check(![viewer renderError] && [Evaluate([viewer webView], @"window.scrollY") doubleValue] >= 1230, @"rapid A to B to A restores A's fresh captured offset before navigation completes");
    // Leaving for Source cancels rendering but preserves the precise callback.
    Evaluate([viewer webView], @"window.scrollTo(0,777)");
    __block BOOL sourceCapture = NO;
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *captured, NSString *identifier, NSDictionary *capturedState) {
        Check([[capturedState objectForKey:@"scrollY"] doubleValue] >= 770, @"Source transition captures the final scroll before cancellation"); sourceCapture = YES;
    }];
    [viewer cancelRendering];
    [viewer displaySnapshot:snapshot viewerIdentifier:@"html"];
    PumpUntil(^BOOL{ return sourceCapture && ![viewer loading]; }, 15);
    Check([Evaluate([viewer webView], @"window.scrollY") doubleValue] >= 770, @"returning from Source uses the fresh callback rather than the timer cache");
    // Hold one WebKit reply to test the public API's bounded fallback. The
    // production provider has no fixture hook and still owns its timeout.
    __block void (^delayedReply)(id, NSError *) = nil;
    Method evaluateMethod = class_getInstanceMethod([WKWebView class], @selector(evaluateJavaScript:completionHandler:));
    IMP originalEvaluate = method_getImplementation(evaluateMethod);
    IMP heldEvaluate = imp_implementationWithBlock(^(WKWebView *object, NSString *script, void (^completion)(id, NSError *)) {
        if ([script isEqual:@"[document.baseURI,window.scrollX,window.scrollY]"]) delayedReply = [completion copy];
        else ((void(*)(id, SEL, NSString *, id))originalEvaluate)(object, @selector(evaluateJavaScript:completionHandler:), script, completion);
    });
    method_setImplementation(evaluateMethod, heldEvaluate);
    NSDictionary *cachedCapture = [[viewer viewerState] retain];
    __block NSUInteger timeoutCallbacks = 0;
    NSTimeInterval captureStarted = [[NSProcessInfo processInfo] systemUptime];
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *captured, NSString *identifier, NSDictionary *capturedState) {
        Check([[captured noteIdentifier] isEqual:@"HTML fixture"] && [capturedState isEqual:cachedCapture], @"missing WebKit reply falls back to immutable call-time cached state");
        timeoutCallbacks++;
    }];
    PumpUntil(^BOOL{ return timeoutCallbacks == 1; }, 2);
    Check([[NSProcessInfo processInfo] systemUptime] - captureStarted < 1.5, @"unresponsive WebKit capture completes within the bounded fallback interval");
    method_setImplementation(evaluateMethod, originalEvaluate);
    imp_removeBlock(heldEvaluate);
    if (delayedReply) { delayedReply(@[@"nvalt-asset://obsolete/", @0, @9999], nil); [delayedReply release]; }
    Check(timeoutCallbacks == 1 && [[[viewer viewerState] objectForKey:@"scrollY"] doubleValue] != 9999, @"late WebKit reply cannot repeat a capture callback or replace its completed state");
    [cachedCapture release];
    [viewer displaySnapshot:Snapshot(@"# Obsolete", @"Old note", 2, assets) viewerIdentifier:@"markdown"];
    [viewer displaySnapshot:Snapshot(@"<p>Current request</p>", @"Current note", 3, assets) viewerIdentifier:@"html"];
    PumpUntil(^BOOL{ return ![viewer loading]; }, 15);
    Pump(.5);
    Check([[viewer renderedHTML] containsString:@"Current request"] && ![[viewer renderedHTML] containsString:@"Obsolete"], @"obsolete render results cannot replace a newer note");
    Check([Evaluate([viewer webView], @"document.title") isEqual:@"Current note"], @"WebKit displays the current request's title");
    Check([Evaluate([viewer webView], @"window.scrollY") integerValue] == 0, @"new note starts with its own viewer scroll state");
    [viewer displaySnapshot:Snapshot(@"h1. Textile mode", @"Same note", 4, assets) viewerIdentifier:@"textile"];
    PumpUntil(^BOOL{ return ![viewer loading]; }, 15);
    Check(![viewer renderError] && [Evaluate([viewer webView], @"document.body.innerText") containsString:@"Textile mode"], @"Textile viewer swaps into the same native body");
    [viewer cancelRendering];
    // Simulate late provider setup after cancellation. This invokes the same
    // entry point as asynchronous content-rule compilation, with no test hook.
    [viewer performSelector:NSSelectorFromString(@"loadRenderResult")];
    Check(![viewer loading] && [viewer valueForKey:@"_navigation"] == nil, @"late provider readiness cannot restart a cancelled document load");
    [viewer displaySnapshot:Snapshot(@"Unsupported", @"Failure", 5, assets) viewerIdentifier:@"pdf"];
    PumpUntil(^BOOL{ return ![viewer loading]; }, 5);
    Check([viewer renderError] != nil && ![viewer validateMenuItem:find], @"failed preparation shows an error and disables output commands");
    [viewer displaySnapshot:Snapshot(@"<p>Closing capture</p>", @"Closing note", 6, assets) viewerIdentifier:@"html"];
    PumpUntil(^BOOL{ return ![viewer loading]; }, 15);
    __block NSUInteger closedCaptureCallbacks = 0;
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *captured, NSString *identifier, NSDictionary *capturedState) {
        Check([[captured noteIdentifier] isEqual:@"Closing note"] && [identifier isEqual:@"html"], @"closing capture retains its call-time identity");
        closedCaptureCallbacks++;
    }];
    [viewer displaySnapshot:Snapshot(@"# Cancel", @"Cancel", 7, assets) viewerIdentifier:@"markdown"];
    [viewer close];
    Check(closedCaptureCallbacks == 1, @"close immediately finishes pending captures with bounded cached fallback");
    Pump(.6);
    Check(closedCaptureCallbacks == 1, @"callbacks arriving after close do not restart or complete a capture twice");
    Check(![viewer loading] && [viewer renderedHTML] == nil && [[viewer webView] navigationDelegate] == nil && [[viewer webView] UIDelegate] == nil, @"close cancels work and releases rendered state and delegates");
    [window orderOut:nil]; [window setContentView:nil]; [window close]; [viewer release];
    Pump(.1);
    fprintf(stdout, "PASS: %lu inline viewer checks\n", (unsigned long)Checks);
    exit(0);
}
@end
int main() {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    ViewerTests *tests = [[[ViewerTests alloc] init] autorelease];
    [NSApp setDelegate:tests];
    [NSApp run];
    [pool drain];
    return 0;
}
