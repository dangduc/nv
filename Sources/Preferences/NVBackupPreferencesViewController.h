#import <Cocoa/Cocoa.h>

@interface NVBackupPreferencesViewController : NSViewController <NSTextFieldDelegate> {
    NSButton *enabledButton, *chooseButton, *backupNowButton, *showButton, *restoreButton, *deleteButton;
    NSPopUpButton *intervalButton;
    NSTextField *recentField, *dailyField, *weeklyField, *storageField, *destinationField;
    NSTextView *statusField;
    NSString *displayedLibraryIdentifier;
    NSString *editingLibraryIdentifier;
    NSMutableDictionary *pendingFieldValues;
    NSError *pendingFieldError;
    BOOL commitFieldsWhenIdle, committingFields;
}
- (void)refreshControls;
// Checks every draft, including drafts in a hidden pane. Busy workers defer valid settings.
- (BOOL)prepareForWindowCloseWithError:(NSError **)error;
- (void)focusFieldForError:(NSError *)error;
@end
