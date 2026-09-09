#import <Cocoa/Cocoa.h>

static NSUInteger Checks, DistinctCountReads;
static void Check(BOOL value, NSString *message) {
    if (!value) { fprintf(stderr, "FAIL %s\n", [message UTF8String]); exit(1); }
    Checks++; fprintf(stdout, "PASS %s\n", [message UTF8String]);
}

// An immutable session double supplies states without a search worker or library.
@interface NVBrowserSession : NSObject { NSDictionary *state; }
- (id)initWithState:(NSDictionary *)value;
- (NSString *)searchString;
- (NSString *)searchMode;
- (BOOL)hasSearchTerms;
- (BOOL)searchResultsAreCurrent;
- (BOOL)searchPending;
- (NSUInteger)resultCount;
- (NSUInteger)distinctResultNoteCount;
- (NSError *)searchError;
@end
@implementation NVBrowserSession
- (id)initWithState:(NSDictionary *)value { if ((self = [super init])) state = [value copy]; return self; }
- (void)dealloc { [state release]; [super dealloc]; }
- (NSString *)searchString { return state[@"query"]; }
- (NSString *)searchMode { return state[@"mode"]; }
- (BOOL)hasSearchTerms { return [state[@"terms"] boolValue]; }
- (BOOL)searchResultsAreCurrent { return [state[@"current"] boolValue]; }
- (BOOL)searchPending { return [state[@"pending"] boolValue]; }
- (NSUInteger)resultCount { return [state[@"count"] unsignedIntegerValue]; }
- (NSUInteger)distinctResultNoteCount { DistinctCountReads++; return 3; }
- (NSError *)searchError { return state[@"error"]; }
@end

@interface SummaryFixture : NSObject {
    NVBrowserSession *sessionValue;
    NSButton *createNoteButton;
    NSTextField *searchStatusField;
    NSSearchField *field;
    NSView *notesSubview;
    NSScrollView *notesScrollView;
    BOOL searchStatusDelayElapsed;
}
- (NVBrowserSession *)browserSession;
- (void)updateSearchAffordance;
- (void)useState:(NSDictionary *)state delayed:(BOOL)delayed height:(CGFloat)height;
- (void)assertQuiet;
- (void)assertStatus:(NSString *)status;
- (void)assertCreate:(BOOL)visible query:(NSString *)query;
- (void)assertRetry;
- (NSArray *)controlIdentities;
@end
@implementation SummaryFixture
- (id)init {
    if ((self = [super init])) {
        createNoteButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        searchStatusField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 18)];
        field = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        notesSubview = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 220)];
        notesScrollView = [[NSScrollView alloc] initWithFrame:[notesSubview bounds]];
        [notesSubview addSubview:notesScrollView];
    }
    return self;
}
- (void)dealloc {
    [sessionValue release]; [createNoteButton release]; [searchStatusField release];
    [field release]; [notesScrollView release]; [notesSubview release]; [super dealloc];
}
- (NVBrowserSession *)browserSession { return sessionValue; }
// This include is the exact method extracted from the recorded source revision.
#include "production.inc"
- (void)useState:(NSDictionary *)state delayed:(BOOL)delayed height:(CGFloat)height {
    [sessionValue release]; sessionValue = [[NVBrowserSession alloc] initWithState:state];
    searchStatusDelayElapsed = delayed;
    [notesSubview setBounds:NSMakeRect(3, 5, 400, height)];
    [self updateSearchAffordance];
}
- (void)assertQuiet {
    Check([searchStatusField isHidden], @"completed search hides the summary control");
    Check([[searchStatusField stringValue] length] == 0 && [[searchStatusField toolTip] length] == 0 && [[field toolTip] length] == 0,
        @"quiet search clears status text and both stale tooltips");
    Check(NSEqualRects([notesScrollView frame], [notesSubview bounds]), @"quiet search returns the entire list bounds to the scroll view");
}
- (void)assertStatus:(NSString *)status {
    Check(![searchStatusField isHidden] && [[searchStatusField stringValue] isEqual:status], @"a delayed or failed search displays its useful status");
    Check([[searchStatusField toolTip] isEqual:status] && [[field toolTip] isEqual:status], @"active status remains available in both tooltips");
    NSRect expected = [notesSubview bounds]; expected.size.height = MAX(0, expected.size.height - 24);
    Check(NSEqualRects([notesScrollView frame], expected), @"active status reserves one row without negative list height");
}
- (void)assertCreate:(BOOL)visible query:(NSString *)query {
    Check([createNoteButton isHidden] == !visible && [createNoteButton action] == @selector(createNoteFromSearch:),
        @"summary removal preserves Create visibility and action");
    if (visible) {
        Check([[createNoteButton title] containsString:query] && [[createNoteButton toolTip] isEqual:[createNoteButton title]],
            @"zero results retain the query-specific Create label and tooltip");
    }
}
- (void)assertRetry {
    Check(![createNoteButton isHidden] && [createNoteButton action] == @selector(retrySearch:) &&
        [[createNoteButton title] isEqual:NSLocalizedString(@"Retry Search", nil)], @"errors retain the Retry action and label");
}
- (NSArray *)controlIdentities { return @[createNoteButton, searchStatusField, field, notesSubview, notesScrollView]; }
@end

