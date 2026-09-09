#import <Cocoa/Cocoa.h>
#import "PrefsWindowController.h"
#import "LinkingEditor.h"
#import <objc/runtime.h>

@interface LinkingEditor (LuuScopedPublicationControl)
- (void)luu_scopedSetSearchHighlightRanges:(NSArray *)ranges;
@end
@implementation LinkingEditor (LuuScopedPublicationControl)
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY") || !getenv("LUU_SCOPED_HIGHLIGHT_CONTROL")) return;
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(setSearchHighlightRanges:)),
        class_getInstanceMethod(self, @selector(luu_scopedSetSearchHighlightRanges:)));
}
- (void)luu_scopedSetSearchHighlightRanges:(NSArray *)ranges {
    if (@available(macOS 11.0, *)) [[self effectiveAppearance] performAsCurrentDrawingAppearance:^{
        [self luu_scopedSetSearchHighlightRanges:ranges];
    }];
}
@end

#import "../../../Regression/user-schemes/dynamic-colors.h"
