#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "NVReadonlyNoteViewer.h"
#import "NVNoteContentSnapshot.h"
@class NVMarkupRenderer, NVMarkupRenderResult, NVScopedAssetHandler, NVViewerCaptureOwner;

// One browser owns this inline provider. It never reads browser selection,
// mutable note objects, global preview preferences, or application delegates.
@interface PreviewController : NSViewController <NVReadonlyNoteViewer, WKNavigationDelegate, WKUIDelegate, NSSearchFieldDelegate> {
    WKWebView *_webView;
    NSTextField *_statusField;
    NSSearchField *_findField;
    NVMarkupRenderer *_renderer;
    NSOperation *_renderOperation;
    NVMarkupRenderResult *_renderResult;
    NVNoteContentSnapshot *_snapshot;
    NSError *_renderError;
    NSString *_viewerIdentifier;
    NVScopedAssetHandler *_assetHandler;
    WKContentRuleList *_resourceRules;
    NSError *_ruleError;
    WKNavigation *_navigation;
    NSUInteger _requestGeneration;
    BOOL _loading;
    BOOL _closed;
    BOOL _rulesReady;
    NSMutableDictionary *_displayState;
    NSTimer *_stateTimer;
    NSMutableSet *_stateCaptures;
    NSMutableDictionary *_stateRevisions;
    NSUInteger _nextStateRevision;
    NVViewerCaptureOwner *_captureOwner;
    NSURL *_documentBaseURL;
}
@property (readonly, retain) WKWebView *webView;
@property (readonly, retain) NVNoteContentSnapshot *snapshot;
@property (readonly, copy) NSString *viewerIdentifier;
@property (readonly, copy) NSString *renderedHTML;
@property (readonly) BOOL loading;
@property (readonly, retain) NSError *renderError;
- (void)displaySnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier;
- (void)cancelRendering;
- (void)close;
- (NSDictionary *)viewerState;
- (void)captureViewerStateWithCompletion:(NVReadonlyViewerStateCompletion)completion;
- (BOOL)hasPendingViewerStateCaptureForSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier;
- (void)restoreViewerState:(NSDictionary *)state;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (IBAction)printPreview:(id)sender;
- (IBAction)saveHTML:(id)sender;
- (IBAction)performFindPanelAction:(id)sender;
@end
