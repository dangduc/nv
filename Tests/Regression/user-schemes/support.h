#import <Cocoa/Cocoa.h>
#import "PrefsWindowController.h"

static NSColor *SchemeColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}
static NSColor *LegacyForeground(void) { return SchemeColor(.14, .19, .23, 1); }
static NSColor *LegacyBackground(void) { return SchemeColor(.93, .96, 1, 1); }
static NSColor *LegacyHighlight(void) { return SchemeColor(1, .2, .1, .25); }
static NSArray *FinalLightColors(void) {
    return @[SchemeColor(.2, .1, .05, 1), SchemeColor(.9, .92, .95, 1), SchemeColor(.2, .8, .4, .5)];
}
static NSArray *FinalDarkColors(void) {
    return @[SchemeColor(.8, .9, 1, 1), SchemeColor(.03, .08, .13, 1), SchemeColor(.9, .3, .1, .5)];
}
static BOOL SameSchemeColor(NSColor *first, NSColor *second) {
    first = [first colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    second = [second colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!first || !second) return NO;
    return fabs([first redComponent] - [second redComponent]) < .005 &&
        fabs([first greenComponent] - [second greenComponent]) < .005 &&
        fabs([first blueComponent] - [second blueComponent]) < .005 &&
        fabs([first alphaComponent] - [second alphaComponent]) < .005;
}
static NSColor *ExpectedHighlight(NSColor *raw, NSColor *background) {
    raw = [raw colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    background = [background colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    CGFloat alpha = [raw alphaComponent];
    return SchemeColor([raw redComponent] * alpha + [background redComponent] * (1 - alpha),
        [raw greenComponent] * alpha + [background greenComponent] * (1 - alpha),
        [raw blueComponent] * alpha + [background blueComponent] * (1 - alpha), 1);
}

// Seed an existing installation before the application loads its preferences.
// These are the three keys shipped before the separate dark palette existed.
@interface NVUserSchemeSeed : NSObject
@end
@implementation NVUserSchemeSeed
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY") || atoi(getenv("NV_REVIEW_PHASE") ?: "0") != 1) return;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[NSArchiver archivedDataWithRootObject:LegacyForeground()] forKey:@"ForegroundTextColor"];
    [defaults setObject:[NSArchiver archivedDataWithRootObject:LegacyBackground()] forKey:@"BackgroundTextColor"];
    [defaults setObject:[NSArchiver archivedDataWithRootObject:LegacyHighlight()] forKey:@"SearchTermHighlightColor"];
    [defaults setInteger:2 forKey:@"ColorScheme"];
    [defaults synchronize];
    [pool drain];
}
@end

static NSUInteger SchemeUndoCallbacks;
@interface NVUserSchemeUndoSentinel : NSObject
- (void)mark;
@end
@implementation NVUserSchemeUndoSentinel
- (void)mark { SchemeUndoCallbacks++; }
@end
