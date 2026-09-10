#import <Cocoa/Cocoa.h>
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NVSearchService.h"

// The production session and native search service are compiled in full.
// These in-memory model doubles never open a library or desktop window.
NSString *NoteTitleColumnString = @"title";
NSString *NoteDateModifiedColumnString = @"Date Modified";
static NSUInteger Checks;
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    Checks++; printf("PASS: %s\n", message);
}
static void Pump(NSTimeInterval seconds) {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && deadline.timeIntervalSinceNow > 0) Pump(.005);
    return condition();
}
@implementation GlobalPrefs
+ (GlobalPrefs *)defaultPrefs { static GlobalPrefs *prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (BOOL)tableIsReverseSorted { return NO; }
- (BOOL)tableColumnsShowPreview { return YES; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)autoCompleteSearches { return NO; }
@end
@implementation NoteObject
- (id)initWithNoteBody:(NSAttributedString *)body title:(NSString *)title delegate:(id)owner format:(NSInteger)format labels:(NSString *)labels {
    if ((self = [super init])) {
        contentString = [body mutableCopy]; titleString = [title copy]; labelString = [labels copy];
        static unsigned char serial; memset(&uniqueNoteIDBytes, 0, sizeof(uniqueNoteIDBytes));
        ((unsigned char *)&uniqueNoteIDBytes)[15] = ++serial;
    }
    return self;
}
- (CFUUIDBytes *)uniqueNoteIDBytes { return &uniqueNoteIDBytes; }
- (NSMutableAttributedString *)contentString { return contentString; }
- (void)setContentString:(NSAttributedString *)contents { [contentString setAttributedString:contents]; }
- (void)dealloc { [contentString release]; [titleString release]; [labelString release]; [super dealloc]; }
@end
@implementation FastListDataSource
- (void)fillArrayFromArray:(NSArray *)array {
    count = array.count; objects = realloc(objects, count * sizeof(id)); [array getObjects:objects range:NSMakeRange(0, count)];
}
- (NSUInteger)count { return count; }
- (NSUInteger)indexOfObjectIdenticalTo:(id)object { for (NSUInteger i = 0; i < count; i++) if (objects[i] == object) return i; return NSNotFound; }
- (void)dealloc { free(objects); [super dealloc]; }
@end
@interface MemoryLibrary : NSObject { @public NSMutableArray *notes; }
@end
@implementation MemoryLibrary
- (id)init { if ((self = [super init])) notes = [[NSMutableArray alloc] init]; return self; }
- (NSArray *)allNotes { return [[notes copy] autorelease]; }
- (void)dealloc { [notes release]; [super dealloc]; }
@end
@interface Owner : NSObject { @public BOOL allowsChange; NSUInteger publications, redraws, completions; NoteObject *selected; NSMutableArray *rows; }
@end
@implementation Owner
- (id)init { if ((self = [super init])) { allowsChange = YES; rows = [[NSMutableArray alloc] init]; } return self; }
- (NoteObject *)selectedNoteObject { return selected; }
- (BOOL)notationListShouldChange:(id)session { return allowsChange; }
- (void)notationListMightChange:(id)session {}
- (void)notationListDidChange:(id)session { publications++; }
- (void)rowShouldUpdate:(NSInteger)row { redraws++; [rows addObject:@(row)]; }
- (void)browserSessionSearchStateDidChange:(id)session {}
- (void)browserSessionSearchDidComplete:(id)session { completions++; }
- (BOOL)horizontalLayout { return NO; }
- (void)dealloc { [rows release]; [super dealloc]; }
@end
typedef NSInteger (*CompareNotes)(id *, id *);
static NSInteger ByDate(id *a, id *b) {
    CFAbsoluteTime x = ((NoteObject *)*a)->modifiedDate, y = ((NoteObject *)*b)->modifiedDate;
    return x < y ? -1 : x > y ? 1 : 0;
}
static NSInteger ByDateReverse(id *a, id *b) { return -ByDate(a, b); }
@interface DateColumn : NSObject
@end
@implementation DateColumn
- (NSString *)identifier { return NoteDateModifiedColumnString; }
- (CompareNotes)sortFunction { return ByDate; }
- (CompareNotes)reverseSortFunction { return ByDateReverse; }
@end
static NoteObject *Note(NSString *title) {
    return [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"seed"] autorelease]
        title:title delegate:nil format:0 labels:@""] autorelease];
}
static NSArray *Visible(NVBrowserSession *session) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger row = 0; row < [[session notesListDataSource] count]; row++) [result addObject:[session noteObjectAtFilteredIndex:row]];
    return result;
}
static BOOL Dirty(NVBrowserSession *session) { return [[session valueForKey:@"bodyRefreshScheduled"] boolValue]; }
static NSUInteger DirtyCount(NVBrowserSession *session) { return [[session valueForKey:@"dirtyBodyUUIDs"] count]; }
static NSData *UUID(NoteObject *note) { return [NSData dataWithBytes:[note uniqueNoteIDBytes] length:16]; }
static void Snapshot(NVSearchService *service, NoteObject *note) {
    [service updateSnapshot:[[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(note) title:note->titleString
        tags:note->labelString source:note.contentString.string revision:1] autorelease]];
}
static void Body(NVBrowserSession *session, NVSearchService *service, NoteObject *note, NSString *source) {
    [note setContentString:[[[NSAttributedString alloc] initWithString:source] autorelease]];
    if (service) Snapshot(service, note);
    [session noteBodyDidChange:note];
}

