// Test-only behavior removal. Never linked into the shipping app.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "AppController.h"

@interface AppController (NVQueryRestorationMutation)
- (void)nv_restoreWithMutation:(NSDictionary *)state;
@end
@implementation AppController (NVQueryRestorationMutation)
+ (void)load {
    if (!getenv("NV_RESTORE_MUTATION")) return;
    const char *root = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!root || ![[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."] ||
        ![[[NSBundle mainBundle] bundlePath] hasPrefix:[[NSString stringWithUTF8String:root] stringByAppendingString:@"/"]]) abort();
    Method original = class_getInstanceMethod(self, @selector(restoreBrowserWindowState:));
    Method replacement = class_getInstanceMethod(self, @selector(nv_restoreWithMutation:));
    if (!original || !replacement || strcmp(method_getTypeEncoding(original), method_getTypeEncoding(replacement))) abort();
    method_exchangeImplementations(original, replacement);
}
- (void)nv_restoreWithMutation:(NSDictionary *)state {
    NSMutableDictionary *mutated = [[state mutableCopy] autorelease];
    NSString *key = strcmp(getenv("NV_RESTORE_MUTATION"), "sort") == 0 ? @"reverse" : @"search";
    NSLog(@"MUTATION: discarding saved %@ = %@", key, [mutated objectForKey:key]);
    [mutated removeObjectForKey:key];
    [self nv_restoreWithMutation:mutated];
}
@end
