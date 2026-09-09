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

// In-memory doubles preserve the model's ivar layout. Production browser and table methods
// run against real, hidden AppKit windows. No notes directory opens.
NSString *NoteTitleColumnString = @"title";
static NSUInteger ContentsReads, LibraryReads, Comparisons, Checks;
static BOOL Autocomplete;
static NSUInteger LabelWrites, ClosedTagEditors;
static NVBrowserSession *InvalidateDuringTitleCommit;
static void (^TitleCommitHook)(NoteObject *);
static NSUInteger TitleWrites, RemoveCalls;
static NSArray *LastRemovedNotes;
static BOOL ConfirmDeletion;
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
- (BOOL)confirmNoteDeletion { return ConfirmDeletion; }
@end
@implementation NoteObject
- (id)initWithNoteBody:(NSAttributedString *)body title:(NSString *)title delegate:(id)owner format:(NSInteger)format labels:(NSString *)labels {
    if ((self = [super init])) { contentString = [body mutableCopy]; titleString = [title copy]; labelString = [labels copy]; static unsigned char serial; memset(&uniqueNoteIDBytes, 0, sizeof(uniqueNoteIDBytes)); ((unsigned char *)&uniqueNoteIDBytes)[15] = ++serial; }
    return self;
}
- (CFUUIDBytes *)uniqueNoteIDBytes { return &uniqueNoteIDBytes; }
- (NSMutableAttributedString *)contentString { ContentsReads++; return contentString; }
- (void)setContentString:(NSAttributedString *)contents { [contentString setAttributedString:contents]; }
- (void)setTitleString:(NSString *)title {
    [titleString release]; titleString = [title copy]; TitleWrites++;
    if (TitleCommitHook) { void (^hook)(NoteObject *) = [TitleCommitHook copy]; [TitleCommitHook release]; TitleCommitHook = nil; hook(self); [hook release]; }
    if (InvalidateDuringTitleCommit) {
        NVBrowserSession *session = InvalidateDuringTitleCommit; InvalidateDuringTitleCommit = nil;
        [session invalidateSearch];
    }
}
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
- (void)removeNotes:(NSArray *)values { RemoveCalls++; [LastRemovedNotes release]; LastRemovedNotes = [values copy]; for (NoteObject *note in values) [notes removeObjectIdenticalTo:note]; }
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

