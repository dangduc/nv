#import <Cocoa/Cocoa.h>
@class AppController, NotationController, NoteObject, NVNoteEditingSession, NVBackupController;

@interface NVApplicationController : NSObject <NSApplicationDelegate> {
    AppController *initialBrowser;
    AppController *lastActiveBrowser;
    AppController *operationBrowser;
    NSMutableArray *browsers;
    NotationController *library;
    NSMutableDictionary *editingSessions;
    NVBackupController *backupController;
    BOOL terminating;
    BOOL finishingTermination;
    BOOL restoring;
    BOOL backupRestoreInProgress;
    BOOL preservingExternalContents;
}
+ (NVApplicationController *)sharedController;
+ (NVApplicationController *)controllerWithInitialBrowser:(AppController *)browser;
- (AppController *)activeBrowser;
- (NSArray *)browserControllers;
- (NotationController *)library;
- (NVBackupController *)backupController;
- (BOOL)restoreBackupArchive:(NSDictionary *)archive toDirectory:(NSURL *)directory error:(NSError **)error;
- (void)setLibrary:(NotationController *)newLibrary;
- (void)browserBecameActive:(AppController *)browser;
- (void)browserWillClose:(AppController *)browser;
- (void)saveWindowStates;
- (void)noteMetadataUpdated:(NoteObject *)note;
- (void)setNote:(NoteObject *)note metadataValue:(NSString *)value isTitle:(BOOL)isTitle;
- (void)restoreWindowStates;
- (IBAction)newWindow:(id)sender;
- (NVNoteEditingSession *)editingSessionForNote:(NoteObject *)note;
- (void)reloadCachedEditingSessionsFromLibrary;
- (void)performLibraryInvocation:(NSInvocation *)invocation fromBrowser:(AppController *)browser;
- (void)preserveExternalContents:(NSAttributedString *)contents forNote:(NoteObject *)note;
- (void)createFromSelection:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
@end

AppController *NVControllerForView(NSView *view);
