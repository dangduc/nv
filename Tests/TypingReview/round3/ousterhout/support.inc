#import <Cocoa/Cocoa.h>
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NVSearchService.h"

// The production session and native search service are compiled in full.
// These in-memory model doubles never open a library or desktop window.
NSString *NoteTitleColumnString = @"title";
NSString *NoteDateModifiedColumnString = @"Date Modified";
static NSUInteger Checks;
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    Checks++; printf("PASS: %s\n", message);
}
static void Pump(NSTimeInterval seconds) {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && deadline.timeIntervalSinceNow > 0) Pump(.005);
    return condition();
}
@implementation GlobalPrefs
+ (GlobalPrefs *)defaultPrefs { static GlobalPrefs *prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (BOOL)tableIsReverseSorted { return NO; }
- (BOOL)tableColumnsShowPreview { return YES; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)autoCompleteSearches { return NO; }
- (BOOL)showWordCount { return NO; }
- (id)bookmarksController { return nil; }
@end
@implementation NoteObject
- (id)initWithNoteBody:(NSAttributedString *)body title:(NSString *)title delegate:(id)owner format:(NSInteger)format labels:(NSString *)labels {
    if ((self = [super init])) {
        contentString = [body mutableCopy]; titleString = [title copy]; labelString = [labels copy];
        static unsigned char serial; memset(&uniqueNoteIDBytes, 0, sizeof(uniqueNoteIDBytes));
        ((unsigned char *)&uniqueNoteIDBytes)[15] = ++serial;
    }
    return self;
}
- (CFUUIDBytes *)uniqueNoteIDBytes { return &uniqueNoteIDBytes; }
- (NSMutableAttributedString *)contentString { return contentString; }
- (void)setContentString:(NSAttributedString *)contents { [contentString setAttributedString:contents]; }
- (void)dealloc { [contentString release]; [titleString release]; [labelString release]; [super dealloc]; }
@end
@implementation FastListDataSource
- (void)fillArrayFromArray:(NSArray *)array {
    count = array.count; objects = realloc(objects, count * sizeof(id)); [array getObjects:objects range:NSMakeRange(0, count)];
}
- (NSUInteger)count { return count; }
- (NSUInteger)indexOfObjectIdenticalTo:(id)object { for (NSUInteger i = 0; i < count; i++) if (objects[i] == object) return i; return NSNotFound; }
- (void)dealloc { free(objects); [super dealloc]; }
@end
@interface MemoryLibrary : NSObject { @public NSMutableArray *notes; }
@end
@implementation MemoryLibrary
- (id)init { if ((self = [super init])) notes = [[NSMutableArray alloc] init]; return self; }
- (NSArray *)allNotes { return [[notes copy] autorelease]; }
- (void)dealloc { [notes release]; [super dealloc]; }
@end
@interface Owner : NSObject { @public BOOL allowsChange; NSUInteger publications, redraws, completions; NoteObject *selected; NSMutableArray *rows; }
@end
@implementation Owner
- (id)init { if ((self = [super init])) { allowsChange = YES; rows = [[NSMutableArray alloc] init]; } return self; }
- (NoteObject *)selectedNoteObject { return selected; }
- (BOOL)notationListShouldChange:(id)session { return allowsChange; }
- (void)notationListMightChange:(id)session {}
- (void)notationListDidChange:(id)session { publications++; }
- (void)rowShouldUpdate:(NSInteger)row { redraws++; [rows addObject:@(row)]; }
- (void)browserSessionSearchStateDidChange:(id)session {}
- (void)browserSessionSearchDidComplete:(id)session { completions++; }
- (BOOL)horizontalLayout { return NO; }
- (void)dealloc { [rows release]; [super dealloc]; }
@end
typedef NSInteger (*CompareNotes)(id *, id *);
static NSInteger ByDate(id *a, id *b) {
    CFAbsoluteTime x = ((NoteObject *)*a)->modifiedDate, y = ((NoteObject *)*b)->modifiedDate;
    return x < y ? -1 : x > y ? 1 : 0;
}
static NSInteger ByDateReverse(id *a, id *b) { return -ByDate(a, b); }
@interface DateColumn : NSObject
@end
@implementation DateColumn
- (NSString *)identifier { return NoteDateModifiedColumnString; }
- (CompareNotes)sortFunction { return ByDate; }
- (CompareNotes)reverseSortFunction { return ByDateReverse; }
@end
static NoteObject *Note(NSString *title) {
    return [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"seed"] autorelease]
        title:title delegate:nil format:0 labels:@""] autorelease];
}
static NSArray *Visible(NVBrowserSession *session) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger row = 0; row < [[session notesListDataSource] count]; row++) [result addObject:[session noteObjectAtFilteredIndex:row]];
    return result;
}
static BOOL Dirty(NVBrowserSession *session) { return [[session valueForKey:@"bodyRefreshScheduled"] boolValue]; }
static NSUInteger DirtyCount(NVBrowserSession *session) { return [[session valueForKey:@"dirtyBodyUUIDs"] count]; }
static NSData *UUID(NoteObject *note) { return [NSData dataWithBytes:[note uniqueNoteIDBytes] length:16]; }
static void Snapshot(NVSearchService *service, NoteObject *note) {
    [service updateSnapshot:[[[NVSearchNoteSnapshot alloc] initWithNoteUUID:UUID(note) title:note->titleString
        tags:note->labelString source:note.contentString.string revision:1] autorelease]];
}
static void Body(NVBrowserSession *session, NVSearchService *service, NoteObject *note, NSString *source) {
    [note setContentString:[[[NSAttributedString alloc] initWithString:source] autorelease]];
    if (service) Snapshot(service, note);
    [session noteBodyDidChange:note];
}
