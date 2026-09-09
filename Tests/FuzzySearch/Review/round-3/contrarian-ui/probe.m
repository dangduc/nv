#import <Cocoa/Cocoa.h>
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NVSearchService.h"
#import "TagEditingManager.h"
#import "BookmarksController.h"
#import "AppController.h"
#import "NSString_NV.h"
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
- (BOOL)showTagsInTopSection { return NO; }
- (void)setShowTagsInTopSection:(BOOL)v sender:(id)sender {}
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
- (NSUndoManager *)undoManager { if (!undoManager) undoManager = [[NSUndoManager alloc] init]; return undoManager; }
- (NSRange)lastSelectedRange { return NSMakeRange(0,0); }
- (void)dealloc { [undoManager release]; [contentString release]; [titleString release]; [labelString release]; [super dealloc]; }
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

#import "LinkingEditor.h"
@interface CountField : NSTextField { @public NSUInteger selections; }
@end
@implementation CountField
- (void)selectText:(id)sender { selections++; }
- (void)setSnapbackString:(NSString *)string { }
@end

@interface InteractionController : NSObject <NSTableViewDelegate> {
@public
    TagEditingManager *tagEditor;
    NotationController *multiTagLibrary;
    NSArray *multiTagNoteUUIDs;
    TestLibrary *activeLibrary;
    NVBrowserSession *notationController;
    PrimaryFixtureTable *notesTableView;
    NSWindow *window;
    NSScrollView *textScrollView;
    CountField *noteTagsField, *field;
    GlobalPrefs *prefsController;
    NoteObject *currentNote;
    NSMutableDictionary *noteSelections;
    NSString *selectedSearchRowKey, *typedString;
    NSArray *savedSelectedNotes;
    LinkingEditor *textView;
    BOOL reloadingNotesList, isFilteringFromTyping, checkDisplay;
    NSUInteger highlights, attachments, headerUpdates;
}
- (NVBrowserSession *)browserSession;
- (NSArray *)pendingMultiTagNotes;
- (void)cancelMultiTagEditing;
- (void)releaseTagEditor:(NSNotification *)notification;
- (void)tagNote:(id)sender;
- (void)multiTag:(id)sender;
- (void)processChangedSelectionForTable:(NSTableView *)table;
@end
@implementation InteractionController
- (NVBrowserSession *)browserSession { return notationController; }
- (NotationController *)sharedNotationController { return (id)activeLibrary; }
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (checkDisplay) [self processChangedSelectionForTable:notesTableView];
}
- (void)cacheTypedStringIfNecessary:(NSString *)string { }
- (void)updateNoteHeader { headerUpdates++; }
- (void)updateSearchAffordance { }
- (void)refreshSearchHighlights { highlights++; }
- (NSString *)searchMode { return [notationController searchMode]; }
- (void)_setCurrentNote:(NoteObject *)note {
    attachments++;
    Check(!checkDisplay, "same-note occurrence never enters editor attachment");
}
- (void)setEmptyViewState:(BOOL)value { }
- (void)postTextUpdate { }
- (void)updateWordCount:(BOOL)value { }
- (void)restoreSourceScroll { }
- (void)updateRTL { }
#include "multi-tag.inc"
#include "display.inc"
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelMultiTagEditing];
    [selectedSearchRowKey release]; [noteSelections release]; [super dealloc];
}
@end

