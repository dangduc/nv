#import <Cocoa/Cocoa.h>
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NVSearchService.h"
#import "TagEditingManager.h"
#import "BookmarksController.h"
#import "AppController.h"
#define SYNTHETIC_TAGS_COLUMN_INDEX 200
#define DOWNCHAR(x) ((x) == NSDownArrowFunctionKey || (x) == NSDownTextMovement)
#define UPCHAR(x) ((x) == NSUpArrowFunctionKey || (x) == NSUpTextMovement)
NSString *NoteLabelsColumnString = @"labels";
NSString *titleOfNote(NoteObject *note) { return note->titleString; }
@interface NSEvent (ProbeCharacter)
- (unichar)firstCharacter;
@end
@implementation NSEvent (ProbeCharacter)
- (unichar)firstCharacter { return [[self characters] length] ? [[self characters] characterAtIndex:0] : 0; }
@end

// In-memory doubles preserve the model's ivar layout. Only browser-session code
// is under test; the executable never opens a notes directory or app window.
NSString *NoteTitleColumnString = @"title";
static NSUInteger ContentsReads, LibraryReads, Comparisons, Checks;
static BOOL Autocomplete;
static NSUInteger LabelWrites, ClosedTagEditors;
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    Checks++;
}
@implementation GlobalPrefs
+ (GlobalPrefs *)defaultPrefs { static GlobalPrefs *prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (BOOL)tableIsReverseSorted { return NO; }
- (BOOL)tableColumnsShowPreview { return YES; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)autoCompleteSearches { return Autocomplete; }
@end
@implementation NoteObject
- (id)initWithNoteBody:(NSAttributedString *)body title:(NSString *)title delegate:(id)owner format:(NSInteger)format labels:(NSString *)labels {
    if ((self = [super init])) { contentString = [body mutableCopy]; titleString = [title copy]; labelString = [labels copy]; static unsigned char serial; memset(&uniqueNoteIDBytes, 0, sizeof(uniqueNoteIDBytes)); ((unsigned char *)&uniqueNoteIDBytes)[15] = ++serial; }
    return self;
}
- (CFUUIDBytes *)uniqueNoteIDBytes { return &uniqueNoteIDBytes; }
- (NSMutableAttributedString *)contentString { ContentsReads++; return contentString; }
- (void)setContentString:(NSAttributedString *)contents { [contentString setAttributedString:contents]; }
- (void)setTitleString:(NSString *)title { [titleString release]; titleString = [title copy]; }
- (void)setLabelString:(NSString *)labels { [labelString release]; labelString = [labels copy]; LabelWrites++; }
- (void)dealloc { [contentString release]; [titleString release]; [labelString release]; [super dealloc]; }
@end
@implementation FastListDataSource
- (void)fillArrayFromArray:(NSArray *)array {
    count = [array count]; objects = realloc(objects, count * sizeof(id)); [array getObjects:objects range:NSMakeRange(0, count)];
}
- (NSUInteger)count { return count; }
- (const id *)immutableObjects { return (const id *)objects; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return count; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return ((NoteObject *)objects[row])->titleString; }
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row { [(NoteObject *)objects[row] setTitleString:value]; }
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
- (void)removeNotes:(NSArray *)values;
- (NoteObject *)noteForUUIDBytes:(CFUUIDBytes *)bytes;
@end
@implementation TestLibrary
- (id)initWithNotes:(NSArray *)values { if ((self = [super init])) notes = [values mutableCopy]; return self; }
- (NSArray *)allNotes { LibraryReads++; return [[notes copy] autorelease]; }
- (void)addNote:(NoteObject *)note { [notes addObject:note]; }
- (void)removeNote:(NoteObject *)note { [notes removeObjectIdenticalTo:note]; }
- (NoteObject *)noteForUUIDBytes:(CFUUIDBytes *)bytes { for (NoteObject *note in notes) if (!memcmp([note uniqueNoteIDBytes], bytes, sizeof(*bytes))) return note; return nil; }
- (void)removeNotes:(NSArray *)values { for (NoteObject *note in values) [notes removeObjectIdenticalTo:note]; }
- (void)dealloc { [notes release]; [super dealloc]; }
@end
@interface TestOwner : NSObject { @public NoteObject *selected; BOOL allowsChange; NSUInteger completions, stateChanges; BOOL invalidateDuringPublication; }
@end
@implementation TestOwner
- (id)init { if ((self = [super init])) allowsChange = YES; return self; }
- (NoteObject *)selectedNoteObject { return selected; }
- (BOOL)notationListShouldChange:(id)session { return allowsChange; }
- (void)notationListMightChange:(id)session { if (invalidateDuringPublication) { invalidateDuringPublication = NO; [session invalidateSearch]; } }
- (void)notationListDidChange:(id)session { }
- (void)browserSessionSearchDidComplete:(id)session { completions++; }
- (void)browserSessionSearchStateDidChange:(id)session { stateChanges++; }
- (BOOL)horizontalLayout { return NO; }
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
// Capture the production excerpt builder's input without initializing a desktop.
@interface NSString (TestPreviewFormatting)
- (id)attributedSingleLineTitle;
- (id)attributedSingleLinePreviewFromBodyText:(NSAttributedString *)body upToWidth:(CGFloat)width;
- (id)attributedMultiLinePreviewFromBodyText:(NSAttributedString *)body upToWidth:(CGFloat)width intrusionWidth:(CGFloat)intrusion;
@end
@implementation NSString (TestPreviewFormatting)
- (id)attributedSingleLineTitle { return [[[NSAttributedString alloc] initWithString:self] autorelease]; }
- (id)attributedSingleLinePreviewFromBodyText:(NSAttributedString *)body upToWidth:(CGFloat)width {
    return [[[NSAttributedString alloc] initWithString:[self stringByAppendingFormat:@" | %@", [body string]]] autorelease];
}
- (id)attributedMultiLinePreviewFromBodyText:(NSAttributedString *)body upToWidth:(CGFloat)width intrusionWidth:(CGFloat)intrusion {
    return [self attributedSingleLinePreviewFromBodyText:body upToWidth:width];
}
@end
@interface TestPreviewColumn : NSObject
@end
@implementation TestPreviewColumn
- (CGFloat)width { return 600; }
@end
@interface TestTable : NSObject { @public NSRange visibleRows; NSUInteger reloads; NoteObject *inlineTarget; BOOL targetExists; }
@end
@implementation TestTable
- (NoteObject *)noteForInlineEditAtRow:(NSInteger)row inSession:(NVBrowserSession *)session { return targetExists ? inlineTarget : nil; }
- (BOOL)hasInlineEditTarget { return inlineTarget != nil; }
- (SEL)attributeSetterForColumn:(id)column { return @selector(setTitleString:); }
- (NSRect)visibleRect { return NSMakeRect(0, 0, 600, 60); }
- (NSRange)rowsInRect:(NSRect)rect { return visibleRows; }
- (id)tableColumnWithIdentifier:(NSString *)identifier { return [[[TestPreviewColumn alloc] init] autorelease]; }
- (NSInteger)columnWithIdentifier:(NSString *)identifier { return 0; }
- (NSInteger)primarySelectedRow { return -1; }
- (void)scrollRowToVisible:(NSInteger)row { }
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)columns { reloads++; }
@end
// Run the exact production occurrence-selection methods on a native NSTableView.
// The small owner supplies only a browser and records delivered row context.
@interface PrimaryFixtureTable : NSTableView { NSString *primarySelectionRowKey; NSInteger affinity; NSTextField *controlField; NoteObject *inlineEditNote; NVBrowserSession *inlineEditSession; NSInteger inlineEditRow; GlobalPrefs *globalPrefs; BOOL lastEventActivatedTagEdit; }
- (NSInteger)primarySelectedRow;
- (void)setPrimarySelectedRow:(NSInteger)row;
- (void)simulateNativeSelectionRebuild:(NSIndexSet *)indexes;
@end
@interface PrimaryFixtureOwner : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public NVBrowserSession *session; NSString *displayedKey; NSUInteger contextChanges;
}
- (NVBrowserSession *)browserSession;
@end
static id NVControllerForView(NSView *view) { return [(NSTableView *)view delegate]; }
@implementation PrimaryFixtureTable
#include "primary-selection.inc"
- (BOOL)browserHorizontalLayout { return NO; }
- (void)updateTitleDereferencorState { }
- (BOOL)eventIsTagEdit:(id)e forColumn:(NSInteger)c row:(NSInteger)r { return NO; }
- (BOOL)addPermanentTableColumn:(id)c { return NO; }
- (id)noteAttributeColumnForIdentifier:(id)i { return nil; }
- (SEL)attributeSetterForColumn:(id)c { return @selector(setTitleString:); }
- (NSMenu *)defaultNoteCommandsMenuWithTarget:(id)target { return [[[NSMenu alloc] initWithTitle:@"Probe"] autorelease]; }
- (void)simulateNativeSelectionRebuild:(NSIndexSet *)indexes { [super deselectAll:nil]; [super selectRowIndexes:indexes byExtendingSelection:NO]; }
- (void)dealloc { [primarySelectionRowKey release]; [super dealloc]; }
@end
@implementation PrimaryFixtureOwner
- (NVBrowserSession *)browserSession { return session; }
- (void)setIsEditing:(BOOL)value { }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return [[session notesListDataSource] count]; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return [session noteObjectAtFilteredIndex:(NSUInteger)row]->titleString;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [(PrimaryFixtureTable *)[notification object] primarySelectedRow];
    [displayedKey release]; displayedKey = [[session rowKeyAtIndex:(NSUInteger)row] copy]; contextChanges++;
}
- (void)dealloc { [displayedKey release]; [super dealloc]; }
@end
static PrimaryFixtureTable *PrimaryTable(NVBrowserSession *session, PrimaryFixtureOwner **ownerOut) {
    PrimaryFixtureOwner *owner = [[[PrimaryFixtureOwner alloc] init] autorelease]; owner->session = session;
    PrimaryFixtureTable *table = [[[PrimaryFixtureTable alloc] initWithFrame:NSMakeRect(0, 0, 500, 200)] autorelease];
    [table setAllowsMultipleSelection:YES]; [table setDataSource:owner]; [table setDelegate:owner]; [table reloadData];
    if (ownerOut) *ownerOut = owner;
    return table;
}
NSString *labelsOfNote(NoteObject *note) { return note->labelString; }
@interface NSString (TestTagWords)
- (NSArray *)labelCompatibleWords;
@end
@interface NSCharacterSet (TestTagWords)
+ (NSCharacterSet *)labelSeparatorCharacterSet;
@end
@implementation NSString (TestTagWords)
- (NSArray *)labelCompatibleWords {
    return [[self componentsSeparatedByCharactersInSet:[NSCharacterSet labelSeparatorCharacterSet]] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
}
@end
@implementation NSCharacterSet (TestTagWords)
+ (NSCharacterSet *)labelSeparatorCharacterSet { return [NSCharacterSet characterSetWithCharactersInString:@" ,\t\n"]; }
@end
@implementation TagEditingManager
@synthesize commonTags, tagFieldString;
- (void)closeTP:(id)sender { ClosedTagEditors++; }
- (void)dealloc { [commonTags release]; [tagFieldString release]; [super dealloc]; }
@end
@interface TagFixtureController : NSObject {
@public TagEditingManager *tagEditor; NotationController *multiTagLibrary; NSArray *multiTagNoteUUIDs;
    TestLibrary *activeLibrary; NVBrowserSession *session; TestTable *notesTableView;
}
- (void)captureMultiTagNotes:(NSArray *)notes;
- (NSArray *)pendingMultiTagNotes;
- (void)cancelMultiTagEditing;
- (void)multiTag:(id)sender;
- (void)releaseTagEditor:(NSNotification *)notification;
@end
@implementation TagFixtureController
- (NotationController *)sharedNotationController { return (id)activeLibrary; }
- (NVBrowserSession *)browserSession { return session; }
#include "multi-tag.inc"
- (void)dealloc { [self cancelMultiTagEditing]; [super dealloc]; }
@end
static TagEditingManager *TagPanel(NSString *text, NSArray *common) {
    TagEditingManager *manager = [[TagEditingManager alloc] init];
    [manager setTagFieldString:text]; [manager setCommonTags:common]; return manager;
}
static void CheckTagTargetCapture(void) {
    NoteObject *a = Note(@"A", @""), *b = Note(@"B", @""), *c = Note(@"C", @"");
    [a setLabelString:@"shared alpha"]; [b setLabelString:@"shared beta"]; [c setLabelString:@"untouched"];
    TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[a, b, c]] autorelease];
    TagFixtureController *controller = [[[TagFixtureController alloc] init] autorelease]; controller->activeLibrary = library;
    [controller captureMultiTagNotes:@[a, b, a]];
    controller->tagEditor = TagPanel(@"new", @[@"shared"]);
    Check([[controller pendingMultiTagNotes] isEqual:@[a, b]], "tag capture deduplicates original note targets in first-selection order");
    LabelWrites = 0; [controller multiTag:nil];
    Check(LabelWrites == 2 && [a->labelString isEqual:@"alpha new"] && [b->labelString isEqual:@"beta new"] && [c->labelString isEqual:@"untouched"], "tag commit applies once to captured notes without consulting later table selection");
    Check(controller->tagEditor == nil && controller->multiTagLibrary == nil && controller->multiTagNoteUUIDs == nil, "tag commit releases the panel and captured targets");
    [controller captureMultiTagNotes:@[a, b]]; controller->tagEditor = TagPanel(@"survivor", @[]);
    [library removeNote:a]; LabelWrites = 0; [controller multiTag:nil];
    Check(LabelWrites == 1 && [b->labelString containsString:@"survivor"], "deleted captured notes are skipped without retargeting");
    [controller captureMultiTagNotes:@[b, c]]; controller->tagEditor = TagPanel(@"wrong library", @[]);
    controller->activeLibrary = [[[TestLibrary alloc] initWithNotes:@[Note(@"replacement", @"")]] autorelease];
    LabelWrites = 0; [controller multiTag:nil];
    Check(LabelWrites == 0 && controller->tagEditor == nil, "library replacement rejects and clears pending tag targets");
    controller->activeLibrary = library;
    [controller captureMultiTagNotes:@[b, c]]; controller->tagEditor = TagPanel(@"ignored", @[]);
    TagEditingManager *foreign = [TagPanel(@"foreign", @[]) autorelease];
    [controller releaseTagEditor:[NSNotification notificationWithName:@"TagEditorShouldRelease" object:foreign]];
    Check(controller->tagEditor != nil && [[controller pendingMultiTagNotes] count] == 2, "another browser's tag-panel release cannot clear this browser's intent");
    [controller releaseTagEditor:[NSNotification notificationWithName:@"TagEditorShouldRelease" object:controller->tagEditor]];
    Check(controller->tagEditor == nil && controller->multiTagNoteUUIDs == nil, "own panel cancellation clears pointers and targets");
    [controller cancelMultiTagEditing];
    Check(controller->multiTagLibrary == nil, "tag cancellation is idempotent");
}
static BOOL Spin(BOOL (^finished)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!finished() && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    return finished();
}
static NSData *UUID(NoteObject *note) { return [NSData dataWithBytes:[note uniqueNoteIDBytes] length:16]; }
static void Capture(NVSearchService *service, TestLibrary *library) {
    NSMutableArray *snapshots = [NSMutableArray array];
    for (NoteObject *note in [library allNotes]) [snapshots addObject:[[[NVSearchNoteSnapshot alloc]
        initWithNoteUUID:UUID(note) title:note->titleString tags:note->labelString source:[[note contentString] string] revision:1] autorelease]];
    [service synchronizeWithSnapshots:snapshots];
}
static void Search(NVBrowserSession *session, NSString *query) {
    [session filterNotesFromString:query];
    Check(Spin(^BOOL { return ![session searchPending]; }), "browser search reaches terminal state");
    Check([session searchResultsAreCurrent] && ![session searchError], "successful terminal state is current");
}
static NSEvent *Key(unichar code, NSEventModifierFlags flags) {
    NSString *chars = [NSString stringWithCharacters:&code length:1];
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:0];
}
static void Dump(NSString *stage, PrimaryFixtureTable *table, NVBrowserSession *session) {
    fprintf(stdout, "%s indexes=%s native=%ld primary=%ld key=%s edited=%ld\n", [stage UTF8String], [[[table selectedRowIndexes] description] UTF8String], (long)[table selectedRow], (long)[table primarySelectedRow], [[session rowKeyAtIndex:(NSUInteger)[table primarySelectedRow]] UTF8String], (long)[table editedRow]);
}
static void CheckNativeInteractions(void) {
    NoteObject *a = Note(@"road", @"road"), *b = Note(@"road zebra", @"road");
    TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[a, b]] autorelease];
    NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library);
    NVBrowserSession *session = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
    TestOwner *owner = [[[TestOwner alloc] init] autorelease]; [session setDelegate:owner];
    [session setSearchService:service]; [session setSearchMode:@"fuzzy"]; Search(session, @"road");
    PrimaryFixtureOwner *primaryOwner;
    PrimaryFixtureTable *table = PrimaryTable(session, &primaryOwner);
    [table setDataSource:(id)[session notesListDataSource]];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:NoteTitleColumnString] autorelease];
    [column setEditable:YES]; [column setWidth:400]; [table addTableColumn:column]; [table reloadData];
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 500, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    [window setReleasedWhenClosed:NO]; [window setContentView:table]; [window makeFirstResponder:table];
    [table selectRowAndScroll:0]; Dump(@"start", table, session);
    [table keyDown:Key(NSDownArrowFunctionKey, NSEventModifierFlagShift)]; Dump(@"shift-down", table, session);
    [table keyDown:Key(NSDownArrowFunctionKey, NSEventModifierFlagShift)]; Dump(@"shift-down twice", table, session);
    [table keyDown:Key(NSUpArrowFunctionKey, NSEventModifierFlagShift)]; Dump(@"shift-up shrink", table, session);
    NSMutableIndexSet *duplicates = [NSMutableIndexSet indexSetWithIndex:0]; [duplicates addIndex:2];
    [table selectRowIndexes:duplicates byExtendingSelection:NO]; [table setPrimarySelectedRow:2];
    Check([[session notesAtIndexes:[table selectedRowIndexes]] count] == 1, "duplicate selections resolve to one note before Return");
    [table keyDown:Key(NSCarriageReturnCharacter, 0)];
    Check([table editedRow] == 2 && [table currentEditor] != nil, "Return edits the primary fuzzy occurrence when both occurrences are selected");
    [window makeFirstResponder:table];
    [table selectRowIndexes:duplicates byExtendingSelection:NO]; [table setPrimarySelectedRow:2];
    NSPoint rowPoint = [table convertPoint:NSMakePoint(10, NSMidY([table rectOfRow:0])) toView:nil];
    NSEvent *contextEvent = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:rowPoint modifierFlags:0 timestamp:0 windowNumber:[window windowNumber] context:nil eventNumber:1 clickCount:1 pressure:1];
    [table menuForEvent:contextEvent];
    Check([[table selectedRowIndexes] isEqualToIndexSet:duplicates] && [table primarySelectedRow] == 0, "context menu changes primary occurrence while preserving duplicate selection");
    [table selectRowAndScroll:0];
    [table editColumn:0 row:0 withEvent:nil select:YES];
    Check([table currentEditor] != nil, "native table starts inline editor");
    [(NSTextView *)[table currentEditor] setString:@"road modified"];
    [table editColumn:0 row:1 withEvent:nil select:YES];
    fprintf(stdout, "INLINE second edit title0=%s title1=%s editor=%s\n", [a->titleString UTF8String], [b->titleString UTF8String], [[[(NSTextView *)[table currentEditor] string] description] UTF8String]);
