// Production pane and native AppKit field editors, with the reusable fake coordinator.
#define main ExistingPreferenceSuiteMain
#include "../../../BackupPreferences/preferences.m"
#undef main

static NSUInteger checks;
static BOOL expectFixed;
static void Assert(BOOL condition, NSString *message) { checks++; Check(condition, message); }

@interface ClosePrefs : NSObject
- (void)synchronize;
@end
@implementation ClosePrefs
- (void)synchronize {}
@end
@interface CloseOwner : NSObject <NSWindowDelegate> {
    ClosePrefs *prefsController;
    NSWindow *window;
}
- (id)initWithWindow:(NSWindow *)value;
@end
@implementation CloseOwner
- (id)initWithWindow:(NSWindow *)value { if ((self = [super init])) { prefsController = [ClosePrefs new]; window = value; } return self; }
// Exact method from PrefsWindowController.m, supplied by the runner.
#include "close-owner.inc"
- (void)dealloc { [NSObject cancelPreviousPerformRequestsWithTarget:prefsController]; [prefsController release]; [super dealloc]; }
@end

static void ExerciseLifetime(BOOL busy, BOOL closeWindow) {
    fakeBackup = [NVBackupController new];
    NVBackupPreferencesViewController *pane = [NVBackupPreferencesViewController new];
    NSView *view = [pane view];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:[view bounds]
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setContentView:view];
    CloseOwner *owner = [[CloseOwner alloc] initWithWindow:window];
    [window setDelegate:owner];
    if (closeWindow) [window makeKeyAndOrderFront:nil];
    NSTextField *recent = [pane valueForKey:@"recentField"];
    NativeEdit(pane, @"recentField", @"321");
    if (busy) SetBusy(pane, YES);
    if (closeWindow) {
        [window performClose:nil];
        Assert(![window isVisible], @"Native close button action closes the visible window");
    }
    else {
        // PrefsWindowController.switchViews: replaces the content view twice.
        NSView *blank = [[[NSView alloc] initWithFrame:[view bounds]] autorelease];
        [window setContentView:blank];
    }
    NSLog(@"OBSERVE: %@ %@: editor=%d, saved=%@, drafts=%@, deferred=%@", busy ? @"busy" : @"idle",
        closeWindow ? @"window-close" : @"pane-switch", [recent currentEditor] != nil,
        [[fakeBackup settings] objectForKey:@"recent"], [pane valueForKey:@"pendingFieldValues"], [pane valueForKey:@"commitFieldsWhenIdle"]);
    if (busy) SetBusy(pane, NO);
    [window setContentView:view];
    [pane refreshControls];
    if (closeWindow && !expectFixed) {
        Assert([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 96 && [recent currentEditor] != nil,
            @"REPRODUCED: closed window keeps edit active and policy unsaved even after idle");
        [window makeFirstResponder:nil];
        Assert([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 321, @"Ending the retained editor commits the pending policy");
    } else {
        Assert([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 321,
            [NSString stringWithFormat:@"%@ %@ commits valid draft by idle", busy ? @"busy" : @"idle", closeWindow ? @"close" : @"pane switch"]);
    }
    Assert([[recent stringValue] isEqualToString:@"321"], @"Reattached pane displays committed value");
    [window setDelegate:nil]; [owner release];
    [window setContentView:nil]; [window close]; [window release];
    [pane release]; [fakeBackup release]; fakeBackup = nil;
}

static void ExerciseDraftAtomicity(void) {
    fakeBackup = [NVBackupController new];
    NVBackupPreferencesViewController *pane = [NVBackupPreferencesViewController new];
    NSView *view = [pane view];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:[view bounds]
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO]; [window setContentView:view];
    SetBusy(pane, YES);
    NativeEdit(pane, @"recentField", @"322");
    NativeEdit(pane, @"dailyField", @"invalid");
    [window makeFirstResponder:nil];
    NSUInteger errorsBefore = errorCount;
    SetBusy(pane, NO);
    Assert(errorCount == errorsBefore + 1, @"Deferred invalid policy produces one error");
    Assert([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 96 &&
        [[[fakeBackup settings] objectForKey:@"daily"] integerValue] == 30, @"Failed policy commit leaves all settings unchanged");
    Assert([[[pane valueForKey:@"recentField"] stringValue] isEqualToString:@"322"] &&
        [[[pane valueForKey:@"dailyField"] stringValue] isEqualToString:@"invalid"], @"Failed policy commit preserves both drafts");
    NativeEdit(pane, @"dailyField", @"46");
    [window makeFirstResponder:nil];
    Assert([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 322 &&
        [[[fakeBackup settings] objectForKey:@"daily"] integerValue] == 46, @"Corrected draft commits the complete policy");
    Assert([[pane valueForKey:@"pendingFieldValues"] count] == 0, @"Successful policy commit clears all stored drafts");
    [window setContentView:nil]; [window close]; [window release];
    [pane release]; [fakeBackup release]; fakeBackup = nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [ProbeApplication sharedApplication];
        expectFixed = argc > 1 && strcmp(argv[1], "--expect-fixed") == 0;
        ExerciseLifetime(NO, NO);
        ExerciseLifetime(YES, NO);
        ExerciseLifetime(NO, YES);
        ExerciseLifetime(YES, YES);
        ExerciseDraftAtomicity();
        printf("PASS: %lu pane lifetime and policy-atomicity assertions\n", (unsigned long)checks);
    }
    return 0;
}
