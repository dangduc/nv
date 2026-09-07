#define main ExistingSearchRegressionMain
#include "../../../Regression/search/search_regression.m"
#undef main

static NSUInteger PreviewBuilds, NoteDeaths, SessionDeaths, OwnerDeaths, LibraryDeaths;
@interface GlobalPrefs (PreviewProbe)
- (BOOL)tableColumnsShowPreview;
@end
@implementation GlobalPrefs (PreviewProbe)
- (BOOL)tableColumnsShowPreview { return NO; }
@end
@interface NSString (PreviewProbe)
- (NSAttributedString *)attributedSingleLineTitle;
@end
@implementation NSString (PreviewProbe)
- (NSAttributedString *)attributedSingleLineTitle {
    PreviewBuilds++;
    return [[[NSAttributedString alloc] initWithString:self] autorelease];
}
@end
@interface PreviewColumn : NSObject { @public CGFloat width; }
@end
@implementation PreviewColumn
- (CGFloat)width { return width; }
@end
@interface PreviewTable : NSObject { PreviewColumn *column; }
- (id)initWithWidth:(CGFloat)width;
@end
@implementation PreviewTable
- (id)initWithWidth:(CGFloat)value { if ((self = [super init])) { column = [PreviewColumn new]; column->width = value; } return self; }
- (id)tableColumnWithIdentifier:(id)identifier { return column; }
- (void)dealloc { [column release]; [super dealloc]; }
@end
@interface LifetimeOwner : TestOwner @end
@implementation LifetimeOwner
- (BOOL)horizontalLayout { return YES; }
- (void)dealloc { OwnerDeaths++; [super dealloc]; }
@end
@interface LifetimeNote : NoteObject @end
@implementation LifetimeNote
- (void)dealloc { NoteDeaths++; [super dealloc]; }
@end
@interface LifetimeLibrary : TestLibrary @end
@implementation LifetimeLibrary
- (void)dealloc { LibraryDeaths++; [super dealloc]; }
@end
@interface LifetimeSession : NVBrowserSession @end
@implementation LifetimeSession
- (void)dealloc { SessionDeaths++; [super dealloc]; }
@end

static void PreviewCaches(void) {
    @autoreleasepool {
        NSMutableArray *notes = [NSMutableArray array];
        for (NSUInteger i = 0; i < 64; i++) [notes addObject:Note([NSString stringWithFormat:@"Note%03lu", (unsigned long)i], @"body")];
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:notes] autorelease];
        NVBrowserSession *first = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        NVBrowserSession *second = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        LifetimeOwner *owner = [[[LifetimeOwner alloc] init] autorelease];
        [first setDelegate:owner]; [second setDelegate:owner];
        PreviewTable *left = [[[PreviewTable alloc] initWithWidth:240] autorelease];
        PreviewTable *right = [[[PreviewTable alloc] initWithWidth:640] autorelease];
        for (NSUInteger pass = 0; pass < 10; pass++) for (NoteObject *note in notes) {
            [first previewForNote:note inTable:(id)left]; [second previewForNote:note inTable:(id)right];
        }
        Check(PreviewBuilds == 128, "1280 preview requests build only 128 distinct window previews");
        id rightPreview = [second previewForNote:[notes firstObject] inTable:(id)right];
        for (NSUInteger resize = 0; resize < 100; resize++) {
            ((PreviewColumn *)[left tableColumnWithIdentifier:nil])->width += 1;
            [first regeneratePreviewsForColumn:(id)[left tableColumnWithIdentifier:nil]
                visibleFilteredRows:NSMakeRange(0, 64) forceUpdate:NO];
            for (NoteObject *note in notes) [first previewForNote:note inTable:(id)left];
            Check([[first valueForKey:@"previewCache"] count] == 64, "resize invalidation bounds the first preview cache");
            Check([second previewForNote:[notes firstObject] inTable:(id)right] == rightPreview, "first window resize preserves second window cached object");
        }
        Check(PreviewBuilds == 6528, "each resize rebuilds only the resized browser's 64 previews");
        NoteObject *renamed = [notes firstObject];
        [renamed->titleString release]; renamed->titleString = [@"Renamed" copy];
        [first libraryDidChange]; [second libraryDidChange];
        Check([[first valueForKey:@"previewCache"] count] == 0 && [[second valueForKey:@"previewCache"] count] == 0,
            "library invalidation removes both browsers' stale previews");
        Check([[[first previewForNote:renamed inTable:(id)left] string] isEqualToString:@"Renamed"] &&
            [[[second previewForNote:renamed inTable:(id)right] string] isEqualToString:@"Renamed"],
            "both rebuilt previews contain the new title");
        [first filterNotesFromString:@"absent123"];
        ContentsReads = LibraryReads = 0;
        [first filterNotesFromString:@"absent1234"];
        Check(ContentsReads == 0 && LibraryReads == 0, "preview invalidation does not regress empty search refinement");
        printf("PREVIEW CHECKS PASSED: requests=1280 initial_builds=128 resizes=100 total_builds=%lu cache_entries_per_window=64\n",
            (unsigned long)PreviewBuilds);
        [first setDelegate:nil]; [second setDelegate:nil];
    }
}
static void DeferredTeardown(void) {
    NoteDeaths = SessionDeaths = OwnerDeaths = LibraryDeaths = 0;
    NSAutoreleasePool *phase = [NSAutoreleasePool new];
    NSMutableArray *notes = [NSMutableArray array];
    for (NSUInteger i = 0; i < 64; i++) {
        NoteObject *note = [[[LifetimeNote alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"body"] autorelease]
            title:[NSString stringWithFormat:@"Lifetime%03lu", (unsigned long)i] delegate:nil format:0 labels:@""] autorelease];
        [notes addObject:note];
    }
    LifetimeLibrary *library = [[LifetimeLibrary alloc] initWithNotes:notes];
    for (NSUInteger i = 0; i < 64; i++) {
        LifetimeSession *session = [[LifetimeSession alloc] initWithLibrary:(id)library];
        LifetimeOwner *owner = [LifetimeOwner new]; owner->allowsChange = NO;
        [session setDelegate:owner];
        [session filterNotesFromString:@"body"];
        [session libraryDidChange]; // Queue the real production deferred refresh.
        // Match AppController teardown: clear its borrowed delegate before release.
        [session setDelegate:nil];
        [session release]; [owner release];
    }
    [library release];
    [phase drain];
    Check(OwnerDeaths == 64, "closed owners are not retained by deferred browser sessions");
    // The run loop retains queued targets. Pump once to deliver those callbacks;
    // this is a liveness bound, not a performance requirement.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    Check(SessionDeaths == 64, "all deferred browser sessions release after their callback");
    Check(NoteDeaths == 64 && LibraryDeaths == 1, "the last deferred session releases its library and candidate notes");
    printf("DEFERRED TEARDOWN PASSED: owners=%lu sessions=%lu notes=%lu libraries=%lu\n",
        (unsigned long)OwnerDeaths, (unsigned long)SessionDeaths, (unsigned long)NoteDeaths, (unsigned long)LibraryDeaths);
}
int main(void) {
    @autoreleasepool {
        PreviewCaches(); DeferredTeardown();
        printf("ROUND3 CACHE AND LIFETIME CHECKS PASSED (%lu checks)\n", (unsigned long)Checks);
    }
    return 0;
}
