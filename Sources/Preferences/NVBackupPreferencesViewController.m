#import "NVBackupPreferencesViewController.h"
#import "NVApplicationController.h"
#import "NVBackupController.h"
#include <math.h>

static NSTextField *NVBackupLabel(NSView *view, NSString *title, NSRect frame) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setStringValue:title];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [[label cell] setWraps:YES];
    [view addSubview:label];
    return label;
}

static NSButton *NVBackupButton(NSView *view, NSString *title, NSRect frame, id target, SEL action) {
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:target];
    [button setAction:action];
    [view addSubview:button];
    return button;
}

@implementation NVBackupPreferencesViewController

- (id)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backupStatusChanged:)
            name:NVBackupStatusDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [displayedLibraryIdentifier release];
    [editingLibraryIdentifier release];
    [super dealloc];
}

- (NSTextField *)numberFieldInView:(NSView *)view frame:(NSRect)frame label:(NSString *)label {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setDelegate:self];
    [field setAlignment:NSTextAlignmentRight];
    [field setAccessibilityLabel:label];
    [view addSubview:field];
    return field;
}

- (void)loadView {
    NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 530)] autorelease];
    enabledButton = NVBackupButton(view, NSLocalizedString(@"Back up notes automatically", nil),
        NSMakeRect(24, 491, 410, 24), self, @selector(settingsChanged:));
    [enabledButton setButtonType:NSSwitchButton];
    NVBackupLabel(view, NSLocalizedString(@"Backups run while nvALT is open. They contain committed note content; unfinished composition is included in a later backup.", nil), NSMakeRect(28, 450, 564, 36));

    NVBackupLabel(view, NSLocalizedString(@"Back up changed notes every:", nil), NSMakeRect(28, 417, 232, 22));
    intervalButton = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(265, 414, 154, 27) pullsDown:NO] autorelease];
    for (NSNumber *minutes in [NSArray arrayWithObjects:@5, @15, @30, @60, nil]) {
        [intervalButton addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"%@ minutes", nil), minutes]];
        [[intervalButton lastItem] setTag:[minutes integerValue] * 60];
    }
    [intervalButton setAccessibilityLabel:NSLocalizedString(@"Backup interval", nil)];
    [intervalButton setTarget:self];
    [intervalButton setAction:@selector(settingsChanged:)];
    [view addSubview:intervalButton];

    NVBackupLabel(view, NSLocalizedString(@"Keep snapshots:", nil), NSMakeRect(28, 378, 120, 22));
    NVBackupLabel(view, NSLocalizedString(@"Recent", nil), NSMakeRect(154, 378, 49, 22));
    recentField = [self numberFieldInView:view frame:NSMakeRect(207, 377, 64, 24) label:NSLocalizedString(@"Recent snapshots to keep", nil)];
    NVBackupLabel(view, NSLocalizedString(@"Daily", nil), NSMakeRect(294, 378, 39, 22));
    dailyField = [self numberFieldInView:view frame:NSMakeRect(336, 377, 64, 24) label:NSLocalizedString(@"Days of snapshots to keep", nil)];
    NVBackupLabel(view, NSLocalizedString(@"Weekly", nil), NSMakeRect(424, 378, 50, 22));
    weeklyField = [self numberFieldInView:view frame:NSMakeRect(478, 377, 64, 24) label:NSLocalizedString(@"Weeks of snapshots to keep", nil)];
    [dailyField setToolTip:NSLocalizedString(@"Keep the latest snapshot per UTC day for this many days.", nil)];
    [weeklyField setToolTip:NSLocalizedString(@"Keep the latest snapshot per UTC week for this many weeks.", nil)];

    NVBackupLabel(view, NSLocalizedString(@"Storage target:", nil), NSMakeRect(28, 342, 169, 22));
    storageField = [self numberFieldInView:view frame:NSMakeRect(207, 340, 170, 24) label:NSLocalizedString(@"Backup storage target in GiB", nil)];
    NVBackupLabel(view, NSLocalizedString(@"GiB", @"Gibibyte unit"), NSMakeRect(385, 342, 44, 22));
    NVBackupLabel(view, NSLocalizedString(@"Daily and weekly history share the same snapshots. The storage target takes priority, but at least three complete snapshots are kept.", nil), NSMakeRect(28, 300, 564, 34));

    NVBackupLabel(view, NSLocalizedString(@"Backup folder", nil), NSMakeRect(28, 273, 200, 20));
    destinationField = NVBackupLabel(view, @"", NSMakeRect(28, 247, 463, 22));
    [destinationField setSelectable:YES];
    [[destinationField cell] setWraps:NO];
    [[destinationField cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    chooseButton = NVBackupButton(view, NSLocalizedString(@"Choose…", nil), NSMakeRect(496, 244, 99, 30), self, @selector(chooseDestination:));

    NSScrollView *statusScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(28, 143, 564, 96)] autorelease];
    [statusScrollView setHasVerticalScroller:YES];
    [statusScrollView setAutohidesScrollers:YES];
    [statusScrollView setDrawsBackground:NO];
    statusField = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 564, 96)] autorelease];
    [statusField setEditable:NO];
    [statusField setSelectable:YES];
    [statusField setRichText:NO];
    [statusField setDrawsBackground:NO];
    [statusField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [statusField setTextColor:[NSColor labelColor]];
    [statusField setTextContainerInset:NSZeroSize];
    [statusField setHorizontallyResizable:NO];
    [statusField setVerticallyResizable:YES];
    [statusField setMinSize:NSMakeSize(0, 96)];
    [statusField setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [statusField setAutoresizingMask:NSViewWidthSizable];
    [[statusField textContainer] setContainerSize:NSMakeSize(564, CGFLOAT_MAX)];
    [[statusField textContainer] setWidthTracksTextView:YES];
    [[statusField textContainer] setLineFragmentPadding:0];
    [statusField setAccessibilityLabel:NSLocalizedString(@"Backup status", nil)];
    [statusScrollView setDocumentView:statusField];
    [view addSubview:statusScrollView];
    backupNowButton = NVBackupButton(view, NSLocalizedString(@"Back Up Now", nil), NSMakeRect(22, 102, 144, 32), self, @selector(backupNow:));
    showButton = NVBackupButton(view, NSLocalizedString(@"Show Backups in Finder", nil), NSMakeRect(171, 102, 238, 32), self, @selector(showBackupsInFinder:));
    restoreButton = NVBackupButton(view, NSLocalizedString(@"Restore Backup…", nil), NSMakeRect(414, 102, 183, 32), self, @selector(restoreBackup:));

    NVBackupLabel(view, NSLocalizedString(@"Encrypted notes stay encrypted; some library settings remain readable. Older backups may need an earlier password. Turning encryption on leaves older unencrypted backups unchanged.", nil), NSMakeRect(28, 51, 564, 45));
    deleteButton = NVBackupButton(view, NSLocalizedString(@"Delete Older Unencrypted Backups…", nil), NSMakeRect(22, 12, 330, 32), self, @selector(deleteUnencryptedBackups:));

    [self setView:view];
    [self refreshControls];
}

- (NVBackupController *)backupController {
    return [[NVApplicationController sharedController] backupController];
}

- (void)backupStatusChanged:(NSNotification *)notification {
    if ([NSThread isMainThread]) [self refreshControls];
    else [self performSelectorOnMainThread:@selector(refreshControls) withObject:nil waitUntilDone:NO];
}

- (void)refreshControls {
    if (![self isViewLoaded]) return;
    NVBackupController *controller = [self backupController];
    NSString *identifier = [controller libraryIdentifier];
    BOOL sameLibrary = (displayedLibraryIdentifier == identifier || [displayedLibraryIdentifier isEqualToString:identifier]);
    if (!sameLibrary) {
        // End an old library's field edit before displaying the new settings. Its delegate rejects that stale edit.
        [[[self view] window] makeFirstResponder:nil];
        [displayedLibraryIdentifier release];
        displayedLibraryIdentifier = [identifier copy];
    }
    NSDictionary *settings = [controller settings];
    BOOL configurable = [controller hasLibrary] && ![controller isBusy];
    [enabledButton setState:[[settings objectForKey:@"enabled"] boolValue] ? NSOnState : NSOffState];
    [enabledButton setEnabled:configurable];
    NSInteger interval = [[settings objectForKey:@"interval"] integerValue];
    if (![intervalButton selectItemWithTag:interval] && settings) {
        [intervalButton addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"%ld seconds", nil), (long)interval]];
        [[intervalButton lastItem] setTag:interval];
        [intervalButton selectItemWithTag:interval];
    }
    [intervalButton setEnabled:configurable && [enabledButton state] == NSOnState];
    NSArray *fields = [NSArray arrayWithObjects:recentField, dailyField, weeklyField, storageField, nil];
    NSArray *keys = [NSArray arrayWithObjects:@"recent", @"daily", @"weekly", @"maxBytes", nil];
    for (NSUInteger index = 0; index < [fields count]; index++) {
        NSTextField *field = [fields objectAtIndex:index];
        if (![field currentEditor]) {
            NSNumber *number = [settings objectForKey:[keys objectAtIndex:index]];
            if (field == storageField && number) {
                NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
                // Enough precision to preserve a byte count when the user only tabs through this field.
                [formatter setMaximumFractionDigits:12];
                [formatter setUsesGroupingSeparator:NO];
                [field setStringValue:[formatter stringFromNumber:[NSNumber numberWithDouble:[number doubleValue] / 1073741824.0]]];
            } else [field setStringValue:number ? [number stringValue] : @""];
        }
        [field setEnabled:configurable];
    }
    NSString *path = [[controller destinationURL] path];
    [destinationField setStringValue:path ?: ([controller hasLibrary]
        ? NSLocalizedString(@"Selected backup folder is unavailable.", nil)
        : NSLocalizedString(@"Open a notes library to configure backups.", nil))];
    [destinationField setToolTip:path];
    NSString *status = [controller statusText] ?: NSLocalizedString(@"No notes library is open.", nil);
    if (![[statusField string] isEqualToString:status]) [statusField setString:status];
    [chooseButton setEnabled:configurable];
    [backupNowButton setEnabled:configurable];
    [deleteButton setEnabled:configurable];
    [showButton setEnabled:[controller destinationURL] != nil];
    [restoreButton setEnabled:configurable];
}

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    [editingLibraryIdentifier release];
    editingLibraryIdentifier = [[[self backupController] libraryIdentifier] copy];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSString *identifier = [[self backupController] libraryIdentifier];
    if (editingLibraryIdentifier && [editingLibraryIdentifier isEqualToString:identifier]) [self settingsChanged:[notification object]];
    [editingLibraryIdentifier release];
    editingLibraryIdentifier = nil;
}

