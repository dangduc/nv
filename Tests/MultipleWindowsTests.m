// Loaded only by run-multiple-windows-tests.py into a disposable app copy.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "NoteAttributeColumn.h"
#import "LinkingEditor.h"
#import "DualField.h"
#import "GlobalPrefs.h"
#import "NSFileManager_NV.h"
#import "ODBEditor.h"

static NSString *TestDirectory;
static NSUInteger Checks;
static void Check(BOOL result, NSString *description) {
    if (!result) { NSLog(@"FAIL: %@", description); exit(1); }
    NSLog(@"PASS: %@", description); Checks++;
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static NoteObject *MakeNote(NotationController *library, NSString *title, NSString *text) {
    NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:text] autorelease]
        title:title delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
    [library addNewNote:note]; Pump(); return note;
}
static void Swap(Class cls, SEL original, SEL replacement) {
    method_exchangeImplementations(class_getInstanceMethod(cls, original), class_getInstanceMethod(cls, replacement));
}
@interface NSFileManager (NVTestPaths)
- (NSString *)nv_testSupportDirectory;
@end
@implementation NSFileManager (NVTestPaths)
- (NSString *)nv_testSupportDirectory { return [TestDirectory stringByAppendingPathComponent:@"Support"]; }
@end

@interface ODBEditor (NVTestIsolation)
- (void)nv_skipExternalEditorInitialization:(id)prefs;
@end
@implementation ODBEditor (NVTestIsolation)
- (void)nv_skipExternalEditorInitialization:(id)prefs { }
@end

