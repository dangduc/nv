#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVSearchService.h"

// Hold the real worker's completed values immediately before browser delivery.
// The test controls delivery order without replacing matching or note creation.
@interface NVHeldNewNoteDelivery : NSObject {
@public
    NVSearchCompletion callback;
    NVSearchResult *result;
    NSError *error;
}
- (void)deliver;
@end
@implementation NVHeldNewNoteDelivery
- (void)deliver { callback(result, error); }
- (void)dealloc { [callback release]; [result release]; [error release]; [super dealloc]; }
@end

static NSMutableArray *HeldNewNoteDeliveries;
static IMP OriginalNewNoteRequest;
static IMP NewNoteRequestGate;
static void InstallNewNoteDeliveryGate(void) {
    HeldNewNoteDeliveries = [NSMutableArray new];
    Method method = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
    OriginalNewNoteRequest = method_getImplementation(method);
    NewNoteRequestGate = imp_implementationWithBlock(^NSUInteger(NVSearchService *service, id owner, NSString *query, NVSearchCompletion completion) {
        NVSearchCompletion delivery = completion;
        if ([query hasPrefix:@"held-"]) {
            delivery = [[^(NVSearchResult *value, NSError *failure) {
                NVHeldNewNoteDelivery *held = [[[NVHeldNewNoteDelivery alloc] init] autorelease];
                held->callback = [completion copy];
                held->result = [value retain];
                held->error = [failure retain];
                [HeldNewNoteDeliveries addObject:held];
            } copy] autorelease];
        }
        return ((NSUInteger (*)(id, SEL, id, id, id))OriginalNewNoteRequest)(service,
            @selector(requestForOwner:query:completion:), owner, query, delivery);
    });
    method_setImplementation(method, NewNoteRequestGate);
}
static void RemoveNewNoteDeliveryGate(void) {
    Method method = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
    method_setImplementation(method, OriginalNewNoteRequest);
    imp_removeBlock(NewNoteRequestGate);
    [HeldNewNoteDeliveries release]; HeldNewNoteDeliveries = nil;
}
