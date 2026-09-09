// Reuse the fixture collaborators and native edit helper. The old main is not run.
#define main ExistingPreferenceSuiteMain
#include "../../../BackupPreferences/preferences.m"
#undef main

static NSUInteger assertions;
static void Assert(BOOL condition, NSString *message) { assertions++; Check(condition, message); }
@interface MemoryPanePrefs : NSObject { NSString *selected; }
- (NSString *)lastSelectedPreferencesPane;
- (void)setLastSelectedPreferencesPane:(NSString *)value sender:(id)sender;
- (void)synchronize;
@end
@implementation MemoryPanePrefs
- (id)init { if ((self = [super init])) selected = [@"General" copy]; return self; }
- (NSString *)lastSelectedPreferencesPane { return selected; }
- (void)setLastSelectedPreferencesPane:(NSString *)value sender:(id)sender { [selected release]; selected = [value copy]; }
- (void)synchronize {}
- (void)dealloc { [selected release]; [super dealloc]; }
@end

NSRect ScaleRectWithFactor(NSRect rect, float factor);
@interface SwitchOwner : NSObject <NSWindowDelegate, NSToolbarDelegate> {
@public
    MemoryPanePrefs *prefsController;
    NSWindow *window;
    NVBackupPreferencesViewController *backupPreferencesViewController;
    NSDictionary *items;
    NSToolbar *toolbar;
    NSView *generalView, *editingView, *fontsColorsView, *databaseView;
    NSPopUpButton *folderLocationsMenuButton;
}
- (id)initWithWindow:(NSWindow *)value;
- (void)switchViews:(NSToolbarItem *)item;
- (NSView *)databaseView;
- (NSMenu *)directorySelectionMenu;
- (void)selectPane:(NSString *)identifier;
@end
@implementation SwitchOwner
- (id)initWithWindow:(NSWindow *)value {
    if ((self = [super init])) {
        prefsController = [MemoryPanePrefs new]; window = value;
        generalView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 260)];
        editingView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 340)];
        databaseView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 510, 380)];
        NSMutableDictionary *built = [NSMutableDictionary dictionary];
        for (NSString *identifier in @[@"General", @"Notes", @"Backups", @"Editing"]) {
            NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
            [item setLabel:identifier]; [item setTarget:self]; [item setAction:@selector(switchViews:)];
            [built setObject:item forKey:identifier];
        }
        items = [built copy];
        toolbar = [[NSToolbar alloc] initWithIdentifier:@"Round3Workflow"];
        [toolbar setDelegate:self]; [toolbar setAllowsUserCustomization:NO]; [toolbar setAutosavesConfiguration:NO];
        [window setToolbar:toolbar]; [window setDelegate:self]; [self switchViews:nil];
    }
    return self;
}
- (NSToolbarItem *)toolbar:(NSToolbar *)value itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)insert { return [items objectForKey:identifier]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)value { return @[@"General", @"Notes", @"Backups", @"Editing"]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)value { return [self toolbarDefaultItemIdentifiers:value]; }
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)value { return [self toolbarDefaultItemIdentifiers:value]; }
- (NSView *)databaseView { return databaseView; }
- (NSMenu *)directorySelectionMenu { return [[[NSMenu alloc] initWithTitle:@"Fixture directories"] autorelease]; }
- (void)selectPane:(NSString *)identifier {
    NSToolbarItem *item = [items objectForKey:identifier];
    [toolbar setSelectedItemIdentifier:identifier];
    Assert([NSApp sendAction:[item action] to:[item target] from:item], @"Native target/action reaches the switch owner");
}
// Exact production methods and scaling function, generated on every run.
#include "switch-owner.inc"
#include "close-owner.inc"
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:prefsController];
    [window setDelegate:nil]; [window setToolbar:nil];
    [prefsController release]; [backupPreferencesViewController release]; [items release]; [toolbar release];
    [generalView release]; [editingView release]; [databaseView release]; [super dealloc];
}
@end

static NSInteger Recent(void) { return [[[fakeBackup settings] objectForKey:@"recent"] integerValue]; }
static NSString *Status(NVBackupPreferencesViewController *pane) { return [[pane valueForKey:@"statusField"] string]; }

