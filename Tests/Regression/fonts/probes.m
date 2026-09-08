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
static BOOL DisplayChangeInProgress;
static NSUInteger DisplayWriteRequests;
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
static NSDictionary *ModelState(NoteObject *note) {
    NSData *source = [note sourceDataReturningError:NULL];
    Check(source != nil, @"font fixture has serializable source bytes");
    return @{@"contents": [[[note contentString] copy] autorelease],
             @"source": source,
             @"modified": @(modifiedDateOfNote(note)),
             @"sequence": @([note logSequenceNumber])};
}
static NSDictionary *HistoryState(NVNoteEditingSession *session) {
    NSUndoManager *undo = [[session note] undoManager];
    return @{@"undo": @([session canUndo]), @"redo": @([session canRedo]),
             @"undoName": [undo undoActionName] ?: @"", @"redoName": [undo redoActionName] ?: @""};
}
@interface NotationController (NVFontWriteAudit)
- (void)nv_fontScheduleWriteForNote:(NoteObject *)note;
@end
@implementation NotationController (NVFontWriteAudit)
- (void)nv_fontScheduleWriteForNote:(NoteObject *)note {
    if (DisplayChangeInProgress) DisplayWriteRequests++;
    [self nv_fontScheduleWriteForNote:note];
}
@end

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
    Swap([NotationController class], @selector(scheduleWriteForNote:), @selector(nv_fontScheduleWriteForNote:));
}
- (void)nv_testDelayed { }
- (void)nv_finishTests { [NSApp terminate:self]; }
- (void)nv_testLaunch:(NSNotification *)notification {
    [NSApp activateIgnoringOtherApps:YES];
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
        AppController *browser = self;
        NoteObject *alpha = [MakeNote(library, @"Font Alpha", @"alpha body") retain];
        NoteObject *beta = [MakeNote(library, @"Font Beta", @"beta body") retain];
        NSFont *oldFont = [[GlobalPrefs defaultPrefs] noteBodyFont];
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"alpha body" attributes:@{ NSFontAttributeName: oldFont }] autorelease]];
        [browser revealNote:alpha options:0]; Pump();
        NVNoteEditingSession *alphaSession = [[app editingSessionForNote:alpha] retain];
        [[alphaSession textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:@" history"] autorelease]];
        [alphaSession commitTextChanges];
        [alphaSession undo];
        Check([alphaSession canRedo], @"font fixture contains existing body Redo history");
        NoteObject *unopenedOne = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"unopened one"] autorelease]
            title:@"Unopened One" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
        NoteObject *unopenedTwo = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"unopened two"] autorelease]
            title:@"Unopened Two" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
        // A batch import selects both notes, without opening either in an editor.
        [library addNotes:@[unopenedOne, unopenedTwo]]; Pump();
        [browser revealNote:beta options:0]; Pump();
        NSUInteger cachedCount = [[app valueForKey:@"editingSessions"] count];
        Check(cachedCount < [[library allNotes] count], @"fixture includes notes with no editing session");
        [library flushAllNoteChanges];
        NSArray *notes = [NSArray arrayWithArray:[library allNotes]];
        NSMutableArray *modelStates = [NSMutableArray array];
        for (NoteObject *note in notes) [modelStates addObject:ModelState(note)];
        NSDictionary *history = HistoryState(alphaSession);
        uint64_t sourceGeneration = [alphaSession sourceGeneration];
        NSFont *newFont = [NSFont fontWithName:[oldFont fontName] size:[oldFont pointSize] + 9.0];
        DisplayChangeInProgress = YES;
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:newFont sender:self];
        // The isolation bootstrap omits application preference registration.
        [browser settingChangedForSelectorString:@"setNoteBodyFont:sender:"]; Pump();
        [library setForegroundTextColor:[NSColor redColor]];
        DisplayChangeInProgress = NO;
        for (NSUInteger index = 0; index < [notes count]; index++) {
            Check([ModelState(notes[index]) isEqual:modelStates[index]], @"font and foreground changes preserve note attributes, source bytes, date, and journal sequence");
        }
        Check(DisplayWriteRequests == 0, @"display changes schedule no note writes");
        Check([HistoryState(alphaSession) isEqual:history], @"display changes preserve existing body Undo and Redo history");
        Check([alphaSession sourceGeneration] == sourceGeneration, @"display changes do not advance source generation");
        NSFont *sessionFont = [[alphaSession textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([sessionFont pointSize] == [newFont pointSize], @"font callback updates hidden cached editor display");
        Check([[app valueForKey:@"editingSessions"] count] == cachedCount, @"font callback does not create sessions for unopened notes");
        [alphaSession redo];
        Check([[[alpha contentString] string] isEqual:@"alpha body history"], @"preference changes preserve the actual Redo operation");
        [alphaSession undo];
        Check([[[alpha contentString] string] isEqual:@"alpha body"], @"Undo restores characters after a display font change");
        NSAttributedString *unopenedContents = [[[unopenedOne contentString] copy] autorelease];
        [browser revealNote:unopenedOne options:0]; Pump();
        LinkingEditor *unopenedEditor = [browser valueForKey:@"textView"];
        Check([[[unopenedEditor textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] pointSize] == [newFont pointSize], @"first opening an untouched record uses the current display font");
        Check([[unopenedOne contentString] isEqualToAttributedString:unopenedContents], @"first display does not restyle the stored note");
        [browser revealNote:alpha options:0]; Pump();
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        NSFont *displayFont = [[editor textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([displayFont pointSize] == [newFont pointSize], @"reopening a cached note displays the requested font");
        [[browser window] makeFirstResponder:editor];
        [editor insertText:@"!" replacementRange:NSMakeRange([[editor string] length],0)]; Pump();
        NSFont *displayAfterEdit = [[editor textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([displayAfterEdit pointSize] == [newFont pointSize], @"editing a reopened note retains the requested display font");
        Check([[[alpha contentString] string] isEqualToString:@"alpha body!"], @"editing a reopened note preserves its text");
        [browser revealNote:beta options:0]; Pump();
        [editor setMarkedText:@"draft " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        Check([editor hasMarkedText], @"fixture has an active composition");
        NSFont *compositionFont = [NSFont fontWithName:[newFont fontName] size:[newFont pointSize] + 2.0];
        NSDictionary *compositionModel = ModelState(beta);
        DisplayChangeInProgress = YES;
        DisplayWriteRequests = 0;
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:compositionFont sender:self];
        [browser settingChangedForSelectorString:@"setNoteBodyFont:sender:"]; Pump();
        DisplayChangeInProgress = NO;
        Check([editor hasMarkedText] && [[editor string] isEqualToString:@"draft beta body"], @"cached-session reload defers replacement during marked text");
        Check([ModelState(beta) isEqual:compositionModel], @"font changes do not commit another pending composition");
        Check(DisplayWriteRequests == 0, @"font changes during composition schedule no source writes");
        [editor unmarkText]; [browser finishEditing]; Pump();
        Check([[[beta contentString] string] isEqualToString:@"draft beta body"], @"deferred font refresh preserves composed text on commit");
        Check([[[editor textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] pointSize] == [compositionFont pointSize], @"composition completion applies the deferred display font");
        [alphaSession release]; [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"FONT REGRESSION TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
