#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "PrefsWindowController.h"
#import "NotationPrefsViewController.h"
#import "NotationPrefs.h"
#import "PassphrasePicker.h"
#import "NoteObject.h"

static NSUInteger SWKeychainLookups;
static BOOL SWWait(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}
static NSView *SWFindView(NSView *view, Class type, NSString *title) {
    if ([view isKindOfClass:type] && (!title || [(id)view respondsToSelector:@selector(title)] && [[(id)view title] isEqual:title])) return view;
    for (NSView *child in [view subviews]) {
        NSView *found = SWFindView(child, type, title);
        if (found) return found;
    }
    return nil;
}
@implementation NotationPrefs (SWIsolatedKeychain)
- (SecKeychainItemRef)sw_noKeychainItem { SWKeychainLookups++; return NULL; }
@end
@interface SWPicker : NSObject {
@public
    NSUInteger calls;
    NSInteger storageWhenShown;
    NSWindow *shownWindow;
    id callback;
    NotationPrefs *prefs;
}
- (void)showAroundWindow:(NSWindow *)window resultDelegate:(id)delegate;
- (void)cancel;
@end
@implementation SWPicker
- (void)showAroundWindow:(NSWindow *)window resultDelegate:(id)delegate {
    calls++; shownWindow = window; callback = delegate;
    storageWhenShown = [prefs notesStorageFormat];
    NSLog(@"PICKER TEST DOUBLE: invocation %lu storage=%ld", (unsigned long)calls, (long)storageWhenShown);
}
- (void)cancel { [callback passphrasePicker:(id)self choseAPassphrase:NO]; }
@end
@implementation NotationPrefsViewController (SWMutation)
- (void)sw_dropQueuedPicker { NSLog(@"MUTATION: suppressed queued picker dispatch"); }
@end
@implementation NSPopUpButton (SWBaselineCompatibility)
- (void)sw_removeLegacyItem:(NSMenuItem *)item { [[self menu] removeItem:item]; }
@end