#import <objc/runtime.h>
static NSResponder *RejectResponder;
@interface ReviewWindow : NSWindow
@end
@implementation ReviewWindow
- (BOOL)makeFirstResponder:(NSResponder *)responder {
    if (responder == RejectResponder && responder) { RejectResponder=nil; return NO; }
    return [super makeFirstResponder:responder];
}
@end
typedef struct {
    NSArray *notes;
    TestLibrary *library;
    NVSearchService *service;
    NVBrowserSession *session;
    TestOwner *owner;
    PrimaryFixtureOwner *tableOwner;
    PrimaryFixtureTable *table;
    NSWindow *window;
} Fixture;
static Fixture FixtureMake(void) {
    Fixture f = {0};
    f.notes = @[Note(@"road Alpha", @"road body"), Note(@"road Beta", @"road body"), Note(@"road Gamma", @"road body")];
    f.library = [[[TestLibrary alloc] initWithNotes:f.notes] autorelease];
    f.service = [[[NVSearchService alloc] init] autorelease]; Capture(f.service, f.library);
    f.session = [[[NVBrowserSession alloc] initWithLibrary:(id)f.library] autorelease];
    f.owner = [[[TestOwner alloc] init] autorelease]; [f.session setDelegate:f.owner];
    [f.session setSearchService:f.service]; [f.session setSearchMode:@"fuzzy"]; Search(f.session, @"road");
    f.table = PrimaryTable(f.session, &f.tableOwner); [f.table setDataSource:(id)[f.session notesListDataSource]];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:NoteTitleColumnString] autorelease];
    [column setEditable:YES]; [column setWidth:400]; [f.table addTableColumn:column]; [f.table reloadData];
    f.window = [[[ReviewWindow alloc] initWithContentRect:NSMakeRect(100,100,500,200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    [f.window setReleasedWhenClosed:NO]; [f.window setContentView:f.table]; [f.window makeFirstResponder:f.table];
    return f;
}
static NSUInteger Row(Fixture f, NoteObject *note, NSString *kind) {
    for (NSUInteger i=0;i<[[f.session notesListDataSource] count];i++)
        if ([f.session noteObjectAtFilteredIndex:i] == note && [[f.session matchKindAtIndex:i] isEqual:kind]) return i;
    return NSNotFound;
}
static void Begin(Fixture f, NoteObject *note, NSString *kind, NSString *value) {
    NSUInteger row=Row(f,note,kind); Check(row!=NSNotFound,"fixture locates requested occurrence");
    [f.table selectRowAndScroll:(NSInteger)row]; [f.table editColumn:0 row:row withEvent:nil select:YES];
    Check([f.table currentEditor]!=nil,"native fixture starts a real inline field editor");
    [(NSTextView *)[f.table currentEditor] setString:value];
}
static void Rebuild(Fixture f) {
    [f.service invalidate]; [f.session invalidateSearch]; Capture(f.service,f.library); [f.session refilterNotes];
    Check(Spin(^BOOL{return [f.session searchResultsAreCurrent];}),"reentrant rebuilt corpus finishes publication");
}
static void Finish(Fixture f) {
    [TitleCommitHook release]; TitleCommitHook=nil;
    [f.window makeFirstResponder:f.table]; [f.table setDelegate:nil]; [f.table setDataSource:nil];
    [f.session setDelegate:nil]; [f.service invalidate]; [f.window orderOut:nil];
}
static void EditReentrancy(void) {
    {
        Fixture f=FixtureMake(); NoteObject *a=f.notes[0],*b=f.notes[1];
        Begin(f,a,@"title",@"road commit after refusal"); NSUInteger requested=Row(f,b,@"fuzzy");
        RejectResponder=f.table; [f.table editColumn:0 row:requested withEvent:nil select:YES];
        Check([a->titleString isEqual:@"road Alpha"] && [f.table currentEditor]!=nil && [f.table noteForInlineEditAtRow:Row(f,a,@"title") inSession:f.session]==a,"refused responder change preserves original editor, text, and target capture");
        Check([[(NSTextView *)[f.table currentEditor] string] isEqual:@"road commit after refusal"],"refused transition leaves uncommitted text available");
        [f.table editColumn:0 row:requested withEvent:nil select:YES];
        Check([a->titleString isEqual:@"road commit after refusal"] && [f.table noteForInlineEditAtRow:requested inSession:f.session]==b,"retry after responder refusal commits old title and captures correct next note");
        printf("CASE responder-refusal old_editor_preserved=1 retry_target_correct=1\n"); Finish(f);
    }
    {
        Fixture f=FixtureMake(); NoteObject *a=f.notes[0],*b=f.notes[1];
        Begin(f,a,@"title",@"road Zulu"); NSUInteger oldB=Row(f,b,@"title");
        TitleCommitHook=[^(NoteObject *note){ Rebuild(f); } copy];
        [f.table editColumn:0 row:oldB withEvent:nil select:YES];
        NSUInteger newB=Row(f,b,@"title");
        Check(oldB!=newB && [a->titleString isEqual:@"road Zulu"],"old commit changes title-group sort and survives the transition");
        Check([f.table editedRow]==newB && [f.table noteForInlineEditAtRow:newB inSession:f.session]==b && [[(NSTextView *)[f.table currentEditor] string] isEqual:b->titleString],"new editor follows requested row identity through synchronous title reorder");
        printf("CASE reorder old_row=%lu resolved_row=%lu\n",(unsigned long)oldB,(unsigned long)newB); Finish(f);
    }
    {
        Fixture f=FixtureMake(); NoteObject *a=f.notes[0];
        Begin(f,a,@"fuzzy",@"renamed outside title group"); NSUInteger requested=Row(f,a,@"title");
        TitleCommitHook=[^(NoteObject *note){ Rebuild(f); } copy];
        [f.table editColumn:0 row:requested withEvent:nil select:YES];
        NSUInteger remaining=Row(f,a,@"fuzzy");
        Check(Row(f,a,@"title")==NSNotFound && remaining!=NSNotFound,"old title commit removes only the title occurrence");
        Check([f.table editedRow]==remaining && [f.table noteForInlineEditAtRow:remaining inSession:f.session]==a,"removed title occurrence falls back to the same note fuzzy row");
        printf("CASE title-removal fallback_row=%lu\n",(unsigned long)remaining); Finish(f);
    }
    {
        Fixture f=FixtureMake(); NoteObject *a=f.notes[0],*b=f.notes[1];
        Begin(f,a,@"title",@"road committed before pending"); NSUInteger requested=Row(f,b,@"fuzzy");
        TitleCommitHook=[^(NoteObject *note){ [f.session invalidateSearch]; } copy];
        [f.table editColumn:0 row:requested withEvent:nil select:YES];
        Check([a->titleString isEqual:@"road committed before pending"] && ![f.session searchResultsAreCurrent],"old title survives synchronous invalidation");
        Check(![f.table currentEditor] && ![f.table hasInlineEditTarget],"guard leaves no new editor or capture while results are pending");
        printf("CASE pending new_editor=0 capture=0\n"); Finish(f);
    }
    {
        Fixture f=FixtureMake(); NoteObject *a=f.notes[0],*b=f.notes[1];
        Begin(f,a,@"title",@"road old note committed"); NSUInteger requested=Row(f,b,@"title");
        TitleCommitHook=[^(NoteObject *note){ [f.library removeNote:b]; Rebuild(f); } copy];
        [f.table editColumn:0 row:requested withEvent:nil select:YES];
        Check(![f.table currentEditor] && ![f.table hasInlineEditTarget] && [a->titleString isEqual:@"road old note committed"],"deletion of requested target during old commit cancels the second editor");
        printf("CASE requested-deletion new_editor=0\n"); Finish(f);
    }
    {
        Fixture f=FixtureMake(); NoteObject *a=f.notes[0],*b=f.notes[1];
        NoteObject *replacement=Note(@"road Beta replacement",@"road body"); memcpy([replacement uniqueNoteIDBytes],[b uniqueNoteIDBytes],sizeof(CFUUIDBytes));
        Begin(f,a,@"title",@"road old note committed"); NSUInteger requested=Row(f,b,@"fuzzy");
        TitleCommitHook=[^(NoteObject *note){ [f.library removeNote:b]; [f.library addNote:replacement]; Rebuild(f); } copy];
        [f.table editColumn:0 row:requested withEvent:nil select:YES];
        Check(![f.table currentEditor] && ![f.table hasInlineEditTarget] && [replacement->titleString isEqual:@"road Beta replacement"],"inline guard rejects a different note object with the same UUID");
        printf("CASE requested-replacement same_uuid=1 new_editor=0\n"); Finish(f);
    }
    {
        Fixture f=FixtureMake(); Fixture other=FixtureMake(); NoteObject *a=f.notes[0],*b=f.notes[1];
        Begin(f,a,@"title",@"road old library committed"); NSUInteger requested=Row(f,b,@"title");
        TitleCommitHook=[^(NoteObject *note){ f.tableOwner->session=other.session; [f.table setDataSource:(id)[other.session notesListDataSource]]; } copy];
        [f.table editColumn:0 row:requested withEvent:nil select:YES];
        Check([a->titleString isEqual:@"road old library committed"] && ![f.table currentEditor] && ![f.table hasInlineEditTarget],"browser-session replacement during old commit prevents a new editor");
        Check([((NoteObject *)other.notes[0])->titleString isEqual:@"road Alpha"],"replacement library remains untouched by old editor transition");
        printf("CASE library-replacement new_editor=0 replacement_unchanged=1\n"); Finish(f); Finish(other);
    }
    {
        Fixture f=FixtureMake(); NoteObject *a=f.notes[0],*b=f.notes[1];
        Begin(f,a,@"title",@"must not reach removed object"); NSUInteger requested=Row(f,b,@"fuzzy");
        [f.library removeNote:a]; NSUInteger writes=TitleWrites;
        [f.table editColumn:0 row:requested withEvent:nil select:YES];
        Check(TitleWrites==writes && [a->titleString isEqual:@"road Alpha"],"old target deletion rejects the obsolete inline commit");
        Check([f.table currentEditor]!=nil && [f.table noteForInlineEditAtRow:requested inSession:f.session]==b,"second live target retains its capture after old target deletion");
        printf("CASE old-target-deletion stale_writes=0 next_target_correct=1\n"); Finish(f);
    }
}
static NSEvent *Context(Fixture f, NSUInteger row) {
    NSPoint point=[f.table convertPoint:NSMakePoint(10,NSMidY([f.table rectOfRow:row])) toView:nil];
    return [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:0 windowNumber:[f.window windowNumber] context:nil eventNumber:1 clickCount:1 pressure:1];
}
static void DuplicateContext(void) {
    Fixture f=FixtureMake(); NoteObject *a=f.notes[0];
    NSUInteger title=Row(f,a,@"title"),fuzzy=Row(f,a,@"fuzzy");
    NSMutableIndexSet *selection=[NSMutableIndexSet indexSetWithIndex:title]; [selection addIndex:fuzzy];
    [f.table selectRowIndexes:selection byExtendingSelection:NO]; [f.table setPrimarySelectedRow:fuzzy];
    NSString *fuzzyKey=[[f.session rowKeyAtIndex:fuzzy] copy]; NSArray *keys=[[f.session rowKeysAtIndexes:selection] copy];
    [f.session setSortColumn:nil reversed:YES]; [f.table reloadData];
    [f.table selectRowIndexes:[f.session indexesForRowKeys:keys] byExtendingSelection:NO];
    Check([f.table primarySelectedRow]==[f.session indexForRowKey:fuzzyKey],"duplicate primary remains fuzzy through title-group reorder");
    NSUInteger newTitle=Row(f,a,@"title"),before=f.tableOwner->contextChanges;
    [f.table menuForEvent:Context(f,newTitle)];
    Check([f.table primarySelectedRow]==newTitle && [[f.session notesAtIndexes:[f.table selectedRowIndexes]] isEqual:@[a]],"context menu changes occurrence while bulk projection retains one UUID");
    Check(f.tableOwner->contextChanges==before+1,"unchanged duplicate membership delivers exactly one primary-change notification");
    printf("CASE duplicate-context old_title=%lu new_title=%lu unique_targets=1 context_notifications=1\n",(unsigned long)title,(unsigned long)newTitle);
    [fuzzyKey release]; [keys release]; Finish(f);
}

static void (^DeleteCompletion)(NSModalResponse);
@interface DeleteController : NSObject {
@public NVBrowserSession *deleteSession; TestLibrary *activeLibrary; PrimaryFixtureTable *notesTableView; GlobalPrefs *prefsController; NSWindow *window;
}
- (NVBrowserSession *)browserSession;
- (NotationController *)sharedNotationController;
- (void)deleteNote:(id)sender;
@end
@implementation DeleteController
- (NVBrowserSession *)browserSession { return deleteSession; }
- (NotationController *)sharedNotationController { return (id)activeLibrary; }
#include "delete-note.inc"
@end
static DeleteController *DeleteOwner(Fixture f) {
    DeleteController *owner=[[[DeleteController alloc] init] autorelease]; owner->deleteSession=f.session; owner->activeLibrary=f.library; owner->notesTableView=f.table; owner->window=f.window; owner->prefsController=[GlobalPrefs defaultPrefs]; return owner;
}
static void SelectAllRows(Fixture f) { [f.table selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,[[f.session notesListDataSource] count])] byExtendingSelection:NO]; }
static void DeliverDelete(void) { void (^completion)(NSModalResponse)=[DeleteCompletion copy]; [DeleteCompletion release]; DeleteCompletion=nil; completion(NSAlertFirstButtonReturn); [completion release]; }
static void BulkIdentity(void) {
    Method method=class_getInstanceMethod([NSAlert class],@selector(beginSheetModalForWindow:completionHandler:)); IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^(id alert,NSWindow *window,void (^completion)(NSModalResponse)){ [DeleteCompletion release]; DeleteCompletion=[completion copy]; });
    method_setImplementation(method,replacement); ConfirmDeletion=YES;
    {
        Fixture f=FixtureMake(); DeleteController *owner=DeleteOwner(f); NoteObject *a=f.notes[0],*b=f.notes[1],*c=f.notes[2];
        NSMutableIndexSet *selection=[NSMutableIndexSet indexSet];
        for (NSString *kind in @[@"title",@"fuzzy"]) { [selection addIndex:Row(f,a,kind)]; [selection addIndex:Row(f,b,kind)]; }
        [f.table selectRowIndexes:selection byExtendingSelection:NO]; [owner deleteNote:nil]; Check(DeleteCompletion!=nil,"real delete action captures delayed confirmation");
        [f.table selectRowAndScroll:Row(f,c,@"fuzzy")]; [f.session setSortColumn:nil reversed:YES];
        RemoveCalls=0; DeliverDelete();
        Check(RemoveCalls==1 && [LastRemovedNotes isEqual:@[a,b]] && [[f.library allNotes] isEqual:@[c]],"delayed delete uses two original UUIDs once despite later selection and sort");
        printf("CASE delayed-delete selected_rows=4 deleted_notes=2 removal_calls=1\n"); Finish(f);
    }
    {
        Fixture f=FixtureMake(); Fixture other=FixtureMake(); DeleteController *owner=DeleteOwner(f);
        memcpy([other.notes[0] uniqueNoteIDBytes],[f.notes[0] uniqueNoteIDBytes],sizeof(CFUUIDBytes));
        SelectAllRows(f); [owner deleteNote:nil]; owner->activeLibrary=other.library; RemoveCalls=0; DeliverDelete();
        Check(RemoveCalls==0 && [[f.library allNotes] count]==3 && [[other.library allNotes] count]==3,"delayed delete rejects library replacement even with a reused UUID");
        printf("CASE delayed-delete-library-replacement removal_calls=0\n"); Finish(f); Finish(other);
    }
    {
        Fixture f=FixtureMake(); DeleteController *owner=DeleteOwner(f); SelectAllRows(f); [owner deleteNote:nil];
        [f.library removeNote:f.notes[1]]; RemoveCalls=0; DeliverDelete();
        Check(RemoveCalls==1 && [LastRemovedNotes count]==2 && [[f.library allNotes] count]==0,"delayed delete skips a removed original target without selecting another row");
        [f.session invalidateSearch]; [owner deleteNote:nil]; Check(DeleteCompletion==nil,"pending search cannot capture another delete intent");
        printf("CASE delayed-delete-removed-target surviving_targets=2\n"); Finish(f);
    }
    method_setImplementation(method,original); imp_removeBlock(replacement); ConfirmDeletion=NO;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; EditReentrancy(); DuplicateContext(); BulkIdentity();
    [LastRemovedNotes release]; LastRemovedNotes=nil;
    printf("ROUND 2 INTERACTION REVIEW PASSED (%lu checks)\n",(unsigned long)Checks);
} return 0; }
