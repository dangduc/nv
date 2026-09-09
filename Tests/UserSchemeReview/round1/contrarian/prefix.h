#import <Cocoa/Cocoa.h>
#import "PrefsWindowController.h"
#import "GlobalPrefs.h"

static BOOL SameContrarianColor(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    b = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return a && b && fabs([a redComponent] - [b redComponent]) < .005 &&
        fabs([a greenComponent] - [b greenComponent]) < .005 &&
        fabs([a blueComponent] - [b blueComponent]) < .005;
}

static NSArray *ContrarianPalette(GlobalPrefs *prefs) {
    return @[[prefs foregroundTextColor], [prefs backgroundTextColor],
        [prefs searchTermHighlightColorRaw:YES], [prefs darkForegroundTextColor],
        [prefs darkBackgroundTextColor], [prefs darkSearchTermHighlightColor]];
}
