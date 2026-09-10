#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
#import "PreviewController.h"

static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
    NSLog(@"PASS: %@", message);
}
static void Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    Check(condition(), @"asynchronous boundary completes before its deadline");
}
static id Evaluate(WKWebView *web, NSString *script) {
    __block BOOL done = NO;
    __block id result = nil;
    [web evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
        Check(error == nil, @"native read-only DOM evaluation succeeds");
        result = [value retain]; done = YES;
    }];
    Await(^BOOL { return done; }, 5);
    return [result autorelease];
}
static NVNoteContentSnapshot *Snapshot(NSString *source, NSString *note, NSUInteger generation) {
    return [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"review-library" noteIdentifier:note generation:generation title:note source:source contentType:@"plain" assetRootURL:nil] autorelease];
}

// The superclass runs the real helper, transports bytes, and sanitizes output.
// This gate delays only delivery of that completed result to the provider.
@interface DeliveryRenderer : NVMarkupRenderer {
    NSMutableArray *requests;
}
- (NSUInteger)requestCount;
- (BOOL)ready:(NSUInteger)index;
- (NSDictionary *)request:(NSUInteger)index;
- (void)deliver:(NSUInteger)index;
@end
@implementation DeliveryRenderer
- (id)init { if ((self = [super init])) requests = [[NSMutableArray alloc] init]; return self; }
- (NSOperation *)renderSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier completion:(NVMarkupRenderCompletion)completion {
    NVMarkupRenderCompletion savedCompletion = [completion copy];
    NSMutableDictionary *request = [[NSMutableDictionary alloc] initWithObjectsAndKeys:snapshot, @"snapshot", identifier, @"viewer", savedCompletion, @"completion", nil];
    [savedCompletion release];
    [requests addObject:request];
    NSOperation *operation = [super renderSnapshot:snapshot viewerIdentifier:identifier completion:^(NVMarkupRenderResult *result, NSError *error) {
        Check([NSThread isMainThread], @"real renderer completion reaches the gate on the main thread");
        [request setObject:result ?: (id)[NSNull null] forKey:@"result"];
        [request setObject:error ?: (id)[NSNull null] forKey:@"error"];
    }];
    [request release];
    return operation;
}
- (NSUInteger)requestCount { return [requests count]; }
- (BOOL)ready:(NSUInteger)index { return index < [requests count] && [[requests objectAtIndex:index] objectForKey:@"result"] != nil; }
- (NSDictionary *)request:(NSUInteger)index { return [requests objectAtIndex:index]; }
- (void)deliver:(NSUInteger)index {
    NSMutableDictionary *request = [requests objectAtIndex:index];
    NVMarkupRenderCompletion callback = [[request objectForKey:@"completion"] copy];
    Check(callback != nil && [self ready:index], @"gate delivers one actual completed result exactly once");
    [request removeObjectForKey:@"completion"];
    id result = [request objectForKey:@"result"], error = [request objectForKey:@"error"];
    callback(result == [NSNull null] ? nil : result, error == [NSNull null] ? nil : error);
    [callback release];
}
- (void)dealloc { [requests release]; [super dealloc]; }
@end

static NSUInteger releasedProviders;
@interface ObservedViewer : PreviewController {
    BOOL recordRelease;
}
- (void)useRenderer:(DeliveryRenderer *)renderer;
- (void)recordRelease;
@end
@implementation ObservedViewer
- (void)useRenderer:(DeliveryRenderer *)renderer { [_renderer release]; _renderer = [renderer retain]; }
- (void)recordRelease { recordRelease = YES; }
- (void)dealloc { if (recordRelease) releasedProviders++; [super dealloc]; }
@end

@interface ExportPanel : NSObject {
@public
    NSURL *destination;
    NSString *proposedName;
    void (^response)(NSModalResponse);
}
@end
@implementation ExportPanel
- (void)setAllowedFileTypes:(NSArray *)types {}
- (void)setNameFieldStringValue:(NSString *)name { [proposedName release]; proposedName = [name copy]; }
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion { response = [completion copy]; }
- (NSURL *)URL { return destination; }
- (void)dealloc { [destination release]; [proposedName release]; [response release]; [super dealloc]; }
@end
static ExportPanel *testPanel;
@interface NSSavePanel (ReviewPanel)
+ (id)reviewSavePanel;
@end
@implementation NSSavePanel (ReviewPanel)
+ (id)reviewSavePanel { return testPanel; }
@end

