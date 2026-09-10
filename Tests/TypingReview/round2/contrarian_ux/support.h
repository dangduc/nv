#import "AppController.h"
#import "NVSourceAnalysis.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"
#import <objc/runtime.h>
static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}
static NSEvent *PopupEvent;
static id PopupCurrentEvent(id object, SEL selector) { return PopupEvent; }
static void Popup(id browser, BOOL visible) {
    PopupEvent = [NSEvent keyEventWithType:NSFlagsChanged location:NSZeroPoint modifierFlags:NSAlternateKeyMask
        timestamp:0 windowNumber:[[browser window] windowNumber] context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:58];
    Method method = class_getInstanceMethod([NSApplication class], @selector(currentEvent));
    IMP original = method_setImplementation(method, (IMP)PopupCurrentEvent);
    @try { [browser popWordCount:visible]; }
    @finally { method_setImplementation(method, original); }
}
