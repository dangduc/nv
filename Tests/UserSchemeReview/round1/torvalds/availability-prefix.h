#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static BOOL NVSimulateMissingDrawingAppearance;
@interface NSAppearance (NVUnavailableDrawingAppearance)
- (void)nv_unavailableDrawingAppearance:(void (^)(void))block;
@end
@implementation NSAppearance (NVUnavailableDrawingAppearance)
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
    Method original = class_getInstanceMethod(self, @selector(performAsCurrentDrawingAppearance:));
    Method replacement = class_getInstanceMethod(self, @selector(nv_unavailableDrawingAppearance:));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
- (void)nv_unavailableDrawingAppearance:(void (^)(void))block {
    if (NVSimulateMissingDrawingAppearance) {
        [self doesNotRecognizeSelector:@selector(performAsCurrentDrawingAppearance:)];
        return;
    }
    [self nv_unavailableDrawingAppearance:block];
}
@end