@interface AppController (NVWindowTests)
- (void)nv_testLaunch:(NSNotification *)notification;
- (void)nv_testDelayed;
- (void)nv_runTests;
@end
@implementation AppController (NVWindowTests)
+ (void)load {
    const char *directory = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!directory) return;
    TestDirectory = [[NSString stringWithUTF8String:directory] copy];
    Swap(self, @selector(applicationDidFinishLaunching:), @selector(nv_testLaunch:));
    Swap(self, @selector(runDelayedUIActionsAfterLaunch), @selector(nv_testDelayed));
    Swap([NSFileManager class], @selector(applicationSupportDirectory), @selector(nv_testSupportDirectory));
    Swap([ODBEditor class], @selector(initializeDatabase:), @selector(nv_skipExternalEditorInitialization:));
}
- (void)nv_testDelayed { }
- (void)nv_finishTests { [NSApp terminate:self]; }
- (void)nv_testLaunch:(NSNotification *)notification {
    [self setupViewsAfterAppAwakened];
    FSRef directory; OSStatus err = FSPathMakeRef((const UInt8 *)[[TestDirectory stringByAppendingPathComponent:@"Notes"] fileSystemRepresentation], &directory, NULL);
    Check(err == noErr, @"temporary library directory exists");
    NotationController *library = [[[NotationController alloc] initWithDirectoryRef:&directory error:&err] autorelease];
    Check(library != nil && err == noErr, @"temporary library opens");
    [self setNotationController:library];
    [self prepareAdditionalWindow];
    [[self window] makeKeyAndOrderFront:self];
    [self performSelector:@selector(nv_runTests) withObject:nil afterDelay:0.3];
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        if (getenv("NV_WINDOW_TEST_RELAUNCH")) {
            Check([[app browserControllers] count] == 2, @"relaunch restores both browser windows");
            Check([[library allNotes] count] == 1 && [((NoteObject *)[[library allNotes] lastObject])->titleString isEqualToString:@"Beta"], @"relaunch reads the saved library");
            Check([[[((NoteObject *)[[library allNotes] lastObject]) contentString] string] isEqualToString:@"beta only persisted edit"],
                @"relaunch preserves the exact body edited in a browser");
            Check([[app browserControllers][0] selectedNoteObject] != nil, @"relaunch restores the first window selection");
            Check([[[app browserControllers][1] browserSession] reverseSorted], @"relaunch restores second window sort");
            AppController *first = [app browserControllers][0];
            AppController *second = [app browserControllers][1];
            Check([[[first browserSession] searchString] isEqualToString:@"beta"] &&
                [[[second browserSession] searchString] isEqualToString:@"only"],
                @"relaunch restores distinct non-empty browser queries");
            DualField *firstField = [first valueForKey:@"field"], *secondField = [second valueForKey:@"field"];
            Check([[firstField stringValue] isEqualToString:@"beta"] && [[secondField stringValue] isEqualToString:@"only"] &&
                [[firstField snapbackString] isEqualToString:@"beta"],
                @"relaunch restores each browser search field");
            if ([[firstField snapbackString] length]) [firstField snapback:self];
            if ([[secondField snapbackString] length]) [secondField snapback:self];
            Pump();
            Check([[firstField stringValue] isEqualToString:@"beta"] && [[secondField stringValue] isEqualToString:@"only"],
                @"snapback returns each restored field to its own query");
            [[first window] makeKeyAndOrderFront:self]; [first searchForString:@"needle"]; Pump();
            // Match the preference-change path: the cache journal belongs to the application.
            [library flushAllNoteChanges];
            [library closeJournal];
            NSString *newPath = [TestDirectory stringByAppendingPathComponent:@"Other Notes"];
            [[NSFileManager defaultManager] createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:NULL];
            FSRef newRef; OSStatus error = FSPathMakeRef((const UInt8 *)[newPath fileSystemRepresentation], &newRef, NULL);
            NotationController *nextLibrary = [[[NotationController alloc] initWithDirectoryRef:&newRef error:&error] autorelease];
            Check(nextLibrary != nil && error == noErr, @"replacement library opens");
            [app setLibrary:nextLibrary]; Pump();
            Check([[app browserControllers][0] sharedNotationController] == nextLibrary && [[app browserControllers][1] sharedNotationController] == nextLibrary, @"changing libraries updates every browser together");
            Check([[[first browserSession] searchString] isEqualToString:@"needle"] && [[[first valueForKey:@"field"] stringValue] isEqualToString:@"needle"], @"changing libraries preserves each browser query");
            library = nextLibrary;
            NSLog(@"RELAUNCH TESTS PASSED (%lu checks)", (unsigned long)Checks);
            [library flushAllNoteChanges]; [library closeJournal];
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
            [[NSUserDefaults standardUserDefaults] synchronize];
            exit(0);
        }
        AppController *a = self;
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha beta") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"beta only") retain];
        NSMenuItem *newWindow = [[NSApp windowsMenu] itemAtIndex:0];
        Check([newWindow action] == @selector(newWindow:) && [[newWindow keyEquivalent] isEqualToString:@"n"] && [newWindow keyEquivalentModifierMask] == (NSEventModifierFlagCommand | NSEventModifierFlagShift), @"Window menu exposes Command-Shift-N");
        [NSApp sendAction:[newWindow action] to:[newWindow target] from:newWindow]; Pump();
        Check([[app browserControllers] count] == 2, @"New Window instantiates a second browser nib");
        AppController *b = [[app browserControllers] lastObject];
        Check([a sharedNotationController] == [b sharedNotationController], @"windows share exactly one library");
        NVBrowserSession *sa = [a browserSession], *sb = [b browserSession];
        [[a window] makeKeyAndOrderFront:self]; [a searchForString:@"alpha"]; Pump();
        [[b window] makeKeyAndOrderFront:self]; [(id)app searchForString:@"beta"]; Pump();
        Check([[sa searchString] isEqualToString:@"alpha"] && [[sb searchString] isEqualToString:@"beta"], @"search commands use the active browser and preserve the other query");
        [b searchForString:@"Created in B"]; [b fieldAction:self]; Pump();
        NoteObject *created = [b selectedNoteObject];
        LinkingEditor *newEditor = [b valueForKey:@"textView"];
        [newEditor insertText:@"new note content" replacementRange:NSMakeRange(0,0)]; Pump();
        Check([created delegate] == library && [created->titleString isEqualToString:@"Created in B"] && [[[created contentString] string] isEqualToString:@"new note content"], @"creating and typing in a new browser writes to the shared library");
        Check([a selectedNoteObject] == alpha, @"creation in B preserves A selection");
        [library removeNotes:@[created]]; Pump();
        [b searchForString:@"beta"]; Pump();
        [sa filterNotesFromString:@"a"]; [sb filterNotesFromString:@"beta"]; [sa filterNotesFromString:@"al"];
        Check([sa noteObjectAtFilteredIndex:0] == alpha && [[sa notesListDataSource] count] == 1, @"interleaved incremental searches preserve Alpha match");
        Check([[sb notesListDataSource] count] == 2, @"searching A leaves B results unchanged");
        [sa filterNotesFromString:@""]; [sb filterNotesFromString:@""];
        [sa setSortColumn:[[a valueForKey:@"notesTableView"] noteAttributeColumnForIdentifier:NoteTitleColumnString] reversed:NO];
        [sb setSortColumn:[[b valueForKey:@"notesTableView"] noteAttributeColumnForIdentifier:NoteTitleColumnString] reversed:YES];
        Check([sa noteObjectAtFilteredIndex:0] == alpha && [sb noteObjectAtFilteredIndex:0] == beta, @"each window sorts independently");
        CGFloat bHeight = [b notesListHeight];
        [a setNotesListHeight:100]; Pump();
        Check(![a horizontalLayout] && ![b horizontalLayout] && fabs([b notesListHeight] - bHeight) < 1,
            @"stacked browser dividers remain independent");
        [a revealNote:alpha options:0]; [b revealNote:alpha options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"], *eb = [b valueForKey:@"textView"];
        Check([ea textStorage] == [eb textStorage], @"same note has one shared NSTextStorage");
        Check([ea window] != [eb window], @"browser editors belong to distinct windows");
        Check([ea layoutManager] != [eb layoutManager], @"each window retains its own text layout");
        [[a window] makeKeyAndOrderFront:self]; [[a window] makeFirstResponder:ea];
        [ea setSelectedRange:NSMakeRange([[ea string] length],0)];
        [ea insertText:@" A" replacementRange:[ea selectedRange]]; Pump();
        Check([[eb string] isEqualToString:@"alpha beta A"] && [[[alpha contentString] string] isEqualToString:[eb string]], @"typing in A immediately updates B and the library");
        [[b window] makeKeyAndOrderFront:self]; [[b window] makeFirstResponder:eb];
        [eb setSelectedRange:NSMakeRange([[eb string] length],0)];
        [eb insertText:@" B" replacementRange:[eb selectedRange]]; Pump();
        Check([[ea string] isEqualToString:@"alpha beta A B"], @"alternating editors preserve both edits");
        [eb undo:self]; Pump();
        Check([[ea string] isEqualToString:@"alpha beta A"] && [[eb string] isEqualToString:[ea string]], @"undo updates both editors");
        [[alpha undoManager] redo]; Pump();
        Check([[ea string] isEqualToString:@"alpha beta A B"], @"redo updates shared note");
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"external alpha beta"] autorelease]]; Pump();
        Check([[ea string] isEqualToString:@"external alpha beta"] && [[eb string] isEqualToString:[ea string]], @"external content updates reach both editors");
        // Reset the note before testing a deferred external update during IME composition.
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"alpha beta"] autorelease]];
        [eb setMarkedText:@"local " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        Check([eb hasMarkedText], @"native editor has an active marked text composition");
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"alpha beta remote"] autorelease]];
        Check([[eb string] isEqualToString:@"local alpha beta"], @"external update does not replace marked text");
        [eb unmarkText]; [b finishEditing]; Pump();
        Check([[ea string] isEqualToString:@"local alpha beta remote"] && [[[alpha contentString] string] isEqualToString:[ea string]], @"non-overlapping external update merges after composition");
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"alpha beta"] autorelease]];
        [eb setMarkedText:@"local" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(0,5)];
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"remote beta"] autorelease]];
        [eb unmarkText]; [b finishEditing]; Pump();
        NoteObject *conflict = nil;
        for (NoteObject *note in [library allNotes]) if ([[[note contentString] string] isEqualToString:@"remote beta"]) conflict = note;
        Check(conflict != nil && [[eb string] isEqualToString:@"local beta"], @"overlapping external edits are preserved in a separate note");
        [library removeNotes:@[conflict]]; Pump();
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"alpha beta A"] autorelease]];
        [eb setSelectedRange:NSMakeRange([[eb string] length],0)];
        [eb insertText:@" B" replacementRange:[eb selectedRange]]; Pump();
        [eb setSelectedRange:NSMakeRange(2,2)];
        [a revealNote:beta options:0]; Pump();
        Check([ea textStorage] != [eb textStorage], @"switching notes detaches only one window layout manager");
        Check([b selectedNoteObject] == alpha && NSEqualRanges([eb selectedRange],NSMakeRange(2,2)), @"switching notes leaves the other window selection unchanged");
        NSDictionary *state = [[b browserWindowState] retain];
        [app newWindow:self]; Pump();
        AppController *c = [[app browserControllers] lastObject]; [c restoreBrowserWindowState:state]; Pump();
        Check([c selectedNoteObject] == alpha && [[c browserSession] reverseSorted], @"window state restores selected note and sort");
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"QuitWhenClosingMainWindow"];
        [[b window] close]; Pump();
        Check([[app browserControllers] count] == 2, @"closing one browser leaves other browsers open");
        [[alpha undoManager] undo]; Pump();
        Check([[[c valueForKey:@"textView"] string] isEqualToString:@"alpha beta A"], @"undo survives closure of its originating window");
        [library removeNotes:@[alpha]]; Pump();
        Check([[c browserSession] indexInFilteredListForNoteIdenticalTo:alpha] == NSNotFound && [c selectedNoteObject] != alpha, @"deletion clears the note from every window");
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"QuitWhenClosingMainWindow"];
        [[a window] close]; Pump();
        Check([[app browserControllers] count] == 1, @"closing the initial window keeps the library and remaining browser alive");
        [c revealNote:beta options:0];
        [[c window] close]; Pump();
        Check([[app browserControllers] count] == 0, @"all browsers can close without quitting when the preference is disabled");
        [(id)app applicationShouldHandleReopen:NSApp hasVisibleWindows:NO]; Pump();
        Check([[app browserControllers] count] == 1 && [app library] == library, @"reopen creates a browser using the existing library");
        AppController *reopened = [[app browserControllers] lastObject];
        [reopened revealNote:beta options:0];
        [app newWindow:self]; Pump();
        [[[app browserControllers] lastObject] restoreBrowserWindowState:state];
        [[reopened window] makeKeyAndOrderFront:self]; [reopened searchForString:@"beta"]; Pump();
        LinkingEditor *durableEditor = [reopened valueForKey:@"textView"];
        [[reopened window] makeFirstResponder:durableEditor];
        [durableEditor insertText:@" persisted edit" replacementRange:NSMakeRange([[durableEditor string] length], 0)]; Pump();
        AppController *secondRestored = [[app browserControllers] lastObject];
        [[secondRestored window] makeKeyAndOrderFront:self]; [secondRestored searchForString:@"only"]; Pump();
        [app saveWindowStates];
        Check([[[NSUserDefaults standardUserDefaults] arrayForKey:@"NVBrowserWindows"] count] == 2, @"persistence records only open browser windows");
        Check([library flushAllNoteChanges], @"shared library flushes successfully");
        [library closeJournal];
        [state release]; [alpha release]; [beta release];
        NSLog(@"MULTIWINDOW TESTS PASSED (%lu checks)", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
