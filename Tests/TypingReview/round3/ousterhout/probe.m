#import "support.inc"
@interface NSString (ProbeUUID)
+ (NSString *)uuidStringWithBytes:(CFUUIDBytes)bytes;
@end
@implementation NSString (ProbeUUID)
#include "uuid.inc"
@end

@interface NVNoteEditingSession : NSObject { @public NoteObject *note; void (^onCommit)(void); NSUInteger reloads; }
- (id)initWithNote:(NoteObject *)value;
- (void)commitTextChanges;
- (void)reloadFromNote;
@end
@implementation NVNoteEditingSession
- (id)initWithNote:(NoteObject *)value { if ((self = [super init])) note = [value retain]; return self; }
- (void)commitTextChanges { if (onCommit) onCommit(); }
- (void)reloadFromNote { reloads++; }
- (void)dealloc { [note release]; [onCommit release]; [super dealloc]; }
@end
@interface ProbeEditor : NSObject { @public NSUInteger clears; }
@end
@implementation ProbeEditor
- (void)removeHighlightedTerms { clears++; }
@end
@interface NSObject (ProbeBookmarks)
- (void)updateBookmarksUI;
@end
@interface AppController : Owner {
@public NVBrowserSession *session; NoteObject *currentNote; BOOL processingSourceEdit;
    NVNoteEditingSession *editingSession; ProbeEditor *textView; GlobalPrefs *prefsController;
    NSUInteger searchHighlightGeneration, posts, wordUpdates, headers, findUpdates;
}
- (NVBrowserSession *)browserSession;
- (void)refreshEditorForNote:(NoteObject *)note;
- (void)updateNoteHeader;
- (void)titleUpdatedForNote:(NoteObject *)note;
@end
@implementation AppController
- (NVBrowserSession *)browserSession { return session; }
- (NoteObject *)selectedNoteObject { return currentNote; }
- (void)postTextUpdate { posts++; }
- (void)updateWordCount:(BOOL)flag { wordUpdates++; }
- (void)updateNoteHeader { headers++; }
- (void)findChanged:(NSNotification *)notification { findUpdates++; }
#include "browser.inc"
@end
@interface Coordinator : NSObject {
@public NSMutableArray *browsers; MemoryLibrary *library; NVSearchService *searchService;
    NSUInteger searchSnapshotRevision; NSMutableDictionary *editingSessions;
}
- (NSArray *)browserControllers;
- (NVNoteEditingSession *)editingSessionForNote:(NoteObject *)note;
- (void)scheduleBrowserRefresh;
@end
@implementation Coordinator
- (NSArray *)browserControllers { return [[browsers copy] autorelease]; }
#include "coordinator.inc"
@end

