#import "PreviewController.h"
#import "NVMarkupRenderer.h"
#import <math.h>

@interface NVScopedAssetHandler : NSObject <WKURLSchemeHandler> {
    NSURL *_rootURL;
    NSString *_requestIdentifier;
}
- (NSURL *)setRootURL:(NSURL *)rootURL;
@end
@implementation NVScopedAssetHandler
- (NSURL *)setRootURL:(NSURL *)rootURL {
    [_rootURL release]; _rootURL = [[rootURL URLByResolvingSymlinksInPath] copy];
    [_requestIdentifier release]; _requestIdentifier = [[[NSUUID UUID] UUIDString] copy];
    return [NSURL URLWithString:[NSString stringWithFormat:@"nvalt-asset://%@/", _requestIdentifier]];
}
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    NSURL *URL = [[task request] URL];
    NSError *error = nil;
    NSData *data = nil;
    NSString *MIME = nil;
    if ([_rootURL isFileURL] && [[URL host] caseInsensitiveCompare:_requestIdentifier] == NSOrderedSame) {
        NSString *root = [[_rootURL path] stringByStandardizingPath];
        NSString *relative = [[URL path] stringByRemovingPercentEncoding];
        while ([relative hasPrefix:@"/"]) relative = [relative substringFromIndex:1];
        NSString *path = [[[root stringByAppendingPathComponent:relative] stringByStandardizingPath] stringByResolvingSymlinksInPath];
        // Only passive, bounded assets within this explicit note scope are served.
        NSDictionary *types = @{@"png":@"image/png", @"jpg":@"image/jpeg", @"jpeg":@"image/jpeg", @"gif":@"image/gif", @"webp":@"image/webp", @"svg":@"image/svg+xml", @"css":@"text/css", @"woff":@"font/woff", @"woff2":@"font/woff2", @"ttf":@"font/ttf"};
        MIME = [types objectForKey:[[path pathExtension] lowercaseString]];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
        if ([path hasPrefix:[root stringByAppendingString:@"/"]] && MIME && [[attributes objectForKey:NSFileType] isEqual:NSFileTypeRegular] && [attributes fileSize] <= 8 * 1024 * 1024)
            data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
    }
    if (!data) {
        [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNoPermissionsToReadFile userInfo:@{NSLocalizedDescriptionKey:@"The viewer cannot read this asset outside its note's asset scope."}]];
        return;
    }
    NSURLResponse *response = [[[NSURLResponse alloc] initWithURL:URL MIMEType:MIME expectedContentLength:[data length] textEncodingName:[MIME isEqual:@"text/css"] ? @"utf-8" : nil] autorelease];
    [task didReceiveResponse:response]; [task didReceiveData:data]; [task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task { }
- (void)dealloc { [_rootURL release]; [_requestIdentifier release]; [super dealloc]; }
@end

// WebKit and timeout callbacks retain this token, not the controller. Closing
// a provider clears its owner and completes outstanding callbacks immediately.
@interface NVViewerCaptureOwner : NSObject {
@public
    PreviewController *owner;
}
@end
@implementation NVViewerCaptureOwner
@end

static NSArray *ViewerStateKey(NVNoteContentSnapshot *snapshot, NSString *identifier) {
    return @[[snapshot libraryIdentifier] ?: @"", [snapshot noteIdentifier] ?: @"", identifier ?: @""];
}

@interface NVViewerStateCapture : NSObject {
@public
    NVNoteContentSnapshot *snapshot;
    NSString *viewerIdentifier;
    NSString *documentBase;
    NSDictionary *cachedState;
    NSArray *presentationKey;
    NSUInteger revision;
    NVReadonlyViewerStateCompletion completion;
    NSMutableArray *coalescedCaptures;
    BOOL finished;
}
@end
@implementation NVViewerStateCapture
- (void)dealloc {
    [snapshot release]; [viewerIdentifier release]; [documentBase release];
    [cachedState release]; [presentationKey release]; [completion release];
    [coalescedCaptures release]; [super dealloc];
}
@end

@interface PreviewController ()
- (void)loadRenderResult;
- (void)showError:(NSError *)error;
- (void)captureDisplayState:(NSTimer *)timer;
- (void)findNext:(id)sender;
- (void)finishStateCapture:(NVViewerStateCapture *)capture documentState:(id)documentState;
- (NSUInteger)beginStateRequestForKey:(NSArray *)key;
- (NVViewerStateCapture *)pendingStateCaptureForKey:(NSArray *)key;
@end

@implementation PreviewController
@synthesize snapshot = _snapshot, webView = _webView, viewerIdentifier = _viewerIdentifier, loading = _loading, renderError = _renderError;
- (id)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _renderer = [[NVMarkupRenderer alloc] init];
        _displayState = [[NSMutableDictionary alloc] init];
        _stateCaptures = [[NSMutableSet alloc] init];
        _stateRevisions = [[NSMutableDictionary alloc] init];
        _captureOwner = [[NVViewerCaptureOwner alloc] init]; _captureOwner->owner = self;
        _viewerIdentifier = [@"markdown" copy];
    }
    return self;
}
- (void)loadView {
    NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
    [self setView:container];
    WKWebViewConfiguration *configuration = [[[WKWebViewConfiguration alloc] init] autorelease];
    [configuration setWebsiteDataStore:[WKWebsiteDataStore nonPersistentDataStore]];
    // CSP and DOM sanitization disable document scripts on every supported OS.
    // Modern WebKit also separates content JavaScript from native evaluation.
    if (@available(macOS 11.0, *)) [[configuration defaultWebpagePreferences] setAllowsContentJavaScript:NO];
    [[configuration preferences] setJavaScriptCanOpenWindowsAutomatically:NO];
    _assetHandler = [[NVScopedAssetHandler alloc] init];
    [configuration setURLSchemeHandler:_assetHandler forURLScheme:@"nvalt-asset"];
    _webView = [[WKWebView alloc] initWithFrame:[container bounds] configuration:configuration];
    [_webView setNavigationDelegate:self]; [_webView setUIDelegate:self];
    [_webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_webView setAccessibilityLabel:NSLocalizedString(@"Read-only note preview", nil)];
    [container addSubview:_webView];
    _statusField = [[NSTextField labelWithString:@""] retain];
    [_statusField setFrame:NSMakeRect(18, NSHeight([container bounds]) - 60, NSWidth([container bounds]) - 36, 44)];
    [_statusField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [_statusField setHidden:YES];
    [container addSubview:_statusField];
    _findField = [[NSSearchField alloc] initWithFrame:NSMakeRect(12, 260, 476, 28)];
    [_findField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [_findField setPlaceholderString:NSLocalizedString(@"Find in preview", nil)];
    [_findField setDelegate:self];
    [_findField setTarget:self]; [_findField setAction:@selector(findNext:)];
    [_findField setHidden:YES];
    [container addSubview:_findField];
    // No document is loaded before these rules are installed. Nonpersistent
    // website data alone does not block network requests.
    NSString *rules = @"[{\"trigger\":{\"url-filter\":\"^https?://\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^wss?://\"},\"action\":{\"type\":\"block\"}}]";
    [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"nvALT-readonly-resources-v1" encodedContentRuleList:rules completionHandler:^(WKContentRuleList *list, NSError *error) {
        if (_closed) return;
        if (error || !list) { _ruleError = [(error ?: [NSError errorWithDomain:NVMarkupRendererErrorDomain code:NVMarkupInvalidOutput userInfo:@{NSLocalizedDescriptionKey:@"The viewer could not configure its resource rules."}]) retain]; [self showError:_ruleError]; return; }
        _resourceRules = [list retain];
        [[[_webView configuration] userContentController] addContentRuleList:list];
        _rulesReady = YES;
        [self loadRenderResult];
    }];
}
- (NSString *)renderedHTML { return [_renderResult HTML]; }
- (BOOL)canDisplaySnapshot:(NVNoteContentSnapshot *)snapshot { return [snapshot source] != nil; }
- (NSSet *)capabilities {
    if (@available(macOS 11.0, *)) return [NSSet setWithObjects:@"selection", @"copy", @"find", @"print", @"html-export", nil];
    return [NSSet setWithObjects:@"selection", @"copy", @"find", @"html-export", nil];
}
- (void)displaySnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier {
    NSAssert([NSThread isMainThread], @"Viewer requests belong to the main thread.");
    if (_closed) return;
    [self view];
    BOOL changedNote = ![[_snapshot noteIdentifier] isEqual:[snapshot noteIdentifier]] || ![[_snapshot libraryIdentifier] isEqual:[snapshot libraryIdentifier]];
    BOOL changedViewer = ![_viewerIdentifier isEqual:identifier];
    [self cancelRendering];
    if (changedNote || changedViewer) {
        [_displayState removeAllObjects];
        // The pending read's cache belongs to this returned presentation. Keep
        // its Find query now; completion supplies only the fresh DOM offsets.
        NVViewerStateCapture *pending = [self pendingStateCaptureForKey:ViewerStateKey(snapshot, identifier)];
        if (pending) [_displayState addEntriesFromDictionary:pending->cachedState];
        [_findField setStringValue:[_displayState objectForKey:@"find"] ?: @""];
    }
    [_snapshot release]; _snapshot = [snapshot retain];
    [_viewerIdentifier release]; _viewerIdentifier = [identifier copy];
    [_renderResult release]; _renderResult = nil;
    [_renderError release]; _renderError = nil;
    _loading = YES;
    [_webView setHidden:YES];
    [_statusField setStringValue:NSLocalizedString(@"Preparing preview…", nil)]; [_statusField setHidden:NO];
    if (_ruleError) { [self showError:_ruleError]; return; }
    NSUInteger generation = _requestGeneration;
    _renderOperation = [[_renderer renderSnapshot:snapshot viewerIdentifier:identifier completion:^(NVMarkupRenderResult *result, NSError *error) {
        if (_closed || generation != _requestGeneration) return;
        [_renderOperation release]; _renderOperation = nil;
        if (error) { [self showError:error]; return; }
        _renderResult = [result retain];
        [self loadRenderResult];
    }] retain];
}
- (void)loadRenderResult {
    if (!_rulesReady || !_renderResult || _closed || !_loading || _navigation || [_stateCaptures count]) return;
    NSURL *baseURL = [_assetHandler setRootURL:[[_renderResult snapshot] assetRootURL]];
    [_documentBaseURL release]; _documentBaseURL = [baseURL copy];
    [_navigation release]; _navigation = [[_webView loadHTMLString:[_renderResult HTML] baseURL:baseURL] retain];
}
- (void)showError:(NSError *)error {
    [_renderError release]; _renderError = [error retain]; _loading = NO;
    [_webView setHidden:YES];
    [_statusField setStringValue:[error localizedDescription] ?: NSLocalizedString(@"The preview is unavailable.", nil)];
    [_statusField setHidden:NO];
}
- (void)cancelRendering {
    _requestGeneration++;
    [_renderOperation cancel]; [_renderOperation release]; _renderOperation = nil;
    [_webView stopLoading];
    [_navigation release]; _navigation = nil;
    _loading = NO;
}
- (void)close {
    if (_closed) return;
    _closed = YES;
    [self cancelRendering]; [_renderer cancelAllRendering];
    for (NVViewerStateCapture *capture in [[[_stateCaptures allObjects] copy] autorelease]) [self finishStateCapture:capture documentState:nil];
    _captureOwner->owner = nil;
    [_stateTimer invalidate]; [_stateTimer release]; _stateTimer = nil;
    [_webView setNavigationDelegate:nil]; [_webView setUIDelegate:nil];
    [[[_webView configuration] userContentController] removeAllContentRuleLists];
    [_webView removeFromSuperview];
    [_renderResult release]; _renderResult = nil;
    [_snapshot release]; _snapshot = nil;
    [_assetHandler setRootURL:nil];
}
- (NSDictionary *)viewerState { return [[_displayState copy] autorelease]; }
- (NSUInteger)beginStateRequestForKey:(NSArray *)key {
    NSUInteger revision = ++_nextStateRevision;
    [_stateRevisions setObject:@(revision) forKey:key];
    return revision;
}
- (NVViewerStateCapture *)pendingStateCaptureForKey:(NSArray *)key {
    NSUInteger revision = [[_stateRevisions objectForKey:key] unsignedIntegerValue];
    for (NVViewerStateCapture *capture in _stateCaptures)
        if (!capture->finished && capture->revision == revision && [capture->presentationKey isEqual:key]) return capture;
    return nil;
}
- (BOOL)hasPendingViewerStateCaptureForSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier {
    return [self pendingStateCaptureForKey:ViewerStateKey(snapshot, identifier)] != nil;
}
- (void)captureViewerStateWithCompletion:(NVReadonlyViewerStateCompletion)completion {
    NSAssert([NSThread isMainThread], @"Viewer state capture belongs to the main thread.");
    if (!completion) return;
    NVViewerStateCapture *capture = [[[NVViewerStateCapture alloc] init] autorelease];
    capture->snapshot = [_snapshot retain];
    capture->viewerIdentifier = [_viewerIdentifier copy];
    capture->documentBase = [[_documentBaseURL absoluteString] copy];
    capture->cachedState = [_displayState copy];
    capture->presentationKey = [ViewerStateKey(_snapshot, _viewerIdentifier) retain];
    capture->completion = [completion copy];
    // Returning to a presentation can leave its old exact DOM read pending.
    // A further departure during loading has no newer document to capture.
    // Join that read without advancing its revision or extending its deadline.
    NVViewerStateCapture *pending = !_closed && _loading ? [self pendingStateCaptureForKey:capture->presentationKey] : nil;
    if (pending) {
        capture->revision = pending->revision;
        [capture->documentBase release]; capture->documentBase = [pending->documentBase copy];
        [capture->cachedState release]; capture->cachedState = [pending->cachedState copy];
        if (!pending->coalescedCaptures) pending->coalescedCaptures = [[NSMutableArray alloc] init];
        [pending->coalescedCaptures addObject:capture];
        return;
    }
    capture->revision = [self beginStateRequestForKey:capture->presentationKey];
    // A loading request's identity can differ from the document still on screen.
    // Its cached state is the only state that belongs to that request.
    if (_closed || _loading || _renderError || !_renderResult || !_documentBaseURL) {
        [self finishStateCapture:capture documentState:nil];
        return;
    }
    [_stateCaptures addObject:capture];
    NVViewerCaptureOwner *token = _captureOwner;
    [_webView evaluateJavaScript:@"[document.baseURI,window.scrollX,window.scrollY]" completionHandler:^(id result, NSError *error) {
        [token->owner finishStateCapture:capture documentState:result];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [token->owner finishStateCapture:capture documentState:nil];
    });
}
- (void)finishStateCapture:(NVViewerStateCapture *)capture documentState:(id)documentState {
    if (capture->finished) return;
    capture->finished = YES;
    // Preserve the call-time query. Only offsets from the same immutable
    // document base can replace the cached offsets.
    NSMutableDictionary *state = [[capture->cachedState mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
    BOOL matchingDocument = [documentState isKindOfClass:[NSArray class]] && [documentState count] == 3 &&
        [[documentState objectAtIndex:0] isKindOfClass:[NSString class]] &&
        [[documentState objectAtIndex:0] caseInsensitiveCompare:capture->documentBase] == NSOrderedSame;
    if (matchingDocument) {
        for (NSUInteger index = 1; index < 3; index++) {
            id value = [documentState objectAtIndex:index];
            if ([value isKindOfClass:[NSNumber class]] && isfinite([value doubleValue]) && [value doubleValue] >= 0)
                [state setObject:value forKey:index == 1 ? @"scrollX" : @"scrollY"];
        }
    }
    BOOL samePresentation = [[_snapshot libraryIdentifier] isEqual:[capture->snapshot libraryIdentifier]] &&
        [[_snapshot noteIdentifier] isEqual:[capture->snapshot noteIdentifier]] && [_viewerIdentifier isEqual:capture->viewerIdentifier];
    // Completion delivery is independent of canonical state: each caller still
    // gets its own result once, but an older reply or timeout cannot win a race
    // with a newer capture, timer read, or explicit restoration of this identity.
    BOOL latestRequest = capture->revision == [[_stateRevisions objectForKey:capture->presentationKey] unsignedIntegerValue];
    if (!_closed && samePresentation && latestRequest) {
        for (NSString *key in @[@"scrollX", @"scrollY"]) if ([state objectForKey:key]) [_displayState setObject:[state objectForKey:key] forKey:key];
    }
    // Keep the navigation barrier until every joined caller receives its result.
    // The browser's newest request can be one of these callers.
    [capture retain];
    NVReadonlyViewerStateCompletion callback = capture->completion; capture->completion = nil;
    NSDictionary *immutableState = [[state copy] autorelease];
    BOOL keepAlive = !_closed;
    if (keepAlive) [self retain];
    callback(capture->snapshot, capture->viewerIdentifier, immutableState);
    [callback release];
    for (NVViewerStateCapture *joined in capture->coalescedCaptures) [self finishStateCapture:joined documentState:documentState];
    [_stateCaptures removeObject:capture];
    [capture release];
    if (keepAlive) { [self loadRenderResult]; [self release]; }
}
- (void)restoreViewerState:(NSDictionary *)state {
    [self beginStateRequestForKey:ViewerStateKey(_snapshot, _viewerIdentifier)];
    [_displayState removeAllObjects];
    for (NSString *key in @[@"scrollX", @"scrollY"]) {
        id value = [state objectForKey:key];
        if ([value isKindOfClass:[NSNumber class]] && isfinite([value doubleValue]) && [value doubleValue] >= 0) [_displayState setObject:value forKey:key];
    }
    [_findField setStringValue:@""];
    id query = [state objectForKey:@"find"];
    if ([query isKindOfClass:[NSString class]]) { [_displayState setObject:query forKey:@"find"]; [_findField setStringValue:query]; }
    if (!_loading && _renderResult) {
        NSString *script = [NSString stringWithFormat:@"window.scrollTo(%f,%f)", [[_displayState objectForKey:@"scrollX"] doubleValue], [[_displayState objectForKey:@"scrollY"] doubleValue]];
        [_webView evaluateJavaScript:script completionHandler:nil];
    }
}
- (void)captureDisplayState:(NSTimer *)timer {
    if (_closed || _loading || [_stateCaptures count] || ![[_webView window] isVisible] || [_webView isHiddenOrHasHiddenAncestor]) return;
    NSUInteger generation = _requestGeneration;
    NSArray *key = ViewerStateKey(_snapshot, _viewerIdentifier);
    NSUInteger revision = [self beginStateRequestForKey:key];
    [_webView evaluateJavaScript:@"[window.scrollX,window.scrollY]" completionHandler:^(id result, NSError *error) {
        if (_closed || generation != _requestGeneration || revision != [[_stateRevisions objectForKey:key] unsignedIntegerValue] ||
            ![result isKindOfClass:[NSArray class]] || [result count] != 2) return;
        if ([[result objectAtIndex:0] isKindOfClass:[NSNumber class]] && [[result objectAtIndex:1] isKindOfClass:[NSNumber class]]) {
            [_displayState setObject:[result objectAtIndex:0] forKey:@"scrollX"];
            [_displayState setObject:[result objectAtIndex:1] forKey:@"scrollY"];
        }
    }];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (_closed || navigation != _navigation) return;
    _loading = NO;
    [_statusField setHidden:YES]; [_webView setHidden:NO];
    NSDictionary *state = [[_displayState copy] autorelease]; [self restoreViewerState:state];
    if (!_stateTimer) _stateTimer = [[NSTimer scheduledTimerWithTimeInterval:.2 target:self selector:@selector(captureDisplayState:) userInfo:nil repeats:YES] retain];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { if (!_closed && navigation == _navigation && [error code] != NSURLErrorCancelled) [self showError:error]; }
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self webView:webView didFailNavigation:navigation withError:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (!_closed) [self showError:[NSError errorWithDomain:NVMarkupRendererErrorDomain code:NVMarkupHelperFailed userInfo:@{NSLocalizedDescriptionKey:@"The preview process stopped. Return to Source, then open Preview again."}]];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *URL = [[action request] URL];
    NSString *scheme = [[URL scheme] lowercaseString];
    if ([action navigationType] == WKNavigationTypeLinkActivated) {
        if ([@[@"http", @"https", @"mailto"] containsObject:scheme]) [[NSWorkspace sharedWorkspace] openURL:URL];
        else if ([scheme isEqual:@"nvalt-asset"] && [[URL fragment] length] && [[URL host] isEqual:[[webView URL] host]] && [[URL path] isEqual:[[webView URL] path]]) { decisionHandler(WKNavigationActionPolicyAllow); return; }
        decisionHandler(WKNavigationActionPolicyCancel); return;
    }
    BOOL internalDocument = ![URL scheme] || [scheme isEqual:@"about"] || [scheme isEqual:@"nvalt-asset"];
    decisionHandler(internalDocument && [action targetFrame] && [[action targetFrame] isMainFrame] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features { return nil; }
- (IBAction)performFindPanelAction:(id)sender {
    if (_closed || _loading || _renderError || !_renderResult) return;
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : NSFindPanelActionShowFindPanel;
    if (tag == NSFindPanelActionNext || tag == NSFindPanelActionPrevious) { [self findNext:sender]; return; }
    if (tag == NSFindPanelActionSetFindString) {
        NSUInteger generation = _requestGeneration;
        [_webView evaluateJavaScript:@"window.getSelection().toString()" completionHandler:^(id value, NSError *error) {
            if (_closed || generation != _requestGeneration) return;
            if (![value isKindOfClass:[NSString class]] || ![value length]) { NSBeep(); return; }
            [_findField setStringValue:value]; [_displayState setObject:value forKey:@"find"];
            [_findField setHidden:NO]; [[_findField window] makeFirstResponder:_findField]; [_findField selectText:self];
        }];
        return;
    }
    if (tag != NSFindPanelActionShowFindPanel) return;
    [_findField setHidden:NO];
    [[_findField window] makeFirstResponder:_findField];
    [_findField selectText:self];
}
- (void)findNext:(id)sender {
    NSString *query = [_findField stringValue];
    if (![query length] || _loading) return;
    [_displayState setObject:query forKey:@"find"];
    BOOL backwards = [sender respondsToSelector:@selector(tag)] && [sender tag] == NSFindPanelActionPrevious;
    if (@available(macOS 11.0, *)) {
        WKFindConfiguration *configuration = [[[WKFindConfiguration alloc] init] autorelease];
        [configuration setBackwards:backwards]; [configuration setWraps:YES];
        [_webView findString:query withConfiguration:configuration completionHandler:^(WKFindResult *result) { if (![result matchFound]) NSBeep(); }];
    } else {
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:@[query] options:0 error:NULL];
        NSString *literal = [[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] autorelease];
        [_webView evaluateJavaScript:[NSString stringWithFormat:@"window.find((%@)[0],false,%@,true)", literal, backwards ? @"true" : @"false"] completionHandler:nil];
    }
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (control == _findField && selector == @selector(cancelOperation:)) {
        [_findField setHidden:YES]; [[_webView window] makeFirstResponder:_webView]; return YES;
    }
    return NO;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (_closed || _loading || _renderError || !_renderResult) return NO;
    SEL action = [item action];
    if (action == @selector(printPreview:)) return [[self capabilities] containsObject:@"print"];
    if (action == @selector(saveHTML:)) return YES;
    if (action == @selector(performFindPanelAction:)) {
        NSInteger tag = [item tag];
        return tag == NSFindPanelActionShowFindPanel || tag == NSFindPanelActionNext ||
            tag == NSFindPanelActionPrevious || tag == NSFindPanelActionSetFindString;
    }
    return NO;
}
- (IBAction)printPreview:(id)sender {
    if (_loading || _renderError || !_renderResult) return;
    if (@available(macOS 11.0, *)) {
        NSPrintOperation *operation = [_webView printOperationWithPrintInfo:[NSPrintInfo sharedPrintInfo]];
        [operation runOperationModalForWindow:[[self view] window] delegate:nil didRunSelector:NULL contextInfo:NULL];
    }
}
- (IBAction)saveHTML:(id)sender {
    if (_loading || _renderError || !_renderResult) return;
    // Capture the displayed result before the sheet. A later selection change
    // must not change the title or bytes being exported.
    NVMarkupRenderResult *result = [[_renderResult retain] autorelease];
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:@[@"html"]];
    [panel setNameFieldStringValue:[[[result snapshot] title] length] ? [[[result snapshot] title] stringByAppendingPathExtension:@"html"] : NSLocalizedString(@"Note.html", @"Default HTML export filename")];
    [panel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        if (![[result HTML] writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:&error]) [[NSAlert alertWithError:error] runModal];
    }];
}
- (void)dealloc {
    [self close];
    [_webView release]; [_statusField release]; [_findField release]; [_renderer release]; [_renderResult release]; [_snapshot release];
    [_renderError release]; [_viewerIdentifier release]; [_assetHandler release]; [_resourceRules release]; [_ruleError release]; [_displayState release]; [_stateCaptures release]; [_stateRevisions release]; [_captureOwner release]; [_documentBaseURL release];
    [super dealloc];
}
@end
