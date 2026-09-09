#import <Cocoa/Cocoa.h>
#import "NVSearchService.h"

// Independent model values come only from each explicit history step.
typedef struct {
    NSString *visibleQuery, *committedQuery, *mode, *selectedTitle;
    BOOL current, toolbarVisible, itemPresent, searchFocused;
} TitlebarModel;

@interface TitlebarDelivery : NSObject {
@public NVSearchCompletion completion; NVSearchResult *result; NSError *error;
}
- (void)deliver;
@end
@implementation TitlebarDelivery
- (void)deliver { completion(result, error); }
- (void)dealloc { [completion release]; [result release]; [error release]; [super dealloc]; }
@end
static NSMutableArray *TitlebarDeliveries;
