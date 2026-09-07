// Loaded only into an isolated app copy by this directory's runner.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NoteObject.h"

static void SkipAppearanceForwarding(id view, SEL selector) {
    void (*superImplementation)(id, SEL) = (void *)class_getMethodImplementation([NSView class], selector);
    superImplementation(view, selector);
    NSLog(@"MUTATION ACTIVATED: appearance callback omitted controller forwarding");
}

// Restore the metadata implementation from the parent of 12936fed.
static void LibraryOnlyMetadataUndo(NVApplicationController *controller, SEL selector,
                                   NoteObject *note, NSString *value, BOOL isTitle) {
    NotationController *library = [controller library];
    if (![[library allNotes] containsObject:note]) return;
    NSString *oldValue = isTitle ? titleOfNote(note) : labelsOfNote(note) ?: @"";
    if ([oldValue isEqualToString:value]) return;
    NSUndoManager *undo = [library undoManager];
    [[undo prepareWithInvocationTarget:controller] setNote:note metadataValue:oldValue isTitle:isTitle];
    if (isTitle) [note setTitleString:value];
    else [note setLabelString:value];
    [undo setActionName:isTitle ? NSLocalizedString(@"Rename Note", nil) : NSLocalizedString(@"Edit Tags", nil)];
    NSLog(@"MUTATION ACTIVATED: metadata registered only with library undo manager; title=%d libraryCanUndo=%d noteCanUndo=%d",
        isTitle, [undo canUndo], [[note undoManager] canUndo]);
}

@interface AppController (NVRoundTwoCanaries)
@end
@implementation AppController (NVRoundTwoCanaries)
+ (void)load {
    const char *kind = getenv("NV_R2_FAULT");
    if (!kind) return;
    const char *directory = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!directory || ![[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."] ||
        ![[[NSBundle mainBundle] bundlePath] hasPrefix:[[NSString stringWithUTF8String:directory] stringByAppendingString:@"/"]]) abort();
    Class cls;
    SEL selector;
    IMP replacement;
    if (!strcmp(kind, "appearance")) {
        cls = NSClassFromString(@"NVBrowserContentView");
        selector = @selector(viewDidChangeEffectiveAppearance);
        replacement = (IMP)SkipAppearanceForwarding;
    } else if (!strcmp(kind, "metadata")) {
        cls = [NVApplicationController class];
        selector = @selector(setNote:metadataValue:isTitle:);
        replacement = (IMP)LibraryOnlyMetadataUndo;
    } else abort();
    Method original = class_getInstanceMethod(cls, selector);
    if (!cls || !original) abort();
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(original));
    NSLog(@"MUTATION INSTALLED: %s", kind);
}
@end
