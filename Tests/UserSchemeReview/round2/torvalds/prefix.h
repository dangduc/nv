#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"

static void Check(BOOL result, NSString *description);
static BOOL NVWatchResolution;
static NSUInteger NVResolutionMode, NVResolutionCalls, NVResultDeaths;
static NSAppearance *NVExpectedAppearance;
static NSColor *NVExpectedBackground;

static BOOL NVSameColor(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return a && b && fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005 &&
        fabs([a alphaComponent] - [b alphaComponent]) < .005;
}

@interface NVTrackedHighlightResult : NSDictionary {
    NSDictionary *contents;
}
@end
@implementation NVTrackedHighlightResult
- (id)init {
    if ((self = [super init])) contents = [@{NSBackgroundColorAttributeName:[NSColor redColor]} retain];
    return self;
}
- (NSUInteger)count { return [contents count]; }
- (id)objectForKey:(id)key { return [contents objectForKey:key]; }
- (NSEnumerator *)keyEnumerator { return [contents keyEnumerator]; }
- (void)dealloc { NVResultDeaths++; [contents release]; [super dealloc]; }
@end

@interface GlobalPrefs (NVTorvaldsEditorResolution)
- (NSDictionary *)nv_reviewHighlightForDarkAppearance:(BOOL)dark backgroundColor:(NSColor *)background;
@end
@implementation GlobalPrefs (NVTorvaldsEditorResolution)
- (NSDictionary *)nv_reviewHighlightForDarkAppearance:(BOOL)dark backgroundColor:(NSColor *)background {
    if (NVWatchResolution) {
        NVResolutionCalls++;
        Check([NSAppearance currentAppearance] == NVExpectedAppearance,
            @"the editor resolves preferences inside its own appearance");
        Check(dark && NVSameColor(background, NVExpectedBackground),
            @"the helper supplies its owning browser palette and resolved background");
        if (NVResolutionMode == 1) return nil;
        if (NVResolutionMode == 2) return [[[NVTrackedHighlightResult alloc] init] autorelease];
        if (NVResolutionMode == 3) [NSException raise:@"NVResolutionFailure" format:@"injected resolver failure"];
    }
    return [self nv_reviewHighlightForDarkAppearance:dark backgroundColor:background];
}
@end

@interface LinkingEditor (NVTorvaldsEditorCompatibility)
- (NSDictionary *)currentSearchHighlightAttributes;
- (NSDictionary *)nv_reviewFallbackHighlightAttributes;
@end
