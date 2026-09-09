#import <Cocoa/Cocoa.h>
#import "NVSearchService.h"
#import "AppController.h"

@interface AppController (SummaryReviewPrivate)
- (void)showSearchProgress;
@end

// Explicit event expectations; no expected value is copied from the status UI.
typedef struct {
    NSString *query, *mode, *title, *status;
    BOOL current, retryVisible;
} SummaryState;
@interface SummaryDelivery : NSObject {
@public NVSearchCompletion completion; NVSearchResult *result; NSError *error;
}
- (void)deliver;
- (void)fail;
@end
@implementation SummaryDelivery
- (void)deliver { completion(result, error); }
- (void)fail { completion(nil, [NSError errorWithDomain:@"SummaryReview" code:1
    userInfo:@{NSLocalizedDescriptionKey:@"Controlled search failure"}]); }
- (void)dealloc { [completion release]; [result release]; [error release]; [super dealloc]; }
@end
static NSMutableArray *SummaryDeliveries;
