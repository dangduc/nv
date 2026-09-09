#import <Cocoa/Cocoa.h>

static NSColor *KColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}
static BOOL KSameColor(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return a && b && fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005 &&
        fabs([a alphaComponent] - [b alphaComponent]) < .005;
}
static NSArray *KPersistedKeys(void) {
    return @[@"ForegroundTextColor", @"BackgroundTextColor", @"SearchTermHighlightColor",
        @"DarkBackgroundTextColor", @"DarkSearchTermHighlightColor"];
}
