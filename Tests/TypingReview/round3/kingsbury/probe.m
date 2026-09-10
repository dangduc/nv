#include "support.inc"
static NSArray *Keys(NVBrowserSession *session) {
    return [session rowKeysAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, Visible(session).count)]];
}
static void PendingActions(NVBrowserSession *s) {
    if (![s searchResultsAreCurrent]) Check(![s notesAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,Visible(s).count)]].count,
        "obsolete projection rejects every row action");
}
static void AllBody(NSArray *sessions, NVSearchService *service, NoteObject *note, NSString *text) {
    [note setContentString:[[[NSAttributedString alloc] initWithString:text] autorelease]];
    Snapshot(service,note);
    for (NVBrowserSession *s in sessions) {
        [s noteBodyDidChange:note];
        if ([s hasSearchTerms]) Check(![s searchResultsAreCurrent],"body edits immediately invalidate active-query membership");
        PendingActions(s);
    }
}
static void Membership(NSArray *sessions) {
    for (NVBrowserSession *s in sessions) { [s invalidateSearch]; PendingActions(s); }
    for (NVBrowserSession *s in sessions) [s libraryDidChange];
}
static void CompareFresh(NVBrowserSession *actual, MemoryLibrary *library, NVSearchService *freshService) {
    NVBrowserSession *fresh=[[NVBrowserSession alloc] initWithLibrary:(id)library];
    Owner *owner=[[Owner alloc] init]; [fresh setDelegate:owner]; [fresh setSearchService:freshService];
    [fresh setSearchMode:[actual searchMode]];
    if ([actual sortColumn]) [fresh setSortColumn:[actual sortColumn] reversed:[actual reverseSorted]];
    [fresh filterNotesFromString:[actual searchString]];
    Check(Await(^BOOL{return [fresh searchResultsAreCurrent] && [actual searchResultsAreCurrent];}),"history and fresh oracle both become current");
    if (![Keys(actual) isEqual:Keys(fresh)]) fprintf(stderr,"actual=%s oracle=%s\n",Keys(actual).description.UTF8String,Keys(fresh).description.UTF8String);
    Check([Keys(actual) isEqual:Keys(fresh)],"eventual occurrence keys and order equal fresh projection");
    Check([Visible(actual) isEqual:Visible(fresh)],"eventual row targets equal fresh projection by object identity");
    Check([actual resultCount]==[fresh resultCount] && [actual distinctResultNoteCount]==[fresh distinctResultNoteCount],"result and unique-note counts equal fresh projection");
    NSArray *actions=[actual notesAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,Visible(actual).count)]];
    Check([[NSSet setWithArray:actions] isEqual:[NSSet setWithArray:Visible(fresh)]] && actions.count==[NSSet setWithArray:actions].count,
        "all-row commands resolve exactly the current unique notes");
    for (NSUInteger i=0;i<Visible(actual).count;i++) {
        NSString *key=[actual rowKeyAtIndex:i];
        Check([actual indexForRowKey:key]==i,"each occurrence key resolves to its current row");
        Check([library->notes containsObject:[actual noteObjectAtFilteredIndex:i]],"no deleted object survives in visible rows");
    }
    Check(!Dirty(actual) && !DirtyCount(actual),"superseded dirty-row work drains completely");
    [fresh setDelegate:nil]; [fresh release]; [owner release];
}
static void Matrix(NSUInteger ordering) {
    MemoryLibrary *library=[[MemoryLibrary alloc] init];
    NoteObject *a=Note(@"needle alpha"),*b=Note(@"needle beta"),*c=Note(@"gamma"),*d=Note(@"delta"),*e=Note(@"epsilon");
    [library->notes addObjectsFromArray:@[a,b,c,d,e]];
    NVSearchService *service=[[NVSearchService alloc] init];
    NSUInteger n=0; for (NoteObject *note in library->notes) { note->modifiedDate=++n; Snapshot(service,note); }
    NSMutableArray *sessions=[NSMutableArray array],*owners=[NSMutableArray array];
    NSArray *queries=@[@"",@"",@"needle",@"needle",@"tagonly",@"needle"];
    NSArray *modes=@[@"exact",@"fuzzy",@"exact",@"fuzzy",@"exact",@"fuzzy"];
    DateColumn *column=[[DateColumn alloc] init];
    for (NSUInteger i=0;i<6;i++) {
        Owner *owner=[[[Owner alloc] init] autorelease];
        NVBrowserSession *s=[[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        [s setDelegate:owner]; [s setSearchService:service]; [s setSearchMode:modes[i]];
        if (i==1) [s setSortColumn:(id)column reversed:YES];
        [s filterNotesFromString:queries[i]]; [sessions addObject:s]; [owners addObject:owner];
    }
    Check(Await(^BOOL{for(NVBrowserSession *s in sessions) if(![s searchResultsAreCurrent]) return NO; return YES;}),"six independent initial projections become current");
    for (Owner *o in owners) o->allowsChange=NO;
    a->modifiedDate=20; AllBody(sessions,service,a,@"needle body edit");
    AllBody(sessions,service,c,@"tagonly body edit"); Pump(.13);
    Check(Dirty(sessions[0]) && DirtyCount(sessions[0])==2 && Dirty(sessions[1]),"both empty-query sessions retain queued edits behind publication gate");
    // Eight deterministic event permutations. Query changes cross the delayed-body
    // path in both directions. Workers can complete while native result publication is gated.
    for (NSUInteger k=0;k<4;k++) {
        NSUInteger op=(k+ordering)%4;
        if (ordering>=4) op=3-op;
        if (op==0) {
            [a->titleString release]; a->titleString=[@"retitled alpha" copy];
            [d->labelString release]; d->labelString=[@"needle tagonly" copy];
            Snapshot(service,a); Snapshot(service,d); Membership(sessions);
        } else if (op==1) {
            [library->notes removeObjectIdenticalTo:b]; [service removeUUID:UUID(b)]; Membership(sessions);
            NoteObject *replacement=Note(@"needle beta"); [library->notes addObject:replacement]; Snapshot(service,replacement); Membership(sessions);
        } else if (op==2) {
            [sessions[0] filterNotesFromString:@"needle"];
            [sessions[2] filterNotesFromString:@""];
            [sessions[3] filterNotesFromString:@"tagonly"];
            [sessions[5] filterNotesFromString:@"absentzzz"];
            [sessions[5] filterNotesFromString:@"needle"];
        } else {
            c->modifiedDate=30; AllBody(sessions,service,c,@"needle latest body");
            AllBody(sessions,service,a,@"no match");
            AllBody(sessions,service,e,@"needle temporary"); AllBody(sessions,service,e,@"seed");
        }
        Pump(.006);
        for (NVBrowserSession *s in sessions) PendingActions(s);
    }
    for (Owner *o in owners) o->allowsChange=YES;
    Check(Await(^BOOL{for(NVBrowserSession *s in sessions) if(![s searchResultsAreCurrent]) return NO; return YES;}),"all interleaved projections converge after unblocking");
    Pump(.25);
    NVSearchService *freshService=[[NVSearchService alloc] init];
    for (NoteObject *note in library->notes) Snapshot(freshService,note);
    for (NVBrowserSession *s in sessions) {
        Check(![Visible(s) containsObject:b],"deleted note cannot reappear after trailing dirty publication");
        CompareFresh(s,library,freshService);
    }
    for (NVBrowserSession *s in sessions) [s setDelegate:nil];
    [freshService invalidate]; [freshService release]; [service invalidate]; [service release];
    [column release]; [library release];
    printf("MATRIX ordering=%lu sessions=6 PASS\n",(unsigned long)ordering);
}
int main(void) { @autoreleasepool {
    for (NSUInteger i=0;i<8;i++) Matrix(i);
    printf("PASS: multi-browser projection matrix (%lu checks; 8 orderings; 48 browser histories)\n",(unsigned long)Checks);
} return 0; }
