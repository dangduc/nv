#import <Cocoa/Cocoa.h>
#import "AppController.h"
#import <objc/runtime.h>

static void Check(BOOL result, NSString *description);
static AppController *OUOuter, *OUInner;
static BOOL OUWatching, OUThrowInner;
static NSUInteger OUOuterCalls, OUInnerCalls;

static BOOL OUSameColor(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return a && b && fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005;
}

@interface AppController (OUScopeReview)
- (void)nv_ouScopedUpdate;
- (void)nv_ouFallbackAppearanceChanged;
@end
@implementation AppController (OUScopeReview)
- (void)nv_ouScopedUpdate {
    if (OUWatching && (self == OUOuter || self == OUInner)) {
        Check([NSAppearance currentAppearance] == [[self window] effectiveAppearance],
            @"the native browser update runs within its own appearance scope");
        if (self == OUOuter) {
            OUOuterCalls++;
            [OUInner browserAppearanceChanged];
            Check([NSAppearance currentAppearance] == [[self window] effectiveAppearance],
                @"the nested browser restores the outer browser appearance before its real update");
        } else {
            OUInnerCalls++;
            if (OUThrowInner) [NSException raise:@"OUNestedAppearanceFailure" format:@"injected nested update failure"];
        }
    }
    [self nv_ouScopedUpdate];
}
@end
