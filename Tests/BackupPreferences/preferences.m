#import <Cocoa/Cocoa.h>
#import "NVBackupPreferencesViewController.h"
#import "NVBackupController.h"
#import "NVApplicationController.h"

NSString * const NVBackupStatusDidChangeNotification = @"NVBackupStatusDidChangeNotification";
static NVBackupController *fakeBackup;
static NSUInteger actionCount, errorCount;
static NSString *lastAction;
static NSString *fakeStatusText;
static BOOL destinationUnavailable;

@interface NVBackupPreferencesViewController (ProbeActions)
- (void)controlTextDidBeginEditing:(NSNotification *)notification;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
- (void)settingsChanged:(id)sender;
@end

@interface ProbeApplication : NSApplication @end
@interface ProbeBackground : NSView @end
@implementation ProbeBackground
- (void)drawRect:(NSRect)rect { [[NSColor windowBackgroundColor] setFill]; NSRectFill(rect); }
@end
@implementation ProbeApplication
- (BOOL)presentError:(NSError *)error { errorCount++; return NO; }
@end

@implementation NVApplicationController
+ (NVApplicationController *)sharedController { static id instance; if (!instance) instance = [self new]; return instance; }
- (NVBackupController *)backupController { return fakeBackup; }
@end

@implementation NVBackupController
- (id)init {
    if ((self = [super init])) {
        librarySettings = [@{@"enabled":@YES, @"interval":@900, @"recent":@96, @"daily":@30, @"weekly":@12, @"maxBytes":@2147483648ULL} mutableCopy];
        libraryIdentifier = [@"library-A" copy];
    }
    return self;
}
- (BOOL)hasLibrary { return YES; }
- (BOOL)isBusy { return busy; }
- (NSString *)libraryIdentifier { return libraryIdentifier; }
- (NSDictionary *)settings { return librarySettings; }
- (BOOL)setSettings:(NSDictionary *)settings error:(NSError **)error {
    [librarySettings setDictionary:settings];
    [[NSNotificationCenter defaultCenter] postNotificationName:NVBackupStatusDidChangeNotification object:self];
    return YES;
}
- (NSURL *)destinationURL { return destinationUnavailable ? nil : [NSURL fileURLWithPath:@"/Users/Example/Library/Application Support/nvALT/Backups/01234567-89AB-CDEF-0123-456789ABCDEF"]; }
- (NSString *)statusText { return fakeStatusText ?: @"Last backup: Sep 8, 2026 at 4:12 PM\nNext backup: Sep 8, 2026 at 4:27 PM\nStorage: 23 snapshots, 145 MB\nBackups are up to date."; }
- (void)backupNow:(id)sender { actionCount++; lastAction = @"backup"; }
- (void)chooseDestination:(id)sender { actionCount++; lastAction = @"choose"; }
- (void)showBackupsInFinder:(id)sender { actionCount++; lastAction = @"show"; }
- (void)restoreBackup:(id)sender { actionCount++; lastAction = @"restore"; }
- (void)deleteUnencryptedBackups:(id)sender { actionCount++; lastAction = @"delete"; }
@end

