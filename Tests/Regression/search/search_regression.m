#import <Cocoa/Cocoa.h>
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"

// In-memory doubles preserve the model's ivar layout. Only browser-session code
// is under test; the executable never opens a notes directory or app window.
NSString *NoteTitleColumnString = @"title";
static NSUInteger ContentsReads, LibraryReads, Comparisons, Checks;
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    Checks++;
}
@implementation GlobalPrefs
+ (GlobalPrefs *)defaultPrefs { static GlobalPrefs *prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (BOOL)tableIsReverseSorted { return NO; }
- (BOOL)autoCompleteSearches { return NO; }
@end
@implementation NoteObject
- (id)initWithNoteBody:(NSAttributedString *)body title:(NSString *)title delegate:(id)owner format:(NSInteger)format labels:(NSString *)labels {
    if ((self = [super init])) { contentString = [body mutableCopy]; titleString = [title copy]; labelString = [labels copy]; }
    return self;
}
- (NSMutableAttributedString *)contentString { ContentsReads++; return contentString; }
- (void)setContentString:(NSAttributedString *)contents { [contentString setAttributedString:contents]; }
- (void)dealloc { [contentString release]; [titleString release]; [labelString release]; [super dealloc]; }
@end
@implementation FastListDataSource
- (void)fillArrayFromArray:(NSArray *)array {
    count = [array count]; objects = realloc(objects, count * sizeof(id)); [array getObjects:objects range:NSMakeRange(0, count)];
}
- (NSUInteger)count { return count; }
- (NSUInteger)indexOfObjectIdenticalTo:(id)object {
    for (NSUInteger i = 0; i < count; i++) if (objects[i] == object) return i;
    return NSNotFound;
}
- (void)dealloc { free(objects); [super dealloc]; }
@end
@interface TestLibrary : NSObject { NSMutableArray *notes; }
- (id)initWithNotes:(NSArray *)values;
- (NSArray *)allNotes;
- (void)addNote:(NoteObject *)note;
- (void)removeNote:(NoteObject *)note;
@end
@implementation TestLibrary
- (id)initWithNotes:(NSArray *)values { if ((self = [super init])) notes = [values mutableCopy]; return self; }
- (NSArray *)allNotes { LibraryReads++; return [[notes copy] autorelease]; }
- (void)addNote:(NoteObject *)note { [notes addObject:note]; }
- (void)removeNote:(NoteObject *)note { [notes removeObjectIdenticalTo:note]; }
- (void)dealloc { [notes release]; [super dealloc]; }
@end
@interface TestOwner : NSObject { @public NoteObject *selected; BOOL allowsChange; }
@end
@implementation TestOwner
- (id)init { if ((self = [super init])) allowsChange = YES; return self; }
- (NoteObject *)selectedNoteObject { return selected; }
- (BOOL)notationListShouldChange:(id)session { return allowsChange; }
- (void)notationListMightChange:(id)session { }
- (void)notationListDidChange:(id)session { }
@end
typedef NSInteger (*CompareNotes)(id *, id *);
static NSInteger Ascending(id *a, id *b) { Comparisons++; return [((NoteObject *)*a)->titleString compare:((NoteObject *)*b)->titleString]; }
static NSInteger Descending(id *a, id *b) { return -Ascending(a, b); }
@interface TestColumn : NSObject
- (CompareNotes)sortFunction;
- (CompareNotes)reverseSortFunction;
@end
@implementation TestColumn
- (CompareNotes)sortFunction { return Ascending; }
- (CompareNotes)reverseSortFunction { return Descending; }
@end
static NoteObject *Note(NSString *title, NSString *body) {
    return [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
        title:title delegate:nil format:0 labels:@""] autorelease];
}
static NSArray *Visible(NVBrowserSession *session) {
    NSMutableArray *notes = [NSMutableArray array];
    for (NSUInteger i = 0; i < [[session notesListDataSource] count]; i++) [notes addObject:[session noteObjectAtFilteredIndex:i]];
    return notes;
}
int main(void) {
    @autoreleasepool {
        NoteObject *a = Note(@"A", @"alpha beta"), *b = Note(@"B", @"beta alpha");
        NoteObject *c = Note(@"C", @"gamma"), *d = Note(@"D", @"alpine café");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[a, b, c, d]] autorelease];
        NVBrowserSession *first = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        NVBrowserSession *second = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];

        [first filterNotesFromString:@"absent"];
        Check([Visible(first) count] == 0, "fixture starts with zero results");
        ContentsReads = LibraryReads = 0;
        [first filterNotesFromString:@"absentx"];
        Check(ContentsReads == 0, "zero-result refinement reads no note contents");
        Check(LibraryReads == 0, "zero-result refinement does not copy the library");

        [first filterNotesFromString:@"al"];
        [second filterNotesFromString:@"be"];
        ContentsReads = LibraryReads = 0;
        [first filterNotesFromString:@"alp"];
        Check(ContentsReads == 3 && LibraryReads == 0, "refinement visits only three previous candidates");
        Check([Visible(first) isEqualToArray:@[a, b, d]], "first browser refines its own matches");
        Check([Visible(second) isEqualToArray:@[a, b]], "second browser retains its own matches");

        [first filterNotesFromString:@"\"alpha beta\""];
        Check([Visible(first) isEqualToArray:@[a]], "quoted phrase matches only adjacent terms");
        [first filterNotesFromString:@"alpha beta"];
        Check([Visible(first) isEqualToArray:@[a, b]], "removing quotes restores broader matches");
        [first filterNotesFromString:@"ALPHA:BETA"];
        Check([Visible(first) isEqualToArray:@[a, b]], "case and separator changes preserve matches");
        [first filterNotesFromString:@"\"alpha:beta\""];
        Check([Visible(first) count] == 0, "quoted colon is literal");
        [first filterNotesFromString:@"alpha:beta"];
        Check([Visible(first) isEqualToArray:@[a, b]], "unquoting colon broadens an empty result");

        TestColumn *column = [[[TestColumn alloc] init] autorelease];
        [first setSortColumn:(id)column reversed:YES];
        Comparisons = 0;
        [first filterNotesFromString:@"ALPHA:BETA"];
        Check(Comparisons == 0, "unchanged matches are not sorted again");
        Check([Visible(first) isEqualToArray:@[b, a]], "refinement preserves reverse sort order");
        [first setSortColumn:nil reversed:NO];

        NSArray *queries = @[@"al", @"alpha", @"beta", @"ALPHA", @"alpha beta", @"\"alpha beta\"",
            @"\"alpha:beta\"", @"alpha:beta", @"\"alpha beta", @"gamma", @"absent", @"absentx", @"",
            @"\"", @"\"alpha\" beta", @"alpha:\"beta\"", @"CAFÉ", @"cafe\u0301"];
        for (NSString *oldQuery in queries) for (NSString *newQuery in queries) {
            [first filterNotesFromString:oldQuery];
            [first filterNotesFromString:newQuery];
            NVBrowserSession *fresh = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
            [fresh filterNotesFromString:newQuery];
            Check([Visible(first) isEqualToArray:Visible(fresh)], "incremental query transition agrees with a fresh search");
        }

        [first filterNotesFromString:@"absent"];
        [c setContentString:[[[NSAttributedString alloc] initWithString:@"absentxyz"] autorelease]];
        [first libraryDidChange];
        [first filterNotesFromString:@"absentx"];
        Check([Visible(first) isEqualToArray:@[c]], "edited note enters the invalidated candidate set");
        NoteObject *added = Note(@"E", @"absentxyz");
        [library addNote:added];
        [first libraryDidChange]; [second libraryDidChange];
        Check([Visible(first) isEqualToArray:@[c, added]], "added note enters existing search results");
        [library removeNote:c];
        [first libraryDidChange]; [second libraryDidChange];
        [first filterNotesFromString:@"absentxy"];
        Check([Visible(first) isEqualToArray:@[added]], "deleted note leaves candidates before refinement");
        Check([Visible(second) isEqualToArray:@[a, b]], "library invalidation preserves another browser query");

        TestOwner *owner = [[[TestOwner alloc] init] autorelease];
        [first setDelegate:owner];
        [first filterNotesFromString:@"missing"];
        owner->selected = a;
        [first libraryDidChange];
        Check([Visible(first) isEqualToArray:@[a]], "library refresh preserves the selected editor row");
        ContentsReads = LibraryReads = 0;
        [first filterNotesFromString:@"missingmore"];
        Check(ContentsReads == 0 && LibraryReads == 0, "pinned row is excluded from refinement candidates");
        Check([Visible(first) count] == 0, "explicit search removes a nonmatching pinned row");
        [first libraryDidChange];
        [library removeNote:a];
        [first libraryDidChange];
        Check([Visible(first) count] == 0, "deletion removes a pinned row too");

        owner->selected = nil;
        owner->allowsChange = NO;
        NoteObject *deferred = Note(@"F", @"missingmorexyz");
        [library addNote:deferred];
        [first libraryDidChange];
        [first filterNotesFromString:@"missingmorex"];
        Check([Visible(first) isEqualToArray:@[deferred]], "deferred UI refresh invalidates candidates immediately");
        [NSObject cancelPreviousPerformRequestsWithTarget:first];
        owner->allowsChange = YES;
        ContentsReads = LibraryReads = 0;
        [first filterNotesFromUTF8String:"missingmorex" forceUncached:YES];
        Check(LibraryReads == 1 && ContentsReads == 4, "forceUncached explicitly refreshes the library snapshot");
        [first setDelegate:nil];
        printf("SEARCH REGRESSIONS PASSED (%lu checks)\n", (unsigned long)Checks);
    }
    return 0;
}
