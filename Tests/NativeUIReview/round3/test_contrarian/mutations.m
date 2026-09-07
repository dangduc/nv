// Review-only isolation and one fault, loaded into a disposable app copy.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "AppController.h"

static IMP OriginalSetup;
static void SkipSync(id controller, SEL selector) { }
static void RemoveListAppearance(AppController *browser, SEL selector) {
    ((void (*)(id, SEL))OriginalSetup)(browser, selector);
    NSView *list = [browser valueForKey:@"notesSubview"];
    if (!list || ![[[list appearance] name] isEqual:NSAppearanceNameAqua]) abort();
    [list setAppearance:nil];
    NSLog(@"MUTATION ACTIVATED: removed explicit Aqua appearance from notesSubview; explicit=%@", [list appearance]);
}

@interface AppController (NVRoundThreeCanary)
@end
@implementation AppController (NVRoundThreeCanary)
+ (void)load {
    const char *directory = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!directory || ![[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."] ||
        ![[[NSBundle mainBundle] bundlePath] hasPrefix:[[NSString stringWithUTF8String:directory] stringByAppendingString:@"/"]]) abort();
    Method sync = class_getInstanceMethod([NotationController class], @selector(startSyncServices));
    if (!sync) abort();
    class_replaceMethod([NotationController class], @selector(startSyncServices), (IMP)SkipSync, method_getTypeEncoding(sync));
    NSLog(@"ISOLATION: sync startup explicitly disabled; fixture disables external editor initialization");
    if (!getenv("NV_R3_REMOVE_LIST_AQUA")) return;
    Method setup = class_getInstanceMethod(self, @selector(setupBrowserContent));
    if (!setup) abort();
    OriginalSetup = method_getImplementation(setup);
    class_replaceMethod(self, @selector(setupBrowserContent), (IMP)RemoveListAppearance, method_getTypeEncoding(setup));
}
@end