- (void)settingsChanged:(id)sender {
    NVBackupController *controller = [self backupController];
    if (![controller hasLibrary] || [controller isBusy]) {
        [self refreshControls];
        return;
    }
    NSMutableDictionary *settings = [[[controller settings] mutableCopy] autorelease];
    NSString *key = nil;
    NSNumber *value = nil;
    NSError *error = nil;
    if (sender == enabledButton) {
        key = @"enabled";
        value = [NSNumber numberWithBool:[enabledButton state] == NSOnState];
    } else if (sender == intervalButton) {
        key = @"interval";
        value = [NSNumber numberWithInteger:[intervalButton selectedTag]];
    } else if (sender == storageField) {
        key = @"maxBytes";
        NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
        [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
        NSString *input = [[storageField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange range = NSMakeRange(0, [input length]);
        NSNumber *number = nil;
        if ([formatter getObjectValue:&number forString:input range:&range error:NULL] && range.length == [input length] && [input length]) {
            double bytes = [number doubleValue] * 1073741824.0;
            if (isfinite(bytes) && bytes >= 1048576.0 && bytes <= 1099511627776.0)
                value = [NSNumber numberWithUnsignedLongLong:(unsigned long long)llround(bytes)];
        }
    } else {
        if (sender == recentField) key = @"recent";
        else if (sender == dailyField) key = @"daily";
        else if (sender == weeklyField) key = @"weekly";
        if (key) {
            NSScanner *scanner = [NSScanner scannerWithString:[sender stringValue]];
            long long count;
            if ([scanner scanLongLong:&count] && [scanner isAtEnd]) value = [NSNumber numberWithLongLong:count];
        }
    }
    if (!key) return;
    if (!value) {
        NSString *description = sender == storageField
            ? NSLocalizedString(@"Enter a storage target from 0.000977 to 1024 GiB (1 MiB to 1 TiB).", nil)
            : NSLocalizedString(@"Enter a whole number of snapshots.", nil);
        error = [NSError errorWithDomain:@"NVBackupPreferencesError" code:1 userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
    } else {
        [settings setObject:value forKey:key];
        [controller setSettings:settings error:&error];
    }
    if (error) [NSApp presentError:error];
    [self refreshControls];
}

- (void)backupNow:(id)sender { [[self backupController] backupNow:sender]; }
- (void)chooseDestination:(id)sender { [[self backupController] chooseDestination:sender]; }
- (void)showBackupsInFinder:(id)sender { [[self backupController] showBackupsInFinder:sender]; }
- (void)restoreBackup:(id)sender { [[self backupController] restoreBackup:sender]; }
- (void)deleteUnencryptedBackups:(id)sender { [[self backupController] deleteUnencryptedBackups:sender]; }

@end
