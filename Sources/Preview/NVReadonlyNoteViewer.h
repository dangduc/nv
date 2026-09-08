#import <Cocoa/Cocoa.h>
@class NVNoteContentSnapshot;
typedef void (^NVReadonlyViewerStateCompletion)(NVNoteContentSnapshot *snapshot, NSString *viewerIdentifier, NSDictionary *state);

// Providers own presentation only. Native providers need not produce HTML or
// claim completion signals that their underlying framework does not expose.
@protocol NVReadonlyNoteViewer <NSObject>
- (NSView *)view;
- (NSString *)viewerIdentifier;
- (BOOL)canDisplaySnapshot:(NVNoteContentSnapshot *)snapshot;
- (NSSet *)capabilities;
- (void)displaySnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier;
- (void)cancelRendering;
- (void)close;
- (NSDictionary *)viewerState;
// Main-thread callback carries call-time identity. Active DOM capture falls back
// to immutable cached state after 0.5 seconds. A loading presentation joins its
// pending exact read without extending that deadline, or uses cache immediately.
// Every request completes once, including superseded requests. Consumers that
// save canonical state must reject callbacks from their older requests.
- (void)captureViewerStateWithCompletion:(NVReadonlyViewerStateCompletion)completion;
- (void)restoreViewerState:(NSDictionary *)state;
@optional
- (BOOL)loading;
- (NSError *)renderError;
- (IBAction)printPreview:(id)sender;
- (IBAction)saveHTML:(id)sender;
- (IBAction)performFindPanelAction:(id)sender;
@end
