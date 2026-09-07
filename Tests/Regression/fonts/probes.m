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
        NoteObject *unopenedOne = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"unopened one"] autorelease]
            title:@"Unopened One" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
        NoteObject *unopenedTwo = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"unopened two"] autorelease]
            title:@"Unopened Two" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
        // A batch import selects both notes, without opening either in an editor.
        [library addNotes:@[unopenedOne, unopenedTwo]]; Pump();
        [browser revealNote:beta options:0]; Pump();
        NSUInteger cachedCount = [[app valueForKey:@"editingSessions"] count];
        Check(cachedCount < [[library allNotes] count], @"fixture includes notes with no editing session");
        NSFont *newFont = [NSFont fontWithName:[oldFont fontName] size:[oldFont pointSize] + 9.0];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:newFont sender:self];
        // The isolation bootstrap omits application preference registration; invoke its production callback.
        [browser settingChangedForSelectorString:@"setNoteBodyFont:sender:"]; Pump();
        NSFont *modelFont = [[alpha contentString] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSFont *sessionFont = [[alphaSession textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([modelFont pointSize] == [newFont pointSize], @"font callback restyles hidden note model");
        Check([sessionFont pointSize] == [newFont pointSize], @"font callback reloads hidden cached editor storage");
        Check([[app valueForKey:@"editingSessions"] count] == cachedCount, @"font callback does not create sessions for unopened notes");
        [browser revealNote:alpha options:0]; Pump();
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        NSFont *displayFont = [[editor textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([displayFont pointSize] == [newFont pointSize], @"reopening a cached note displays the requested font");
        [[browser window] makeFirstResponder:editor];
        [editor insertText:@"!" replacementRange:NSMakeRange([[editor string] length],0)]; Pump();
        NSFont *savedFont = [[alpha contentString] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([savedFont pointSize] == [newFont pointSize], @"editing a reopened note preserves the requested model font");
        Check([[[alpha contentString] string] isEqualToString:@"alpha body!"], @"editing a reopened note preserves its text");
        [browser revealNote:beta options:0]; Pump();
        [editor setMarkedText:@"draft " selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,0)];
        Check([editor hasMarkedText], @"fixture has an active composition");
        NSFont *compositionFont = [NSFont fontWithName:[newFont fontName] size:[newFont pointSize] + 2.0];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:compositionFont sender:self];
        [browser settingChangedForSelectorString:@"setNoteBodyFont:sender:"]; Pump();
        Check([editor hasMarkedText] && [[editor string] isEqualToString:@"draft beta body"], @"cached-session reload defers replacement during marked text");
        [editor unmarkText]; [browser finishEditing]; Pump();
        Check([[[beta contentString] string] isEqualToString:@"draft beta body"], @"deferred font refresh preserves composed text on commit");
        [alphaSession release]; [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"FONT REGRESSION TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
