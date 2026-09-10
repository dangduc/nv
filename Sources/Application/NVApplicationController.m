#import "NVApplicationController.h"
#import "AppController.h"
#import "AppController_Importing.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "BookmarksController.h"
#import "NotationPrefs.h"
#import "NSString_NV.h"
#import "NVBackupController.h"
#import "NVBackupStore.h"
#import "LinkingEditor.h"
#import "NVSearchService.h"

static NVApplicationController *NVSharedApplicationController;
static NSString * const NVBrowserWindowsKey = @"NVBrowserWindows";

@interface NVApplicationController ()
- (void)setLibrary:(NotationController *)newLibrary finishingOldLibrary:(BOOL)finish;
- (BOOL)rejectInvocationDuringBackupRestore:(NSInvocation *)invocation;
@end

AppController *NVControllerForView(NSView *view) {
    if ([view respondsToSelector:@selector(delegate)]) {
        id owner = [(id)view delegate];
        if ([owner isKindOfClass:[AppController class]]) return owner;
    }
    id controller = [[view window] windowController];
    if ([controller isKindOfClass:[AppController class]]) return controller;
    controller = [[view window] delegate];
    if ([controller isKindOfClass:[AppController class]]) return controller;
    if ([[NSApp delegate] isKindOfClass:[AppController class]]) return (id)[NSApp delegate];
    return [[NVApplicationController sharedController] activeBrowser];
}

