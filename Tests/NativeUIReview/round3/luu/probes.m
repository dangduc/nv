// Injected only into the temporary app created by run.py.
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
static NSUInteger Checks, RefreshCalls;
static BOOL MeasureRefresh;
static double RefreshMilliseconds;
static void Check(BOOL result, NSString *description) {
    if (!result) { NSLog(@"FAIL: %@", description); exit(1); }
    NSLog(@"PASS: %@", description); Checks++;
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static void Swap(Class cls, SEL first, SEL second) {
    method_exchangeImplementations(class_getInstanceMethod(cls, first), class_getInstanceMethod(cls, second));
}
static NoteObject *NewNote(NotationController *library, NSString *title, NSString *labels) {
    return [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"A short body for metadata cost."] autorelease]
        title:title delegate:library format:[library currentNoteStorageFormat] labels:labels] autorelease];
}
static void Summary(NSUInteger count, NSString *kind, NSString *operation, NSArray *samples) {
    NSArray *sorted = [samples sortedArrayUsingSelector:@selector(compare:)];
    NSLog(@"METADATA_COST notes=%lu windows=2 kind=%@ operation=%@ samples=%lu median_ms=%.3f min_ms=%.3f max_ms=%.3f values=%@",
        (unsigned long)count, kind, operation, (unsigned long)[samples count],
        [sorted[[samples count] / 2] doubleValue], [[sorted firstObject] doubleValue], [[sorted lastObject] doubleValue], samples);
}

