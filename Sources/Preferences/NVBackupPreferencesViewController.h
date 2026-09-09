#import <Cocoa/Cocoa.h>

@interface NVBackupPreferencesViewController : NSViewController <NSTextFieldDelegate> {
    NSButton *enabledButton, *chooseButton, *backupNowButton, *showButton, *restoreButton, *deleteButton;
    NSPopUpButton *intervalButton;
    NSTextField *recentField, *dailyField, *weeklyField, *storageField, *destinationField;
    NSTextView *statusField;
    NSString *displayedLibraryIdentifier;
    NSString *editingLibraryIdentifier;
}
- (void)refreshControls;
@end