#if EXPECT_INLINE_PRESERVED
    Check([a->titleString isEqualToString:@"road modified"], "starting an edit on another row must commit the previous title");
#else
    Check([a->titleString isEqualToString:@"road"], "HEAD regression reproduces: previous inline title discarded by target replacement");
#endif
    [window makeFirstResponder:table];
    [table selectRowAndScroll:0];
    [table editColumn:0 row:0 withEvent:nil select:YES];
    [(NSTextView *)[table currentEditor] setString:@"road tabbed"];
    [(NSTextView *)[table currentEditor] insertTab:nil];
    fprintf(stdout, "INLINE tab title0=%s edited=%ld captured=%d editor=%s\n", [a->titleString UTF8String], (long)[table editedRow], [table hasInlineEditTarget], [[[(NSTextView *)[table currentEditor] string] description] UTF8String]);
    if ([table currentEditor]) {
        [(NSTextView *)[table currentEditor] setString:@"road zebra tabbed"];
        [session invalidateSearch];
        [window makeFirstResponder:table];
        fprintf(stdout, "INLINE tab after invalidation title1=%s\n", [b->titleString UTF8String]);
    }
    [window makeFirstResponder:table];
    [table selectRowAndScroll:0]; [table editColumn:0 row:0 withEvent:nil select:YES];
    [(NSTextView *)[table currentEditor] setString:@"road deleted edit"];
