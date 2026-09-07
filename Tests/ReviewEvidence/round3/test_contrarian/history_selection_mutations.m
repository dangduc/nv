// Test-only history and selection mutations in disposable app copies.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVNoteEditingSession.h"

@interface NVNoteEditingSession (NVAcceptanceMutations)
- (void)nv_skipHistoryFinalization;
- (void)nv_replaceWholeSnapshot:(NSAttributedString *)contents;
@end
@implementation NVNoteEditingSession (NVAcceptanceMutations)
+ (void)load {
    const char *mode = getenv("NV_ACCEPTANCE_MUTATION");
    if (!mode) return;
    const char *root = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!root || ![[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."] ||
        ![[[NSBundle mainBundle] bundlePath] hasPrefix:[[NSString stringWithUTF8String:root] stringByAppendingString:@"/"]]) abort();
    BOOL history = strcmp(mode, "history") == 0;
    if (!history && strcmp(mode, "selection") != 0) abort();
    Method original = class_getInstanceMethod(self, history ? @selector(finishEditingForHistoryChange) : @selector(applyContents:));
    Method replacement = class_getInstanceMethod(self, history ? @selector(nv_skipHistoryFinalization) : @selector(nv_replaceWholeSnapshot:));
    if (!original || !replacement || strcmp(method_getTypeEncoding(original), method_getTypeEncoding(replacement))) abort();
    method_exchangeImplementations(original, replacement);
}
- (void)nv_skipHistoryFinalization {
    NSLog(@"MUTATION: skipping marked-text finalization before history");
}
- (void)nv_replaceWholeSnapshot:(NSAttributedString *)contents {
    NSLog(@"MUTATION: replacing the whole shared text snapshot");
    [textStorage setAttributedString:contents];
}
@end
