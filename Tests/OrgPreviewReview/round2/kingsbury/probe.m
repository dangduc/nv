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
        Check(error == nil, @"native DOM command completes without an error");
        result = [value retain]; done = YES;
    }];
    Await(^BOOL { return done; }, 5);
    return [result autorelease];
}
static NSString *Literal(NSString *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:NULL];
    NSString *json = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return [json substringWithRange:NSMakeRange(1, [json length] - 2)];
}
static NVNoteContentSnapshot *Snapshot(NSString *source, NSString *note, NSUInteger generation) {
    return [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"round-two-library" noteIdentifier:note generation:generation title:note source:source contentType:@"plain" assetRootURL:nil] autorelease];
}

// Observe actual WebKit navigation decisions, then use the production policy.
@interface NavigationViewer : PreviewController {
@public
    NSUInteger activatedLinks;
    NSUInteger allowedFragments;
}
@end
@implementation NavigationViewer
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    BOOL activated = [action navigationType] == WKNavigationTypeLinkActivated;
    if (activated) activatedLinks++;
    [super webView:webView decidePolicyForNavigationAction:action decisionHandler:^(WKNavigationActionPolicy policy) {
        if (activated && policy == WKNavigationActionPolicyAllow && [[[[action request] URL] fragment] length]) allowedFragments++;
        decisionHandler(policy);
    }];
}
@end

static void Ready(NavigationViewer *viewer, NVNoteContentSnapshot *snapshot, NSString *format) {
    Await(^BOOL { return ![viewer loading] && [viewer renderedHTML] != nil && [viewer renderError] == nil; }, 15);
    Check([viewer snapshot] == snapshot && [[viewer viewerIdentifier] isEqual:format], @"provider owns the requested source snapshot and viewer identity");
}
static NSDictionary *Capture(NavigationViewer *viewer) {
    __block NSDictionary *result = nil;
    NVNoteContentSnapshot *expected = [viewer snapshot];
    NSString *format = [viewer viewerIdentifier];
    [viewer captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
        Check(snapshot == expected && [identifier isEqual:format], @"state capture retains the exact presentation identity");
        result = [state copy];
    }];
    Await(^BOOL { return result != nil; }, 3);
    return [result autorelease];
}
static void Navigate(NavigationViewer *viewer, NSString *label, NSString *expectedID) {
    NSUInteger previous = viewer->activatedLinks, allowed = viewer->allowedFragments;
    NSString *script = [NSString stringWithFormat:@"(()=>{window.scrollTo(0,0);const a=Array.from(document.links).find(x=>x.textContent===%@);return a?{href:a.getAttribute('href'),base:document.baseURI}:null})()", Literal(label)];
    NSDictionary *before = Evaluate([viewer webView], script);
    Check([before[@"href"] hasPrefix:@"#"], [NSString stringWithFormat:@"%@ uses a fragment URL", label]);
    Check([[[before[@"href"] substringFromIndex:1] stringByRemovingPercentEncoding] isEqual:expectedID], [NSString stringWithFormat:@"%@ resolves to its expected heading ID", label]);
    NSString *click = [NSString stringWithFormat:@"Array.from(document.links).find(x=>x.textContent===%@).click();true", Literal(label)];
    Check([Evaluate([viewer webView], click) boolValue], @"native host asks the real DOM link to activate");
    Await(^BOOL { return viewer->activatedLinks == previous + 1; }, 3);
    Check(viewer->allowedFragments == allowed + 1, @"production navigation policy allows exactly one current-document fragment");
    NSDictionary *after = Evaluate([viewer webView], [NSString stringWithFormat:@"(()=>{const target=document.getElementById(%@);return {id:decodeURIComponent(location.hash.slice(1)),y:window.scrollY,top:target.getBoundingClientRect().top,base:document.baseURI,headings:document.querySelectorAll('h1,h2').length}})()", Literal(expectedID)]);
    Check([after[@"id"] isEqual:expectedID] && [after[@"y"] doubleValue] > 300 && fabs([after[@"top"] doubleValue]) < 2, @"real fragment navigation reaches the target heading and scrolls it to the viewport");
    Check([after[@"base"] hasPrefix:[before[@"base"] componentsSeparatedByString:@"#"][0]] && [after[@"headings"] unsignedIntegerValue] == 6, @"fragment navigation retains the same complete document");
    Check(![viewer loading] && [viewer renderError] == nil && ![[viewer webView] isHidden], @"fragment navigation keeps the current preview visible and usable");
    NSDictionary *captured = Capture(viewer);
    NSLog(@"EVIDENCE: fragment base %@, captured scroll %@, actual scroll %@", after[@"base"], captured[@"scrollY"], after[@"y"]);
    Check(fabs([captured[@"scrollY"] doubleValue] - [after[@"y"] doubleValue]) <= 2, @"immediate state capture records the heading position after fragment navigation");
}
static void ExpectScroll(NavigationViewer *viewer, double expected, NSString *label) {
    double actual = [Evaluate([viewer webView], @"window.scrollY") doubleValue];
    Check(fabs(actual - expected) <= 2, label);
}

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