static NSDictionary *State(NSString *mode, NSString *query, BOOL terms, BOOL current, BOOL pending, NSUInteger count, NSError *error) {
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithDictionary:@{
        @"mode": mode, @"query": query, @"terms": @(terms), @"current": @(current), @"pending": @(pending), @"count": @(count)}];
    if (error) state[@"error"] = error;
    return state;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        SummaryFixture *browser = [[SummaryFixture alloc] init];
        SummaryFixture *peer = [[SummaryFixture alloc] init];
        NSArray *original = [[browser controlIdentities] copy];
        NSDictionary *complete = State(@"fuzzy", @"café", YES, YES, NO, 12, nil);
        NSDictionary *pending = State(@"fuzzy", @"café", YES, NO, YES, 0, nil);
        NSError *error = [NSError errorWithDomain:@"SummaryReview" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Fixture search failed"}];
        NSDictionary *failed = State(@"fuzzy", @"café", YES, NO, NO, 0, error);
        [peer useState:failed delayed:YES height:220]; [peer assertStatus:@"Fixture search failed"]; [peer assertRetry];
        for (NSNumber *height in @[@0, @8, @24, @220]) {
            // Delayed search -> completed search must clear the old status.
            [browser useState:pending delayed:YES height:[height doubleValue]];
            [browser assertStatus:NSLocalizedString(@"Searching…", nil)]; [browser assertCreate:NO query:@"café"];
            [browser useState:complete delayed:YES height:[height doubleValue]];
            [browser assertQuiet]; [browser assertCreate:NO query:@"café"];
            // Error -> completion must clear the error and recover the full list.
            [browser useState:failed delayed:YES height:[height doubleValue]];
            [browser assertStatus:@"Fixture search failed"]; [browser assertRetry];
            [browser useState:complete delayed:YES height:[height doubleValue]];
            [browser assertQuiet]; [browser assertCreate:NO query:@"café"];
            [browser useState:pending delayed:NO height:[height doubleValue]];
            [browser assertQuiet]; [browser assertCreate:NO query:@"café"];
            [browser useState:State(@"fuzzy", @"missing", YES, YES, NO, 0, nil) delayed:YES height:[height doubleValue]];
            [browser assertQuiet]; [browser assertCreate:YES query:@"missing"];
            [browser useState:State(@"exact", @"café", YES, YES, NO, 12, nil) delayed:YES height:[height doubleValue]];
            [browser assertQuiet]; [browser assertCreate:NO query:@"café"];
            [browser useState:State(@"fuzzy", @"", NO, YES, NO, 12, nil) delayed:YES height:[height doubleValue]];
            [browser assertQuiet]; [browser assertCreate:NO query:@""];
            Check([[browser controlIdentities] isEqual:original], @"all transitions reuse the existing controls and container");
            [peer assertStatus:@"Fixture search failed"]; [peer assertRetry];
        }
        Check(DistinctCountReads == 0, @"affordance no longer depends on the distinct-note count");
        fprintf(stdout, "RESULT passes=%lu distinct_count_reads=%lu\n", (unsigned long)Checks, (unsigned long)DistinctCountReads);
        [original release]; [browser release]; [peer release];
    }
    return 0;
}
