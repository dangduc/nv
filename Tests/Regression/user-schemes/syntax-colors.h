#import "support.h"
#import "LinkingEditor.h"
#import "NVSourceHighlighter.h"
#import <objc/runtime.h>

@interface LinkingEditor (NVSyntaxColorChecks)
- (NSColor *)sourceColorForCapture:(NSString *)capture;
@end

static NSColor *CustomSyntaxColor(NSUInteger kind, BOOL dark) {
    return [NSColor colorWithCalibratedHue:0.04 + kind * 0.11 saturation:dark ? 0.4 : 0.8
        brightness:dark ? 0.9 : 0.45 alpha:1];
}

// AppKit can consume or discard dirty flags for occluded windows. Observe the
// redraw requests themselves while leaving their production implementation intact.
static NSMutableSet *SyntaxRedrawnEditors;
static IMP OriginalSyntaxSetNeedsDisplay;
static void ObserveSyntaxSetNeedsDisplay(id editor, SEL selector, BOOL dirty) {
    if (dirty) [SyntaxRedrawnEditors addObject:[NSValue valueWithPointer:editor]];
    ((void (*)(id, SEL, BOOL))OriginalSyntaxSetNeedsDisplay)(editor, selector, dirty);
}
@interface NVSyntaxRedrawProbe : NSObject
@end
@implementation NVSyntaxRedrawProbe
+ (void)load {
    Method method = class_getInstanceMethod([LinkingEditor class], @selector(setNeedsDisplay:));
    OriginalSyntaxSetNeedsDisplay = method_getImplementation(method);
    if (!class_addMethod([LinkingEditor class], @selector(setNeedsDisplay:), (IMP)ObserveSyntaxSetNeedsDisplay, method_getTypeEncoding(method)))
        method_setImplementation(method, (IMP)ObserveSyntaxSetNeedsDisplay);
}
@end