static NSString *Notebook(void) {
    NSMutableString *text = [NSMutableString stringWithString:@"* Contents\n[[*Release plan][Starred target]]\n\n[[Release plan][Exact target]]\n\n[[#release-plan][Explicit target]]\n\n[[*Résumé 日本語][Unicode target]]\n\n[[*Auto Heading][Generated target]]\n\n[[*Duplicate][Duplicate target]]\n\n"];
    for (NSUInteger i = 0; i < 55; i++) [text appendFormat:@"Opening paragraph %lu.\n\n", (unsigned long)i];
    [text appendString:@"* TODO Release plan\n:PROPERTIES:\n:CUSTOM_ID: release-plan\n:END:\nRelease body.\n\n"];
    for (NSUInteger i = 0; i < 30; i++) [text appendFormat:@"Release paragraph %lu.\n\n", (unsigned long)i];
    [text appendString:@"** Résumé 日本語\n:PROPERTIES:\n:CUSTOM_ID: résumé-東京\n:END:\nUnicode body.\n\n* Auto Heading\nGenerated anchor body.\n\n* Duplicate\nFirst duplicate body.\n\n"];
    for (NSUInteger i = 0; i < 30; i++) [text appendFormat:@"Duplicate paragraph %lu.\n\n", (unsigned long)i];
    [text appendString:@"* Duplicate\nSecond duplicate body.\n\n"];
    for (NSUInteger i = 0; i < 50; i++) [text appendFormat:@"Final paragraph %lu.\n\n", (unsigned long)i];
    return text;
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *firstWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(20, 50, 700, 480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSWindow *peerWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(740, 50, 700, 480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [firstWindow setReleasedWhenClosed:NO]; [peerWindow setReleasedWhenClosed:NO];
    [firstWindow orderFront:nil]; [peerWindow orderFront:nil];
    NavigationViewer *first = [[NavigationViewer alloc] init], *peer = [[NavigationViewer alloc] init];
    [firstWindow setContentView:[first view]]; [peerWindow setContentView:[peer view]];
    NSString *source = Notebook();
    NVNoteContentSnapshot *note = Snapshot(source, @"Notebook", 1);
    [first displaySnapshot:note viewerIdentifier:@"org"]; [peer displaySnapshot:note viewerIdentifier:@"org"];
    Ready(first, note, @"org"); Ready(peer, note, @"org");
    Check([[first renderedHTML] isEqual:[peer renderedHTML]], @"two native windows render the same immutable Org document");
    NSDictionary *headingIDs = Evaluate([first webView], @"(()=>{const h=Array.from(document.querySelectorAll('h1,h2'));return {automatic:h.find(x=>x.textContent==='Auto Heading').id,duplicate:h.find(x=>x.textContent==='Duplicate').id,all:h.map(x=>x.id)}})()");
    Check([headingIDs[@"all"] count] == 6 && [[NSSet setWithArray:headingIDs[@"all"]] count] == 6, @"every rendered heading receives a distinct document ID");
    NSLog(@"CASE: native fragment navigation for fixed heading-link forms");
    Navigate(first, @"Starred target", @"release-plan");
    Navigate(first, @"Exact target", @"release-plan");
    Navigate(first, @"Explicit target", @"release-plan");
    Navigate(first, @"Unicode target", @"résumé-東京");
    Navigate(first, @"Generated target", headingIDs[@"automatic"]);
    Navigate(first, @"Duplicate target", headingIDs[@"duplicate"]);
    ExpectScroll(peer, 0, @"fragment navigation in one window leaves the peer at its original position");

    NSLog(@"CASE: independent window state survives note/viewer changes and source replacement");
    [first restoreViewerState:@{@"scrollY": @420, @"find": @"Release paragraph"}];
    [peer restoreViewerState:@{@"scrollY": @860, @"find": @"Final paragraph"}];
    NSDictionary *firstState = [Capture(first) copy], *peerState = [Capture(peer) copy];
    Check(fabs([firstState[@"scrollY"] doubleValue] - 420) <= 2 && fabs([peerState[@"scrollY"] doubleValue] - 860) <= 2 && ![firstState[@"find"] isEqual:peerState[@"find"]], @"two providers capture separate scroll and Find state for the same note");
    NVNoteContentSnapshot *other = Snapshot(@"<h1>Other note</h1><p>Other contents.</p>", @"Other note", 2);
    [first displaySnapshot:other viewerIdentifier:@"html"]; Ready(first, other, @"html");
    Check([[[first viewerState] objectForKey:@"find"] length] == 0, @"another note and viewer do not inherit Org Find state");
    ExpectScroll(peer, 860, @"switching one provider to another note leaves peer scroll unchanged");
    [first displaySnapshot:note viewerIdentifier:@"org"]; [first restoreViewerState:firstState]; Ready(first, note, @"org");
    ExpectScroll(first, 420, @"restored Org presentation uses its own retained scroll state");
    Check([[[first viewerState] objectForKey:@"find"] isEqual:@"Release paragraph"] && [[[peer viewerState] objectForKey:@"find"] isEqual:@"Final paragraph"], @"returning to Org retains independent Find queries in both windows");
    NSString *updatedSource = [source stringByAppendingString:@"\nUPDATED_SOURCE_GENERATION\n"];
    NVNoteContentSnapshot *updated = Snapshot(updatedSource, @"Notebook", 3);
    [first displaySnapshot:updated viewerIdentifier:@"org"]; [peer displaySnapshot:updated viewerIdentifier:@"org"];
    Ready(first, updated, @"org"); Ready(peer, updated, @"org");
    ExpectScroll(first, 420, @"same-note source replacement retains the first window position");
    ExpectScroll(peer, 860, @"same-note source replacement retains the second window position");
    Check([[first renderedHTML] containsString:@"UPDATED_SOURCE_GENERATION"] && [[peer renderedHTML] isEqual:[first renderedHTML]], @"both providers converge to the replacement source generation");
    Navigate(first, @"Unicode target", @"résumé-東京");
    ExpectScroll(peer, 860, @"a fragment click after source replacement still leaves peer state unchanged");
    Check([[note source] isEqual:source] && [[updated source] isEqual:updatedSource], @"navigation and state operations preserve both immutable source generations");

    NSLog(@"CASE: export anchors remain bound to the document displayed when export starts");
    NSString *exportHTML = [[first renderedHTML] copy];
    testPanel = [[ExportPanel alloc] init]; testPanel->destination = [[NSURL fileURLWithPath:@(argv[1])] retain];
    Method originalPanel = class_getClassMethod([NSSavePanel class], @selector(savePanel)), replacementPanel = class_getClassMethod([NSSavePanel class], @selector(reviewSavePanel));
    method_exchangeImplementations(originalPanel, replacementPanel); [first saveHTML:nil]; method_exchangeImplementations(originalPanel, replacementPanel);
    Check(testPanel->response != nil && [testPanel->proposedName isEqual:@"Notebook.html"], @"export captures the current notebook document and title");
    [first displaySnapshot:other viewerIdentifier:@"html"]; Ready(first, other, @"html");
    testPanel->response(NSModalResponseOK);
    NSString *exported = [NSString stringWithContentsOfURL:testPanel->destination encoding:NSUTF8StringEncoding error:NULL];
    Check([exported isEqual:exportHTML] && [exported containsString:@"id=\"release-plan\""] && [exported containsString:@"href=\"#release-plan\""], @"delayed export preserves exact displayed bytes and matching heading anchors after note change");
    Check([exported containsString:@"#r%C3%A9sum%C3%A9-%E6%9D%B1%E4%BA%AC"] && [exported containsString:@"UPDATED_SOURCE_GENERATION"], @"export retains encoded Unicode fragment targets from the displayed source generation");
    [testPanel->response release]; testPanel->response = nil; [testPanel release]; testPanel = nil;
    [firstState release]; [peerState release]; [exportHTML release];
    [first close]; [peer close]; [first release]; [peer release]; [firstWindow close]; [peerWindow close]; [firstWindow release]; [peerWindow release];
    NSLog(@"PASS: %lu native Org heading-navigation, state and export checks", (unsigned long)checks);
    return 0;
} }
