// Production pane and native AppKit field editors, with the reusable fake coordinator.
#define main ExistingPreferenceSuiteMain
#include "../../../BackupPreferences/preferences.m"
#undef main

static NSUInteger checks;
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
    NVBackupPreferencesViewController *backupPreferencesViewController;
    NSDictionary *items;
    NSToolbar *toolbar;
}
- (id)initWithWindow:(NSWindow *)value pane:(NVBackupPreferencesViewController *)pane;
- (void)switchViews:(NSToolbarItem *)item;
@end
@implementation CloseOwner
- (id)initWithWindow:(NSWindow *)value pane:(NVBackupPreferencesViewController *)pane {
    if ((self = [super init])) {
        prefsController = [ClosePrefs new]; window = value; backupPreferencesViewController = pane;
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Backups"] autorelease];
        items = [@{@"Backups":item} retain];
        toolbar = [[NSToolbar alloc] initWithIdentifier:@"CloseProbe"];
    }
    return self;
}
- (void)switchViews:(NSToolbarItem *)item {
    Assert([[item itemIdentifier] isEqual:@"Backups"], @"Invalid close selects the Backups pane");
    [backupPreferencesViewController refreshControls];
    [window setContentView:[[[NSView alloc] initWithFrame:[[window contentView] bounds]] autorelease]];
    [window setContentView:[backupPreferencesViewController view]];
}
// Exact method from PrefsWindowController.m, supplied by the runner.
#include "close-owner.inc"
- (void)dealloc { [NSObject cancelPreviousPerformRequestsWithTarget:prefsController]; [prefsController release]; [items release]; [toolbar release]; [super dealloc]; }
@end

static void ExerciseLifetime(BOOL busy, BOOL closeWindow) {
    fakeBackup = [NVBackupController new];
    NVBackupPreferencesViewController *pane = [NVBackupPreferencesViewController new];
    NSView *view = [pane view];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:[view bounds]
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setContentView:view];
    CloseOwner *owner = [[CloseOwner alloc] initWithWindow:window pane:pane];
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
    Assert([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 321,
        [NSString stringWithFormat:@"%@ %@ commits valid draft by idle", busy ? @"busy" : @"idle", closeWindow ? @"close" : @"pane switch"]);
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
    Assert(errorCount == errorsBefore, @"Deferred invalid policy does not open an unsolicited validation dialog");
    Assert([[[pane valueForKey:@"statusField"] string] containsString:@"Backup settings were not saved."], @"Deferred invalid policy has a visible status explanation");
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

static void ExerciseInvalidClose(BOOL busy, BOOL hidden, NSString *fieldKey, NSString *input) {
    fakeBackup = [NVBackupController new];
    NVBackupPreferencesViewController *pane = [NVBackupPreferencesViewController new];
    NSView *view = [pane view];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:[view bounds]
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO]; [window setContentView:view];
    CloseOwner *owner = [[CloseOwner alloc] initWithWindow:window pane:pane];
    [window setDelegate:owner]; [window makeKeyAndOrderFront:nil];
    if (busy) SetBusy(pane, YES);
    NativeEdit(pane, fieldKey, input);
    if (hidden) [window setContentView:[[[NSView alloc] initWithFrame:[view bounds]] autorelease]];
    NSUInteger errorsBefore = errorCount;
    NSDictionary *saved = [[fakeBackup settings] copy];
    [window performClose:nil];
    NSTextField *field = [pane valueForKey:fieldKey];
    NSLog(@"INVALID CLOSE: busy=%d hidden=%d %@=%@ errors=%lu expected=%lu editor=%d", busy, hidden, fieldKey, input,
        (unsigned long)errorCount, (unsigned long)(errorsBefore + 1), [field currentEditor] != nil);
    Assert([window isVisible] && [view window] == window, @"Invalid close keeps Preferences open with Backups visible");
    Assert(errorCount == errorsBefore + 1 && [field currentEditor] != nil, @"Invalid close shows one actionable error and focuses the field");
    Assert([[field stringValue] isEqual:input] && [[fakeBackup settings] isEqual:saved], @"Invalid close preserves the draft and saved policy");
    if (busy) {
        SetBusy(pane, NO);
        Assert(errorCount == errorsBefore + 1, @"Worker completion after rejected close does not show another dialog");
    }
    NSTextView *editor = (NSTextView *)[field currentEditor];
    [editor insertText:@"12" replacementRange:NSMakeRange(0, [[editor string] length])];
    [window performClose:nil];
    Assert(![window isVisible] && ![field currentEditor], @"Corrected draft permits close and ends editing");
    Assert([[pane valueForKey:@"pendingFieldValues"] count] == 0, @"Corrected close saves pending fields");
    Assert(errorCount == errorsBefore + 1, @"Correcting the selected field produces no duplicate error");
    [saved release]; [window setDelegate:nil]; [owner release];
    [window setContentView:nil]; [window close]; [window release]; [pane release]; [fakeBackup release]; fakeBackup = nil;
}

