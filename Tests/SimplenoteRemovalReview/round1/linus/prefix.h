#import "NotationPrefsViewController.h"

static void NVCollectViews(NSView *view, NSMutableArray *result) {
    if ([result containsObject:view]) return;
    [result addObject:view];
    for (NSView *child in [view subviews]) NVCollectViews(child, result);
    if ([view isKindOfClass:[NSTabView class]]) {
        for (NSTabViewItem *item in [(NSTabView *)view tabViewItems]) NVCollectViews([item view], result);
    }
}