@interface RevealTable : NSObject { @public NVBrowserSession *session; Owner *owner; NSInteger row; }
@end
@implementation RevealTable
- (id)init { if ((self = [super init])) row = -1; return self; }
- (NSInteger)primarySelectedRow { return row; }
- (void)selectRowAndScroll:(NSUInteger)index { row = index; owner->selected = [session noteObjectAtFilteredIndex:index]; }
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend { [self selectRowAndScroll:indexes.firstIndex]; }
- (void)deselectAll:(id)sender { row = -1; owner->selected = nil; }
@end
@interface RevealField : NSObject { NSString *value; }
@end
@implementation RevealField
- (NSString *)stringValue { return value; }
- (void)setStringValue:(NSString *)next { [value release]; value = [next copy]; }
- (void)dealloc { [value release]; [super dealloc]; }
@end
@interface RevealOwner : Owner {
@public NVBrowserSession *notationController; MemoryLibrary *library;
    RevealTable *notesTableView; RevealField *field; id window; NSDictionary *pendingSearchReveal;
}
- (NVBrowserSession *)browserSession;
- (MemoryLibrary *)sharedNotationController;
- (NSString *)searchMode;
- (void)cancelSearchIntents;
- (void)controlTextDidChange:(NSNotification *)notification;
- (NSUInteger)revealNote:(NoteObject *)note options:(NSUInteger)opts;
@end
@implementation RevealOwner
- (NVBrowserSession *)browserSession { return notationController; }
- (MemoryLibrary *)sharedNotationController { return library; }
- (NSString *)searchMode { return [notationController searchMode]; }
- (void)cancelSearchIntents { [pendingSearchReveal release]; pendingSearchReveal = nil; }
- (void)controlTextDidChange:(NSNotification *)notification { [notationController filterNotesFromString:[field stringValue]]; }
- (void)setViewingNote:(BOOL)flag {}
- (void)focusNoteBody {}
#include "reveal.inc"
- (void)dealloc { [pendingSearchReveal release]; [notesTableView release]; [field release]; [super dealloc]; }
@end

