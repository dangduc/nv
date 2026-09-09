#import <Cocoa/Cocoa.h>

@interface FocusProbe : NSObject <NSSearchFieldDelegate, NSWindowDelegate> {
@public NSWindow *window; NSSearchField *field;
    BOOL searchAutocompletePending; NSString *pendingSearchReturnQuery;
    NSDictionary *pendingSearchReveal, *pendingSearchRestoration;
}
- (BOOL)searchFieldHasFocus;
- (void)cancelTransientSearchIntents;
- (void)windowDidResignKey:(NSNotification *)notification;
@end
@implementation FocusProbe
#include "focus-methods.inc"
@end

static BOOL PumpUntil(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:.02]
                                              inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event) [NSApp sendEvent:event];
    }
    return condition();
}
static void Arm(FocusProbe *probe) {
    [probe->pendingSearchReturnQuery release]; probe->pendingSearchReturnQuery = [@"pending-zero" copy];
    probe->searchAutocompletePending = YES;
}
static void PrintState(const char *name, FocusProbe *probe, NSUInteger resignCount, NSUInteger activeLossCount) {
    printf("%s active=%d key=%d field_focus=%d pending_return=%d autocomplete=%d reveal=%d restoration=%d resign_count=%lu active_loss_count=%lu\n",
           name, [NSApp isActive], [probe->window isKeyWindow], [probe searchFieldHasFocus],
           probe->pendingSearchReturnQuery != nil, probe->searchAutocompletePending,
           probe->pendingSearchReveal != nil, probe->pendingSearchRestoration != nil,
           (unsigned long)resignCount, (unsigned long)activeLossCount);
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRunningApplication *previous = [[[NSWorkspace sharedWorkspace] frontmostApplication] retain];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp finishLaunching];
        FocusProbe *probe = [[FocusProbe alloc] init];
        probe->pendingSearchReveal = [@{@"note":@"explicit-reveal"} copy];
        probe->pendingSearchRestoration = [@{@"note":@"explicit-restoration"} copy];
        probe->window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 360, 120)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [probe->window setReleasedWhenClosed:NO]; [probe->window setDelegate:probe];
        NSWindow *peer = [[NSWindow alloc] initWithContentRect:NSMakeRect(30, 30, 260, 90)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [peer setReleasedWhenClosed:NO];
        probe->field = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, 60, 300, 24)];
        [probe->field setStringValue:@"pending-zero"]; [probe->field setDelegate:probe];
        [[probe->window contentView] addSubview:probe->field];
        __block NSUInteger resignCount = 0, activeLossCount = 0;
        id windowObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResignKeyNotification object:probe->window queue:nil
            usingBlock:^(NSNotification *note) { resignCount++; }];
        id activeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidResignActiveNotification object:NSApp queue:nil
            usingBlock:^(NSNotification *note) { activeLossCount++; }];
        [probe->window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        BOOL started = PumpUntil(^BOOL { return [NSApp isActive] && [probe->window isKeyWindow]; });
        BOOL accepted = [probe->window makeFirstResponder:probe->field]; Arm(probe);
        PrintState("APPKIT_INITIAL", probe, resignCount, activeLossCount);
        [peer makeKeyAndOrderFront:nil];
        BOOL peerActivated = PumpUntil(^BOOL { return [peer isKeyWindow] && ![probe->window isKeyWindow]; });
        PrintState("APPKIT_RESIGNED", probe, resignCount, activeLossCount);
        BOOL keyCanceled = ![probe searchFieldHasFocus] && !probe->pendingSearchReturnQuery && !probe->searchAutocompletePending &&
            probe->pendingSearchReveal && probe->pendingSearchRestoration;
        [probe->window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        BOOL reentered = PumpUntil(^BOOL { return [NSApp isActive] && [probe->window isKeyWindow]; });
        [probe->window makeFirstResponder:probe->field];
        PrintState("APPKIT_REENTERED", probe, resignCount, activeLossCount);
        BOOL stayedCanceled = !probe->pendingSearchReturnQuery && !probe->searchAutocompletePending;
        Arm(probe); BOOL activationRequested = [previous activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        BOOL deactivated = PumpUntil(^BOOL { return ![NSApp isActive] && activeLossCount > 0; });
        PrintState("APPKIT_DEACTIVATED", probe, resignCount, activeLossCount);
        printf("APPKIT_PRECONDITIONS started=%d accepted=%d peer_activated=%d reentered=%d activation_requested=%d deactivated=%d\n",
            started, accepted, peerActivated, reentered, activationRequested, deactivated);
        BOOL activationCanceled = ![probe searchFieldHasFocus] && !probe->pendingSearchReturnQuery && !probe->searchAutocompletePending &&
            probe->pendingSearchReveal && probe->pendingSearchRestoration;
        [[NSNotificationCenter defaultCenter] removeObserver:windowObserver]; [[NSNotificationCenter defaultCenter] removeObserver:activeObserver];
        [probe->window setDelegate:nil]; [probe->field setDelegate:nil]; [probe->window close]; [peer close]; [peer release];
        [probe->field release]; [probe->window release]; [probe->pendingSearchReturnQuery release];
        [probe->pendingSearchReveal release]; [probe->pendingSearchRestoration release]; [probe release];
        [previous activateWithOptions:NSApplicationActivateIgnoringOtherApps]; [previous release];
        return started && accepted && peerActivated && keyCanceled && reentered && stayedCanceled && deactivated && activationCanceled ? 0 : 1;
    }
}
