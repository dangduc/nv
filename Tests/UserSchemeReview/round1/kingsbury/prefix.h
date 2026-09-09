#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVSearchService.h"
#import "LinkingEditor.h"

@interface NVSchemeDelivery : NSObject {
@public
    id owner;
    NVSearchLiteralRangesCompletion callback;
    NSArray *ranges;
    NSString *source;
    NSError *error;
}
- (void)deliver;
@end
@implementation NVSchemeDelivery
- (void)deliver { callback(ranges, source, error); }
- (void)dealloc {
    [owner release]; [callback release]; [ranges release]; [source release]; [error release];
    [super dealloc];
}
@end
static NSMutableArray *Deliveries;
static NSMapTable *Applied;
static IMP OriginalLiteral, OriginalValidation, OriginalApply;
static NVSearchLiteralRangesCompletion GateCompletion(id requestOwner, NVSearchLiteralRangesCompletion completion) {
    return [[^(NSArray *ranges, NSString *source, NSError *error) {
        NVSchemeDelivery *delivery = [[[NVSchemeDelivery alloc] init] autorelease];
        delivery->owner = [requestOwner retain];
        delivery->callback = [completion copy];
        delivery->ranges = [ranges copy]; delivery->source = [source copy]; delivery->error = [error retain];
        [Deliveries addObject:delivery];
    } copy] autorelease];
}
static void InstallSchemeGate(void) {
    Deliveries = [NSMutableArray new];
    Applied = [[NSMapTable strongToStrongObjectsMapTable] retain];
    SEL literal = @selector(requestLiteralRangesInSource:matchingSource:query:owner:completion:);
    SEL validate = @selector(validateSourceRanges:source:matchingSource:owner:completion:);
    Method method = class_getInstanceMethod([NVSearchService class], literal);
    OriginalLiteral = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^(id service, NSString *source, NSString *displayed,
        NSString *query, id owner, NVSearchLiteralRangesCompletion completion) {
        ((void (*)(id, SEL, id, id, id, id, id))OriginalLiteral)(service, literal,
            source, displayed, query, owner, GateCompletion(owner, completion));
    }));
    method = class_getInstanceMethod([NVSearchService class], validate);
    OriginalValidation = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^(id service, NSArray *ranges, NSString *source,
        NSString *displayed, id owner, NVSearchLiteralRangesCompletion completion) {
        ((void (*)(id, SEL, id, id, id, id, id))OriginalValidation)(service, validate,
            ranges, source, displayed, owner, GateCompletion(owner, completion));
    }));
    method = class_getInstanceMethod([LinkingEditor class], @selector(setSearchHighlightRanges:));
    OriginalApply = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^(id editor, NSArray *ranges) {
        [Applied setObject:@([[Applied objectForKey:editor] unsignedIntegerValue] + 1) forKey:editor];
        ((void (*)(id, SEL, id))OriginalApply)(editor, @selector(setSearchHighlightRanges:), ranges);
    }));
}
static NSColor *C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}
static BOOL Same(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return a && b && fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005 &&
        fabs([a alphaComponent] - [b alphaComponent]) < .005;
}
static NSColor *Blend(NSColor *highlight, NSColor *background) {
    CGFloat a = [highlight alphaComponent];
    return C([highlight redComponent] * a + [background redComponent] * (1-a),
        [highlight greenComponent] * a + [background greenComponent] * (1-a),
        [highlight blueComponent] * a + [background blueComponent] * (1-a), 1);
}