static void Check(BOOL condition, NSString *message) { if (!condition) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Edit(NVBackupPreferencesViewController *pane, NSString *fieldKey, NSString *value) {
    NSTextField *field = [pane valueForKey:fieldKey];
    NSNotification *notification = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field];
    [pane controlTextDidBeginEditing:notification];
    [field setStringValue:value];
    [pane controlTextDidEndEditing:notification];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [ProbeApplication sharedApplication];
        fakeBackup = [NVBackupController new];
        NVBackupPreferencesViewController *pane = [NVBackupPreferencesViewController new];
        NSView *view = [pane view];
        for (NSView *child in [view subviews]) Check(NSContainsRect([view bounds], [child frame]), @"All controls fit pane bounds");
        Check([[pane valueForKey:@"recentField"] integerValue] == 96, @"Initial retention");
        [[pane valueForKey:@"enabledButton"] performClick:nil];
        Check(![[[fakeBackup settings] objectForKey:@"enabled"] boolValue], @"Checkbox saves setting");
        Check(![[pane valueForKey:@"intervalButton"] isEnabled], @"Disabled schedule disables interval");
        [[pane valueForKey:@"enabledButton"] performClick:nil];
        [[pane valueForKey:@"intervalButton"] selectItemWithTag:1800];
        [pane settingsChanged:[pane valueForKey:@"intervalButton"]];
        Check([[[fakeBackup settings] objectForKey:@"interval"] integerValue] == 1800, @"Interval saves seconds");
        Edit(pane, @"recentField", @"128");
        Edit(pane, @"dailyField", @"45");
        Edit(pane, @"weeklyField", @"24");
        NSString *storageInput = [NSNumberFormatter localizedStringFromNumber:@2.5 numberStyle:NSNumberFormatterDecimalStyle];
        Edit(pane, @"storageField", storageInput);
        Check([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 128, @"Recent count saves");
        Check([[[fakeBackup settings] objectForKey:@"daily"] integerValue] == 45, @"Daily count saves");
        Check([[[fakeBackup settings] objectForKey:@"weekly"] integerValue] == 24, @"Weekly count saves");
        Check([[[fakeBackup settings] objectForKey:@"maxBytes"] unsignedLongLongValue] == 2684354560ULL, @"GiB converts to bytes");
        Edit(pane, @"storageField", [storageInput stringByAppendingString:@"oops"]);
        Check(errorCount == 1 && [[[fakeBackup settings] objectForKey:@"maxBytes"] unsignedLongLongValue] == 2684354560ULL, @"Invalid suffix rejected");
        NSMutableDictionary *precisionSettings = [[fakeBackup settings] mutableCopy];
        [precisionSettings setObject:@1048576 forKey:@"maxBytes"];
        [fakeBackup setSettings:precisionSettings error:NULL];
        Edit(pane, @"storageField", [[pane valueForKey:@"storageField"] stringValue]);
        Check([[[fakeBackup settings] objectForKey:@"maxBytes"] unsignedLongLongValue] == 1048576ULL, @"Tabbing through storage preserves exact byte target");
        [precisionSettings release];
        NSTextField *recent = [pane valueForKey:@"recentField"];
        NSNotification *editing = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:recent];
        [pane controlTextDidBeginEditing:editing];
        [recent setStringValue:@"777"];
        [fakeBackup setValue:@"library-B" forKey:@"libraryIdentifier"];
        NSMutableDictionary *settings = [[fakeBackup settings] mutableCopy];
        [settings setObject:@333 forKey:@"recent"];
        [fakeBackup setSettings:settings error:NULL];
        [pane controlTextDidEndEditing:editing];
        Check([[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 333, @"Stale field edit cannot alter new library");
        [fakeBackup setValue:@YES forKey:@"busy"];
        [pane refreshControls];
        for (NSString *key in @[@"enabledButton", @"recentField", @"chooseButton", @"backupNowButton", @"restoreButton", @"deleteButton"]) Check(![[pane valueForKey:key] isEnabled], @"Busy controller disables mutations");
        [fakeBackup setValue:@NO forKey:@"busy"];
        [pane refreshControls];
        for (NSString *key in @[@"backupNowButton", @"chooseButton", @"showButton", @"restoreButton", @"deleteButton"]) [[pane valueForKey:key] performClick:nil];
        Check(actionCount == 5 && [lastAction isEqualToString:@"delete"], @"All actions reach coordinator");
        destinationUnavailable = YES;
        [pane refreshControls];
        Check([[[pane valueForKey:@"destinationField"] stringValue] isEqualToString:@"Selected backup folder is unavailable."], @"Unavailable destination copy recognizes the open library");
        Check(![[pane valueForKey:@"showButton"] isEnabled] && [[pane valueForKey:@"chooseButton"] isEnabled], @"Unavailable destination permits choosing a replacement");
        destinationUnavailable = NO;
        [pane refreshControls];

        NSWindow *window = [[NSWindow alloc] initWithContentRect:[view bounds] styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        ProbeBackground *background = [[[ProbeBackground alloc] initWithFrame:[view bounds]] autorelease];
        [background addSubview:view];
        [window setContentView:background];
        [view layoutSubtreeIfNeeded];
        NSMutableString *longStatus = [NSMutableString string];
        for (NSUInteger line = 0; line < 30; line++) [longStatus appendFormat:@"Backup status line %lu\n", (unsigned long)line];
        [longStatus appendString:@"Error: this final failure remains accessible."];
        fakeStatusText = longStatus;
        [pane refreshControls];
        NSTextView *status = [pane valueForKey:@"statusField"];
        Check([[status string] isEqual:longStatus] && ![status isEditable] && [status isSelectable], @"Complete status is read-only and selectable");
        [[status layoutManager] ensureLayoutForTextContainer:[status textContainer]];
        NSRange errorRange = [[status string] rangeOfString:@"Error:"];
        [status scrollRangeToVisible:errorRange];
        NSRange glyphs = [[status layoutManager] glyphRangeForCharacterRange:errorRange actualCharacterRange:NULL];
        NSRect errorRect = [[status layoutManager] boundingRectForGlyphRange:glyphs inTextContainer:[status textContainer]];
        Check(NSIntersectsRect([status visibleRect], errorRect) && [status visibleRect].origin.y > 0, @"Final error can scroll into view");
        fakeStatusText = nil;
        [pane refreshControls];
        [status scrollRangeToVisible:NSMakeRange(0, 0)];
        NSBitmapImageRep *rep = [background bitmapImageRepForCachingDisplayInRect:[background bounds]];
        [background cacheDisplayInRect:[background bounds] toBitmapImageRep:rep];
        if (argc > 1) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        NSLog(@"PASS: settings, validation, stale library edit, busy controls, five actions, and pane bounds");
    }
    return 0;
}
