@interface ReviewBrowser : NSObject { @public NVBrowserSession *session; }
- (NVBrowserSession *)browserSession;
@end
@implementation ReviewBrowser
- (NVBrowserSession *)browserSession { return session; }
@end

// Dependencies are in-memory doubles. Every included method is copied unchanged
// from the production application coordinator by run-coordinator.py.
@interface ReviewCoordinator : NSObject {
@public TestLibrary *library; NVSearchService *searchService; NSArray *browsers; NSUInteger searchSnapshotRevision;
}
- (NSArray *)browserControllers;
- (void)refreshBrowsers;
- (void)scheduleBrowserRefresh;
- (NVSearchNoteSnapshot *)searchSnapshotForNote:(NoteObject *)note;
- (void)invalidateBrowserSearches;
- (void)searchableNoteDidChange:(NoteObject *)note;
- (void)searchableNoteWasRemoved:(NoteObject *)note;
@end
@implementation ReviewCoordinator
- (NSArray *)browserControllers { return browsers; }
#include "coordinator-methods.inc"
@end

int main(void) {
    @autoreleasepool {
        NoteObject *road = Note(@"road", @"road body"), *fresh = Note(@"other", @"new source");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, fresh]] autorelease];
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library);
        ReviewCoordinator *coordinator = [[[ReviewCoordinator alloc] init] autorelease];
        coordinator->library = library; coordinator->searchService = service;
        ReviewBrowser *left = [[[ReviewBrowser alloc] init] autorelease], *right = [[[ReviewBrowser alloc] init] autorelease];
        left->session = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        right->session = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        coordinator->browsers = @[left, right];
        for (ReviewBrowser *browser in coordinator->browsers) {
            [browser->session setSearchService:service]; [browser->session setSearchMode:@"fuzzy"];
        }
        Search(left->session, @"road"); Search(right->session, @"new");
        NSUInteger oldLeft = left->session.searchResult.requestID, oldRight = right->session.searchResult.requestID;
        NSUInteger oldRevision = service.corpusRevision;
        [coordinator searchableNoteDidChange:road];
        Check(service.corpusRevision == oldRevision && [left->session searchResultsAreCurrent] && [right->session searchResultsAreCurrent], "unchanged model notification preserves both browser identities");
        [coordinator scheduleBrowserRefresh];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        Check(left->session.searchResult.requestID == oldLeft && right->session.searchResult.requestID == oldRight, "display refresh reuses each browser's completed request");
        [fresh setContentString:[[[NSAttributedString alloc] initWithString:@"road new body"] autorelease]];
        [coordinator searchableNoteDidChange:fresh];
        Check(![left->session searchResultsAreCurrent] && ![right->session searchResultsAreCurrent], "coordinator mutation invalidates both browsers before the run loop");
        Check(![service isRequestCurrent:oldLeft forOwner:left->session] && ![service isRequestCurrent:oldRight forOwner:right->session], "coordinator mutation synchronously cancels both worker request identities");
        Check([[service snapshotForUUID:UUID(fresh)].source isEqual:@"road new body"], "coordinator captures committed source at the mutation boundary");
        Check(Spin(^BOOL { return [left->session searchResultsAreCurrent] && [right->session searchResultsAreCurrent]; }), "deferred coordinator refresh completes both new requests");
        Check([Visible(left->session) count] == 3 && [Visible(right->session) count] == 1, "different browser queries resolve one changed shared corpus");
        [fresh setTitleString:@"road renamed"];
        [coordinator searchableNoteDidChange:fresh];
        Check(![left->session searchResultsAreCurrent] && ![right->session searchResultsAreCurrent], "title mutation shares the synchronous invalidation contract");
        Check(Spin(^BOOL { return [left->session searchResultsAreCurrent] && [right->session searchResultsAreCurrent]; }), "title mutation completes both browser refreshes");
        Check([Visible(left->session) count] == 4, "title mutation adds one occurrence without merging fuzzy overlap");
        [library removeNote:fresh]; [coordinator searchableNoteWasRemoved:fresh];
        Check(![left->session searchResultsAreCurrent] && ![right->session searchResultsAreCurrent], "removal invalidates both browsers before a deferred refresh");
        Check([service snapshotForUUID:UUID(fresh)] == nil, "removal drops the immutable version synchronously");
        Check(Spin(^BOOL { return [left->session searchResultsAreCurrent] && [right->session searchResultsAreCurrent]; }), "removal refreshes both windows");
        Check([Visible(left->session) count] == 2 && [Visible(right->session) count] == 0, "removal drops all matching occurrences in each query");
        NSUInteger finalRevision = service.corpusRevision;
        [fresh setContentString:[[[NSAttributedString alloc] initWithString:@"detached note mutation"] autorelease]];
        [coordinator searchableNoteDidChange:fresh];
        Check(service.corpusRevision == finalRevision && [service snapshotForUUID:UUID(fresh)] == nil, "detached model callback cannot reinsert a deleted UUID");
        [left->session setDelegate:nil]; [right->session setDelegate:nil]; [service invalidate];
        [NSObject cancelPreviousPerformRequestsWithTarget:coordinator];
        printf("COORDINATOR OWNERSHIP REVIEW: %lu checks passed\n", (unsigned long)Checks);
    }
    return 0;
}
