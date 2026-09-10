#import "NotationPrefs.h"
#import "NVSourceHighlighter.h"

@interface ReviewPrefsOwner : NSObject {
@public
    NotationPrefs *prefs;
}
@end
@implementation ReviewPrefsOwner
- (NotationPrefs *)notationPrefs { return prefs; }
@end

static void CollectSourceMenus(NSMenu *menu, NSMutableArray *menus) {
    BOOL hasSyntax = NO;
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == @selector(selectSourceSyntax:)) hasSyntax = YES;
        if ([item submenu]) CollectSourceMenus([item submenu], menus);
    }
    if (hasSyntax) [menus addObject:menu];
}
