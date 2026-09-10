#import <Cocoa/Cocoa.h>
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"

// These doubles preserve production NoteObject ivar layout and expose just the
// in-memory APIs called by NVBrowserSession. No filesystem or UI is involved.
NSString *NoteTitleColumnString = @"title";
NSString *NoteDateModifiedColumnString = @"Date Modified";
static NSUInteger ProbeContentsReadCount;
@implementation GlobalPrefs
+ (GlobalPrefs *)defaultPrefs { static GlobalPrefs *prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (BOOL)tableIsReverseSorted { return NO; }
- (BOOL)autoCompleteSearches { return NO; }
@end
@implementation NoteObject
- (id)initWithNoteBody:(NSAttributedString *)body title:(NSString *)title delegate:(id)owner format:(NSInteger)format labels:(NSString *)labels {
    if ((self = [super init])) {
        contentString = [body mutableCopy]; titleString = [title copy]; labelString = [labels copy];
        cTitle = strdup([[title lowercaseString] UTF8String]);
        cContents = strdup([[[body string] lowercaseString] UTF8String]);
        cLabels = strdup([[labels lowercaseString] UTF8String]);
    }
    return self;
}
- (NSMutableAttributedString *)contentString { ProbeContentsReadCount++; return contentString; }
- (void)dealloc { free(cTitle); free(cContents); free(cLabels); [contentString release]; [titleString release]; [labelString release]; [super dealloc]; }
#include "legacy-note-search.inc"
@end
@implementation FastListDataSource
- (void)fillArrayFromArray:(NSArray *)array {
    count = [array count]; objects = realloc(objects, count * sizeof(id)); [array getObjects:objects range:NSMakeRange(0, count)];
}
- (NSUInteger)count { return count; }
- (const id *)immutableObjects { return (const id *)objects; }
- (BOOL)filterArrayUsingFunction:(BOOL (*)(id, void *))present context:(void *)context {
    NSUInteger initial = count, next = 0;
    for (NSUInteger i = 0; i < count; i++) if (present(objects[i], context)) objects[next++] = objects[i];
    count = next;
    return count != initial;
}
- (void)dealloc { free(objects); [super dealloc]; }
@end
@interface ProbeLibrary : NSObject { NSArray *notes; }
- (id)initWithCount:(NSUInteger)count;
- (NSArray *)allNotes;
@end
@implementation ProbeLibrary
- (id)initWithCount:(NSUInteger)count {
    if ((self = [super init])) {
        NSMutableArray *made = [NSMutableArray array];
        for (NSUInteger i = 0; i < count; i++) {
            NSString *title = [NSString stringWithFormat:@"Note %08lu", (unsigned long)((i * 7919) % count)];
            NSString *body = [title stringByPaddingToLength:2048 withString:@"abcdefghijklmnopqrstuvw " startingAtIndex:0];
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
                title:title delegate:nil format:0 labels:@""] autorelease];
            [made addObject:note];
        }
        notes = [made copy];
    }
    return self;
}
- (NSArray *)allNotes { return [[notes copy] autorelease]; }
- (void)dealloc { [notes release]; [super dealloc]; }
@end
char *replaceString(char *oldString, const char *newString) {
    char *replacement = strdup(newString); free(oldString); return replacement;
}
NSMutableArray *prefixParentsOfNote(NoteObject *note) { return note->prefixParentNotes; }
@interface LegacySearch : NSObject {
    NSArray *allNotes;
    FastListDataSource *notesListDataSource;
    GlobalPrefs *prefsController;
    char *currentFilterStr, *manglingString;
    NSUInteger lastWordInFilterStr, selectedNoteIndex;
}
- (id)initWithNotes:(NSArray *)notes;
- (BOOL)filterNotesFromUTF8String:(const char *)string forceUncached:(BOOL)force;
@end
@implementation LegacySearch
- (id)initWithNotes:(NSArray *)notes {
    if ((self = [super init])) {
        allNotes = [notes copy]; notesListDataSource = [[FastListDataSource alloc] init];
        [notesListDataSource fillArrayFromArray:notes]; prefsController = [GlobalPrefs defaultPrefs];
    }
    return self;
}
#include "legacy-controller-search.inc"
- (void)dealloc { [allNotes release]; [notesListDataSource release]; free(currentFilterStr); free(manglingString); [super dealloc]; }
@end
static void Run(NSUInteger count) {
    @autoreleasepool {
        ProbeLibrary *library = [[[ProbeLibrary alloc] initWithCount:count] autorelease];
        LegacySearch *legacy = [[[LegacySearch alloc] initWithNotes:[library allNotes]] autorelease];
        [legacy filterNotesFromUTF8String:"absent" forceUncached:NO];
        CFAbsoluteTime legacyStart = CFAbsoluteTimeGetCurrent();
        [legacy filterNotesFromUTF8String:"absentx" forceUncached:NO];
        printf("notes=%lu legacy_extending_zero_results_ms=%.6f\n", (unsigned long)count, (CFAbsoluteTimeGetCurrent() - legacyStart) * 1000);
        NVBrowserSession *session = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        for (NSString *query in @[@"absent", @"absentx", @"Note", @""]) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            for (NSUInteger i = 0; i < 5; i++) @autoreleasepool { [session filterNotesFromString:query]; }
            printf("notes=%lu bytes_per_note=2048 query='%s' matches=%lu mean_ms=%.3f\n", (unsigned long)count,
                [query UTF8String], (unsigned long)[[session notesListDataSource] count], (CFAbsoluteTimeGetCurrent() - start) * 200);
        }
        [session filterNotesFromString:@"absent"];
        ProbeContentsReadCount = 0;
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        [session filterNotesFromString:@"absentx"];
        printf("notes=%lu extending_zero_results_ms=%.3f note_contents_read=%lu\n", (unsigned long)count,
            (CFAbsoluteTimeGetCurrent() - start) * 1000, (unsigned long)ProbeContentsReadCount);
        [session filterNotesFromString:@""];
        start = CFAbsoluteTimeGetCurrent();
        for (NSUInteger i = 0; i < 3; i++) [session libraryDidChange];
        printf("notes=%lu three_unfiltered_windows_refresh_ms=%.3f\n", (unsigned long)count, (CFAbsoluteTimeGetCurrent() - start) * 1000);
        NVBrowserSession *second = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        [session filterNotesFromString:@"0000004"];
        [second filterNotesFromString:@"absent"];
        [session filterNotesFromString:@"00000042"];
        NSCAssert([[session notesListDataSource] count] == 1, @"first session retains its incremental result");
        NSCAssert([[second notesListDataSource] count] == 0, @"second session remains independent");
        puts("interleaved_search_independence=pass");
    }
}
int main(void) { Run(1000); Run(10000); Run(25000); return 0; }
