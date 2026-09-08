#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "PreviewController.h"

static NSUInteger ProviderInitializations;
static NSUInteger ProviderViewLoads;
static NSUInteger ProviderCloses;

@interface PreviewController (NVMinimalRoundTwo)
- (id)nv_minimal_init;
- (void)nv_minimal_loadView;
- (void)nv_minimal_close;
@end
@implementation PreviewController (NVMinimalRoundTwo)
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(init)), class_getInstanceMethod(self, @selector(nv_minimal_init)));
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(loadView)), class_getInstanceMethod(self, @selector(nv_minimal_loadView)));
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(close)), class_getInstanceMethod(self, @selector(nv_minimal_close)));
}
- (id)nv_minimal_init { ProviderInitializations++; return [self nv_minimal_init]; }
- (void)nv_minimal_loadView { ProviderViewLoads++; [self nv_minimal_loadView]; }
- (void)nv_minimal_close { ProviderCloses++; [self nv_minimal_close]; }
@end
