#include "support.h"
#import "NVApplicationController.h"
#import "AppController.h"

@interface MemoryLibrary (LegacyRows)
@end
@implementation MemoryLibrary (LegacyRows)
- (FastListDataSource *)notesListDataSource {
    FastListDataSource *source = [[[FastListDataSource alloc] init] autorelease];
    [source fillArrayFromArray:notes]; return source;
}
- (NoteObject *)noteObjectAtFilteredIndex:(NSUInteger)index { return notes[index]; }
@end

@interface NVBrowserSession (TimerAccess)
- (void)refreshDirtyBodyRows;
@end
@interface TimedSession : NVBrowserSession { @public NSUInteger timers; double firstDirty, firstDelivery, maxDelay; }
@end
@implementation TimedSession
- (void)notePreviewDidChange:(NoteObject *)note {
    if (!Dirty(self)) firstDirty = CFAbsoluteTimeGetCurrent();
    [super notePreviewDidChange:note];
}
- (void)refreshDirtyBodyRows {
    double now = CFAbsoluteTimeGetCurrent();
    timers++; if (!firstDelivery) firstDelivery = now;
    maxDelay = MAX(maxDelay, now - firstDirty);
    [super refreshDirtyBodyRows];
}
@end
@interface Browser : Owner { @public TimedSession *session; NSUInteger headers, editors; }
@end
@implementation Browser
- (NVBrowserSession *)browserSession { return session; }
- (void)updateNoteHeader { headers++; }
- (void)titleUpdatedForNote:(id)note { headers++; }
- (void)refreshEditorForNote:(id)note { editors++; }
@end
@implementation NVApplicationController
#include "coordinator.inc"
@end
@interface Coordinator : NVApplicationController
- (id)initWithLibrary:(id)model service:(id)service browsers:(NSArray *)owners;
@end
@implementation Coordinator
- (id)initWithLibrary:(id)model service:(id)service browsers:(NSArray *)owners {
    if ((self = [super init])) { library = [model retain]; searchService = [service retain]; browsers = [owners mutableCopy]; }
    return self;
}
- (void)dealloc { [NSObject cancelPreviousPerformRequestsWithTarget:self]; [library release]; [searchService release]; [browsers release]; [super dealloc]; }
@end
static void Reset(NSArray *owners) {
    for (Browser *owner in owners) {
        owner->publications = owner->redraws = owner->headers = owner->editors = 0;
        [owner->rows removeAllObjects]; owner->session->timers = 0;
        owner->session->firstDirty = owner->session->firstDelivery = owner->session->maxDelay = 0;
    }
}
static void BodyEdit(Coordinator *app, NoteObject *note, NSUInteger serial) {
    [note setContentString:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"edit %lu", serial]] autorelease]];
    note->modifiedDate = CFAbsoluteTimeGetCurrent();
    [app searchableNoteDidChange:note];
    // The legacy library projection can report the same note again.
    [app rowShouldUpdate:0];
    [app noteEditorChanged:[NSNotification notificationWithName:@"fixture" object:note]];
}
static void Report(NSString *scenario, NSArray *owners) {
    for (NSUInteger i = 0; i < owners.count; i++) {
        Browser *b = owners[i];
        printf("METRIC %s browser=%lu timers=%lu rows=%lu full=%lu max_deadline_ms=%.3f\n",
            scenario.UTF8String, i, b->session->timers, b->redraws, b->publications, b->session->maxDelay * 1000);
    }
}
int main(void) { @autoreleasepool {
    MemoryLibrary *library = [[MemoryLibrary alloc] init];
    for (NSUInteger i = 0; i < 64; i++) { NoteObject *n = Note([NSString stringWithFormat:@"Note %02lu", i]); n->modifiedDate = i; [library->notes addObject:n]; }
    NoteObject *edited = library->notes[0];
    NVSearchService *service = [[NVSearchService alloc] init];
    for (NoteObject *n in library->notes) Snapshot(service, n);
    NSMutableArray *owners = [NSMutableArray array];
    DateColumn *date = [[[DateColumn alloc] init] autorelease];
    for (NSUInteger i = 0; i < 3; i++) {
        Browser *owner = [[[Browser alloc] init] autorelease];
        owner->session = [[TimedSession alloc] initWithLibrary:(id)library];
        [owner->session setSearchService:service]; [owner->session setDelegate:(id)owner];
        if (i == 2) [owner->session setSortColumn:(id)date reversed:YES];
        owner->selected = edited; [owners addObject:owner];
    }
    Coordinator *app = [[Coordinator alloc] initWithLibrary:library service:service browsers:owners];
    Reset(owners); double began = CFAbsoluteTimeGetCurrent();
    for (NSUInteger i = 0; i < 70; i++) { BodyEdit(app, edited, i); Pump(.01); }
    double finalKey = CFAbsoluteTimeGetCurrent();
    for (Browser *b in owners) {
        Check(b->session->timers >= 5 && b->session->firstDelivery < finalKey, "sustained edits deliver before final key");
        Check(b->session->firstDelivery - began < .16, "first delivery retains initial 100 ms deadline");
    }
    Pump(.15); Report(@"sustained_body", owners);
    for (NSUInteger i = 0; i < owners.count; i++) {
        Browser *b = owners[i];
        Check(b->session->timers >= 6 && b->session->timers <= 9 && b->session->maxDelay < .16, "timer rate stays bounded with duplicate legacy row signals");
        Check(b->publications == (i == 2 ? 1 : 0), "Date Modified rebuilds once; title order skips full refresh");
        Check(b->redraws + b->publications == b->session->timers, "one row or changed-order publication per timer");
        Check(!Dirty(b->session) && !DirtyCount(b->session), "last body edit drains completely");
        Check(b->editors == 70 && b->headers == 0, "editor fanout adds no header refresh or full refresh scheduling");
    }
    Check([((Browser *)owners[2])->session noteObjectAtFilteredIndex:0] == edited, "Date Modified browser publishes correct latest-note order");
    // Pending body work followed by 50 synchronous metadata mutations must use one full publication.
    Reset(owners); BodyEdit(app, edited, 1000);
    for (NSUInteger i = 0; i < 50; i++) {
        [edited->titleString release]; edited->titleString = [[NSString stringWithFormat:@"Renamed %lu", i] copy];
        [app searchableNoteDidChange:edited]; [app titleUpdatedForNote:edited]; [app noteMetadataUpdated:edited];
    }
    Pump(.18); Report(@"synchronous_metadata_burst", owners);
    for (Browser *b in owners) {
        Check(b->publications == 1 && b->redraws == 0 && b->session->timers == 0, "metadata burst coalesces and cancels old dirty-row callback");
        Check([b->session searchResultsAreCurrent] && !Dirty(b->session), "metadata replacement projection is current and leaves no delayed body work");
    }
    // Separate run-loop turns are separate metadata updates; none may grow a trailing body reload.
    Reset(owners);
    for (NSUInteger turn = 0; turn < 20; turn++) {
        BodyEdit(app, edited, 2000 + turn);
        for (NSUInteger j = 0; j < 5; j++) {
            [edited->labelString release]; edited->labelString = [[NSString stringWithFormat:@"tag-%lu-%lu", turn, j] copy];
            [app searchableNoteDidChange:edited]; [app noteMetadataUpdated:edited];
        }
        Pump(.025);
    }
    Pump(.16); Report(@"twenty_metadata_turns", owners);
    for (Browser *b in owners) Check(b->publications == 20 && b->redraws == 0 && b->session->timers == 0,
        "twenty metadata turns yield twenty publications with no trailing duplicate refresh");
    // Alternating which note becomes newest requires one changed-order publication each deadline.
    Reset(owners); NoteObject *other = library->notes[1];
    for (NSUInteger cycle = 0; cycle < 6; cycle++) {
        NoteObject *target = cycle % 2 ? edited : other;
        [target setContentString:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"cycle %lu", cycle]] autorelease]];
        target->modifiedDate = CFAbsoluteTimeGetCurrent(); [app searchableNoteDidChange:target]; Pump(.115);
        Check([((Browser *)owners[2])->session noteObjectAtFilteredIndex:0] == target, "each changed Date Modified order publishes by next deadline");
    }
    Report(@"alternating_date_order", owners);
    for (NSUInteger i = 0; i < owners.count; i++) {
        Browser *b = owners[i]; Check(b->session->timers == 6 && b->publications == (i == 2 ? 6 : 0), "changed-order refresh occurs exactly once per due timer");
    }
    for (Browser *b in owners) { [b->session setDelegate:nil]; [b->session release]; }
    [app release]; [service invalidate]; [service release]; [library release];
    printf("PASS: sustained coordinator scheduling (%lu checks)\n", Checks);
} return 0; }