typedef struct {
    NSArray *notes;
    TestLibrary *library;
    NVSearchService *service;
    NVBrowserSession *session;
    TestOwner *owner;
    PrimaryFixtureTable *table;
    NSWindow *window;
    InteractionController *controller;
} Interaction;
static NSUInteger Row(Interaction f, NoteObject *note, NSString *kind) {
    for (NSUInteger row=0; row<[[f.session notesListDataSource] count]; row++)
        if ([f.session noteObjectAtFilteredIndex:row] == note && [[f.session matchKindAtIndex:row] isEqual:kind]) return row;
    return NSNotFound;
}
static Interaction Make(void) {
    Interaction f = {0};
    f.notes = @[Note(@"road Alpha", @"road source A"), Note(@"road Beta", @"road source B"), Note(@"road Gamma", @"road source C")];
    [f.notes[0] setLabelString:@"common alpha"]; [f.notes[1] setLabelString:@"common beta"]; [f.notes[2] setLabelString:@"gamma"];
    f.library = [[[TestLibrary alloc] initWithNotes:f.notes] autorelease];
    f.service = [[[NVSearchService alloc] init] autorelease]; Capture(f.service, f.library);
    f.session = [[[NVBrowserSession alloc] initWithLibrary:(id)f.library] autorelease];
    f.owner = [[[TestOwner alloc] init] autorelease]; [f.session setDelegate:f.owner];
    [f.session setSearchService:f.service]; [f.session setSearchMode:@"fuzzy"]; Search(f.session, @"road");
    f.table = PrimaryTable(f.session, NULL);
    f.controller = [[[InteractionController alloc] init] autorelease];
    f.controller->notationController=f.session; f.controller->activeLibrary=f.library; f.controller->notesTableView=f.table;
    f.controller->prefsController=[GlobalPrefs defaultPrefs];
    f.controller->noteTagsField=[[[CountField alloc] initWithFrame:NSMakeRect(0,0,200,24)] autorelease];
    f.controller->field=[[[CountField alloc] initWithFrame:NSMakeRect(0,0,200,24)] autorelease];
    [f.table setDelegate:f.controller]; [f.table setDataSource:(id)[f.session notesListDataSource]];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:NoteTitleColumnString] autorelease];
    [column setWidth:440]; [f.table addTableColumn:column]; [f.table reloadData];
    f.window=[[[NSWindow alloc] initWithContentRect:NSMakeRect(50,50,500,260) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    [f.window setReleasedWhenClosed:NO]; [f.window setTitle:@"Disposable fuzzy interaction review"];
    [f.table setFrame:NSMakeRect(0,60,500,200)]; [[f.window contentView] addSubview:f.table];
    f.controller->window=f.window;
    f.controller->textScrollView=[[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,500,60)] autorelease];
    [[f.window contentView] addSubview:f.controller->textScrollView];
    [[NSNotificationCenter defaultCenter] addObserver:f.controller selector:@selector(releaseTagEditor:) name:@"TagEditorShouldRelease" object:nil];
    Check([[f.session notesListDataSource] count] == 6, "three literal title rows precede three complete fuzzy rows");
    for (NoteObject *note in f.notes) Check(Row(f,note,@"title")!=NSNotFound && Row(f,note,@"fuzzy")!=NSNotFound, "each fixture note has both required occurrences");
    return f;
}
static void Select(Interaction f, NSArray *notes, NSString *primaryKind) {
    NSMutableIndexSet *indexes=[NSMutableIndexSet indexSet];
    for (NoteObject *note in notes) { [indexes addIndex:Row(f,note,@"title")]; [indexes addIndex:Row(f,note,@"fuzzy")]; }
    [f.table selectRowIndexes:indexes byExtendingSelection:NO];
    [f.table setPrimarySelectedRow:Row(f,notes[0],primaryKind)];
}
static void OpenTags(Interaction f) {
    [f.controller tagNote:nil];
    Check(f.controller->tagEditor && [f.controller->tagEditor isMultitagging], "production action loads actual native tag panel nib");
    Check([[[f.controller->tagEditor tagField] window] isKindOfClass:[NSPanel class]], "production tag manager owns native panel and field");
    Check([f.controller->multiTagNoteUUIDs count] == 2, "capture stores two UUIDs for four selected occurrence rows");
}
static void End(Interaction f) {
    [f.controller cancelMultiTagEditing];
    [f.table setDelegate:nil]; [f.table setDataSource:nil]; [f.session setDelegate:nil];
    [f.service invalidate]; [f.window orderOut:nil];
}
static void TagCases(void) {
    {
        Interaction f=Make(); Select(f,@[f.notes[0]],@"fuzzy");
        [f.controller tagNote:nil];
        Check([f.table numberOfSelectedRows]==2 && f.controller->tagEditor==nil && f.controller->noteTagsField->selections==1,
            "two occurrences of one note select the single-note header instead of opening bulk tags");
        printf("CASE one-note-duplicates rows=2 header_selections=1 bulk_panels=0\n"); End(f);
    }
    {
        Interaction f=Make(); Select(f,@[f.notes[0],f.notes[1]],@"fuzzy"); OpenTags(f);
        NSSet *common=[NSSet setWithArray:[f.controller->tagEditor commonTags]];
        Check([common isEqual:[NSSet setWithObject:@"common"]],"production tag action derives common labels from unique selected notes");
        [f.controller->tagEditor setTagFieldString:@"new"];
        Select(f,@[f.notes[2]],@"title");
        [f.session setSortColumn:(id)[[[TestColumn alloc] init] autorelease] reversed:YES]; [f.session sortAndRedisplayNotes];
        [f.session invalidateSearch];
        LabelWrites=0; [f.controller multiTag:nil];
        Check(LabelWrites==2 && [((NoteObject *)f.notes[0])->labelString isEqual:@"alpha new"] && [((NoteObject *)f.notes[1])->labelString isEqual:@"beta new"] && [((NoteObject *)f.notes[2])->labelString isEqual:@"gamma"],
            "delayed tags apply once to captured UUIDs after selection sort and pending-search changes");
        Check(f.controller->tagEditor==nil && f.controller->multiTagNoteUUIDs==nil && f.controller->multiTagLibrary==nil,"successful delayed tags release panel and target capture");
        printf("CASE delayed-tags captured_rows=4 unique_targets=2 writes=2 later_selection_untouched=1\n"); End(f);
    }
    {
        Interaction f=Make(); Select(f,@[f.notes[0],f.notes[1]],@"fuzzy"); OpenTags(f);
        [f.controller->tagEditor setTagFieldString:@"survivor"];
        [f.library removeNote:f.notes[0]]; Select(f,@[f.notes[2]],@"fuzzy");
        LabelWrites=0; [f.controller multiTag:nil];
        Check(LabelWrites==1 && [((NoteObject *)f.notes[0])->labelString isEqual:@"common alpha"] && [((NoteObject *)f.notes[1])->labelString isEqual:@"beta survivor"],"delayed tags skip the removed captured UUID and mutate its surviving peer once");
        printf("CASE removed-target writes=1 removed_note_untouched=1\n"); End(f);
    }
    {
        Interaction f=Make(); Select(f,@[f.notes[0],f.notes[1]],@"fuzzy"); OpenTags(f);
        [f.controller->tagEditor setTagFieldString:@"resurrected"];
        NoteObject *replacement=Note(@"replacement Alpha",@"replacement body"); memcpy([replacement uniqueNoteIDBytes],[f.notes[0] uniqueNoteIDBytes],sizeof(CFUUIDBytes));
        [replacement setLabelString:@"common replacement"]; [f.library removeNote:f.notes[0]]; [f.library addNote:replacement];
        LabelWrites=0; [f.controller multiTag:nil];
        Check(LabelWrites==2 && [replacement->labelString isEqual:@"replacement resurrected"] && [((NoteObject *)f.notes[0])->labelString isEqual:@"common alpha"],"same-library UUID identity resolves the current object without mutating the removed object");
        printf("CASE same-library-same-uuid replacement_receives_tag=1 old_object_untouched=1\n"); End(f);
    }
    {
        Interaction f=Make(); Select(f,@[f.notes[0],f.notes[1]],@"fuzzy"); OpenTags(f);
        [f.controller->tagEditor setTagFieldString:@"wrong-library"];
        NoteObject *replacement=Note(@"foreign Alpha",@"foreign source"); memcpy([replacement uniqueNoteIDBytes],[f.notes[0] uniqueNoteIDBytes],sizeof(CFUUIDBytes));
        f.controller->activeLibrary=[[[TestLibrary alloc] initWithNotes:@[replacement]] autorelease];
        LabelWrites=0; [f.controller multiTag:nil];
        Check(LabelWrites==0 && [replacement->labelString isEqual:@""] && [((NoteObject *)f.notes[0])->labelString isEqual:@"common alpha"],"replacement library rejects delayed tags even when UUIDs are reused");
        Check(f.controller->tagEditor==nil && f.controller->multiTagLibrary==nil,"rejected library transition closes and releases the pending panel");
        printf("CASE library-replacement reused_uuid=1 total_writes=0\n"); End(f);
    }
    {
        Interaction f=Make(); Select(f,@[f.notes[0],f.notes[1]],@"title"); OpenTags(f);
        TagEditingManager *old=[f.controller->tagEditor retain];
        [old setTagFieldString:@"obsolete"];
        Select(f,@[f.notes[1],f.notes[2]],@"fuzzy"); OpenTags(f);
        Check(f.controller->tagEditor!=old,"new bulk action replaces its previous native panel");
        [f.controller releaseTagEditor:[NSNotification notificationWithName:@"TagEditorShouldRelease" object:old]];
        Check(f.controller->tagEditor!=nil && [[f.controller pendingMultiTagNotes] isEqual:@[f.notes[1],f.notes[2]]],"delayed notification from old panel preserves the replacement capture");
        [f.controller->tagEditor setTagFieldString:@"current"];
        LabelWrites=0; [f.controller multiTag:nil];
        Check(LabelWrites==2 && [((NoteObject *)f.notes[0])->labelString isEqual:@"common alpha"] && [((NoteObject *)f.notes[1])->labelString containsString:@"current"] && [((NoteObject *)f.notes[2])->labelString containsString:@"current"],"replaced action mutates only the second capture");
        [old release]; printf("CASE panel-replacement old_notification_ignored=1 current_writes=2\n"); End(f);
    }
    {
        Interaction f=Make(); Select(f,@[f.notes[0],f.notes[1]],@"fuzzy"); OpenTags(f);
        [f.controller->tagEditor setTagFieldString:@"uncommitted"];
        TagEditingManager *panel=[f.controller->tagEditor retain];
        [panel windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:[[panel tagField] window]]];
        Check(f.controller->tagEditor==nil && f.controller->multiTagNoteUUIDs==nil,"production panel focus-loss callback cancels the captured action through its notification");
        LabelWrites=0; [f.controller multiTag:nil];
        Check(LabelWrites==0,"a late action after native panel cancellation cannot mutate notes");
        [panel release]; printf("CASE panel-focus-loss captured_targets=0 late_writes=0\n"); End(f);
    }
}