@interface NVApplicationController (NVLuuTiming)
- (void)nv_luuRefresh;
@end
@implementation NVApplicationController (NVLuuTiming)
- (void)nv_luuRefresh {
    if (!MeasureRefresh) { [self nv_luuRefresh]; return; }
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    [self nv_luuRefresh];
    RefreshMilliseconds += (CFAbsoluteTimeGetCurrent() - start) * 1000;
    RefreshCalls++;
}
@end
@interface NSFileManager (NVLuuPaths)
- (NSString *)nv_luuSupport;
@end
@implementation NSFileManager (NVLuuPaths)
- (NSString *)nv_luuSupport { return [TestDirectory stringByAppendingPathComponent:@"Support"]; }
@end
@interface ODBEditor (NVLuuIsolation)
- (void)nv_luuSkipExternal:(id)prefs;
@end
@implementation ODBEditor (NVLuuIsolation)
- (void)nv_luuSkipExternal:(id)prefs { }
@end
@interface AppController (NVLuuMetadataCost)
- (void)nv_luuLaunch:(NSNotification *)notification;
- (void)nv_luuDelayed;
- (void)nv_luuRun;
@end
@implementation AppController (NVLuuMetadataCost)
+ (void)load {
    const char *directory = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!directory) return;
    TestDirectory = [[NSString stringWithUTF8String:directory] copy];
    Swap(self, @selector(applicationDidFinishLaunching:), @selector(nv_luuLaunch:));
    Swap(self, @selector(runDelayedUIActionsAfterLaunch), @selector(nv_luuDelayed));
    Swap([NSFileManager class], @selector(applicationSupportDirectory), @selector(nv_luuSupport));
    Swap([ODBEditor class], @selector(initializeDatabase:), @selector(nv_luuSkipExternal:));
    Swap([NVApplicationController class], @selector(refreshBrowsers), @selector(nv_luuRefresh));
}
- (void)nv_luuDelayed { }
- (void)nv_luuLaunch:(NSNotification *)notification {
    [self setupViewsAfterAppAwakened];
    FSRef directory;
    OSStatus err = FSPathMakeRef((const UInt8 *)[[TestDirectory stringByAppendingPathComponent:@"Notes"] fileSystemRepresentation], &directory, NULL);
    Check(err == noErr, @"temporary library directory exists");
    NotationController *library = [[[NotationController alloc] initWithDirectoryRef:&directory error:&err] autorelease];
    Check(library != nil && err == noErr, @"temporary library opens");
    [self setNotationController:library];
    [self prepareAdditionalWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [[self window] makeKeyAndOrderFront:self];
    [self performSelector:@selector(nv_luuRun) withObject:nil afterDelay:0.3];
}
- (void)nv_luuRun {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self && [[app browserControllers] count] == 2, @"the fixture has exactly two browser windows");
        [NSApp activateIgnoringOtherApps:YES];
        [[self window] makeKeyAndOrderFront:self];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while ((![[self window] isKeyWindow] || ![NSApp isActive] || [app activeBrowser] != self) && [deadline timeIntervalSinceNow] > 0) Pump();
        Check([NSApp isActive] && [[self window] isKeyWindow] && [app activeBrowser] == self,
            @"native activation makes the fixture key and active");
        for (AppController *browser in @[self, peer]) {
            [[browser window] setContentSize:NSMakeSize(800, 600)];
            [browser setNotesListHeight:120];
            [browser setUserColorScheme:browser];
            Check([[browser valueForKey:@"userScheme"] integerValue] == 2, @"the fixture uses an explicit editor color scheme");
        }
        NoteObject *target = [NewNote(library, @"bench target seed", @"other") retain];
        NoteObject *sentinel = [NewNote(library, @"bench watch sentinel", @"") retain];
        [library addNotes:@[target, sentinel]]; Pump();
        NSTableView *mainTable = [self valueForKey:@"notesTableView"];
        NSTableView *peerTable = [peer valueForKey:@"notesTableView"];
        for (NSNumber *size in @[@1000, @10000]) {
            NSUInteger count = [size unsignedIntegerValue];
            NSMutableArray *batch = [NSMutableArray array];
            for (NSUInteger index = [library totalNoteCount]; index < count; index++) {
                [batch addObject:NewNote(library, [NSString stringWithFormat:@"bench Fixture %05lu", (unsigned long)index], @"")];
            }
            [library addNotes:batch]; Pump();
            [self searchForString:@"bench"]; [self revealNote:target options:0];
            [peer searchForString:@"watch"]; [peer revealNote:sentinel options:0]; Pump();
            [[self window] makeKeyAndOrderFront:self];
            [[self window] makeFirstResponder:[self valueForKey:@"textView"]]; Pump();
            Check([library totalNoteCount] == count && [mainTable numberOfRows] == count,
                @"the primary query matches every fixture note");
            Check([self selectedNoteObject] == target && [peer selectedNoteObject] == sentinel,
                @"both browsers select their intended fixture notes");
            NSLog(@"COST_FIXTURE notes=%lu primary_query=%@ peer_query=%@ primary_sort=%@ peer_sort=%@ autocomplete=%d",
                (unsigned long)count, [[self browserSession] searchString], [[peer browserSession] searchString],
                [[[self browserSession] sortColumn] identifier], [[[peer browserSession] sortColumn] identifier],
                [[GlobalPrefs defaultPrefs] autoCompleteSearches]);
            for (NSString *kind in @[@"title", @"tags"]) {
                BOOL isTitle = [kind isEqualToString:@"title"];
                NSMutableArray *dispatch = [NSMutableArray array], *refresh = [NSMutableArray array], *calls = [NSMutableArray array];
                for (NSUInteger pass = 0; pass < 6; pass++) {
                    NSString *value = isTitle ? (pass % 2 ? @"bench target beta" : @"bench target alpha") :
                        (pass % 2 ? @"other" : @"watch");
                    if (isTitle) [self renameNote:self]; else [self tagNote:self];
                    NSTextField *control = [self valueForKey:isTitle ? @"noteTitleField" : @"noteTagsField"];
                    NSTextView *fieldEditor = (id)[control currentEditor];
                    Check(fieldEditor != nil && [[self window] isKeyWindow], @"native metadata field editor owns the prepared edit");
                    [fieldEditor insertText:value replacementRange:NSMakeRange(0, [[fieldEditor string] length])];
                    Pump(); // Exclude field insertion and preexisting scheduled work.
                    RefreshMilliseconds = 0; RefreshCalls = 0; MeasureRefresh = YES;
                    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                    BOOL handled = [self control:control textView:fieldEditor doCommandBySelector:@selector(insertNewline:)];
                    double dispatchMS = (CFAbsoluteTimeGetCurrent() - start) * 1000;
                    NSUInteger synchronousCalls = RefreshCalls;
                    Pump();
                    NSUInteger firstDrainCalls = RefreshCalls;
                    Pump(); // Assert that a second event-loop drain adds no refresh.
                    MeasureRefresh = NO;
                    Check(handled && synchronousCalls == 0 && RefreshCalls > 0 && RefreshCalls == firstDrainCalls,
                        @"Return commits metadata and deferred browser refresh settles in the first drain");
                    Check([(isTitle ? titleOfNote(target) : labelsOfNote(target)) isEqualToString:value],
                        @"the note contains the committed metadata value");
                    Check([mainTable numberOfRows] == count && [self selectedNoteObject] == target &&
                        [peer selectedNoteObject] == sentinel, @"metadata refresh preserves both browser selections and the primary result count");
                    NSUInteger expectedPeerRows = [labelsOfNote(target) isEqualToString:@"watch"] ? 2 : 1;
                    Check([peerTable numberOfRows] == expectedPeerRows &&
                        [[[self browserSession] searchString] isEqualToString:@"bench"] &&
                        [[[peer browserSession] searchString] isEqualToString:@"watch"],
                        @"the peer query gains or loses the tagged target without changing either query");
                    Check([[[target contentString] string] isEqualToString:@"A short body for metadata cost."],
                        @"metadata commits preserve the body text");
                    NSLog(@"COST_SAMPLE notes=%lu kind=%@ pass=%lu warmup=%d dispatch_ms=%.3f refresh_ms=%.3f refresh_calls=%lu peer_rows=%lu",
                        (unsigned long)count, kind, (unsigned long)pass, pass == 0, dispatchMS, RefreshMilliseconds,
                        (unsigned long)RefreshCalls, (unsigned long)expectedPeerRows);
                    if (pass) {
                        [dispatch addObject:@(dispatchMS)]; [refresh addObject:@(RefreshMilliseconds)]; [calls addObject:@(RefreshCalls)];
                    }
                }
                Summary(count, kind, @"Return_dispatch", dispatch);
                Summary(count, kind, @"deferred_refresh", refresh);
                NSLog(@"COST_REFRESH_CALLS notes=%lu kind=%@ values=%@", (unsigned long)count, kind, calls);
            }
        }
        Check([library totalNoteCount] == 10000, @"metadata edits never create or delete fixture notes");
        [target release]; [sentinel release];
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND3 LUU METADATA COST PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
