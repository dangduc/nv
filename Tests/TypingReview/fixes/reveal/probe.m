#include "support.h"

@interface TrackedOwner : RevealOwner
@end
@implementation TrackedOwner
- (void)browserSessionSearchDidComplete:(NVBrowserSession *)session {
    completions++; [super browserSessionSearchDidComplete:session];
}
@end
@interface BackgroundWindow : NSObject { @public NSUInteger frontCalls; }
@end
@implementation BackgroundWindow
- (BOOL)isKeyWindow { return NO; }
- (void)makeKeyAndOrderFront:(id)sender { frontCalls++; }
@end

typedef struct {
    MemoryLibrary *library;
    NVBrowserSession *session;
    TrackedOwner *owner;
    NVSearchService *service;
    BackgroundWindow *window;
} Fixture;
static Fixture MakeFixture(NSString *mode, NSString *query) {
    Fixture f;
    f.library = [[MemoryLibrary alloc] init];
    f.session = [[NVBrowserSession alloc] initWithLibrary:(id)f.library];
    f.service = [[NVSearchService alloc] init]; [f.session setSearchService:f.service];
    f.owner = [[TrackedOwner alloc] init]; f.owner->library = f.library; f.owner->notationController = f.session;
    f.owner->notesTableView = [[RevealTable alloc] init]; f.owner->notesTableView->session = f.session; f.owner->notesTableView->owner = f.owner;
    f.owner->field = [[RevealField alloc] init]; [f.owner->field setStringValue:query];
    f.window = [[BackgroundWindow alloc] init]; f.owner->window = f.window;
    [f.session setDelegate:f.owner]; [f.session setSearchMode:mode]; [f.session filterNotesFromString:query];
    Check(Await(^BOOL { return [f.session searchResultsAreCurrent]; }), "fixture has a current starting projection");
    return f;
}
static NoteObject *AddTarget(Fixture f, NSString *title) {
    NoteObject *note = Note(title); [f.library->notes addObject:note]; Snapshot(f.service, note);
    [f.session invalidateSearch];
    [f.session performSelector:@selector(libraryDidChange) withObject:nil afterDelay:0];
    Check(![f.session searchResultsAreCurrent], "model invalidation continues to disable stale row actions");
    return note;
}
static void Destroy(Fixture f) {
    [f.session setDelegate:nil]; [f.session release]; [f.service invalidate]; [f.service release];
    [f.owner release]; [f.window release]; [f.library release];
}
static void ImmediateReveal(NSString *mode, NSString *query, BOOL expectedClear) {
    printf("SCENARIO: immediate %s query '%s'\n", mode.UTF8String, query.UTF8String);
    Fixture f = MakeFixture(mode, query); NoteObject *note = AddTarget(f, @"New matching note");
    NSUInteger row = [f.owner revealNote:note options:0];
    Check(row != NSNotFound && f.owner->selected == note && !f.owner->pendingSearchReveal,
          "Reveal synchronously selects the newly added note");
    Check([[f.owner->field stringValue] isEqual:expectedClear ? @"" : query],
          "Reveal preserves a matching query and clears an excluding query");
    Pump(.25);
    Check(f.owner->selected == note && !f.owner->pendingSearchReveal && [f.session searchResultsAreCurrent],
          "the note remains selected after delayed work drains");
    Check(f.window->frontCalls == 0, "Reveal without order-front options does not activate a background window");
    Destroy(f);
}
static void InlineBlockedReveal(void) {
    printf("SCENARIO: inline editor blocks Exact publication\n");
    Fixture f = MakeFixture(@"exact", @"New matching note"); NoteObject *note = AddTarget(f, @"New matching note");
    f.owner->allowsChange = NO;
    NSUInteger before = f.owner->completions;
    Check([f.owner revealNote:note options:0] == NSNotFound && f.owner->pendingSearchReveal[@"note"] == note,
          "Reveal queues while the inline editor prohibits list changes");
    Pump(.25);
    Check(![f.session searchResultsAreCurrent] && !f.owner->selected && f.owner->completions == before,
          "the blocked projection stays unavailable and does not complete early");
    f.owner->allowsChange = YES;
    Check(Await(^BOOL { return f.owner->selected == note; }), "ending inline editing resumes and delivers the pending Reveal");
    Check(!f.owner->pendingSearchReveal && f.owner->completions == before + 1,
          "synchronous publication completes the selection intent once");
    Pump(.2);
    Check(f.owner->completions == before + 1 && f.window->frontCalls == 0,
          "the delayed delivery neither repeats completion nor activates the background window");
    Destroy(f);
}
static void CompositionReveal(void) {
    printf("SCENARIO: search composition blocks synchronous Reveal\n");
    Fixture f = MakeFixture(@"exact", @"New matching note"); NoteObject *note = AddTarget(f, @"New matching note");
    f.owner->searchHasPendingComposition = YES; [f.session suspendSearchForComposition:YES];
    NSUInteger before = f.owner->completions;
    Check([f.owner revealNote:note options:0] == NSNotFound, "Reveal does not bypass the session's composition gate");
    Pump(.2);
    Check(!f.owner->selected && ![f.session searchResultsAreCurrent] && f.owner->completions == before,
          "composition keeps the old projection inactive without an early selection callback");
    // Match the existing new-query policy: committing a field change cancels
    // selection intents before ending composition and submitting that query.
    [f.owner cancelSearchIntents]; f.owner->searchHasPendingComposition = NO;
    [f.session suspendSearchForComposition:NO];
    Check(!f.owner->pendingSearchReveal && !f.owner->selected,
          "committing a new query preserves the existing intent-cancellation policy");
    Destroy(f);
}
static void AsyncFuzzyReveal(void) {
    printf("SCENARIO: active Fuzzy query preserves asynchronous delivery\n");
    Fixture f = MakeFixture(@"fuzzy", @"New matching note"); NoteObject *note = AddTarget(f, @"New matching note");
    NSUInteger before = f.owner->completions;
    Check([f.owner revealNote:note options:0] == NSNotFound && f.owner->pendingSearchReveal[@"note"] == note,
          "Reveal waits for active Fuzzy results instead of forcing a synchronous projection");
    Check(f.owner->completions == before && !f.owner->selected,
          "active Fuzzy Reveal has no synchronous completion");
    Check(Await(^BOOL { return f.owner->selected == note; }), "the native Fuzzy completion delivers the requested note");
    Check(!f.owner->pendingSearchReveal && f.owner->completions == before + 1 && f.window->frontCalls == 0,
          "Fuzzy completion consumes the intent once without background activation");
    Destroy(f);
}
int main(void) { @autoreleasepool {
    ImmediateReveal(@"exact", @"New matching note", NO);
    ImmediateReveal(@"exact", @"Excluded query", YES);
    ImmediateReveal(@"fuzzy", @"", NO);
    InlineBlockedReveal(); CompositionReveal(); AsyncFuzzyReveal();
    printf("PASS: Reveal fix (%lu checks)\n", (unsigned long)Checks);
} return 0; }
