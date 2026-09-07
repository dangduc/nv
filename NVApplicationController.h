#import <Cocoa/Cocoa.h>
@class AppController, NotationController, NoteObject, NVNoteEditingSession;

@interface NVApplicationController : NSObject <NSApplicationDelegate> {
    AppController *initialBrowser;
    AppController *lastActiveBrowser;
    AppController *operationBrowser;
    NSMutableArray *browsers;
    NotationController *library;
    NSMutableDictionary *editingSessions;
    BOOL terminating;
    BOOL restoring;
    BOOL preservingExternalContents;
}
+ (NVApplicationController *)sharedController;
+ (NVApplicationController *)controllerWithInitialBrowser:(AppController *)browser;
- (AppController *)activeBrowser;
- (NSArray *)browserControllers;
- (NotationController *)library;
- (void)setLibrary:(NotationController *)newLibrary;
- (void)browserBecameActive:(AppController *)browser;
- (void)browserWillClose:(AppController *)browser;
- (void)saveWindowStates;
- (void)restoreWindowStates;
- (IBAction)newWindow:(id)sender;
- (NVNoteEditingSession *)editingSessionForNote:(NoteObject *)note;
- (void)reloadCachedEditingSessionsFromLibrary;
- (void)performLibraryInvocation:(NSInvocation *)invocation fromBrowser:(AppController *)browser;
- (void)preserveExternalContents:(NSAttributedString *)contents forNote:(NoteObject *)note;
@end

AppController *NVControllerForView(NSView *view);
