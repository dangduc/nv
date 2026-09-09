#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

// Witnesses hold names only. They never retain the object under observation.
static NSMutableDictionary *NVReviewDeaths;
static char NVReviewWitnessKey, NVReviewCycleKey;
@interface NVReviewDeathWitness : NSObject { NSString *name; }
- (id)initWithName:(NSString *)value;
@end
@implementation NVReviewDeathWitness
- (id)initWithName:(NSString *)value {
    if ((self = [super init])) name = [value copy];
    return self;
}
- (void)dealloc {
    NSUInteger count = [[NVReviewDeaths objectForKey:name] unsignedIntegerValue];
    [NVReviewDeaths setObject:@(count + 1) forKey:name];
    [name release]; [super dealloc];
}
@end
static void NVReviewObserve(id object, NSString *name) {
    NVReviewDeathWitness *witness = [[NVReviewDeathWitness alloc] initWithName:name];
    objc_setAssociatedObject(object, &NVReviewWitnessKey, witness, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [witness release];
}
