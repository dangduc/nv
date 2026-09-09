// New bounded round-three histories. Real native matching finishes before the
// delivery gate records a callback. The tests then choose its publication order.
#import <objc/runtime.h>

@interface HeldDelivery : NSObject {
@public NVSearchCompletion completion; NVSearchResult *result; NSError *error;
}
- (void)deliver;
@end
@implementation HeldDelivery
- (void)deliver { completion(result, error); }
- (void)dealloc { [completion release]; [result release]; [error release]; [super dealloc]; }
@end
static NSMutableArray *deliveries;
static HeldDelivery *AwaitDelivery(NSUInteger index) {
    Check(Spin(^BOOL { return [deliveries count] > index; }), "real worker reaches the controlled delivery boundary");
    return [deliveries objectAtIndex:index];
}
static NSUInteger Start(StateController *controller, NSString *query) {
    NSUInteger index = [deliveries count]; Pending(controller, query); AwaitDelivery(index); return index;
}
static NSString *RowKey(NoteObject *note, NSString *kind) {
    const unsigned char *bytes = (const unsigned char *)[note uniqueNoteIDBytes];
    NSMutableString *key = [NSMutableString stringWithFormat:@"%@:", kind];
    for (NSUInteger i = 0; i < 16; i++) [key appendFormat:@"%02x", bytes[i]];
    return key;
}
static NSDictionary *State(NoteObject *note, NSString *query, NSString *kind) {
    return @{@"search":query, @"searchMode":@"fuzzy", @"note":[NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]],
        @"searchRowKey":RowKey(note, kind), @"selection":NSStringFromRange(NSMakeRange(1, 2))};
}
static void RequireSelection(StateController *controller, NoteObject *note, NSString *kind, const char *message) {
    Check([controller->notationController searchResultsAreCurrent] && controller->currentNote == note &&
        [[controller->notationController rowKeyAtIndex:[controller->notesTableView primarySelectedRow]] isEqual:RowKey(note, kind)], message);
}
static NSUInteger Recapture(StateController *controller, NVSearchService *service, TestLibrary *library) {
    NSUInteger index = [deliveries count];
    Capture(service, library); [controller->notationController libraryDidChange]; AwaitDelivery(index);
    Check(![controller->notationController searchResultsAreCurrent], "changed corpus stays pending behind the publication gate");
    return index;
}
static void Compose(StateController *controller, NSString *text, BOOL marked) {
    [controller->field setStringValue:text]; controller->field->editor->marked = marked;
    [controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification
        object:controller->field userInfo:@{@"NSFieldEditor":controller->field->editor}]];
}
static void DuplicateOccurrenceHistory(void) {
    NoteObject *road = Note(@"Road map", @"road source"), *body = Note(@"Copper", @"road copper");
    TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, body]] autorelease];
    NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;
    StateController *c = Controller(library, service);
    NSUInteger first = [deliveries count]; [c restoreBrowserWindowState:State(road, @"road", @"fuzzy")]; AwaitDelivery(first);
    [[deliveries objectAtIndex:first] deliver];
    RequireSelection(c, road, @"fuzzy", "initial restoration chooses the native occurrence of a duplicated note");
    Check([c->notationController resultCount] == 3 && [c->notationController distinctResultNoteCount] == 2,
        "initial corpus has both title and native occurrences");
    [c revealNote:road options:0];
    RequireSelection(c, road, @"fuzzy", "accepted Reveal of the selected note preserves its native occurrence");
    [library addNote:Note(@"A road", @"road")];
    NSUInteger next = Recapture(c, service, library);
    [c restoreBrowserWindowState:State(road, @"road", @"fuzzy")];
    [[deliveries objectAtIndex:first] deliver];
    Check(c->pendingSearchRestoration && ![c->notationController searchResultsAreCurrent], "old duplicate result cannot consume a newer restoration");
    [[deliveries objectAtIndex:next] deliver];
    RequireSelection(c, road, @"fuzzy", "row-key restoration follows its native occurrence after title rows shift");
    Check(NSEqualRanges(c->textView->selection, NSMakeRange(1, 2)) && !c->pendingSearchRestoration,
        "current restoration applies its caret and consumes its intent exactly once");
    printf("HISTORY duplicate-primary: completed\n");
}
static void CorpusAndLatestIntentHistory(void) {
    NoteObject *road = Note(@"Road map", @"road source"), *copper = Note(@"Copper", @"road copper");
    TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, copper]] autorelease];
    NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;
    StateController *c = Controller(library, service);
    NSUInteger first = [deliveries count]; [c restoreBrowserWindowState:State(road, @"road", @"title")]; AwaitDelivery(first);
    [c revealNote:copper options:0];
    [copper setTitleString:@"Road copper"];
    NSUInteger next = Recapture(c, service, library);
    [[deliveries objectAtIndex:first] deliver];
    Check(c->pendingSearchReveal && !c->pendingSearchRestoration && ![c->notationController searchResultsAreCurrent],
        "old corpus cannot consume the latest accepted Reveal");
    [c->window makeFirstResponder:c->textView];
    [[deliveries objectAtIndex:next] deliver];
    RequireSelection(c, copper, @"title", "latest Reveal resolves against renamed title rows after focus loss");
    Check(!c->pendingSearchReveal && c->creations == 0, "accepted Reveal completes without note creation");

    first = [deliveries count]; [c retrySearch:nil]; AwaitDelivery(first);
    [c notation:(id)c->notationController revealNotes:@[road, copper, road]];
    [library removeNote:road]; next = Recapture(c, service, library);
    [[deliveries objectAtIndex:first] deliver]; [[deliveries objectAtIndex:next] deliver];
    NSArray *selected = [c->notationController notesAtIndexes:[c->notesTableView selectedRowIndexes]];
    Check([selected isEqual:@[copper]] && !c->pendingSearchReveal,
        "plural Reveal drops a deleted target and selects each surviving UUID once");
    Check([c->notationController indexForRowKey:RowKey(road, @"title")] == NSNotFound,
        "deleted note has no current title or fallback occurrence");
    printf("HISTORY corpus-latest-intent: completed\n");
}
static void QueryErrorHistory(void) {
    NoteObject *road = Note(@"Road map", @"road source"), *copper = Note(@"Copper", @"road copper");
    TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, copper]] autorelease];
    NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;
    StateController *c = Controller(library, service);
    NSUInteger first = Start(c, @"road"); [c revealNote:road options:0];
    HeldDelivery *old = [deliveries objectAtIndex:first];
    old->completion(nil, [NSError errorWithDomain:@"BoundedReviewFailure" code:1 userInfo:nil]);
    Check([c->notationController searchError] && c->pendingSearchReveal && c->creations == 0,
        "failed publication cannot consume an accepted selection or create a note");
    NSUInteger second = [deliveries count]; [c restoreBrowserWindowState:State(copper, @"copper", @"fuzzy")]; AwaitDelivery(second);
    [old deliver];
    Check(c->pendingSearchRestoration && !c->pendingSearchReveal && ![c->notationController searchResultsAreCurrent],
        "late success from failed request cannot replace the newer restoration");
    NSUInteger third = Start(c, @"new unique zero query"); [c performSearchReturn];
    [[deliveries objectAtIndex:second] deliver];
    Check(c->creations == 0 && c->pendingSearchReturnQuery && !c->pendingSearchRestoration,
        "new user query supersedes restoration and waits for its own completion");
    [[deliveries objectAtIndex:third] deliver];
    Check(c->creations == 1 && [c->createdTitles isEqual:@[@"new unique zero query"]],
        "only the current explicit Return creates the current zero-result query");
    [old deliver]; [[deliveries objectAtIndex:second] deliver];
    Check(c->creations == 1 && c->bodyFocuses == 1, "obsolete completions cannot repeat the accepted Return");
    printf("HISTORY query-error: completed\n");
}
static void CompositionAndCloseHistory(void) {
    NoteObject *road = Note(@"Road map", @"road source"), *copper = Note(@"Copper", @"road copper");
    TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, copper]] autorelease];
    NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;
    StateController *c = Controller(library, service);
    NSUInteger first = Start(c, @"road"); [c revealNote:road options:0];
    Compose(c, @"unfinished", YES);
    Check(c->searchHasPendingComposition && !c->pendingSearchReveal && ![c->notationController searchResultsAreCurrent],
        "new composition cancels earlier accepted Reveal and suspends publication");
    [[deliveries objectAtIndex:first] deliver]; [c performSearchReturn];
    Check(c->creations == 0 && !c->pendingSearchReturnQuery, "marked text rejects late results and Return intents");
    [c revealNote:copper options:0];
    Check(c->pendingSearchReveal != nil, "a newer Reveal can wait while composition is suspended");
    NSUInteger second = [deliveries count]; Compose(c, @"copper", NO); AwaitDelivery(second);
    [[deliveries objectAtIndex:second] deliver];
    RequireSelection(c, copper, @"title", "committed query resumes matching and replaces earlier composition-time intents");
    first = Start(c, @"road"); [c restoreBrowserWindowState:State(road, @"road", @"fuzzy")]; [c revealNote:copper options:0];
    NSUInteger closes = ClosedWindows;
    [c windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:c->window]];
    Check(c->closed && ClosedWindows == closes + 1 && !c->pendingSearchReveal && !c->pendingSearchRestoration,
        "window close clears accepted programmatic intents and invokes the coordinator close boundary");
    [[deliveries objectAtIndex:first] deliver];
    Check(c->creations == 0 && c->bodyFocuses == 0 && c->currentNote == nil && ![c->notationController searchResultsAreCurrent],
        "held completion after close cannot reopen a note or create content");
    StateController *other = Controller(library, service);
    second = Start(other, @"copper"); [[deliveries objectAtIndex:second] deliver];
    RequireSelection(other, copper, @"title", "closed browser cancellation leaves another browser usable on the shared service");
    printf("HISTORY composition-close: completed\n");
}
int main(void) {
    @autoreleasepool {
        Autocomplete = YES; deliveries = [NSMutableArray new];
        Method method = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
        IMP original = method_getImplementation(method);
        IMP gate = imp_implementationWithBlock(^NSUInteger(NVSearchService *service, id owner, NSString *query, NVSearchCompletion completion) {
            return ((NSUInteger(*)(id, SEL, id, id, id))original)(service, @selector(requestForOwner:query:completion:), owner, query,
                ^(NVSearchResult *result, NSError *error) {
                    HeldDelivery *held = [[[HeldDelivery alloc] init] autorelease];
                    held->completion = [completion copy]; held->result = [result retain]; held->error = [error retain];
                    [deliveries addObject:held];
                });
        });
        method_setImplementation(method, gate);
        DuplicateOccurrenceHistory(); CorpusAndLatestIntentHistory(); QueryErrorHistory(); CompositionAndCloseHistory();
        method_setImplementation(method, original); imp_removeBlock(gate);
        [deliveries removeAllObjects]; [deliveries release]; deliveries = nil;
        printf("ROUND THREE KINGSBURY STATE REVIEW: %lu checks passed\n", (unsigned long)Checks);
    }
    return 0;
}
