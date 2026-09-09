#import <Cocoa/Cocoa.h>

// Real AppKit field/window lifecycle supporting the deterministic intent trace.
// Uses one short-lived window. No user defaults or notes storage is opened.
@interface FocusProbe : NSObject <NSSearchFieldDelegate, NSWindowDelegate> {
@public NSWindow *window; NSSearchField *field; NSUInteger ended, resigned;
}
- (BOOL)searchFieldHasFocus;
@end
@implementation FocusProbe
#include "focus-method.inc"
- (void)controlTextDidEndEditing:(NSNotification *)notification { ended++; }
- (void)windowDidResignKey:(NSNotification *)notification { resigned++; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRunningApplication *previous = [[[NSWorkspace sharedWorkspace] frontmostApplication] retain];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        FocusProbe *probe = [[FocusProbe alloc] init];
        NSRect frame = NSMakeRect(0, 0, 360, 120);
        probe->window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [probe->window setReleasedWhenClosed:NO]; [probe->window setDelegate:probe];
        probe->field = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, 60, 300, 24)];
        [probe->field setStringValue:@"waiting-zero"]; [probe->field setDelegate:probe];
        [[probe->window contentView] addSubview:probe->field];
        [probe->window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (![probe->window isKeyWindow] && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:.02]
                                                  inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event) [NSApp sendEvent:event];
        }
        BOOL accepted = [probe->window makeFirstResponder:probe->field];
        BOOL keyBefore = [probe->window isKeyWindow], focusBefore = [probe searchFieldHasFocus];
        id editor = [probe->field currentEditor];
        NSUInteger endedBefore = probe->ended, resignedBefore = probe->resigned;
        [probe->window resignKeyWindow];
        BOOL keyAfter = [probe->window isKeyWindow], focusAfter = [probe searchFieldHasFocus];
        printf("APPKIT_FOCUS accepted=%d key_before=%d focus_before=%d key_after=%d focus_after=%d same_editor=%d text_end_delta=%lu resign_delta=%lu\n",
               accepted, keyBefore, focusBefore, keyAfter, focusAfter, [probe->field currentEditor] == editor,
               (unsigned long)(probe->ended - endedBefore), (unsigned long)(probe->resigned - resignedBefore));
        BOOL reproduced = accepted && keyBefore && focusBefore && !keyAfter && focusAfter &&
                          [probe->field currentEditor] == editor && probe->ended == endedBefore && probe->resigned == resignedBefore + 1;
        [probe->window setDelegate:nil]; [probe->field setDelegate:nil];
        [probe->window close]; [probe->field release]; [probe->window release]; [probe release];
        [previous activateWithOptions:NSApplicationActivateIgnoringOtherApps]; [previous release];
        return reproduced ? 0 : 1;
    }
}
