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
    [NSApp activateIgnoringOtherApps:YES];
    [[self window] makeKeyAndOrderFront:self];
    [self performSelector:@selector(nv_runTests) withObject:nil afterDelay:0.3];
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *a = self;
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        NoteObject *note = [MakeNote(library, @"Undo composition ordering", @"base") retain];
        [a revealNote:note options:0]; [b revealNote:note options:0]; Pump();
        LinkingEditor *ea = [a valueForKey:@"textView"];
        LinkingEditor *eb = [b valueForKey:@"textView"];
        [[b window] makeFirstResponder:eb];
        [eb insertText:@" committed" replacementRange:NSMakeRange(4,0)]; Pump();
        Check([[ea string] isEqualToString:@"base committed"] && [[eb string] isEqualToString:[ea string]], @"ordinary edit reaches both browser editors");
        [eb undo:self]; Pump();
        Check([[[note contentString] string] isEqualToString:@"base"], @"control: ordinary undo updates the note model");
        [eb redo:self]; Pump();
        Check([[[note contentString] string] isEqualToString:@"base committed"], @"control: ordinary redo updates the note model");

        [eb setMarkedText:@"draft " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        Check([eb hasMarkedText] && [[eb string] isEqualToString:@"draft base committed"], @"native editor has an active composition");
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"base committed REMOTE"] autorelease]];
        Check([[eb string] isEqualToString:@"draft base committed"], @"external update is initially deferred while text is marked");
        Check([[[note contentString] string] isEqualToString:@"base committed REMOTE"], @"external text is initially present in model");

        NSMenuItem *undoItem = [[[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@""] autorelease];
        NSMenuItem *redoItem = [[[NSMenuItem alloc] initWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@""] autorelease];
        Check([ea validateMenuItem:undoItem], @"undo menu permits a pending composition and external update");
        Check(![ea validateMenuItem:redoItem], @"redo menu excludes a pending composition and external update");
        // Invoke Undo from the other browser while b owns the marked text.
        [ea undo:self]; Pump();
        Check(![eb hasMarkedText], @"undo finishes composition in every attached editor");
        Check([[[note contentString] string] isEqualToString:@"base committed REMOTE"], @"undo preserves the deferred external update and removes only the local composition");
        Check([[ea string] isEqualToString:[eb string]] && [[ea string] isEqualToString:[[note contentString] string]], @"both browser editors match the preserved model");
        [ea undo:self]; Pump();
        Check([[[note contentString] string] isEqualToString:@"base committed REMOTE"], @"older undo snapshots cannot remove the external update");
        [eb redo:self]; Pump();
        Check([[[note contentString] string] isEqualToString:@"draft base committed REMOTE"], @"redo restores the local composition while retaining external text");
        Check([[library allNotes] count] == 1, @"disjoint edits merge without a conflict copy");

        NoteObject *overlap = [MakeNote(library, @"Overlapping composition", @"base") retain];
        [a revealNote:overlap options:0]; [b revealNote:overlap options:0]; Pump();
        [eb insertText:@" committed" replacementRange:NSMakeRange(4,0)]; Pump();
        [eb setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(0,4)];
        [overlap setContentString:[[[NSAttributedString alloc] initWithString:@"REMOTE committed"] autorelease]];
        [ea undo:self]; Pump();
        Check([[[overlap contentString] string] isEqualToString:@"base committed"], @"overlapping edit undo removes the local composition");
        NSUInteger remoteCopies = 0;
        for (NoteObject *candidate in [library allNotes]) {
            if ([[[candidate contentString] string] isEqualToString:@"REMOTE committed"]) remoteCopies++;
        }
        Check(remoteCopies == 1, @"overlapping external edit survives in exactly one conflict copy");
        [eb redo:self]; Pump();
        Check([[[overlap contentString] string] isEqualToString:@"LOCAL committed"], @"redo restores the overlapping local edit");
        Check([[library allNotes] count] == 3, @"redo does not duplicate the conflict note");

        NoteObject *redoNote = [MakeNote(library, @"Redo during composition", @"one") retain];
        [a revealNote:redoNote options:0]; [b revealNote:redoNote options:0]; Pump();
        [eb insertText:@" two" replacementRange:NSMakeRange(3,0)]; Pump();
        [eb undo:self]; Pump();
        Check([[redoNote undoManager] canRedo], @"redo control has a pending previous edit");
        [eb setMarkedText:@"draft " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        [redoNote setContentString:[[[NSAttributedString alloc] initWithString:@"one REMOTE"] autorelease]];
        Check(![ea validateMenuItem:redoItem], @"redo menu disables a stale redo branch during composition");
        [ea redo:self]; Pump();
        Check(![eb hasMarkedText], @"redo finishes another browser's composition");
        Check([[[redoNote contentString] string] isEqualToString:@"draft one REMOTE"], @"redo preserves new local and external edits instead of replaying stale history");
        Check(![[redoNote undoManager] canRedo], @"new composition invalidates the previous redo branch");
        [eb undo:self]; Pump();
        Check([[[redoNote contentString] string] isEqualToString:@"one REMOTE"], @"undo after a redo command still preserves the external update");
        NoteObject *firstEdit = [MakeNote(library, @"First marked edit", @"initial") retain];
        [a revealNote:firstEdit options:0]; [b revealNote:firstEdit options:0]; Pump();
        Check(![[firstEdit undoManager] canUndo], @"first composition control has no existing undo group");
        [eb setMarkedText:@"draft " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        Check([ea validateMenuItem:undoItem], @"undo menu enables the first marked edit without an existing undo group");
        [ea undo:self]; Pump();
        Check([[[firstEdit contentString] string] isEqualToString:@"initial"], @"undo removes the first marked edit");
        Check([ea validateMenuItem:redoItem], @"redo menu enables the finalized composition after undo");
        [a searchForString:@"Unchanged external snapshot"]; Pump();
        [NSApp activateIgnoringOtherApps:YES];
        [[b window] makeKeyAndOrderFront:self];
        NSDate *activationDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while ((![[b window] isKeyWindow] || ![NSApp isActive] || [app activeBrowser] != b) &&
            [activationDeadline timeIntervalSinceNow] > 0) Pump();
        if (![[b window] isKeyWindow] || ![NSApp isActive] || [app activeBrowser] != b)
            NSLog(@"Reveal fixture: active=%d key=%@ main=%@ peer=%@ activeBrowser=%@ expected=%@",
                [NSApp isActive], [NSApp keyWindow], [NSApp mainWindow], [b window], [app activeBrowser], b);
        Check([[b window] isKeyWindow] && [NSApp isActive] && [app activeBrowser] == b,
            @"the peer browser is active before background reveal");
        NoteObject *noop = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"base"] autorelease]
            title:@"Unchanged external snapshot" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
        [library addNewNote:noop];
        Check([[a browserSession] indexInFilteredListForNoteIdenticalTo:noop] == NSNotFound,
            @"a new matching note is absent before the background browser refresh");
        [a revealNote:noop options:0];
        Check([a selectedNoteObject] == noop && [[a fieldSearchString] isEqual:@"Unchanged external snapshot"],
            @"reveal refreshes a stale browser list without clearing its matching query");
        Check([[b window] isKeyWindow], @"background reveal preserves the active window");
        // Keep the background browser filtered away from the target. Reveal
        // must select the requested note without requiring that window to be key.
        [a searchForString:@"First marked edit"]; Pump();
        [[b window] makeKeyAndOrderFront:self]; Pump();
        [a revealNote:noop options:0]; [b revealNote:noop options:0]; Pump();
        Check([a selectedNoteObject] == noop && [b selectedNoteObject] == noop,
            @"background reveal selects the requested note in both editors");
        Check([[a fieldSearchString] length] == 0 && [[b fieldSearchString] length] == 0 && [[b window] isKeyWindow],
            @"revealing an excluded note clears its browser query without activating that window");
        [eb insertText:@"!" replacementRange:NSMakeRange(4,0)]; Pump();
        NSAttributedString *baseline = [[noop contentString] copy];
        [eb setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(5,0)];
        NSUInteger beforeNoop = [[library allNotes] count];
        [noop setContentString:baseline];
        [eb unmarkText]; [b finishEditing]; Pump();
        Check([[[noop contentString] string] isEqualToString:@"base!LOCAL"], @"unchanged external snapshot preserves local append");
        Check([[library allNotes] count] == beforeNoop, @"unchanged external snapshot creates no conflict note");
        [ea undo:self]; Pump();
        Check([[[noop contentString] string] isEqualToString:@"base!"], @"unchanged snapshot retains undo of composition");
        [ea undo:self]; Pump();
        Check([[[noop contentString] string] isEqualToString:@"base"], @"unchanged snapshot retains earlier undo history");
        [ea redo:self]; [ea redo:self]; Pump();
        Check([[[noop contentString] string] isEqualToString:@"base!LOCAL"], @"unchanged snapshot retains both redo actions");
        [baseline release];

        NoteObject *styled = MakeNote(library, @"Discarded external formatting", @"base");
        [a revealNote:styled options:0]; [b revealNote:styled options:0]; Pump();
        [eb insertText:@"!" replacementRange:NSMakeRange(4,0)]; Pump();
        NSMutableAttributedString *restyled = [[styled contentString] mutableCopy];
        NSFont *sourceFont = [[GlobalPrefs defaultPrefs] noteBodyFont];
        NSFont *externalFont = [NSFont systemFontOfSize:[sourceFont pointSize] + 13.0];
        [restyled addAttributes:@{NSFontAttributeName: externalFont, NSForegroundColorAttributeName: [NSColor magentaColor],
            NSUnderlineStyleAttributeName: @1, NSStrikethroughStyleAttributeName: @1, @"ExternalAuthoredStyle": @YES}
            range:NSMakeRange(0, [restyled length])];
        [eb setMarkedText:@"LOCAL" selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange(5,0)];
        NSUInteger beforeStyle = [[library allNotes] count];
        [styled setContentString:restyled];
        Check([eb hasMarkedText] && [[eb string] isEqualToString:@"base!LOCAL"], @"discarding external formatting preserves the active local composition");
        [eb unmarkText]; [b finishEditing]; Pump();
        Check([[[styled contentString] string] isEqualToString:@"base!LOCAL"], @"attribute-only external source preserves appended composition characters");
        Check([[library allNotes] count] == beforeStyle, @"discarded formatting creates no text conflict note");
        for (NSAttributedString *text in @[[styled contentString], [ea textStorage], [eb textStorage]]) {
            NSDictionary *attributes = [text attributesAtIndex:0 effectiveRange:NULL];
            Check([attributes[NSFontAttributeName] isEqual:sourceFont] && !attributes[NSUnderlineStyleAttributeName] &&
                !attributes[NSStrikethroughStyleAttributeName] && !attributes[@"ExternalAuthoredStyle"],
                @"source model and peer editors discard authored formatting and use the current source font");
        }
        [ea undo:self]; Pump();
        Check([[[styled contentString] string] isEqualToString:@"base!"], @"Undo after discarded formatting removes only the local composition");
        [ea undo:self]; Pump();
        Check([[[styled contentString] string] isEqualToString:@"base"], @"discarded formatting preserves earlier source Undo history");
        [eb redo:self]; [eb redo:self]; Pump();
        Check([[[styled contentString] string] isEqualToString:@"base!LOCAL"], @"Redo restores both source edits after external formatting is discarded");
        NSDictionary *restoredAttributes = [[styled contentString] attributesAtIndex:0 effectiveRange:NULL];
        Check([restoredAttributes[NSFontAttributeName] isEqual:sourceFont] && !restoredAttributes[@"ExternalAuthoredStyle"],
            @"Undo and Redo never restore discarded external formatting");
        Check([[ea string] isEqualToString:[eb string]] && [[ea string] isEqualToString:[[styled contentString] string]],
            @"peer editors and source model agree after composition and history changes");
        [restyled release];
        [note release]; [overlap release]; [redoNote release]; [firstEdit release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"EDITING HISTORY REGRESSION TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
