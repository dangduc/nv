#import <Cocoa/Cocoa.h>
#import "PrefsWindowController.h"

static NSColor *NVDynamicResolvedColor(NSColor *color, NSAppearance *appearance) {
    __block NSColor *resolved = nil;
    if (@available(macOS 11.0, *)) [appearance performAsCurrentDrawingAppearance:^{
        resolved = [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] retain];
    }];
    return [resolved autorelease];
}
static BOOL NVDynamicSameColor(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!a || !b) return NO;
    return fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005 &&
        fabs([a alphaComponent] - [b alphaComponent]) < .005;
}
static NSColor *NVDynamicExpectedHighlight(NSColor *raw, NSColor *background, NSAppearance *appearance) {
    NSColor *resolved = NVDynamicResolvedColor(raw, appearance);
    CGFloat alpha = [resolved alphaComponent];
    return [NSColor colorWithCalibratedRed:[resolved redComponent] * alpha + [background redComponent] * (1 - alpha)
        green:[resolved greenComponent] * alpha + [background greenComponent] * (1 - alpha)
        blue:[resolved blueComponent] * alpha + [background blueComponent] * (1 - alpha) alpha:1];
}