static void TestExactReveal(void) {
    MemoryLibrary *library = [[MemoryLibrary alloc] init];
    NVBrowserSession *session = [[NVBrowserSession alloc] initWithLibrary:(id)library];
    RevealOwner *owner = [[RevealOwner alloc] init]; owner->library = library; owner->notationController = session;
    owner->notesTableView = [[RevealTable alloc] init]; owner->notesTableView->session = session; owner->notesTableView->owner = owner;
    owner->field = [[RevealField alloc] init]; [owner->field setStringValue:@"New matching note"];
    [session setDelegate:owner]; [session filterNotesFromString:[owner->field stringValue]];
    NoteObject *note = Note(@"New matching note"); [library->notes addObject:note];
    // The application's searchable-note hook invalidates every browser before
    // its deferred refresh. A background Reveal can arrive in this gap.
    [session invalidateSearch];
    [session performSelector:@selector(libraryDidChange) withObject:nil afterDelay:0];
    NSUInteger row = [owner revealNote:note options:0];
#ifdef BASELINE_REVEAL
    Check(row != NSNotFound && owner->selected == note && !owner->pendingSearchReveal,
          "BASELINE: Exact Reveal refilters and selects the matching new note synchronously");
#else
    Check(row == NSNotFound && owner->selected != note && owner->pendingSearchReveal[@"note"] == note,
          "REPRODUCED: candidate Exact Reveal queues its selection before list refresh");
#endif
    Pump(.3);
    Check([session searchResultsAreCurrent] && [Visible(session) isEqual:@[note]], "deferred Exact projection becomes current with the requested note present");
#ifdef BASELINE_REVEAL
    Check(owner->selected == note && !owner->pendingSearchReveal, "BASELINE: requested note stays selected after deferred publication");
#else
    Check(owner->selected != note && owner->pendingSearchReveal[@"note"] == note && owner->completions == 0,
          "REPRODUCED: current Exact projection leaves Reveal stranded without a completion callback");
#endif
    Check([[owner->field stringValue] isEqual:@"New matching note"], "matching Exact query is preserved in both versions");
    [session setDelegate:nil]; [session release]; [owner release]; [library release];
}

