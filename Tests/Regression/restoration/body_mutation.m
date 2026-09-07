// Test-only persistence mutation. Never linked into the shipping app.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NoteObject.h"

@interface NoteObject (NVBodySerializationMutation)
- (void)nv_encodeSubstitutingBody:(NSCoder *)coder;
@end
@implementation NoteObject (NVBodySerializationMutation)
+ (void)load {
    if (!getenv("NV_BODY_MUTATION")) return;
    const char *root = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!root || ![[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."] ||
        ![[[NSBundle mainBundle] bundlePath] hasPrefix:[[NSString stringWithUTF8String:root] stringByAppendingString:@"/"]]) abort();
    Method original = class_getInstanceMethod(self, @selector(encodeWithCoder:));
    Method replacement = class_getInstanceMethod(self, @selector(nv_encodeSubstitutingBody:));
    if (!original || !replacement || strcmp(method_getTypeEncoding(original), method_getTypeEncoding(replacement))) abort();
    method_exchangeImplementations(original, replacement);
}
- (void)nv_encodeSubstitutingBody:(NSCoder *)coder {
    // Keep the live model unchanged. Only the archived body changes; its length stays equal.
    NSMutableAttributedString *original = contentString;
    NSString *replacement = [@"" stringByPaddingToLength:[original length] withString:@"x" startingAtIndex:0];
    contentString = [[NSMutableAttributedString alloc] initWithString:replacement];
    @try {
        NSLog(@"MUTATION: archiving substituted body for %@ (%lu -> %lu characters)", titleString, (unsigned long)[original length], (unsigned long)[contentString length]);
        [self nv_encodeSubstitutingBody:coder];
    } @finally {
        [contentString release];
        contentString = original;
    }
}
@end
