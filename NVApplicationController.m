#import "NVApplicationController.h"
#import "AppController.h"
#import "AppController_Importing.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "BookmarksController.h"
#import "NotationPrefs.h"
#import "NotationSyncServiceManager.h"
#import "NSString_NV.h"

static NVApplicationController *NVSharedApplicationController;
static NSString * const NVBrowserWindowsKey = @"NVBrowserWindows";

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
    if (newLibrary == library) return;
    for (AppController *browser in [self browserControllers]) [browser finishEditing];
    for (NVNoteEditingSession *session in [editingSessions allValues]) [session close];
    [editingSessions removeAllObjects];
    [library setDelegate:nil];
    [library closeAllResources];
    [library autorelease];
    library = [newLibrary retain];
    [library setDelegate:self];
    [library setUndoManager:[[[NSUndoManager alloc] init] autorelease]];
    [library filterNotesFromString:@""];
    for (AppController *browser in [self browserControllers]) [browser attachLibrary:library];
    // The MainMenu owner also retains the application-level preference and status UI.
    if (![browsers containsObject:initialBrowser]) [initialBrowser attachLibrary:library];
    [[[GlobalPrefs defaultPrefs] bookmarksController] setDataSource:library];
    [library startSyncServices];
}
- (IBAction)newWindow:(id)sender {
    if (!library) return;
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
- (void)performLibraryInvocation:(NSInvocation *)invocation fromBrowser:(AppController *)browser {
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
    return [initialBrowser applicationShouldTerminate:sender];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self saveWindowStates];
    terminating = YES;
    for (NVNoteEditingSession *session in [editingSessions allValues]) [session commitPendingTextChanges];
    [initialBrowser applicationWillTerminate:notification];
    for (NVNoteEditingSession *session in [editingSessions allValues]) [session close];
}
- (IBAction)toggleNVActivation:(id)sender {
    if (![browsers count]) [self newWindow:sender];
    else [[self activeBrowser] toggleNVActivation:sender];
}
- (void)application:(NSApplication *)sender openFiles:(NSArray *)files {
    if (library && ![browsers count]) [self newWindow:sender];
    [[self activeBrowser] application:sender openFiles:files];
}
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    if (library && ![browsers count]) [self newWindow:self];
    [[self activeBrowser] handleGetURLEvent:event withReplyEvent:reply];
}
- (void)refreshNotesList { for (AppController *browser in [self browserControllers]) [browser refreshNotesList]; }
- (void)updateRTL { for (AppController *browser in [self browserControllers]) [browser updateRTL]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    if (![browsers count]) [self newWindow:self];
    else [[[self activeBrowser] window] makeKeyAndOrderFront:self];
    return YES;
}
- (BOOL)applicationOpenUntitledFile:(NSApplication *)application {
    return [self applicationShouldHandleReopen:application hasVisibleWindows:NO];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
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
- (void)forwardInvocation:(NSInvocation *)invocation {
    id target = [self forwardTargetForSelector:[invocation selector]];
    if ([target respondsToSelector:[invocation selector]]) [invocation invokeWithTarget:target];
    else [self doesNotRecognizeSelector:[invocation selector]];
}
@end
