#include "support.h"

@interface IntentOwner : RevealOwner { @public NSUInteger stateDepth, maxStateDepth, highlightCalls; }
@end
@implementation IntentOwner
- (void)browserSessionSearchStateDidChange:(NVBrowserSession *)session {
    stateDepth++; maxStateDepth = MAX(maxStateDepth, stateDepth);
    [super browserSessionSearchStateDidChange:session]; stateDepth--;
}
- (void)browserSessionSearchDidComplete:(NVBrowserSession *)session {
    completions++; [super browserSessionSearchDidComplete:session];
}
- (void)refreshSearchHighlights { highlightCalls++; }
@end

typedef struct { MemoryLibrary *library; NVBrowserSession *session; NVSearchService *service; IntentOwner *owner; NoteObject *a, *b; } Fixture;
static Fixture MakeFixture(NSString *query) {
    Fixture f;
    f.library = [[MemoryLibrary alloc] init]; f.a = Note(@"Alpha"); f.b = Note(@"Beta");
    [f.library->notes addObjectsFromArray:@[f.a, f.b]];
    f.session = [[NVBrowserSession alloc] initWithLibrary:(id)f.library];
    f.service = [[NVSearchService alloc] init]; Snapshot(f.service, f.a); Snapshot(f.service, f.b);
    [f.session setSearchService:f.service];
    f.owner = [[IntentOwner alloc] init]; f.owner->library = f.library; f.owner->notationController = f.session;
    f.owner->notesTableView = [[RevealTable alloc] init]; f.owner->notesTableView->owner = f.owner; f.owner->notesTableView->session = f.session;
    f.owner->field = [[RevealField alloc] init]; [f.owner->field setStringValue:query];
    [f.session setDelegate:f.owner]; [f.session filterNotesFromString:query];
    Check([f.session searchResultsAreCurrent], "starting Exact projection is current");
    f.owner->allowsChange = NO; [f.session invalidateSearch];
    [f.session performSelector:@selector(libraryDidChange) withObject:nil afterDelay:0];
    return f;
}
static void Destroy(Fixture f) {
    [f.session setDelegate:nil]; [f.session release]; [f.service invalidate]; [f.service release];
    [f.owner release]; [f.library release];
}
static void Unblock(Fixture f) {
    f.owner->allowsChange = YES; [f.session libraryDidChange];
    Check([f.session searchResultsAreCurrent], "unblocked publication is current");
}
static void LatestRevealWins(void) {
    printf("SCENARIO: blocked Reveal replaced by another Reveal, then an invalid target\n");
    Fixture f = MakeFixture(@"");
    [f.owner revealNote:f.a options:0]; [f.owner revealNote:f.b options:0];
    NoteObject *absent = Note(@"Absent");
    Check([f.owner revealNote:absent options:0] == NSNotFound, "invalid library target is rejected");
    Check(f.owner->pendingSearchReveal[@"note"] == f.b, "invalid Reveal preserves latest accepted intent");
    Unblock(f);
    Check(f.owner->selected == f.b && !f.owner->pendingSearchReveal, "one current publication delivers the replacement target");
    NSUInteger completed = f.owner->completions; Pump(.3);
    Check(completed == 1 && f.owner->completions == completed, "delayed retry cannot repeat the consumed Reveal");
    Destroy(f);
}
static void RestorationReplacement(void) {
    printf("SCENARIO: restoration replaces blocked Reveal and Reveal replaces restoration\n");
    Fixture f = MakeFixture(@""); [f.owner revealNote:f.a options:0];
    [f.owner cancelSearchIntents]; NSDictionary *state = @{@"note":@"restoration-sentinel"};
    f.owner->pendingSearchRestoration = [state copy];
    Unblock(f);
    Check(f.owner->restorationDeliveries == 1 && f.owner->lastRestoration == state && !f.owner->pendingSearchRestoration,
          "synchronous publication consumes the restoration payload once");
    Check(!f.owner->selected && !f.owner->pendingSearchReveal, "replaced Reveal cannot select its old target");
    f.owner->allowsChange = NO; [f.session invalidateSearch];
    f.owner->pendingSearchRestoration = [state copy]; [f.owner revealNote:f.b options:0];
    Unblock(f);
    Check(f.owner->selected == f.b && f.owner->restorationDeliveries == 1, "later accepted Reveal cancels older restoration");
    Destroy(f);
}
static void NestedQueryClearing(void) {
    printf("SCENARIO: excluded pending Reveal clears query during completion publication\n");
    Fixture f = MakeFixture(@"Alpha"); [f.owner revealNote:f.b options:0];
    Unblock(f);
    Check(f.owner->selected == f.b && [[f.session searchString] isEqual:@""], "excluded target is selected after nested empty-query publication");
    Check(f.owner->maxStateDepth >= 2, "test entered a nested production state callback");
    Check(f.owner->completions == 1 && !f.owner->searchApplyingResult && !f.owner->pendingSearchReveal,
          "recursive publications neither redeliver nor leave the application guard set");
    Pump(.3); Check(f.owner->selected == f.b && f.owner->completions == 1, "draining deferred work preserves the nested completion result");
    Destroy(f);
}
static void MultiRevealReplacement(void) {
    printf("SCENARIO: multi-note Reveal replaces single intent, then user cancels\n");
    Fixture f = MakeFixture(@"Alpha"); [f.owner revealNote:f.a options:0];
    [f.owner notation:(id)f.session revealNotes:@[f.b, f.a, f.b, Note(@"Absent")]];
    Check([f.owner->pendingSearchReveal[@"notes"] isEqual:@[f.b, f.a]], "multi-note intent filters missing notes and deduplicates UUIDs");
    Unblock(f);
    Check([[f.session searchString] isEqual:@""] && !f.owner->pendingSearchReveal && f.owner->completions == 1,
          "multi-note completion clears excluding query and consumes one intent");
    f.owner->allowsChange = NO; [f.session invalidateSearch]; [f.owner revealNote:f.b options:0];
    [f.owner cancelSearchIntents]; NoteObject *before = f.owner->selected; Unblock(f);
    Check(f.owner->selected == before && f.owner->completions == 1, "canceled explicit intent cannot run on the next current publication");
    Destroy(f);
}
int main(void) { @autoreleasepool {
    LatestRevealWins(); RestorationReplacement(); NestedQueryClearing(); MultiRevealReplacement();
    printf("PASS: intent publication review (%lu checks)\n", (unsigned long)Checks);
} return 0; }
