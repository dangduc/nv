#import <Cocoa/Cocoa.h>
#import "BookmarksController.h"
#import "SavedSearchesController.h"
#include <stdio.h>
#include <string.h>

static NSUInteger checks;
#define CHECK(condition, message) do { checks++; if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } } while (0)
@protocol LogNote
- (CFUUIDBytes *)uniqueNoteIDBytes;
@end
@interface NoteObject : NSObject <LogNote> { CFUUIDBytes bytes; }
@end
@implementation NoteObject
- (id)init { if ((self = [super init])) bytes.byte0 = 1; return self; }
- (CFUUIDBytes *)uniqueNoteIDBytes { return &bytes; }
@end
static NSString *titleOfNote(NoteObject *note) { return @"Sample"; }
@interface NSString (TestUUID)
- (CFUUIDBytes)uuidBytes;
+ (NSString *)uuidStringWithBytes:(CFUUIDBytes)bytes;
@end
@implementation NSString (TestUUID)
- (CFUUIDBytes)uuidBytes {
    CFUUIDRef uuid = CFUUIDCreateFromString(kCFAllocatorDefault, (CFStringRef)self);
    CFUUIDBytes result = {0};
    if (uuid) { result = CFUUIDGetUUIDBytes(uuid); CFRelease(uuid); }
    return result;
}
+ (NSString *)uuidStringWithBytes:(CFUUIDBytes)bytes {
    CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, bytes);
    NSString *result = [(NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
    CFRelease(uuid); return result;
}
@end
@interface TestDefaults : NSObject { NSMutableDictionary *values; }
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (void)setDouble:(double)value forKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
@end
@implementation TestDefaults
- (id)init { if ((self=[super init])) values=[NSMutableDictionary new]; return self; }
- (void)dealloc { [values release]; [super dealloc]; }
- (id)objectForKey:(NSString *)key { return values[key]; }
- (void)setObject:(id)object forKey:(NSString *)key { values[key]=object; }
- (void)removeObjectForKey:(NSString *)key { [values removeObjectForKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { values[key]=@(value); }
- (double)doubleForKey:(NSString *)key { return [values[key] doubleValue]; }
@end
@interface FastListDataSource : NSObject
- (NSUInteger)indexOfObjectIdenticalTo:(id)note;
@end
@implementation FastListDataSource
- (NSUInteger)indexOfObjectIdenticalTo:(id)note { return note ? 0 : NSNotFound; }
@end
@interface NotesTableView : NSObject { @public NSInteger row; FastListDataSource *source; }
- (NSInteger)selectedRow;
- (id)dataSource;
- (double)distanceFromRow:(NSUInteger)index forVisibleArea:(NSRect)rect;
- (NSRect)visibleRect;
@end
@implementation NotesTableView
- (id)init { if ((self=[super init])) { row=1; source=[FastListDataSource new]; } return self; }
- (void)dealloc { [source release]; [super dealloc]; }
- (NSInteger)selectedRow { return row; }
- (id)dataSource { return source; }
- (double)distanceFromRow:(NSUInteger)index forVisibleArea:(NSRect)rect { return index * 100.0; }
- (NSRect)visibleRect { return NSMakeRect(0,0,100,100); }
@end
@interface TestController : NSObject { @public NoteBookmark *restored; NSString *mode, *rowKey; }
- (NSString *)searchMode;
- (NSString *)selectedSearchResultRowKey;
@end
@implementation TestController
- (NSString *)searchMode { return mode; }
- (NSString *)selectedSearchResultRowKey { return rowKey; }
- (void)bookmarksController:(BookmarksController *)controller restoreNoteBookmark:(NoteBookmark *)bookmark inBackground:(BOOL)background {
    CHECK(background, "followed-link restoration remains nonactivating");
    [restored release]; restored=[bookmark retain];
}
- (void)dealloc { [restored release]; [super dealloc]; }
@end
@interface GlobalPrefs : NSObject { @public TestDefaults *defaults; }
- (void)setLastSearchString:(NSString *)string selectedNote:(id<LogNote>)note scrollOffsetForTableView:(NotesTableView *)table sender:(id)sender;
- (NSString *)lastSearchString;
- (NSString *)lastSearchMode;
- (NSString *)lastSearchResultRowKey;
- (CFUUIDBytes)UUIDBytesOfLastSelectedNote;
- (double)scrollOffsetOfLastSelectedNote;
@end
static NSString *LastSearchStringKey=@"LastSearchString", *LastSearchModeKey=@"LastSearchMode", *LastSearchResultRowKey=@"LastSearchResultRowKey";
static NSString *LastSelectedNoteUUIDBytesKey=@"LastSelectedNoteUUIDBytes", *LastScrollOffsetKey=@"LastScrollOffset";
#define SEND_CALLBACKS() ((void)0)
@interface TestDualField : NSObject { @public NSMutableArray *followedLinks; TestController *controller; }
- (BOOL)hasFollowedLinks;
- (void)clearFollowedLinks;
- (void)pushFollowedLink:(NoteBookmark *)bookmark;
- (NoteBookmark *)popLastFollowedLink;
@end
#define NVControllerForView(view) controller
#include "production.inc"

int main(void) {
    @autoreleasepool {
        NSString *uuid=@"01000000-0000-0000-0000-000000000000";
        NoteObject *note=[NoteObject new];
        NSDictionary *legacy=@{@"SearchString":@"Road",@"NoteUUIDString":uuid};
        NoteBookmark *old=[[[NoteBookmark alloc] initWithDictionary:legacy] autorelease];
        CHECK([[old searchMode] isEqual:@"exact"] && ![old resultRowKey], "legacy bookmark decodes Exact without occurrence");
        NoteBookmark *title=[[[NoteBookmark alloc] initWithNoteObject:note searchString:@"Road" searchMode:@"fuzzy" resultRowKey:@"title:01000000-0000-0000-0000-000000000000"] autorelease];
        NoteBookmark *fuzzy=[[[NoteBookmark alloc] initWithNoteObject:note searchString:@"Road" searchMode:@"fuzzy" resultRowKey:@"fuzzy:01000000-0000-0000-0000-000000000000"] autorelease];
        NoteBookmark *round=[[[NoteBookmark alloc] initWithDictionary:[fuzzy dictionaryRep]] autorelease];
        CHECK([fuzzy isEqual:round] && [fuzzy hash]==[round hash], "bookmark round trip retains mode and occurrence identity");
        CHECK(![title isEqual:fuzzy] && ![old isEqual:title], "same note can have distinct saved occurrences and modes");
        CHECK(![fuzzy isEqual:@"Road"], "bookmark equality accepts unrelated object safely");
        CHECK(([[NSSet setWithObjects:old,title,fuzzy,round,nil] count]==3), "hash set preserves distinct occurrence entries");
        NoteBookmark *noString=[[[NoteBookmark alloc] initWithNoteUUIDBytes:*[note uniqueNoteIDBytes] searchString:nil] autorelease];
        CHECK([[[noString dictionaryRep] objectForKey:@"NoteUUIDString"] isEqual:uuid], "missing query retains note UUID");
        CHECK(![[[NoteBookmark alloc] initWithDictionary:@{@"NoteUUIDString":@3}] autorelease], "malformed bookmark UUID type rejected");
        NoteBookmark *badMode=[[[NoteBookmark alloc] initWithDictionary:@{@"NoteUUIDString":uuid,@"SearchMode":@3,@"ResultRowKey":@3}] autorelease];
        CHECK([[badMode searchMode] isEqual:@"exact"] && ![badMode resultRowKey], "invalid bookmark metadata decodes safely");
        SavedSearch *oldSearch=[[[SavedSearch alloc] initWithDictionary:legacy] autorelease];
        SavedSearch *fuzzySearch=[[[SavedSearch alloc] initWithSearchString:@"ROAD" searchMode:@"fuzzy"] autorelease];
        CHECK([[oldSearch searchMode] isEqual:@"exact"], "legacy saved search decodes Exact");
        CHECK(![oldSearch isEqual:fuzzySearch], "saved searches preserve distinct search modes");
        [fuzzySearch setSelectedNote:note resultRowKey:[fuzzy resultRowKey]];
        SavedSearch *savedRound=[[[SavedSearch alloc] initWithDictionary:[fuzzySearch dictionaryRep]] autorelease];
        CHECK([[savedRound resultRowKey] isEqual:[fuzzy resultRowKey]] && [savedRound isEqual:fuzzySearch], "saved search round trip retains mode and row");
        [fuzzySearch setSelectedNote:[fuzzySearch selectedNote] resultRowKey:[fuzzySearch resultRowKey]];
        CHECK([fuzzySearch selectedNote]==note && [[fuzzySearch resultRowKey] isEqual:[fuzzy resultRowKey]], "reassigning same note and row is ownership safe");
        [fuzzySearch setSelectedNote:nil];
        CHECK(![fuzzySearch resultRowKey], "removing selected note clears occurrence");
        GlobalPrefs *prefs=[GlobalPrefs new]; prefs->defaults=[TestDefaults new];
        TestController *controller=[TestController new]; controller->mode=@"fuzzy"; controller->rowKey=[fuzzy resultRowKey];
        NotesTableView *table=[NotesTableView new];
        CHECK([[prefs lastSearchMode] isEqual:@"exact"] && ![prefs lastSearchResultRowKey], "legacy last-search defaults to Exact");
        [prefs setLastSearchString:@"\"a\nb\"" selectedNote:note scrollOffsetForTableView:table sender:controller];
        CHECK([[prefs lastSearchString] isEqual:@"\"a\nb\""], "persist exact query bytes including phrase newline");
        CHECK([[prefs lastSearchMode] isEqual:@"fuzzy"] && [[prefs lastSearchResultRowKey] isEqual:[fuzzy resultRowKey]], "last search retains fuzzy occurrence");
        CHECK([prefs scrollOffsetOfLastSelectedNote]==100.0, "scroll anchor uses selected duplicate occurrence");
        [prefs setLastSearchString:nil selectedNote:nil scrollOffsetForTableView:table sender:nil];
        CHECK([[prefs lastSearchMode] isEqual:@"exact"] && ![prefs lastSearchResultRowKey], "legacy writer clears newer metadata");
        CHECK(![prefs->defaults objectForKey:LastSelectedNoteUUIDBytesKey], "nil note clears stale UUID");
        CHECK([prefs scrollOffsetOfLastSelectedNote]==0.0, "nil note clears stale scroll anchor");
        [prefs->defaults setObject:@3 forKey:LastSearchModeKey];
        [prefs->defaults setObject:@3 forKey:LastSearchResultRowKey];
        CHECK([[prefs lastSearchMode] isEqual:@"exact"] && ![prefs lastSearchResultRowKey], "invalid preferences metadata decodes safely");
        TestDualField *field=[TestDualField new]; field->followedLinks=[NSMutableArray new]; field->controller=controller;
        [field pushFollowedLink:title]; [field pushFollowedLink:fuzzy];
        CHECK([field popLastFollowedLink]==fuzzy && controller->restored==fuzzy, "followed link forwards saved row and mode through async restore hook");
        CHECK([field hasFollowedLinks] && [field popLastFollowedLink]==title && ![field hasFollowedLinks], "snapback stack preserves occurrence order");
        CHECK(![field popLastFollowedLink], "empty snapback does not restore stale bookmark");
        [field->followedLinks release]; [field release];
        [prefs->defaults release]; [prefs release]; [controller release]; [table release]; [note release];
        printf("PASS: %lu persistence checks. Actual model/defaults/snapback methods, in-memory fixtures.\n", (unsigned long)checks);
    }
    return 0;
}
