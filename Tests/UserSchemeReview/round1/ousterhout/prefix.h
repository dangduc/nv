#import <Cocoa/Cocoa.h>

static NSColor *OUColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}
static BOOL OUSame(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!a || !b) return NO;
    return fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005 &&
        fabs([a alphaComponent] - [b alphaComponent]) < .005;
}
static NSColor *OUBlend(NSColor *raw, NSColor *background) {
    raw = [raw colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    background = [background colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    CGFloat a = [raw alphaComponent];
    return OUColor(a * [raw redComponent] + (1-a) * [background redComponent],
        a * [raw greenComponent] + (1-a) * [background greenComponent],
        a * [raw blueComponent] + (1-a) * [background blueComponent], 1);
}
