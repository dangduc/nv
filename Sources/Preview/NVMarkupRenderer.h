#import <Foundation/Foundation.h>
@class NVNoteContentSnapshot;

extern NSString * const NVMarkupRendererErrorDomain;
typedef NS_ENUM(NSInteger, NVMarkupRendererErrorCode) {
    NVMarkupUnsupportedContent = 1, NVMarkupHelperUnavailable, NVMarkupHelperFailed,
    NVMarkupTimedOut, NVMarkupCancelled, NVMarkupLimitExceeded, NVMarkupInvalidOutput
};

@interface NVMarkupRenderResult : NSObject {
    NVNoteContentSnapshot *_snapshot;
    NSString *_viewerIdentifier;
    NSString *_HTML;
}
@property (readonly, retain) NVNoteContentSnapshot *snapshot;
@property (readonly, copy) NSString *viewerIdentifier;
@property (readonly, copy) NSString *HTML;
- (id)initWithSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier HTML:(NSString *)HTML;
@end

typedef void (^NVMarkupRenderCompletion)(NVMarkupRenderResult *result, NSError *error);
@interface NVMarkupRenderer : NSObject {
    NSOperationQueue *_queue;
    NSBundle *_resourceBundle;
    NSTimeInterval _timeLimit;
}
- (id)initWithResourceBundle:(NSBundle *)bundle;
// The token can be cancelled from any thread. Completion runs on the main thread.
- (NSOperation *)renderSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier completion:(NVMarkupRenderCompletion)completion;
- (void)cancelAllRendering;
// Useful for bounded converter fixtures. Each submitted request captures its limit.
@property NSTimeInterval timeLimit;
@end
