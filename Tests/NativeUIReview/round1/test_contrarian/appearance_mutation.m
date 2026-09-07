// Test-only mutation, loaded into a copied app with isolated preferences.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "AppController.h"

static void SkipAppearanceForwarding(id view, SEL selector) {
    void (*superImplementation)(id, SEL) = (void *)class_getMethodImplementation([NSView class], selector);
    superImplementation(view, selector);
    NSLog(@"MUTATION: omitted browser appearance forwarding");
}

@interface AppController (NVAppearanceMutation)
@end
@implementation AppController (NVAppearanceMutation)
+ (void)load {
    if (!getenv("NV_APPEARANCE_MUTATION")) return;
    const char *root = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!root || ![[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."] ||
        ![[[NSBundle mainBundle] bundlePath] hasPrefix:[[NSString stringWithUTF8String:root] stringByAppendingString:@"/"]]) abort();
    Class viewClass = NSClassFromString(@"NVBrowserContentView");
    SEL selector = @selector(viewDidChangeEffectiveAppearance);
    Method original = class_getInstanceMethod(viewClass, selector);
    if (!viewClass || !original) abort();
    class_replaceMethod(viewClass, selector, (IMP)SkipAppearanceForwarding, method_getTypeEncoding(original));
}
@end
