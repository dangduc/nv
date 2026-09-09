#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVSourceHighlighter.h"

static NSUInteger LuuParserCalls;
@interface NVSourceParser (LuuMeasurements)
- (NSArray *)luu_capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)generation;
@end
@implementation NVSourceParser (LuuMeasurements)
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(capturesForString:syntaxIdentifier:cancellationToken:generation:)),
        class_getInstanceMethod(self, @selector(luu_capturesForString:syntaxIdentifier:cancellationToken:generation:)));
}
- (NSArray *)luu_capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)generation {
    __atomic_add_fetch(&LuuParserCalls, 1, __ATOMIC_RELAXED);
    return [self luu_capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:generation];
}
@end

static BOOL LuuSameColor(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!a || !b) return NO;
    return fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005 &&
        fabs([a alphaComponent] - [b alphaComponent]) < .005;
}
static NSColor *LuuColor(CGFloat red, CGFloat green, CGFloat blue) {
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1];
}