static void ExerciseHiddenCompletionAndContextSwitch(void) {
    fakeBackup = [NVBackupController new];
    NVBackupPreferencesViewController *pane = [NVBackupPreferencesViewController new];
    NSView *view = [pane view];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:[view bounds]
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO]; [window setContentView:view];
    CloseOwner *owner = [[CloseOwner alloc] initWithWindow:window pane:pane];
    [window setDelegate:owner]; [window makeKeyAndOrderFront:nil];
    SetBusy(pane, YES);
    NativeEdit(pane, @"recentField", @"invalid");
    [window setContentView:[[[NSView alloc] initWithFrame:[view bounds]] autorelease]];
    NSUInteger errorsBefore = errorCount;
    SetBusy(pane, NO);
    Assert(errorCount == errorsBefore && [view window] == nil, @"Hidden invalid draft stays silent when the worker finishes");
    [window performClose:nil];
    Assert([window isVisible] && [view window] == window && errorCount == errorsBefore + 1,
        @"Closing after hidden validation reveals Backups and explains the invalid draft");
    NSTextView *editor = (NSTextView *)[[pane valueForKey:@"recentField"] currentEditor];
    [editor insertText:@"321" replacementRange:NSMakeRange(0, [[editor string] length])];
    SetBusy(pane, YES);
    [window performClose:nil];
    Assert(![window isVisible] && [[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 96,
        @"Corrected draft closes during busy without premature settings writes");
    [fakeBackup setValue:@"library-next" forKey:@"libraryIdentifier"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NVBackupStatusDidChangeNotification object:fakeBackup];
    SetBusy(pane, NO);
    Assert([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 96 &&
        [[pane valueForKey:@"pendingFieldValues"] count] == 0, @"Library switch discards a closed pane's old deferred draft");
    Assert(errorCount == errorsBefore + 1, @"Library switch clears draft errors without a later dialog");
    [window setDelegate:nil]; [owner release]; [window setContentView:nil]; [window release];
    [pane release]; [fakeBackup release]; fakeBackup = nil;
}

int main(void) {
    @autoreleasepool {
        [ProbeApplication sharedApplication];
        ExerciseLifetime(NO, NO);
        ExerciseLifetime(YES, NO);
        ExerciseLifetime(NO, YES);
        ExerciseLifetime(YES, YES);
        ExerciseDraftAtomicity();
        for (NSNumber *busy in @[@NO, @YES]) {
            ExerciseInvalidClose([busy boolValue], NO, @"recentField", @"2");
            ExerciseInvalidClose([busy boolValue], NO, @"dailyField", @"3651");
            ExerciseInvalidClose([busy boolValue], NO, @"weeklyField", @"521");
            ExerciseInvalidClose([busy boolValue], NO, @"storageField", @"1025");
            ExerciseInvalidClose([busy boolValue], YES, @"recentField", @"unfinished");
        }
        ExerciseHiddenCompletionAndContextSwitch();
        printf("PASS: %lu pane lifetime and policy-atomicity assertions\n", (unsigned long)checks);
    }
    return 0;
}