@implementation NVApplicationController
+ (NVApplicationController *)sharedController { return NVSharedApplicationController; }
+ (NVApplicationController *)controllerWithInitialBrowser:(AppController *)browser {
    if (!NVSharedApplicationController) {
        NVSharedApplicationController = [[self alloc] init];
        NVSharedApplicationController->initialBrowser = [browser retain];
        NVSharedApplicationController->browsers = [[NSMutableArray alloc] initWithObjects:browser, nil];
        NVSharedApplicationController->editingSessions = [[NSMutableDictionary alloc] init];
        NVSharedApplicationController->lastActiveBrowser = browser;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:NVSharedApplicationController selector:@selector(noteEditorChanged:) name:NVNoteEditorDidChangeNotification object:nil];
        [[NSAppleEventManager sharedAppleEventManager] setEventHandler:NVSharedApplicationController
            andSelector:@selector(handleGetURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    }
    return NVSharedApplicationController;
}
- (NSArray *)browserControllers { return [[browsers copy] autorelease]; }
- (NotationController *)library { return library; }
- (NVBackupController *)backupController { return backupController; }
- (NVSearchService *)searchService { return searchService; }
- (NVSearchNoteSnapshot *)searchSnapshotForNote:(NoteObject *)note {
    return [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:[NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)]
        title:note->titleString tags:note->labelString source:[[note contentString] string] revision:++searchSnapshotRevision] autorelease];
}
- (void)invalidateBrowserSearches {
    for (AppController *browser in [self browserControllers]) [[browser browserSession] invalidateSearch];
    [self scheduleBrowserRefresh];
}
- (void)searchableNoteDidChange:(NoteObject *)note {
    if (!searchService || ![[library allNotes] containsObject:note]) return;
    if ([searchService updateSnapshot:[self searchSnapshotForNote:note]]) [self invalidateBrowserSearches];
}
- (void)searchableNoteWasRemoved:(NoteObject *)note {
    NSData *uuid = [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
    if ([searchService removeUUID:uuid]) [self invalidateBrowserSearches];
}
- (AppController *)activeBrowser {
    id controller = [[NSApp mainWindow] windowController];
    if ([browsers containsObject:controller]) return controller;
    if ([browsers containsObject:lastActiveBrowser]) return lastActiveBrowser;
    return [browsers count] ? [browsers lastObject] : initialBrowser;
}
- (void)browserBecameActive:(AppController *)browser {
    if (![browsers containsObject:browser]) [browsers addObject:browser];
    lastActiveBrowser = browser;
    [[browser valueForKey:@"notesTableView"] invalidateViewMenus];
    [self retargetMenu:[NSApp mainMenu]];
    [browser updateNoteMenus];
}
- (void)retargetMenu:(NSMenu *)menu {
    if ([(id)[menu delegate] isKindOfClass:[NSView class]]) [menu setDelegate:(id)self];
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == @selector(switchViewLayout:) || [item action] == @selector(toggleLayoutOrientation:)) {
            [menu removeItem:item];
            continue;
        }
        if ([[item target] isKindOfClass:[AppController class]] || [[item target] isKindOfClass:[NSView class]]) [item setTarget:self];
        if ([item submenu]) [self retargetMenu:[item submenu]];
    }
}
- (void)menuNeedsUpdate:(NSMenu *)menu {
    NotesTableView *table = [[self activeBrowser] valueForKey:@"notesTableView"];
    [menu setDelegate:(id)table];
    [table menuNeedsUpdate:menu];
    [menu setDelegate:(id)self];
    [self retargetMenu:menu];
}
- (void)configureMenus {
    [self retargetMenu:[NSApp mainMenu]];
    [self retargetMenu:[initialBrowser statBarMenu]];
    NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
    if ([notesMenu indexOfItemWithTarget:self andAction:@selector(newNote:)] < 0) {
        NSMenuItem *newNoteItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"New Note", nil) action:@selector(newNote:) keyEquivalent:@"n"] autorelease];
        [newNoteItem setTarget:self];
        [notesMenu insertItem:newNoteItem atIndex:0];
    }
    for (NSMenu *root in @[[NSApp mainMenu], [initialBrowser statBarMenu]]) {
        NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
        for (NSUInteger i = 0; i < [pending count]; i++) {
            NSMenu *candidate = pending[i];
            BOOL hasColors = NO, hasSystem = NO;
            BOOL hasPreview = NO, hasViewerMenu = NO;
            NSInteger notePreviewsIndex = -1;
            BOOL hasTopSectionControls = NO;
            for (NSMenuItem *item in [candidate itemArray]) {
                if ([item submenu]) [pending addObject:[item submenu]];
                if ([item action] == @selector(setBWColorScheme:)) hasColors = YES;
                if ([item action] == @selector(setSystemColorScheme:)) hasSystem = YES;
                if ([item action] == @selector(togglePreview:)) {
                    hasPreview = YES;
                    [item setTitle:NSLocalizedString(@"Toggle Preview", nil)];
                }
                if ([item action] == @selector(toggleSourceView:)) [item setTitle:NSLocalizedString(@"Show Source", nil)];
                // The action updates preferences and every browser's layout.
                // A nib value binding would toggle the preference a second time.
                if ([item action] == @selector(toggleWordCount:) && [item infoForBinding:NSValueBinding])
                    [item unbind:NSValueBinding];
                if ([item tag] == 24001) hasViewerMenu = YES;
                if ([item action] == @selector(toggleNoteBodyPreviews:)) notePreviewsIndex = [candidate indexOfItem:item];
                if ([item action] == @selector(toggleTitleInTopSection:)) hasTopSectionControls = YES;
            }
            if (notePreviewsIndex >= 0 && !hasTopSectionControls) {
                NSInteger insertionIndex = notePreviewsIndex + 1;
                for (NSArray *spec in @[@[@"Hide Title in Top Section", @"toggleTitleInTopSection:"],
                                          @[@"Hide Tag in Top Section", @"toggleTagsInTopSection:"],
                                          @[@"Hide Source-Preview Toggle and Syntax Type in Top Section", @"toggleBodyControlsInTopSection:"],
                                          @[@"Hide Notes List", @"toggleNotesList:"],
                                          @[@"Show Preview", @"toggleSourcePreview:"]]) {
                    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(spec[0], nil)
                        action:NSSelectorFromString(spec[1]) keyEquivalent:@""] autorelease];
                    [item setTarget:self];
                    [candidate insertItem:item atIndex:insertionIndex++];
                }
                NSMenuItem *syntax = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Syntax Type", nil)
                    action:NULL keyEquivalent:@""] autorelease];
                NSMenu *choices = [[[NSMenu alloc] initWithTitle:[syntax title]] autorelease];
                for (NSArray *entry in @[@[@"Plain Text", @"plain"], @[@"Markdown", @"markdown"],
                                          @[@"Textile", @"textile"], @[@"HTML", @"html"], @[@"JSON", @"json"], @[@"Org", @"org"]]) {
                    NSMenuItem *choice = [choices addItemWithTitle:NSLocalizedString(entry[0], nil)
                        action:@selector(selectSourceSyntax:) keyEquivalent:@""];
                    [choice setTarget:self];
                    [choice setRepresentedObject:entry[1]];
                }
                [syntax setSubmenu:choices];
                [candidate insertItem:syntax atIndex:insertionIndex];
            }
            // Only the main Preview menu contains Show Source. The status menu
            // keeps its compact toggle without duplicate format submenus.
            if (hasPreview && !hasViewerMenu && [candidate indexOfItemWithTarget:self andAction:@selector(toggleSourceView:)] >= 0) {
                for (NSArray *spec in @[@[@"Preview Format", @"selectPreviewMode:", @[@[@"Markdown", @"markdown"], @[@"Textile", @"textile"], @[@"HTML", @"html"]]],
                                          @[@"Source Syntax", @"selectSourceSyntax:", @[@[@"Plain Text", @"plain"], @[@"Markdown", @"markdown"], @[@"Textile", @"textile"], @[@"HTML", @"html"], @[@"JSON", @"json"], @[@"Org", @"org"]]]]) {
                    NSMenuItem *parent = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(spec[0], nil) action:NULL keyEquivalent:@""] autorelease];
                    [parent setTag:24001];
                    NSMenu *choices = [[[NSMenu alloc] initWithTitle:[parent title]] autorelease];
                    for (NSArray *entry in spec[2]) {
                        NSMenuItem *choice = [choices addItemWithTitle:NSLocalizedString(entry[0], nil) action:NSSelectorFromString(spec[1]) keyEquivalent:@""];
                        [choice setTarget:self]; [choice setRepresentedObject:entry[1]];
                    }
                    [parent setSubmenu:choices]; [candidate addItem:parent];
                }
            }
            if (hasColors && !hasSystem) {
                NSMenuItem *system = [candidate addItemWithTitle:NSLocalizedString(@"Follow System Appearance", nil) action:@selector(setSystemColorScheme:) keyEquivalent:@""];
                [system setTarget:self];
            }
        }
    }
    NSMenu *menu = [NSApp windowsMenu];
    // The old single-window command used this shortcut too. AppKit clears duplicates.
    for (NSMenuItem *existing in [menu itemArray]) {
        if ([existing action] == @selector(makeActiveAndShowWindow:)) {
            [existing setKeyEquivalent:@""];
            [existing setTitle:NSLocalizedString(@"Show Active Window", nil)];
        }
    }
    if ([menu indexOfItemWithTarget:self andAction:@selector(newWindow:)] < 0) {
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"New Window", nil)
                                                    action:@selector(newWindow:) keyEquivalent:@"n"] autorelease];
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
        [item setTarget:self];
        [menu insertItem:item atIndex:0];
        [menu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [initialBrowser applicationDidFinishLaunching:notification];
    [self performSelector:@selector(finishLaunching) withObject:nil afterDelay:0.0];
}
- (void)finishLaunching {
    [self configureMenus];
    [[GlobalPrefs defaultPrefs] registerAppActivationKeystrokeWithTarget:self selector:@selector(toggleNVActivation:)];
    [NSApp setServicesProvider:self];
    [[[GlobalPrefs defaultPrefs] bookmarksController] setAppController:(id)self];
    [self restoreWindowStates];
}
- (void)setLibrary:(NotationController *)newLibrary {
    if (backupRestoreInProgress) return;
    [self setLibrary:newLibrary finishingOldLibrary:YES];
}
- (void)setLibrary:(NotationController *)newLibrary finishingOldLibrary:(BOOL)finish {
    if (newLibrary == library) return;
    if (finish) for (AppController *browser in [self browserControllers]) [browser finishEditing];
    for (NVNoteEditingSession *session in [editingSessions allValues]) {
        if (finish) [session close];
        else [session closeWithoutCommitting];
    }
    [editingSessions removeAllObjects];
    [searchService invalidate];
    [searchService release]; searchService = nil;
    [library setDelegate:nil];
    if (finish) [library closeAllResources];
    else [library finishPreparedBackupRestore];
    [library autorelease];
    library = [newLibrary retain];
    [library setDelegate:self];
    searchService = [[NVSearchService alloc] init];
    NSMutableArray *snapshots = [NSMutableArray arrayWithCapacity:[[library allNotes] count]];
    for (NoteObject *note in [library allNotes]) [snapshots addObject:[self searchSnapshotForNote:note]];
    [searchService synchronizeWithSnapshots:snapshots];
    [library setUndoManager:[[[NSUndoManager alloc] init] autorelease]];
    [library filterNotesFromString:@""];
    for (AppController *browser in [self browserControllers]) [browser attachLibrary:library finishingOldLibrary:finish];
    // The MainMenu owner also retains the application-level preference and status UI.
    if (![browsers containsObject:initialBrowser]) [initialBrowser attachLibrary:library finishingOldLibrary:finish];
    if (!finish) [[GlobalPrefs defaultPrefs] setNotationPrefs:[library notationPrefs] sender:self];
    [[[GlobalPrefs defaultPrefs] bookmarksController] setDataSource:library];
    if (!backupController) backupController = [[NVBackupController alloc] initWithApplicationController:self];
    [backupController setLibrary:library];
}
- (BOOL)restoreBackupArchive:(NSDictionary *)archive toDirectory:(NSURL *)directory error:(NSError **)error {
    if (error) *error = nil;
    if (terminating || restoring || !library || ![archive objectForKey:@"data"] || !directory) {
        if (error) *error = [NSError errorWithDomain:@"NVBackupRestore" code:3 userInfo:@{
            NSLocalizedDescriptionKey:NSLocalizedString(@"The library is not available for a restore operation.", nil)}];
        return NO;
    }
    for (AppController *browser in [self browserControllers]) {
        if ([[browser valueForKey:@"textView"] hasMarkedText]) {
            if (error) *error = [NSError errorWithDomain:@"NVBackupRestore" code:1 userInfo:@{
                NSLocalizedDescriptionKey:NSLocalizedString(@"Finish composing text before switching to a restored library.", nil)}];
            return NO;
        }
    }
    NSString *originalPath = [[[library notesDirectoryURL] URLByResolvingSymlinksInPath] path];
    NSString *newPath = [[directory URLByResolvingSymlinksInPath] path];
    if ([newPath isEqual:originalPath] || [newPath hasPrefix:[originalPath stringByAppendingString:@"/"]]) {
        if (error) *error = [NSError errorWithDomain:@"NVBackupRestore" code:2 userInfo:@{
            NSLocalizedDescriptionKey:NSLocalizedString(@"Restore into an empty folder outside the active notes folder.", nil)}];
        return NO;
    }
    if (![NVBackupStore writeRestoreArchiveData:[archive objectForKey:@"data"] toEmptyDirectory:directory error:error]) return NO;
    for (AppController *browser in [self browserControllers]) [browser finishEditing];
    for (NVNoteEditingSession *session in [editingSessions allValues]) [session commitPendingTextChanges];
    if (![library prepareForBackupRestoreWithError:error]) return NO;
    restoring = YES;
    backupRestoreInProgress = YES;
    FSRef ref;
    OSStatus status = FSPathMakeRef((const UInt8 *)[newPath fileSystemRepresentation], &ref, NULL);
    NotationController *replacement = nil;
    @try {
        if (status == noErr) replacement = [[NotationController alloc] initWithRestoredDirectoryRef:&ref
            unlockedPrefs:[archive objectForKey:@"unlockedPrefs"] error:&status];
    } @catch (NSException *exception) {
        status = -1;
        NSLog(@"Could not initialize the restored library.");
    }
    if (replacement) {
        [self setLibrary:replacement finishingOldLibrary:NO];
        [replacement release];
        backupRestoreInProgress = NO;
        restoring = NO;
        [self saveWindowStates];
        return YES;
    }
    NSError *resumeError = nil;
    // The original checkpoint is safe, but ordinary database autosave needs a
    // journal. Keep the application modal until exclusive resume succeeds.
    for (;;) {
        @try {
            if (!terminating && [library resumeAfterBackupRestoreFailureWithError:&resumeError]) break;
        } @catch (NSException *exception) {
            NSLog(@"Could not resume the original library during backup restore recovery.");
        }
        @try {
            NSInteger response = NSRunCriticalAlertPanel(
                terminating ? NSLocalizedString(@"nvALT could not finish quitting.", nil) :
                    NSLocalizedString(@"The original library cannot resume saving.", nil),
                terminating ? NSLocalizedString(@"Your notes are saved. Choose Quit to try again.", nil) :
                    NSLocalizedString(@"Your notes are saved. Quit any other copy of nvALT, then choose Retry. You can also quit and reopen nvALT.", nil),
                terminating ? NSLocalizedString(@"Quit", nil) : NSLocalizedString(@"Retry", nil),
                terminating ? nil : NSLocalizedString(@"Quit", nil), nil);
            if (terminating || response == NSAlertAlternateReturn) [NSApp terminate:self];
        } @catch (NSException *exception) {
            // A canceled or exceptional termination must not expose editors
            // after the original journal failed to reopen.
            NSLog(@"Could not complete backup restore recovery.");
        }
    }
    backupRestoreInProgress = NO;
    restoring = NO;
    if (error) *error = resumeError ?: [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{
        NSLocalizedDescriptionKey:NSLocalizedString(@"The restored library could not open. The original library remains selected.", nil)}];
    return NO;
}
- (IBAction)newWindow:(id)sender {
    if (!library || backupRestoreInProgress) return;
    AppController *browser = [[AppController alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"BrowserWindow" bundle:[NSBundle mainBundle]];
    NSArray *objects = nil;
    if (![nib instantiateWithOwner:browser topLevelObjects:&objects]) {
        [nib release];
        [browser release];
        NSBeep();
        return;
    }
    [browser retainWindowObjects:objects];
    [nib release];
    [browsers addObject:browser];
    [browser attachLibrary:library];
    [browser prepareAdditionalWindow];
    NSWindow *previous = [[self activeBrowser] window];
    NSPoint topLeft = NSMakePoint(NSMinX([previous frame]) + 24, NSMaxY([previous frame]) - 24);
    [[browser window] cascadeTopLeftFromPoint:topLeft];
    lastActiveBrowser = browser;
    [[browser window] makeKeyAndOrderFront:self];
    [browser release];
    [self saveWindowStates];
}
- (void)browserWillClose:(AppController *)browser {
    [browser finishEditing];
    if (terminating) return;
    [browser retain];
    [browsers removeObjectIdenticalTo:browser];
    if (lastActiveBrowser == browser) lastActiveBrowser = [browsers lastObject];
    [self saveWindowStates];
    BOOL quit = ![browsers count] && [[GlobalPrefs defaultPrefs] quitWhenClosingWindow];
    [browser performSelector:@selector(release) withObject:nil afterDelay:0.0];
    if (quit) [NSApp terminate:self];
}
- (void)saveWindowStates {
    if (terminating || restoring) return;
    NSMutableArray *states = [NSMutableArray array];
    for (AppController *browser in [self browserControllers]) [states addObject:[browser browserWindowState]];
    [[NSUserDefaults standardUserDefaults] setObject:states forKey:NVBrowserWindowsKey];
}
- (void)restoreWindowStates {
    NSArray *states = [[NSUserDefaults standardUserDefaults] arrayForKey:NVBrowserWindowsKey];
    restoring = YES;
    for (NSUInteger i = 0; i < MIN([states count], 20U); i++) {
        id state = [states objectAtIndex:i];
        if (![state isKindOfClass:[NSDictionary class]]) continue;
        if (i) [self newWindow:self];
        [[browsers lastObject] restoreBrowserWindowState:state];
    }
    restoring = NO;
}
- (NVNoteEditingSession *)editingSessionForNote:(NoteObject *)note {
    if (!note) return nil;
    NSString *key = [NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]];
    NVNoteEditingSession *session = [editingSessions objectForKey:key];
    if (!session) {
        session = [[[NVNoteEditingSession alloc] initWithNote:note] autorelease];
        [editingSessions setObject:session forKey:key];
    }
    return session;
}
- (void)reloadCachedEditingSessionsFromLibrary {
    // Refresh the display font in cached sessions, including notes with no editor.
    // Each session defers the refresh while an attached editor has marked text.
    for (NVNoteEditingSession *session in [editingSessions allValues]) [session reloadFromNote];
    [self scheduleBrowserRefresh];
}
- (void)performLibraryInvocation:(NSInvocation *)invocation fromBrowser:(AppController *)browser {
    // Only the active termination callback can use normal checkpoint calls.
    // A failed termination returns to the same paused command boundary.
    if (!finishingTermination && [self rejectInvocationDuringBackupRestore:invocation]) return;
    AppController *previous = operationBrowser;
    operationBrowser = browser;
    @try { [invocation invokeWithTarget:library]; }
    @finally { operationBrowser = previous; }
}
- (void)preserveExternalContents:(NSAttributedString *)contents forNote:(NoteObject *)note {
    NSString *title = [note->titleString stringByAppendingFormat:@" (%@)", NSLocalizedString(@"external changes", nil)];
    NoteObject *copy = [[[NoteObject alloc] initWithNoteBody:contents title:title delegate:library
                                                   format:[library currentNoteStorageFormat] labels:note->labelString] autorelease];
    preservingExternalContents = YES;
    @try { [library addNewNote:copy]; }
    @finally { preservingExternalContents = NO; }
}
- (void)refreshBrowsers {
    for (AppController *browser in [self browserControllers]) [[browser browserSession] libraryDidChange];
}
- (void)scheduleBrowserRefresh {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshBrowsers) object:nil];
    [self performSelector:@selector(refreshBrowsers) withObject:nil afterDelay:0.0];
}
- (BOOL)notationListShouldChange:(NotationController *)notation { return YES; }
- (void)notationListMightChange:(NotationController *)notation { }
- (void)notationListDidChange:(NotationController *)notation { [self scheduleBrowserRefresh]; }
- (void)rowShouldUpdate:(NSInteger)row { [self scheduleBrowserRefresh]; }
- (void)noteMetadataUpdated:(NoteObject *)note {
    for (AppController *browser in [self browserControllers]) {
        if ([browser selectedNoteObject] == note) [browser updateNoteHeader];
    }
    [self scheduleBrowserRefresh];
}
- (void)setNote:(NoteObject *)note metadataValue:(NSString *)value isTitle:(BOOL)isTitle {
    if (backupRestoreInProgress) return;
    if (![[library allNotes] containsObject:note]) return;
    [[self editingSessionForNote:note] setMetadataValue:value isTitle:isTitle];
}
- (void)titleUpdatedForNote:(NoteObject *)note {
    for (AppController *browser in [self browserControllers]) [browser titleUpdatedForNote:note];
    [self scheduleBrowserRefresh];
}
- (void)contentsUpdatedForNote:(NoteObject *)note {
    [[self editingSessionForNote:note] reloadFromNote];
    [self scheduleBrowserRefresh];
}
- (void)noteEditorChanged:(NSNotification *)notification {
    for (AppController *browser in [self browserControllers]) [browser refreshEditorForNote:[notification object]];
    [self scheduleBrowserRefresh];
}
- (void)notation:(NotationController *)notation revealNote:(NoteObject *)note options:(NSUInteger)options {
    if (preservingExternalContents) { [self scheduleBrowserRefresh]; return; }
    AppController *browser = operationBrowser ?: [self activeBrowser];
    [[browser browserSession] libraryDidChange];
    [browser revealNote:note options:options];
}
- (void)notation:(NotationController *)notation revealNotes:(NSArray *)notes {
    if (preservingExternalContents) { [self scheduleBrowserRefresh]; return; }
    AppController *browser = operationBrowser ?: [self activeBrowser];
    [[browser browserSession] libraryDidChange];
    [browser notation:(id)[browser browserSession] revealNotes:notes];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    for (AppController *browser in [self browserControllers]) [browser finishEditing];
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self saveWindowStates];
    terminating = YES;
    finishingTermination = YES;
    @try {
        [backupController stop];
        [searchService invalidate];
        for (NVNoteEditingSession *session in [editingSessions allValues]) [session commitPendingTextChanges];
        [initialBrowser applicationWillTerminate:notification];
        for (NVNoteEditingSession *session in [editingSessions allValues]) [session close];
    } @finally {
        finishingTermination = NO;
    }
}
- (IBAction)toggleNVActivation:(id)sender {
    if (backupRestoreInProgress) return;
    if (![browsers count]) [self newWindow:sender];
    else [[self activeBrowser] toggleNVActivation:sender];
}
- (void)application:(NSApplication *)sender openFiles:(NSArray *)files {
    if (backupRestoreInProgress) { [sender replyToOpenOrPrint:NSApplicationDelegateReplyFailure]; return; }
    if (library && ![browsers count]) [self newWindow:sender];
    [[self activeBrowser] application:sender openFiles:files];
}
- (void)createFromSelection:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
    if (backupRestoreInProgress) {
        if (error) *error = NSLocalizedString(@"Finish restoring the library before creating a note from a selection.", nil);
        return;
    }
    [[self forwardTargetForSelector:_cmd] createFromSelection:pboard userData:userData error:error];
}
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    if (backupRestoreInProgress) {
        [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithInt32:errAEEventNotHandled] forKeyword:keyErrorNumber];
        return;
    }
    if (library && ![browsers count]) [self newWindow:self];
    [[self activeBrowser] handleGetURLEvent:event withReplyEvent:reply];
}
- (void)refreshNotesList { for (AppController *browser in [self browserControllers]) [browser refreshNotesList]; }
- (void)updateRTL { for (AppController *browser in [self browserControllers]) [browser updateRTL]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    if (backupRestoreInProgress) return NO;
    if (![browsers count]) [self newWindow:self];
    else [[[self activeBrowser] window] makeKeyAndOrderFront:self];
    return YES;
}
- (BOOL)applicationOpenUntitledFile:(NSApplication *)application {
    return [self applicationShouldHandleReopen:application hasVisibleWindows:NO];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (backupRestoreInProgress) return NO;
    if ([item action] == @selector(newWindow:)) return library != nil;
    id target = [self forwardTargetForSelector:[item action]];
    return [target respondsToSelector:@selector(validateMenuItem:)] ? [target validateMenuItem:item] : YES;
}
- (id)forwardTargetForSelector:(SEL)selector {
    NSString *name = NSStringFromSelector(selector);
    if ([name isEqualToString:@"showPreferencesWindow:"] || [name hasPrefix:@"application"] ||
        [name isEqualToString:@"togDockIcon:"] || [name isEqualToString:@"toggleStatusItem:"]) return initialBrowser;
    AppController *browser = [self activeBrowser];
    if ([browser respondsToSelector:selector]) return browser;
    for (NSString *key in @[@"notesTableView", @"textView", @"field"]) {
        id view = [browser valueForKey:key];
        if ([view respondsToSelector:selector]) return view;
    }
    return browser;
}
- (BOOL)respondsToSelector:(SEL)selector { return [super respondsToSelector:selector] || [[self forwardTargetForSelector:selector] respondsToSelector:selector]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [super methodSignatureForSelector:selector] ?: [[self forwardTargetForSelector:selector] methodSignatureForSelector:selector];
}
- (BOOL)rejectInvocationDuringBackupRestore:(NSInvocation *)invocation {
    if (!backupRestoreInProgress) return NO;
    NSUInteger length = [[invocation methodSignature] methodReturnLength];
    if (length) {
        NSMutableData *zero = [NSMutableData dataWithLength:length];
        [invocation setReturnValue:[zero mutableBytes]];
    }
    return YES;
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    if ([self rejectInvocationDuringBackupRestore:invocation]) return;
    SEL selector = [invocation selector];
    if (selector == @selector(setSystemColorScheme:) || selector == @selector(setBWColorScheme:) ||
        selector == @selector(setLCColorScheme:) || selector == @selector(setUserColorScheme:)) {
        for (AppController *browser in [self browserControllers]) [invocation invokeWithTarget:browser];
        return;
    }
    id target = [self forwardTargetForSelector:[invocation selector]];
    if ([target respondsToSelector:[invocation selector]]) [invocation invokeWithTarget:target];
    else [self doesNotRecognizeSelector:[invocation selector]];
}
@end
