#import "AppController.h"
#import "NVBrowserSession.h"
#import "NVSearchService.h"
#import "LinkingEditor.h"

static AppController *TrackedBrowser, *TrackedPeer;
static NSUInteger FullRefreshes, DirtyRows, OriginPosts, PeerPosts, Headers, LiteralRequests;
static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}
static BOOL HasBackground(LinkingEditor *editor) {
    NSLayoutManager *layout = [editor layoutManager];
    for (NSUInteger index = 0; index < [[editor string] length];) {
        NSRange range;
        if ([layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:index effectiveRange:&range]) return YES;
        index = MAX(index + 1, NSMaxRange(range));
    }
    return NO;
}
@interface AppController (NVRefreshCounters)
- (void)nv_countList:(id)session;
- (void)nv_countRow:(NSInteger)row;
- (void)nv_countPost;
- (void)nv_countHeader;
@end
@implementation AppController (NVRefreshCounters)
- (void)nv_countList:(id)session { if (self == TrackedBrowser) FullRefreshes++; [self nv_countList:session]; }
- (void)nv_countRow:(NSInteger)row { if (self == TrackedBrowser) DirtyRows++; [self nv_countRow:row]; }
- (void)nv_countPost { if (self == TrackedBrowser) OriginPosts++; if (self == TrackedPeer) PeerPosts++; [self nv_countPost]; }
- (void)nv_countHeader { if (self == TrackedBrowser || self == TrackedPeer) Headers++; [self nv_countHeader]; }
@end
@interface NVSearchService (NVRefreshCounters)
- (void)nv_countLiteral:(NSString *)source matchingSource:(NSString *)matching query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion;
@end
@implementation NVSearchService (NVRefreshCounters)
- (void)nv_countLiteral:(NSString *)source matchingSource:(NSString *)matching query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion {
    LiteralRequests++;
    [self nv_countLiteral:source matchingSource:matching query:query owner:owner completion:completion];
}
@end
