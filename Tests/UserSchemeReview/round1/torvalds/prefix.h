#import <Cocoa/Cocoa.h>

static NSArray *NVLegacyArchives;
static NSUInteger NVPreferenceCallbacks;

static BOOL NVSameRGBA(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!a || !b) return NO;
    return fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005 &&
        fabs([a alphaComponent] - [b alphaComponent]) < .005;
}

@interface NVLegacyPaletteSeed : NSObject
- (void)settingChangedForSelectorString:(NSString *)selector;
@end
@implementation NVLegacyPaletteSeed
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *colors = @[[NSColor colorWithCalibratedWhite:.23 alpha:1],
        [NSColor colorWithDeviceCyan:.02 magenta:.03 yellow:.08 black:.01 alpha:1],
        [NSColor colorWithCalibratedRed:.7 green:.2 blue:.5 alpha:.3]];
    NSMutableArray *archives = [NSMutableArray array];
    NSArray *keys = @[@"ForegroundTextColor", @"BackgroundTextColor", @"SearchTermHighlightColor"];
    for (NSUInteger i = 0; i < [keys count]; i++) {
        NSData *data = [NSArchiver archivedDataWithRootObject:colors[i]];
        [archives addObject:data];
        [defaults setObject:data forKey:keys[i]];
    }
    NVLegacyArchives = [archives copy];
    [defaults setInteger:2 forKey:@"ColorScheme"];
    [defaults synchronize];
    [pool drain];
}
- (void)settingChangedForSelectorString:(NSString *)selector { NVPreferenceCallbacks++; }
@end