#if !BASELINE_INLINE
    NSString *beforeDeletion = [[a->titleString copy] autorelease]; [library removeNote:a];
    [window makeFirstResponder:table];
    Check([a->titleString isEqual:beforeDeletion], "actual captured inline target rejects commit after library removes note");
    [library addNote:a];
    [table selectRowAndScroll:0]; [table editColumn:0 row:0 withEvent:nil select:YES];
    [(NSTextView *)[table currentEditor] setString:@"road retained capture"];
    [session invalidateSearch]; [window makeFirstResponder:table];
    Check([a->titleString isEqual:@"road retained capture"], "actual captured inline target commits after search invalidation");
    NSIndexSet *pendingSelection = [[[table selectedRowIndexes] copy] autorelease];
    [table selectRowAndScroll:1]; [table keyDown:Key(NSCarriageReturnCharacter, 0)];
    Check([[table selectedRowIndexes] isEqualToIndexSet:pendingSelection] && ![table currentEditor] && [table menuForEvent:contextEvent] == nil, "pending native table blocks selection, Return editing, and context menu");
#endif
    [window makeFirstResponder:table];
    [table setDelegate:nil]; [table setDataSource:nil]; [window orderOut:nil];
    [session setDelegate:nil]; [service invalidate];
}
static NSArray *FuzzyUUIDs(NVBrowserSession *session) {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSUInteger i = 0; i < [Visible(session) count]; i++)
        if ([[session matchKindAtIndex:i] isEqualToString:@"fuzzy"]) [ids addObject:UUID([session noteObjectAtFilteredIndex:i])];
    return ids;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        CheckTagTargetCapture();
        CheckNativeInteractions();
        NoteObject *a = Note(@"qzr Zebra", @"first body"), *b = Note(@"qzr Alpha", @"second body");
        NoteObject *c = Note(@"Body only", @"q----z----r"), *d = Note(@"Empty", @"none");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[a, b, c, d]] autorelease];
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library);
        NVBrowserSession *session = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        TestOwner *owner = [[[TestOwner alloc] init] autorelease]; [session setDelegate:owner];
        [session setSearchService:service]; [session setSearchMode:@"fuzzy"];
        Search(session, @"qzr");
        Check([Visible(session) count] == 5, "both complete groups include overlapping notes");
        Check([session resultCount] == 5 && [session distinctResultNoteCount] == 3, "row and distinct note counts differ");
        Check([session noteObjectAtFilteredIndex:0] == b && [session noteObjectAtFilteredIndex:1] == a, "literal title group appears first in column order");
        Check([[session matchKindAtIndex:0] isEqualToString:@"title"] && [[session matchKindAtIndex:2] isEqualToString:@"fuzzy"], "occurrences carry separate kinds");
        Check([FuzzyUUIDs(session) isEqual:[[session searchResult] fuzzyNoteUUIDs]], "complete fuzzy order equals service order");
        NSArray *nativeOrder = [[FuzzyUUIDs(session) copy] autorelease];
        NSUInteger requestID = [[session searchResult] requestID], generation = [session searchGeneration];
        [session filterNotesFromString:@"qzr"]; [session libraryDidChange];
        Check([[session searchResult] requestID] == requestID && [session searchGeneration] == generation, "equal query and presentation refresh reuse matching identity");
        NSString *titleKey = [[session rowKeyAtIndex:0] copy];
        NSUInteger duplicate = NSNotFound;
        for (NSUInteger i = 2; i < 5; i++) if ([session noteObjectAtFilteredIndex:i] == b) duplicate = i;
        NSString *fuzzyKey = [[session rowKeyAtIndex:duplicate] copy];
        Check(![titleKey isEqualToString:fuzzyKey], "one note has distinct occurrence keys");
        Check([session indexForRowKey:fuzzyKey] == duplicate, "row lookup preserves selected occurrence");
        Check([[session rowKeysAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]] count] == 5, "row selection keeps duplicates");
        Check([[session notesAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]] count] == 3, "bulk note targets deduplicate UUIDs");
        Check([[[session notesListDataSource] objectsAtFilteredIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]] count] == 3, "legacy table bulk projection also deduplicates");
        PrimaryFixtureOwner *primaryOwner;
        PrimaryFixtureTable *primaryTable = PrimaryTable(session, &primaryOwner);
        [primaryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:duplicate] byExtendingSelection:NO];
        [primaryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:YES];
        NSIndexSet *duplicateSelection = [[[primaryTable selectedRowIndexes] copy] autorelease];
        [primaryTable simulateNativeSelectionRebuild:duplicateSelection];
        Check([[primaryTable selectedRowIndexes] isEqualToIndexSet:duplicateSelection], "native selection rebuild preserves duplicate row membership");
        printf("NATIVE PRIMARY EVIDENCE: selectedRow=%ld, occurrencePrimary=%ld\n", (long)[primaryTable selectedRow], (long)[primaryTable primarySelectedRow]);
        Check([[session rowKeyAtIndex:[primaryTable primarySelectedRow]] isEqual:titleKey] && [primaryOwner->displayedKey isEqual:titleKey], "title occurrence remains primary after complete NSIndexSet restoration");
        NSUInteger contextsBefore = primaryOwner->contextChanges;
        [primaryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:duplicate] byExtendingSelection:YES];
        Check([primaryOwner->displayedKey isEqual:fuzzyKey] && primaryOwner->contextChanges > contextsBefore, "adding already-selected fuzzy occurrence changes display context without changing membership");
        [primaryTable selectRowIndexes:duplicateSelection byExtendingSelection:NO];
        Check([[session rowKeyAtIndex:[primaryTable primarySelectedRow]] isEqual:fuzzyKey], "fuzzy occurrence remains primary after complete NSIndexSet restoration");
        NSArray *selectedOccurrenceKeys = [[session rowKeysAtIndexes:duplicateSelection] copy];
        [session setSortColumn:nil reversed:YES];
        Check([session noteObjectAtFilteredIndex:0] == a && [session noteObjectAtFilteredIndex:1] == b, "column reverse changes title group");
        Check([FuzzyUUIDs(session) isEqual:nativeOrder] && [[session searchResult] requestID] == requestID, "column reverse leaves native group and matching identity unchanged");
        Check([session noteObjectAtFilteredIndex:[session indexForRowKey:fuzzyKey]] == b && [[session matchKindAtIndex:[session indexForRowKey:fuzzyKey]] isEqualToString:@"fuzzy"], "occurrence survives column sort");
        [primaryTable reloadData];
        [primaryTable selectRowIndexes:[session indexesForRowKeys:selectedOccurrenceKeys] byExtendingSelection:NO];
        Check([[session rowKeyAtIndex:[primaryTable primarySelectedRow]] isEqual:fuzzyKey], "primary fuzzy key survives title-group reorder");
        Check([[session notesAtIndexes:[primaryTable selectedRowIndexes]] count] == 1, "two selected occurrences still project to one edit target");
        NVBrowserSession *peerSession = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        [peerSession setSearchService:service]; [peerSession setSearchMode:@"fuzzy"]; Search(peerSession, @"qzr");
        PrimaryFixtureTable *peerTable = PrimaryTable(peerSession, NULL);
        NSUInteger peerTitle = [peerSession indexForRowKey:titleKey];
        [peerTable selectRowIndexes:[NSIndexSet indexSetWithIndex:peerTitle] byExtendingSelection:NO];
        Check([[peerSession rowKeyAtIndex:[peerTable primarySelectedRow]] isEqual:titleKey] && [[session rowKeyAtIndex:[primaryTable primarySelectedRow]] isEqual:fuzzyKey], "separate browser tables keep independent primary occurrences for one shared note");
        [peerTable setDelegate:nil]; [peerTable setDataSource:nil]; [peerSession setDelegate:nil];
        [selectedOccurrenceKeys release];
        [primaryTable setDelegate:nil]; [primaryTable setDataSource:nil];
        Autocomplete = YES;
        Check([session preferredSelectedNoteIndex] < 2, "autocomplete searches title group first");
        Autocomplete = NO;

        [session filterNotesFromString:@"Body"];
        Check([session searchPending] && ![session searchResultsAreCurrent], "new query disables old rows synchronously");
        Check([[session notesAtIndexes:[NSIndexSet indexSetWithIndex:0]] count] == 0, "pending rows cannot supply bulk targets");
        [session filterNotesFromString:@"Empty"];
        Check(Spin(^BOOL { return [session searchResultsAreCurrent]; }), "superseding query completes");
        Check([session noteObjectAtFilteredIndex:0] == d, "obsolete result cannot replace latest query");

        [session setSearchMode:@"exact"]; Search(session, @"first body");
        Check([Visible(session) isEqual:@[a]], "Exact mode retains existing all-field literal logic");
        [session setSearchMode:@"fuzzy"]; Search(session, @" :\t\n\"\"");
        Check(![session hasSearchTerms] && [Visible(session) count] == 4 && [session resultCount] == 4, "separator-only fuzzy query is synchronous unique all-notes list");
        Check([[session matchKindAtIndex:0] isEqualToString:@"exact"], "no-term rows have a single stable kind");

        Search(session, @"qzr");
        owner->selected = b;
        [b->titleString release]; b->titleString = [@"Changed" copy];
        [b setContentString:[[[NSAttributedString alloc] initWithString:@"nothing matches"] autorelease]];
        [service invalidate]; [session invalidateSearch]; Capture(service, library); [session libraryDidChange];
        Check(Spin(^BOOL { return [session searchResultsAreCurrent]; }), "corpus replacement completes");
        Check([[session matchKindAtIndex:[Visible(session) count] - 1] isEqualToString:@"retained"] && [session noteObjectAtFilteredIndex:[Visible(session) count] - 1] == b, "open nonmatching editor gets a separate retained row");
        Check([session resultCount] == 3 && [session distinctResultNoteCount] == 2, "retained editor excluded from result counts");
        Check([session indexForRowKey:fuzzyKey] == [Visible(session) count] - 1, "removed fuzzy occurrence falls back to retained same note");
        Search(session, @"qzr x");
        Check([Visible(session) count] == 0, "explicit query removes retained editor row");
        owner->selected = nil;

        owner->allowsChange = NO;
        [session filterNotesFromString:@"Empty"];
        Check(Spin(^BOOL { return [session valueForKey:@"deferredSearchResult"] != nil; }), "completion defers during active table editing");
        Check([session searchPending] && ![session searchResultsAreCurrent], "deferred completion keeps prior rows unavailable");
        owner->allowsChange = YES;
        Check(Spin(^BOOL { return [session searchResultsAreCurrent]; }), "deferred completion publishes once editing ends");
        Check([session noteObjectAtFilteredIndex:0] == d, "deferred publication resolves correct result");

        [session suspendSearchForComposition:YES];
        NSUInteger compositionGeneration = [session searchGeneration];
        Check([session searchPending] && ![session searchResultsAreCurrent], "composition immediately invalidates rows");
        [session filterNotesFromString:@"qzr"];
        Check([session searchPending] && ![session searchResultsAreCurrent], "composing text never publishes a query");
        [session suspendSearchForComposition:NO];
        Check([session searchGeneration] > compositionGeneration && Spin(^BOOL { return [session searchResultsAreCurrent]; }), "composition commit establishes a fresh identity");
        Check([session noteObjectAtFilteredIndex:0] == a, "composition result matches committed query");

        unichar chars[] = {'x', 0, 'y'};
        NSString *bad = [NSString stringWithCharacters:chars length:3];
        [session filterNotesFromString:bad];
        Check(Spin(^BOOL { return ![session searchPending]; }) && [session searchError] != nil, "invalid query has terminal error");
        generation = [session searchGeneration]; NSUInteger errorsBefore = owner->completions;
        [session libraryDidChange]; [session filterNotesFromString:bad];
        Check([session searchGeneration] == generation && owner->completions == errorsBefore && [session searchError] != nil, "presentation and equal query do not retry terminal error");
        Check(![session searchResultsAreCurrent] && [[session notesAtIndexes:[NSIndexSet indexSetWithIndex:0]] count] == 0, "failure does not activate old rows or imply zero matches");

        Search(session, @"qzr");
        __block BOOL highlights = NO;
        NSUInteger cIndex = [session indexInFilteredListForNoteIdenticalTo:c];
        [session requestSourceHighlightsForRow:cIndex completion:^(NSArray *ranges, NSString *source) {
            Check([ranges count] > 0 && [source isEqualToString:@"q----z----r"], "fuzzy source positions use original text"); highlights = YES;
        }];
        Check(Spin(^BOOL { return highlights; }), "source positions complete independently of membership");
        __block BOOL staleHighlights = NO;
        [session requestSourceHighlightsForRow:cIndex completion:^(NSArray *ranges, NSString *source) { staleHighlights = YES; }];
        Search(session, @"Empty");
        Check(!staleHighlights, "superseded source positions do not publish");

        NoteObject *longNote = Note(@"Long source", [[@"x" stringByPaddingToLength:3000 withString:@"x" startingAtIndex:0] stringByAppendingString:@"l--m--n ending"]);
        [library addNote:longNote]; [service invalidate]; [session invalidateSearch]; Capture(service, library);
        Search(session, @"lmn");
        Check([Visible(session) isEqual:@[longNote]], "long-note excerpt fixture has one native result");
        TestTable *table = [[[TestTable alloc] init] autorelease]; table->visibleRows = NSMakeRange(0, 1);
        NSString *beforeExcerpt = [[session previewForRow:0 inTable:(id)table] string];
        Check(![beforeExcerpt containsString:@"l--m--n"], "pending excerpt uses ordinary source start");
        __block BOOL sourceAlongsideExcerpt = NO;
        [session requestSourceHighlightsForRow:0 completion:^(NSArray *ranges, NSString *source) { sourceAlongsideExcerpt = YES; }];
        Check(Spin(^BOOL { return table->reloads > 0 && sourceAlongsideExcerpt; }), "visible excerpt and selected source positions coexist");
        NSString *afterExcerpt = [[session previewForRow:0 inTable:(id)table] string];
        Check([afterExcerpt containsString:@"l--m--n"] && [afterExcerpt containsString:@"Fuzzy match"], "native source positions place late match in context preview");
        table->visibleRows = NSMakeRange(NSNotFound, 0);
        [session previewForRow:0 inTable:(id)table];
        Check([[session valueForKey:@"excerptPositions"] count] == 0, "excerpt positions are bounded to visible rows");
        [library removeNote:longNote]; [service invalidate]; [session invalidateSearch]; Capture(service, library);
        Search(session, @"Empty");

        TestTable *editingTable = [[[TestTable alloc] init] autorelease];
        editingTable->inlineTarget = a; editingTable->targetExists = YES;
        [session invalidateSearch];
        [[session notesListDataSource] tableView:(id)editingTable setObjectValue:@"qzr edited" forTableColumn:nil row:0];
        Check([a->titleString isEqualToString:@"qzr edited"], "active inline edit commits through captured note despite unrelated invalidation");
        editingTable->targetExists = NO;
        [[session notesListDataSource] tableView:(id)editingTable setObjectValue:@"wrong target" forTableColumn:nil row:0];
        Check([a->titleString isEqualToString:@"qzr edited"], "deleted captured inline target cannot fall back to current row");
        [service invalidate]; Capture(service, library); Search(session, @"Empty");

        owner->invalidateDuringPublication = YES;
        [session filterNotesFromString:@"qzr"];
        Check(Spin(^BOOL { return !owner->invalidateDuringPublication; }), "publication hook executed");
        Check(![session searchResultsAreCurrent], "delegate mutation between preparation and row replacement rejects publication");
        [session refilterNotes]; Check(Spin(^BOOL { return [session searchResultsAreCurrent]; }), "explicit retry recovers invalidated publication");
        [session removeNotesAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [Visible(session) count])]];
        Check([[library allNotes] count] == 2, "bulk deletion acts once on each unique matching note");
        [service invalidate]; [session invalidateSearch]; Capture(service, library); [session libraryDidChange];
        Check(Spin(^BOOL { return [session searchResultsAreCurrent]; }) && [Visible(session) count] == 0, "deletion removes all duplicate occurrences");
        [titleKey release]; [fuzzyKey release];
        [session setDelegate:nil]; [service invalidate];
        printf("FUZZY BROWSER TESTS PASSED (%lu checks)\n", (unsigned long)Checks);
    }
    return 0;
}
