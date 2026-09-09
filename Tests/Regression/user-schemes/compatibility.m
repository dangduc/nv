// The runner inserts the production method. Only its availability expression
// changes for runtime simulation of the pre-macOS 11 branch on a current host.
#import <Cocoa/Cocoa.h>

static NSUInteger Checks;
static BOOL NVUseModernAppearanceAPI;
static void Check(BOOL passed, NSString *message) {
    if (!passed) { NSLog(@"FAIL: %@", message); exit(1); }
    Checks++; NSLog(@"PASS: %@", message);
}

@interface NVCompatibilityPrefs : NSObject
@end
@implementation NVCompatibilityPrefs
- (NSColor *)foregroundTextColor { return [NSColor blackColor]; }
- (NSColor *)backgroundTextColor { return [NSColor whiteColor]; }
- (NSColor *)darkForegroundTextColor { return [NSColor whiteColor]; }
- (NSColor *)darkBackgroundTextColor { return [NSColor blackColor]; }
@end

@interface NVCompatibilityWindow : NSObject
@property (retain) NSAppearance *appearance;
@end
@implementation NVCompatibilityWindow
@synthesize appearance;
- (NSAppearance *)effectiveAppearance { return appearance; }
- (void)dealloc { [appearance release]; [super dealloc]; }
@end

@interface NVCompatibilityTable : NSObject
@property NSUInteger invalidations;
@end
@implementation NVCompatibilityTable
@synthesize invalidations;
- (void)setNeedsDisplay:(BOOL)value { if (value) invalidations++; }
@end

@interface NVCompatibilityBrowser : NSObject {
@public
    BOOL awakenedViews;
    NSInteger userScheme;
    NVCompatibilityWindow *window;
    NVCompatibilityPrefs *prefsController;
    NVCompatibilityTable *notesTableView;
    BOOL useDarkPalette;
    BOOL throwDuringUpdate;
    NSUInteger updates;
    NSColor *storedForeground;
    NSColor *storedBackground;
}
- (void)browserAppearanceChanged;
@end
@implementation NVCompatibilityBrowser
- (id)init {
    if ((self = [super init])) {
        awakenedViews = YES;
        userScheme = 2;
        window = [NVCompatibilityWindow new];
        prefsController = [NVCompatibilityPrefs new];
        notesTableView = [NVCompatibilityTable new];
    }
    return self;
}
- (BOOL)usesDarkUserColorScheme { return userScheme == 2 && useDarkPalette; }
- (void)setForegrndColor:(NSColor *)color { [color retain]; [storedForeground release]; storedForeground = color; }
- (void)setBackgrndColor:(NSColor *)color { [color retain]; [storedBackground release]; storedBackground = color; }
- (void)updateColorScheme {
    updates++;
    Check([NSAppearance currentAppearance] == [window effectiveAppearance],
        @"the fallback applies the owning browser appearance during color update");
    if (throwDuringUpdate) [NSException raise:@"NVCompatibilityUpdateFailure" format:@"injected update failure"];
}
#include "appearance.inc"
- (void)dealloc {
    [window release]; [prefsController release]; [notesTableView release];
    [storedForeground release]; [storedBackground release]; [super dealloc];
}
@end

int main(void) {
    @autoreleasepool {
        // This host runs native AppKit but forces the old availability branch.
        if (@available(macOS 11.0, *)) {
            NVCompatibilityBrowser *browser = [[[NVCompatibilityBrowser alloc] init] autorelease];
            NSAppearance *previous = [[NSAppearance currentAppearance] retain];
            NSAppearance *sentinel = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            NSAppearance *owningAppearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            Check(sentinel != nil && owningAppearance != nil && sentinel != owningAppearance,
                @"the fixture has distinct native appearances");
            NVUseModernAppearanceAPI = NO;
            [browser->window setAppearance:owningAppearance];
            [NSAppearance setCurrentAppearance:sentinel];
            for (NSUInteger scheme = 2; scheme <= 3; scheme++) {
                browser->userScheme = scheme;
                browser->useDarkPalette = YES;
                @autoreleasepool { [browser browserAppearanceChanged]; }
                Check([NSAppearance currentAppearance] == sentinel,
                    @"a successful User or System update restores the previous appearance");
                Check(browser->storedForeground != nil && browser->storedBackground != nil,
                    @"the update retains both resolved colors beyond the callback pool");
                browser->throwDuringUpdate = YES;
                NSException *caught = nil;
                @try { [browser browserAppearanceChanged]; }
                @catch (NSException *exception) { caught = exception; }
                Check([[caught name] isEqual:@"NVCompatibilityUpdateFailure"],
                    @"the injected update exception reaches the caller");
                Check([NSAppearance currentAppearance] == sentinel,
                    @"a failed User or System update still restores the previous appearance");
                browser->throwDuringUpdate = NO;
            }
            NSUInteger updates = browser->updates;
            for (NSUInteger scheme = 0; scheme < 2; scheme++) {
                browser->userScheme = scheme;
                [browser browserAppearanceChanged];
                Check(browser->updates == updates && [NSAppearance currentAppearance] == sentinel,
                    @"fixed schemes do not enter the appearance scope");
            }
            Check([browser->notesTableView invalidations] == 4,
                @"successful updates invalidate the notes table and failures propagate before invalidation");
            [NSAppearance setCurrentAppearance:previous];
            [previous release];
            NSLog(@"APPEARANCE COMPATIBILITY PASSED (%lu checks)", (unsigned long)Checks);
            return 0;
        }
        NSLog(@"This simulation requires a macOS 11 or later host.");
        return 77;
    }
}