static void TestInterleavings(void) {
    MemoryLibrary *library = [[MemoryLibrary alloc] init];
    NoteObject *a = Note(@"A"), *b = Note(@"B"), *c = Note(@"C");
    [library->notes addObjectsFromArray:@[a, b, c]];
    NVBrowserSession *session = [[NVBrowserSession alloc] initWithLibrary:(id)library];
    Owner *owner = [[Owner alloc] init]; [session setDelegate:owner];
    NVSearchService *service = [[NVSearchService alloc] init];
    for (NoteObject *note in library->notes) Snapshot(service, note);
    [session setSearchService:service];

    // Gate publication as an active inline field editor does. Multiple body
    // notifications must preserve their dirty UUIDs until one permitted flush.
    owner->allowsChange = NO;
    NSUInteger publications = owner->publications;
    Body(session, service, a, @"first edit"); Body(session, service, b, @"second edit");
    Pump(.24);
    Check(Dirty(session) && DirtyCount(session) == 2 && owner->redraws == 0, "blocked row publication retains both dirty UUIDs");
    Check([Visible(session) isEqual:@[a, b, c]] && [session searchResultsAreCurrent], "body-only delay preserves actionable empty-query membership");
    owner->allowsChange = YES;
    Check(Await(^BOOL { return owner->redraws == 2; }), "unblocking delivers both affected rows");
    Check(owner->publications == publications && [owner->rows isEqual:@[@0, @1]] && !DirtyCount(session), "coalesced dirty rows avoid a full publication and clear once");

    // Dirty rows cannot overtake a deletion while the regular projection is
    // paused. A later body edit is deliberately queued after invalidation.
    owner->allowsChange = NO;
    Body(session, service, a, @"pending before deletion");
    [library->notes removeObjectIdenticalTo:b]; [service removeUUID:UUID(b)];
    [session invalidateSearch]; [session libraryDidChange];
    Body(session, service, c, @"pending after deletion"); Pump(.24);
    Check(![session searchResultsAreCurrent] && ![[session notesAtIndexes:[NSIndexSet indexSetWithIndex:1]] count], "deletion disables stale row actions while its publication is paused");
    owner->allowsChange = YES;
    Check(Await(^BOOL { return [session searchResultsAreCurrent]; }), "deferred membership publication resumes after inline editing");
    Pump(.25);
    Check([Visible(session) isEqual:@[a, c]] && !Dirty(session) && !DirtyCount(session), "pending body work cannot resurrect a deleted note");

    // Suspension is the browser search-field composition boundary. Source
    // edits from a peer may continue while that query cannot publish.
    Body(session, service, a, @"queued before composition");
    [session suspendSearchForComposition:YES];
    Body(session, service, c, @"peer changes during composition"); Pump(.22);
    Check(![session searchResultsAreCurrent] && DirtyCount(session) == 1, "composition defers peer dirty-row publication");
    [session suspendSearchForComposition:NO]; Pump(.2);
    Check([session searchResultsAreCurrent] && [Visible(session) isEqual:@[a, c]] && !Dirty(session), "composition resume replaces the projection and cancels trailing dirty work");

    // A pending empty-query body refresh is superseded by an Exact search;
    // another edit must then invalidate membership synchronously.
    Body(session, service, a, @"needle");
    [session filterNotesFromString:@"needle"]; Pump(.15);
    Check([Visible(session) isEqual:@[a]] && !Dirty(session), "query change cancels pending empty-query redraws");
    Body(session, service, a, @"no match remains");
    Check(![session searchResultsAreCurrent], "active Exact query rejects stale membership immediately");
    Check(Await(^BOOL { return [session searchResultsAreCurrent]; }) && !Visible(session).count, "Exact replacement removes the former match");

    [session filterNotesFromString:@""]; [session setSearchMode:@"fuzzy"];
    Body(session, service, a, @"needle"); [session filterNotesFromString:@"needle"];
    Check(Await(^BOOL { return [session searchResultsAreCurrent]; }) && [Visible(session) containsObject:a], "Fuzzy search publishes the current source after pending dirty work");
    Body(session, service, a, @"removed");
    Check(![session searchResultsAreCurrent], "active Fuzzy query rejects stale membership immediately");
    Check(Await(^BOOL { return [session searchResultsAreCurrent]; }) && !Visible(session).count, "Fuzzy replacement excludes the obsolete body match");

    [session filterNotesFromString:@""];
    a->modifiedDate = 1; c->modifiedDate = 2;
    DateColumn *column = [[DateColumn alloc] init]; [session setSortColumn:(id)column reversed:YES];
    NSString *key = [[session rowKeyAtIndex:1] copy];
    a->modifiedDate = 3; Body(session, service, a, @"newest");
    Check(Await(^BOOL { return [session noteObjectAtFilteredIndex:0] == a; }), "Date Modified dirty publication reorders the existing members");
    Check([[session rowKeyAtIndex:0] isEqual:key] && [session resultCount] == 2 && [Visible(session) isEqual:@[a, c]], "Date Modified reorder preserves occurrence identity and result membership");
    [key release]; [column release];

    // Library replacement closes the old browser session's delegate first.
    // Leave both a scheduled body timer and a detached callback opportunity.
    owner->allowsChange = NO;
    Body(session, service, a, @"old library pending");
    [session setDelegate:nil];
    publications = owner->publications; NSUInteger redraws = owner->redraws;
    [session notePreviewDidChange:c]; Pump(.24);
    Check(!Dirty(session) && !DirtyCount(session) && owner->publications == publications && owner->redraws == redraws,
          "detachment cancels pending timers and rejects later legacy preview notifications");
    MemoryLibrary *replacement = [[MemoryLibrary alloc] init]; NoteObject *newNote = Note(@"Replacement");
    [replacement->notes addObject:newNote];
    NVBrowserSession *newSession = [[NVBrowserSession alloc] initWithLibrary:(id)replacement];
    [newSession setDelegate:owner]; owner->allowsChange = YES; Pump(.2);
    Check([Visible(newSession) isEqual:@[newNote]], "old-library timer cannot publish into the replacement session");
    [newSession setDelegate:nil]; [newSession release]; [replacement release];
    [session release]; [service invalidate]; [service release]; [owner release]; [library release];
}

int main(void) { @autoreleasepool {
#ifndef BASELINE_REVEAL
    TestInterleavings();
#endif
    TestExactReveal();
    printf("PASS: browser interleavings (%lu checks)\n", (unsigned long)Checks);
} return 0; }