int main(void) {
    @autoreleasepool {
        [ProbeApplication sharedApplication];
        fakeBackup = [NVBackupController new]; fakeStatusText = @"Initial backup status";
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 480, 260)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        [window setReleasedWhenClosed:NO];
        SwitchOwner *owner = [[SwitchOwner alloc] initWithWindow:window];
        [window makeKeyAndOrderFront:nil];
        Assert(owner->backupPreferencesViewController == nil, @"Unopened Backups pane remains lazy");
        [window performClose:nil];
        Assert(![window isVisible] && owner->backupPreferencesViewController == nil, @"Close before first Backups visit does not create its pane");
        [window makeKeyAndOrderFront:nil]; [owner selectPane:@"Backups"];
        NVBackupPreferencesViewController *pane = owner->backupPreferencesViewController;
        Assert(pane != nil && [pane view] == [window contentView], @"First Backups action creates and installs its production view");
        NSSize size = [[window contentView] frame].size;
        Assert(size.width == 620 && size.height == 530, @"Production frame conversion gives Backups its intended dimensions");
        for (NSNumber *busy in @[@NO, @YES]) {
            SetBusy(pane, [busy boolValue]); NSInteger before = Recent();
            NSString *draft = [busy boolValue] ? @"322" : @"321";
            NativeEdit(pane, @"recentField", draft); [owner selectPane:@"Backups"];
            Assert(owner->backupPreferencesViewController == pane && [pane view] == [window contentView], @"Same-pane reselection reuses the visible pane");
            Assert([[pane valueForKey:@"recentField"] currentEditor] == nil, @"Same-pane replacement ends its native field edit");
            if ([busy boolValue]) Assert(Recent() == before && [[pane valueForKey:@"commitFieldsWhenIdle"] boolValue], @"Busy same-pane reselection defers the completed draft");
            SetBusy(pane, NO);
            Assert(Recent() == [draft integerValue] && [[pane valueForKey:@"pendingFieldValues"] count] == 0, @"Same-pane reselection saves the draft by idle");
        }
        NSLog(@"PASS: lazy creation, same-pane actions, and native dimensions");

        SetBusy(pane, YES); NativeEdit(pane, @"recentField", @"333"); NativeEdit(pane, @"dailyField", @"unfinished");
        [owner selectPane:@"Editing"];
        Assert([[pane view] window] == nil && [window contentView] == owner->editingView, @"Production switch detaches Backups while busy");
        NSUInteger beforeErrors = errorCount;
        fakeStatusText = @"Destination disconnected during backup"; SetBusy(pane, NO);
        Assert(errorCount == beforeErrors && [window contentView] == owner->editingView, @"Hidden completion changes neither the pane nor the modal error count");
        Assert([Status(pane) containsString:@"Destination disconnected"] && [Status(pane) containsString:@"Backup settings were not saved."], @"Hidden status retains operation and draft errors together");
        Assert(Recent() == 322 && [[[fakeBackup settings] objectForKey:@"daily"] integerValue] == 30, @"Invalid hidden policy leaves all saved settings unchanged");
        [window performClose:nil];
        NSText *editor = [[pane valueForKey:@"dailyField"] currentEditor];
        Assert([window isVisible] && [window contentView] == [pane view], @"Rejected hidden close reveals Backups through production switchViews");
        Assert([[owner->toolbar selectedItemIdentifier] isEqual:@"Backups"] && [[owner->prefsController lastSelectedPreferencesPane] isEqual:@"Backups"] && [[window title] isEqual:@"Backups"], @"Rejected close keeps visible, saved, and titled pane identity together");
        Assert(errorCount == beforeErrors + 1 && editor != nil && NSEqualRanges([editor selectedRange], NSMakeRange(0, [@"unfinished" length])), @"Rejected close reports one error and selects the complete invalid draft");
        NativeEdit(pane, @"dailyField", @"46"); [window performClose:nil];
        Assert(![window isVisible] && Recent() == 333 && [[[fakeBackup settings] objectForKey:@"daily"] integerValue] == 46, @"Correction saves the complete policy before native close");
        Assert(![Status(pane) containsString:@"Backup settings were not saved."] && [Status(pane) containsString:@"Destination disconnected"], @"Correction clears the draft error and retains the operation error");
        fakeStatusText = @"Destination reconnected; backup complete"; SetBusy(pane, NO);
        [window makeKeyAndOrderFront:nil]; [owner switchViews:nil];
        Assert([window contentView] == [pane view] && [Status(pane) isEqual:fakeStatusText] && [[owner->toolbar selectedItemIdentifier] isEqual:@"Backups"], @"Reopen restores saved pane selection and status received while closed");
        Assert(errorCount == beforeErrors + 1, @"Correction and reopen show no duplicate error");
        NSLog(@"PASS: hidden operation/draft errors, rejected-close selection, correction, and closed-window status");

        SetBusy(pane, YES); NativeEdit(pane, @"recentField", @"444"); [owner selectPane:@"Notes"];
        Assert([[pane valueForKey:@"pendingFieldValues"] count] == 1 && [[pane view] window] == nil, @"Notes pane hides a deferred old-library draft");
        beforeErrors = errorCount;
        [fakeBackup setValue:@"library-next" forKey:@"libraryIdentifier"];
        NSMutableDictionary *nextSettings = [[fakeBackup settings] mutableCopy];
        [nextSettings setObject:@24 forKey:@"recent"]; [nextSettings setObject:@NO forKey:@"enabled"];
        [fakeBackup setValue:nextSettings forKey:@"librarySettings"]; [nextSettings release];
        fakeStatusText = @"New library: automatic backups are off"; SetBusy(pane, NO);
        Assert([[pane valueForKey:@"pendingFieldValues"] count] == 0 && ![[pane valueForKey:@"commitFieldsWhenIdle"] boolValue], @"Library notification clears hidden drafts and old deferred save");
        [owner selectPane:@"Backups"];
        Assert(Recent() == 24 && [[pane valueForKey:@"recentField"] integerValue] == 24 && [Status(pane) isEqual:fakeStatusText], @"Return from Notes displays the new library policy and status");
        Assert([[pane valueForKey:@"enabledButton"] state] == NSOffState && ![[pane valueForKey:@"intervalButton"] isEnabled], @"Returned pane uses the new schedule state");
        [window performClose:nil];
        Assert(![window isVisible] && Recent() == 24 && errorCount == beforeErrors, @"Close after library change cannot save the old draft or show its error");
        NSLog(@"PASS: hidden draft isolation after an injected library notification");
        [window setDelegate:nil]; [window setContentView:nil]; [owner release]; [window close]; [window release];
        [fakeBackup release]; fakeBackup = nil; fakeStatusText = nil;
        printf("PASS: %lu new production pane-switch workflow assertions\n", (unsigned long)assertions);
    }
    return 0;
}