static void Metadata(Coordinator *c, NoteObject *n, BOOL title, NSString *value) {
    if (title) { [n->titleString release]; n->titleString = [value copy]; }
    else { [n->labelString release]; n->labelString = [value copy]; }
    [c searchableNoteDidChange:n];
    if (title) [c titleUpdatedForNote:n]; else [c noteMetadataUpdated:n];
}
static void SetBody(Coordinator *c, NoteObject *n, NSString *value) {
    [n setContentString:[[[NSAttributedString alloc] initWithString:value] autorelease]];
    [c searchableNoteDidChange:n];
    [c noteEditorChanged:[NSNotification notificationWithName:@"probe" object:n]];
}
int main(void) { @autoreleasepool {
    Coordinator *c = [[Coordinator alloc] init]; c->browsers = [[NSMutableArray alloc] init];
    c->library = [[MemoryLibrary alloc] init]; c->searchService = [[NVSearchService alloc] init];
    c->editingSessions = [[NSMutableDictionary alloc] init];
    NoteObject *n = Note(@"Alpha"), *other = Note(@"Beta"); [c->library->notes addObjectsFromArray:@[n, other]];
    Snapshot(c->searchService, n); Snapshot(c->searchService, other);
    for (int i = 0; i < 3; i++) {
        AppController *b = [[AppController alloc] init]; b->currentNote = i == 2 ? other : n;
        b->session = [[NVBrowserSession alloc] initWithLibrary:(id)c->library];
        [b->session setSearchService:c->searchService]; [b->session setDelegate:b];
        [b->session filterNotesFromString:@""]; b->publications = 0;
        b->editingSession = [[c editingSessionForNote:b->currentNote] retain];
        b->textView = [[ProbeEditor alloc] init]; b->prefsController = [GlobalPrefs defaultPrefs];
        [[NSNotificationCenter defaultCenter] addObserver:b selector:@selector(findChanged:) name:@"TextFindContextShouldUpdate" object:b];
        [c->browsers addObject:b]; [b release];
    }
    AppController *origin = c->browsers[0], *peer = c->browsers[1], *unrelated = c->browsers[2];
    Check(origin->editingSession == peer->editingSession && origin->editingSession != unrelated->editingSession,
          "same UUID shares one cached session while another note has its own session");
    Check([c editingSessionForNote:nil] == nil && c->editingSessions.count == 2, "nil note does not allocate a cached session");
    printf("SCENARIO: body then metadata inside the originating source commit\n");
    origin->editingSession->onCommit = [^{
        SetBody(c, n, @"first body");
        Check(origin->posts == 0 && peer->posts == 1 && unrelated->posts == 0, "source guard suppresses only originating duplicate broadcast");
        Check(Dirty(origin->session) && Dirty(peer->session) && Dirty(unrelated->session), "body model hook queues each browser list independently");
        Metadata(c, n, NO, @"tagged");
        Check(origin->headers == 1 && peer->headers == 1 && unrelated->headers == 0, "metadata headers reach selected peers even during source guard");
        Check(!Dirty(origin->session) && ![origin->session searchResultsAreCurrent], "metadata replaces pending body rows with full invalidation");
    } copy];
    [origin textDidChange:[NSNotification notificationWithName:@"probe" object:origin->textView]];
    Check(!origin->processingSourceEdit && origin->posts == 1 && peer->posts == 1, "source handler clears guard and updates origin exactly once");
    Check(origin->wordUpdates == 1 && peer->wordUpdates == 1 && origin->findUpdates == 1 && peer->findUpdates == 1,
          "word and find callbacks occur once per selected browser");
    Pump(.25);
    Check(origin->publications == 1 && peer->publications == 1 && unrelated->publications == 1, "one full publication consumes interleaved metadata and body changes in all browsers");
    Check(origin->redraws == 0 && peer->redraws == 0 && unrelated->redraws == 0, "superseded body timer cannot cause a duplicate row redraw");
    Check([[c->searchService snapshotForUUID:UUID(n)].tags isEqual:@"tagged"] && [[c->searchService snapshotForUUID:UUID(n)].source isEqual:@"first body"], "committed snapshot contains both metadata and source changes");

    printf("SCENARIO: metadata then two body changes before the scheduled refresh\n");
    Metadata(c, n, YES, @"Renamed"); SetBody(c, n, @"second body"); SetBody(c, n, @"final body");
    Check(origin->headers == 2 && peer->headers == 2 && unrelated->headers == 0, "title update retains both selected headers");
    Pump(.25);
    Check(origin->publications == 2 && peer->publications == 2 && unrelated->publications == 2, "reverse interleaving completes one new full publication per browser");
    NSUInteger before = origin->publications; [c searchableNoteDidChange:n]; Pump(.15);
    Check(origin->publications == before && !Dirty(origin->session), "unchanged snapshot creates no further refresh work");

    printf("SCENARIO: body-only notification keeps fixed row refresh boundary\n");
    SetBody(c, n, @"body after metadata settled");
    Check([origin->session searchResultsAreCurrent] && Dirty(origin->session), "body-only broadcast preserves current empty-query commands and queues row work");
    Pump(.2);
    Check(origin->publications == before && peer->publications == before && unrelated->publications == before,
          "body-only editor broadcast does not schedule full list publication");
    Check(origin->redraws == 1 && peer->redraws == 1 && unrelated->redraws == 1,
          "body-only update redraws its one row in every browser independently of selected note");

    printf("SCENARIO: failed source commit followed by external editor update\n");
    [origin->editingSession->onCommit release]; origin->editingSession->onCommit = [^{ [NSException raise:@"ProbeFailure" format:@"controlled commit failure"]; } copy];
    BOOL caught = NO; @try { [origin textDidChange:[NSNotification notificationWithName:@"probe" object:origin->textView]]; }
    @catch (NSException *exception) { caught = [exception.name isEqual:@"ProbeFailure"]; }
    Check(caught && !origin->processingSourceEdit, "finally releases source guard after commit exception");
    NSUInteger oldPosts = origin->posts;
    [c noteEditorChanged:[NSNotification notificationWithName:@"probe" object:n]];
    Check(origin->posts == oldPosts + 1, "later external broadcast still reaches the original browser");
    NVNoteEditingSession *cached = origin->editingSession;
    [c contentsUpdatedForNote:n]; Pump(.05);
    Check([c editingSessionForNote:n] == cached && cached->reloads == 1 && c->editingSessions.count == 2, "external contents reload uses the existing shared session");
    Check(origin->publications == before + 1 && peer->publications == before + 1, "explicit external contents refresh reaches both browser lists");
    [cached->onCommit release]; cached->onCommit = nil;
    for (AppController *b in c->browsers) {
        [[NSNotificationCenter defaultCenter] removeObserver:b]; [b->session setDelegate:nil];
        [b->session release]; [b->editingSession release]; [b->textView release];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:c]; [c->searchService invalidate];
    [c->browsers release]; [c->editingSessions release]; [c->library release]; [c->searchService release]; [c release];
    printf("PASS: refresh ownership review (%lu checks)\n", (unsigned long)Checks);
} return 0; }
