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
        [browser revealNote:beta options:0]; Pump();
        NSFont *newFont = [NSFont fontWithName:[oldFont fontName] size:[oldFont pointSize] + 9.0];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:newFont sender:self];
        // The isolation bootstrap omits application preference registration; explicitly invoke its callback.
        [browser settingChangedForSelectorString:@"setNoteBodyFont:sender:"]; Pump();
        NSFont *modelFont = [[alpha contentString] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSFont *sessionFont = [[alphaSession textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSLog(@"EVIDENCE hidden-note font old=%.0f requested=%.0f model=%.0f session=%.0f", [oldFont pointSize], [newFont pointSize], [modelFont pointSize], [sessionFont pointSize]);
        Check([modelFont pointSize] == [newFont pointSize], @"font callback restyles hidden note model");
        Check([sessionFont pointSize] == [oldFont pointSize], @"BUG cached session retains superseded font");
        [browser revealNote:alpha options:0]; Pump();
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        NSFont *displayFont = [[editor textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSLog(@"EVIDENCE reopened-note display-font=%.0f expected=%.0f", [displayFont pointSize], [newFont pointSize]);
        Check([displayFont pointSize] == [oldFont pointSize], @"BUG reopening attaches stale styled storage");
        [[browser window] makeFirstResponder:editor];
        [editor insertText:@"!" replacementRange:NSMakeRange([[editor string] length],0)]; Pump();
        NSFont *overwrittenFont = [[alpha contentString] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSLog(@"EVIDENCE model-font-after-edit=%.0f expected=%.0f", [overwrittenFont pointSize], [newFont pointSize]);
        Check([overwrittenFont pointSize] == [oldFont pointSize], @"BUG next edit overwrites model font with stale session font");
        [browser revealNote:beta options:0]; Pump();
        [library removeNotes:@[alpha]]; Pump();
        [[library undoManager] removeAllActions];
        [[alpha undoManager] removeAllActions];
        NSUInteger beforeCount = [[app valueForKey:@"editingSessions"] count];
        NSLog(@"EVIDENCE deleted session still cached=%d session-count=%lu", [[[app valueForKey:@"editingSessions"] allValues] containsObject:alphaSession], (unsigned long)beforeCount);
        Check([[[app valueForKey:@"editingSessions"] allValues] containsObject:alphaSession], @"deleted note session is retained after undo history clears");
        [alphaSession release]; [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"TORVALDS ROUND 1 PROBES COMPLETED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