static void ReadyResult(DeliveryRenderer *renderer, NSUInteger index, BOOL success) {
    Await(^BOOL { return [renderer ready:index]; }, 15);
    NSDictionary *request = [renderer request:index];
    Check(success ? request[@"result"] != [NSNull null] && request[@"error"] == [NSNull null] : request[@"result"] == [NSNull null] && request[@"error"] != [NSNull null], @"gate holds the expected real renderer outcome");
    if (success) Check([request[@"result"] snapshot] == request[@"snapshot"] && [[request[@"result"] viewerIdentifier] isEqual:request[@"viewer"]], @"real result retains its exact request snapshot and viewer");
}
static void ReadyViewer(PreviewController *viewer, NVNoteContentSnapshot *snapshot, NSString *viewerID, NSString *marker) {
    Await(^BOOL { return ![viewer loading] && [viewer renderedHTML] != nil && [viewer renderError] == nil; }, 15);
    Check([viewer snapshot] == snapshot && [[viewer viewerIdentifier] isEqual:viewerID], @"provider exposes the current immutable snapshot and viewer identity");
    Check([[viewer renderedHTML] containsString:marker], @"provider retains HTML for the current request");
    Check([Evaluate([viewer webView], @"document.body.textContent") containsString:marker], @"native WK document displays the current request");
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(50, 50, 720, 500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO]; [window orderFront:nil];
    DeliveryRenderer *renderer = [[DeliveryRenderer alloc] init];
    ObservedViewer *viewer = [[ObservedViewer alloc] init]; [viewer useRenderer:renderer];
    [[window contentView] addSubview:[viewer view]];
    [[viewer view] setFrame:[[window contentView] bounds]];

    NSLog(@"CASE: obsolete Org completion follows a newer HTML note");
    NSMutableString *mutable = [NSMutableString stringWithString:@"* TODO OLD_ORG\nBody *bold*.\n"];
    NVNoteContentSnapshot *old = Snapshot(mutable, @"Old note", 1);
    [viewer displaySnapshot:old viewerIdentifier:@"org"];
    [mutable appendString:@"MUTATED_AFTER_SNAPSHOT\n"];
    ReadyResult(renderer, 0, YES);
    Check(![[old source] containsString:@"MUTATED_AFTER_SNAPSHOT"] && ![[[renderer request:0][@"result"] HTML] containsString:@"MUTATED_AFTER_SNAPSHOT"], @"Org request and its actual output retain immutable source before caller mutation");
    NVNoteContentSnapshot *html = Snapshot(@"<h1>CURRENT_HTML</h1>", @"Other note", 2);
    [viewer displaySnapshot:html viewerIdentifier:@"html"]; ReadyResult(renderer, 1, YES);
    [renderer deliver:1]; ReadyViewer(viewer, html, @"html", @"CURRENT_HTML");
    NSString *htmlBytes = [[viewer renderedHTML] copy];
    [renderer deliver:0];
    Check([[viewer renderedHTML] isEqual:htmlBytes] && [viewer snapshot] == html && [viewer renderError] == nil, @"late successful Org completion cannot replace the newer HTML result");
    Check(![Evaluate([viewer webView], @"document.body.textContent") containsString:@"OLD_ORG"], @"obsolete Org content never enters the current HTML DOM");
    [htmlBytes release];

    NSLog(@"CASE: two Org generations complete in reverse delivery order");
    NVNoteContentSnapshot *intermediate = Snapshot(@"* TODO INTERMEDIATE_ORG\n", @"Shared note", 3);
    NVNoteContentSnapshot *current = Snapshot(@"* DONE CURRENT_ORG\n# note body\n", @"Shared note", 4);
    [viewer displaySnapshot:intermediate viewerIdentifier:@"org"]; ReadyResult(renderer, 2, YES);
    [viewer displaySnapshot:current viewerIdentifier:@"org"]; ReadyResult(renderer, 3, YES);
    [renderer deliver:3]; ReadyViewer(viewer, current, @"org", @"CURRENT_ORG");
    [renderer deliver:2];
    Check([viewer snapshot] == current && [[viewer renderedHTML] containsString:@"CURRENT_ORG"] && ![[viewer renderedHTML] containsString:@"INTERMEDIATE_ORG"], @"late Org generation cannot roll the same note back");

    NSLog(@"CASE: obsolete failure follows successful Org recovery");
    NVNoteContentSnapshot *unsupported = Snapshot(@"* ERROR_OLD\n", @"Shared note", 5);
    [viewer displaySnapshot:unsupported viewerIdentifier:@"org-unavailable"]; ReadyResult(renderer, 4, NO);
    NVNoteContentSnapshot *recovered = Snapshot(@"* DONE RECOVERED_ORG\nBody *bold*.\n", @"Export note", 6);
    [viewer displaySnapshot:recovered viewerIdentifier:@"org"]; ReadyResult(renderer, 5, YES);
    [renderer deliver:5]; ReadyViewer(viewer, recovered, @"org", @"RECOVERED_ORG");
    [renderer deliver:4];
    Check([viewer renderError] == nil && ![viewer loading] && ![[viewer webView] isHidden] && [[viewer renderedHTML] containsString:@"RECOVERED_ORG"], @"obsolete failure cannot hide or invalidate a later Org document");

    NSLog(@"CASE: pending export survives provider closure and a late Org result");
    NSString *exportBytes = [[viewer renderedHTML] copy];
    testPanel = [[ExportPanel alloc] init]; testPanel->destination = [[NSURL fileURLWithPath:@(argv[1])] retain];
    Method originalPanel = class_getClassMethod([NSSavePanel class], @selector(savePanel));
    Method replacementPanel = class_getClassMethod([NSSavePanel class], @selector(reviewSavePanel));
    method_exchangeImplementations(originalPanel, replacementPanel);
    [viewer saveHTML:nil];
    method_exchangeImplementations(originalPanel, replacementPanel);
    Check(testPanel->response != nil && [testPanel->proposedName isEqual:@"Export note.html"], @"export begins with the displayed Org result and its title");
    NVNoteContentSnapshot *closing = Snapshot(@"* TODO CLOSED_PROVIDER_ORG\n", @"Closing note", 7);
    [viewer displaySnapshot:closing viewerIdentifier:@"org"]; ReadyResult(renderer, 6, YES);
    [viewer recordRelease]; [viewer close];
    Check([viewer snapshot] == nil && [viewer renderedHTML] == nil && ![viewer loading] && [[viewer webView] navigationDelegate] == nil, @"close clears presentation and navigation while the completed result is held");
    [viewer release]; viewer = nil;

    DeliveryRenderer *newRenderer = [[DeliveryRenderer alloc] init];
    ObservedViewer *reopened = [[ObservedViewer alloc] init]; [reopened useRenderer:newRenderer];
    [[window contentView] addSubview:[reopened view]];
    NVNoteContentSnapshot *newNote = Snapshot(@"* TODO REOPENED_ORG\n", @"Reopened note", 8);
    [reopened displaySnapshot:newNote viewerIdentifier:@"org"]; ReadyResult(newRenderer, 0, YES);
    [newRenderer deliver:0]; ReadyViewer(reopened, newNote, @"org", @"REOPENED_ORG");
    testPanel->response(NSModalResponseOK);
    NSString *exported = [NSString stringWithContentsOfURL:testPanel->destination encoding:NSUTF8StringEncoding error:NULL];
    Check([exported isEqual:exportBytes] && ![exported containsString:@"REOPENED_ORG"] && ![exported containsString:@"CLOSED_PROVIDER_ORG"], @"export response after closure writes exactly the originally displayed Org bytes");
    [testPanel->response release]; testPanel->response = nil;
    [testPanel release]; testPanel = nil;
    [renderer deliver:6];
    Await(^BOOL { return releasedProviders == 1; }, 3);
    Check([reopened snapshot] == newNote && [[reopened renderedHTML] containsString:@"REOPENED_ORG"] && [reopened renderError] == nil, @"late completion releases the closed provider without changing its replacement");
    Check([Evaluate([reopened webView], @"document.body.textContent") containsString:@"REOPENED_ORG"], @"replacement WK document remains current after old-provider completion");
    Check([renderer requestCount] == 7 && [newRenderer requestCount] == 1, @"all eight submitted requests participate in the asserted schedules");
    [exportBytes release]; [reopened close]; [reopened release]; [newRenderer release]; [renderer release];
    [window close]; [window release];
    NSLog(@"PASS: %lu Org asynchronous publication and export checks", (unsigned long)checks);
    return 0;
} }