@interface StorageEdit : NSObject { NSTextStorage *storage; NSUndoManager *undo; }
- (id)initWithStorage:(NSTextStorage *)value undo:(NSUndoManager *)manager;
- (void)replace:(NSString *)value;
@end
@implementation StorageEdit
- (id)initWithStorage:(NSTextStorage *)value undo:(NSUndoManager *)manager { if ((self=[super init])) { storage=[value retain]; undo=[manager retain]; } return self; }
- (void)replace:(NSString *)value { [[undo prepareWithInvocationTarget:self] replace:[NSString stringWithString:[storage string]]]; [storage replaceCharactersInRange:NSMakeRange(0,[storage length]) withString:value]; }
- (void)dealloc { [storage release]; [undo release]; [super dealloc]; }
@end
static void SameNoteOccurrence(void) {
    Interaction f=Make(); NoteObject *note=f.notes[0];
    NSTextStorage *storage=[[[NSTextStorage alloc] initWithString:@"source before edit"] autorelease];
    NSLayoutManager *layout=[[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container=[[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(500,1000)] autorelease];
    [storage addLayoutManager:layout]; [layout addTextContainer:container];
    NSTextView *editor=[[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,500,60) textContainer:container] autorelease];
    [editor setAllowsUndo:NO]; [f.controller->textScrollView setDocumentView:editor];
    f.controller->textView=(id)editor; f.controller->currentNote=note; f.controller->checkDisplay=YES;
    NSUndoManager *undo=[note undoManager]; [undo setGroupsByEvent:NO];
    StorageEdit *edit=[[[StorageEdit alloc] initWithStorage:storage undo:undo] autorelease];
    [undo beginUndoGrouping]; [edit replace:@"source after edit"]; [undo endUndoGrouping];
    [editor setSelectedRange:NSMakeRange(4,3)];
    id originalStorage=[layout textStorage];
    Select(f,@[note],@"title");
    [f.controller processChangedSelectionForTable:f.table];
    NSString *titleKey=[[f.controller->selectedSearchRowKey copy] autorelease];
    [f.table preparePrimarySelectionForRow:Row(f,note,@"fuzzy")];
    [f.table notifyPrimaryChangeFromKey:titleKey selectedIndexes:[f.table selectedRowIndexes]];
    Check([f.controller->selectedSearchRowKey isEqual:[f.session rowKeyAtIndex:Row(f,note,@"fuzzy")]],"primary-only duplicate occurrence change reaches the browser display context");
    Check([f.table numberOfSelectedRows]==2 && f.controller->currentNote==note && f.controller->attachments==0,"duplicate selection retains one note without editor attachment");
    Check([layout textStorage]==originalStorage && [storage layoutManagers].count==1 && [editor selectedRange].location==4 && [editor selectedRange].length==3,"same-note occurrence leaves storage layout attachment and caret range unchanged");
    Check([[storage string] isEqual:@"source after edit"] && [undo canUndo] && ![undo canRedo],"same-note occurrence preserves source and its existing Undo entry");
    NSUInteger previousHighlights=f.controller->highlights;
    [f.table preparePrimarySelectionForRow:Row(f,note,@"title")];
    NSString *fuzzyKey=[[f.controller->selectedSearchRowKey copy] autorelease];
    [f.table notifyPrimaryChangeFromKey:fuzzyKey selectedIndexes:[f.table selectedRowIndexes]];
    Check([f.controller->selectedSearchRowKey isEqual:titleKey] && f.controller->highlights==previousHighlights+1,"returning to title occurrence refreshes highlights without replacing the note");
    [undo undo]; Check([[storage string] isEqual:@"source before edit"] && [undo canRedo],"one Undo still restores the body edit after both occurrence changes");
    [undo redo]; Check([[storage string] isEqual:@"source after edit"] && [undo canUndo],"one Redo still restores the body edit after both occurrence changes");
    printf("CASE same-note-occurrence rows=2 editor_attachments=0 undo_and_redo_preserved=1 highlights=%lu\n",f.controller->highlights);
    f.controller->checkDisplay=NO; [undo removeAllActions]; End(f);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        TagCases(); SameNoteOccurrence();
        printf("ROUND 3 INTERACTION REVIEW PASSED (%lu checks across 8 scenarios)\n",Checks);
    }
    return 0;
}
