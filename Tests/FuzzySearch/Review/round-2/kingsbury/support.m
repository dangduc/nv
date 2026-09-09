#import "AppController.h"
#import "NVApplicationController.h"
#import "NSString_NV.h"
#import "SecureTextEntryManager.h"

#ifndef NV_REVIEW_EXPECT_FIXED
#define NV_REVIEW_EXPECT_FIXED 0
#endif

// Foundation controls are explicit deterministic doubles. Production session,
// corpus, service and native matching all execute unmodified.
@interface StateEditor : NSObject { @public BOOL marked; NSString *value; NSRange selection; }
- (BOOL)hasMarkedText;
- (NSString *)string;
- (void)setSelectedRange:(NSRange)range;
- (void)scrollPoint:(NSPoint)point;
@end
@implementation StateEditor
- (BOOL)hasMarkedText { return marked; }
- (NSString *)string { return value ?: @""; }
- (void)setSelectedRange:(NSRange)range { selection = range; }
- (void)scrollPoint:(NSPoint)point {}
- (void)removeHighlightedTerms {}
- (void)setAllowsUndo:(BOOL)value {}
- (BOOL)textFinderIsVisible { return NO; }
@end
@interface StateField : NSObject { @public StateEditor *editor; NSString *value; }
- (id)currentEditor;
- (NSString *)stringValue;
- (void)setStringValue:(NSString *)string;
- (void)selectText:(id)sender;
@end
@implementation StateField
- (id)currentEditor { return editor; }
- (NSString *)stringValue { return value ?: @""; }
- (void)setStringValue:(NSString *)string { [value release]; value = [string copy]; editor->value = value; }
- (void)selectText:(id)sender {}
- (void)dealloc { [value release]; [super dealloc]; }
@end
@interface StateWindow : NSObject { @public id responder; BOOL key; }
- (id)firstResponder;
- (BOOL)isKeyWindow;
- (BOOL)makeFirstResponder:(id)object;
@end
@implementation StateWindow
- (id)firstResponder { return responder; }
- (BOOL)isKeyWindow { return key; }
- (BOOL)makeFirstResponder:(id)object { responder = object; return YES; }
- (void)makeKeyAndOrderFront:(id)sender { key = YES; }
- (void)setFrameFromString:(NSString *)string {}
- (NSEvent *)currentEvent { return nil; }
@end
@class StateController;
@interface StateTable : NSObject { @public NSInteger row; NSIndexSet *selection; StateController *owner; TestColumn *column; }
- (NSInteger)primarySelectedRow;
- (void)selectRowAndScroll:(NSInteger)index;
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
- (void)deselectAll:(id)sender;
- (NSInteger)numberOfSelectedRows;
- (NSIndexSet *)selectedRowIndexes;
- (NSArray *)labelCompletionsForString:(NSString *)text index:(NSInteger)index;
@end

static NVSearchService *ActiveSearchService;
static NSUInteger ClosedWindows;
@implementation NVApplicationController
+ (NVApplicationController *)sharedController { static id singleton; if (!singleton) singleton = [[self alloc] init]; return singleton; }
- (NVSearchService *)searchService { return ActiveSearchService; }
- (void)browserWillClose:(id)browser { ClosedWindows++; }
@end
@implementation SecureTextEntryManager
+ (id)sharedInstance { return nil; }
@end
@implementation NSString (ReviewUUID)
+ (NSString *)uuidStringWithBytes:(CFUUIDBytes)bytes {
    CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(NULL, bytes);
    NSString *result = [(NSString *)CFUUIDCreateString(NULL, uuid) autorelease]; CFRelease(uuid); return result;
}
@end
@implementation TestColumn (ReviewIdentifier)
- (NSString *)identifier { return NoteTitleColumnString; }
@end
@implementation TestLibrary (ReviewUI)
- (id)labelsListDataSource { return nil; }
- (id)notationPrefs { return nil; }
@end
@implementation GlobalPrefs (ReviewUI)
- (NSString *)sortedTableColumnKey { return NoteTitleColumnString; }
@end

@interface StateController : NSObject {
@public NVBrowserSession *notationController;
    StateField *field; StateEditor *textView; StateWindow *window; StateTable *notesTableView;
    GlobalPrefs *prefsController; NoteObject *currentNote; NSString *selectedSearchRowKey;
    BOOL searchAutocompletePending, searchApplyingResult, searchHasPendingComposition, searchSubmitting, searchStatusDelayElapsed;
    NSUInteger searchIntentGeneration, searchHighlightGeneration;
    NSString *pendingSearchReturnQuery; NSDictionary *pendingSearchRestoration, *pendingSearchReveal;
    NSString *typedString; BOOL typedStringIsCached, isFilteringFromTyping, reloadingNotesList, isAutocompleting, wasDeleting;
    TagEditingManager *tagEditor; id metadataControl; BOOL isEditing, applicationOwner;
    BOOL browserHorizontalLayout, viewingNote; NSUInteger presentationStateGeneration; CGFloat pendingListHeight;
    NSView *splitView; NSMutableDictionary *noteSelections, *noteBodyStates; NSUndoManager *windowUndoManager;
    NSString *selectedViewerIdentifier;
    NSUInteger creations, bodyFocuses; NSMutableArray *createdTitles; BOOL closed;
}
@property BOOL isEditing;
- (NVBrowserSession *)browserSession;
- (NotationController *)sharedNotationController;
- (NSString *)searchMode;
- (void)cancelSearchIntents;
- (void)cancelTransientSearchIntents;
- (void)searchForString:(NSString *)string mode:(NSString *)mode;
- (void)controlTextDidChange:(NSNotification *)notification;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
- (void)browserSessionSearchStateDidChange:(NVBrowserSession *)session;
- (void)browserSessionSearchDidComplete:(NVBrowserSession *)session;
- (void)performSearchReturn;
- (BOOL)searchFieldHasFocus;
- (NSUInteger)revealNote:(NoteObject *)note options:(NSUInteger)options;
- (void)notation:(NotationController *)notation revealNotes:(NSArray *)notes;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)restoreBrowserWindowState:(NSDictionary *)state;
- (void)applyRestoredSearchNoteState:(NSDictionary *)state;
- (void)attachLibrary:(NotationController *)library finishingOldLibrary:(BOOL)finish;
- (void)windowWillClose:(NSNotification *)notification;
- (void)windowDidResignKey:(NSNotification *)notification;
- (void)cancelOperation:(id)sender;
@end
@implementation StateTable
- (id)init { if ((self = [super init])) { row = -1; selection = [NSIndexSet new]; column = [TestColumn new]; } return self; }
- (NSInteger)primarySelectedRow { return row; }
- (NSIndexSet *)selectedRowIndexes { return selection; }
- (NSInteger)numberOfSelectedRows { return [selection count]; }
- (NSArray *)labelCompletionsForString:(NSString *)text index:(NSInteger)index { return @[]; }
- (void)selectRowAndScroll:(NSInteger)index { [self selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO]; }
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend {
    [selection release]; selection = [indexes copy]; row = [indexes count] ? [indexes firstIndex] : -1;
    [owner tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self]];
}
- (void)deselectAll:(id)sender { [self selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO]; }
- (void)scrollRowToVisible:(NSInteger)index {}
- (void)scrollRowToVisible:(NSInteger)index withVerticalOffset:(CGFloat)offset {}
- (void)scrollPoint:(NSPoint)point {}
- (id)noteAttributeColumnForIdentifier:(NSString *)identifier { return column; }
- (void)setSortDirection:(BOOL)reverse inTableColumn:(id)column {}
- (void)restoreColumnLayoutState:(id)state {}
- (void)abortEditing {}
- (void)setDataSource:(id)value {}
- (void)setLabelsListSource:(id)value {}
- (void)reloadData {}
- (void)dealloc { [selection release]; [column release]; [super dealloc]; }
@end
@implementation StateController
@synthesize isEditing;
- (id)init {
    if ((self = [super init])) {
        field = [StateField new]; field->editor = [[StateEditor new] autorelease];
        textView = [[StateEditor new] autorelease]; window = [StateWindow new]; window->key = YES; window->responder = field->editor;
        notesTableView = [StateTable new]; notesTableView->owner = self;
        prefsController = [GlobalPrefs defaultPrefs]; createdTitles = [NSMutableArray new];
        noteSelections = [NSMutableDictionary new]; noteBodyStates = [NSMutableDictionary new];
        selectedViewerIdentifier = [@"markdown" copy];
    }
    return self;
}
- (NVBrowserSession *)browserSession { return notationController; }
- (NotationController *)sharedNotationController { return [notationController library]; }
- (NoteObject *)selectedNoteObject { return currentNote; }
- (BOOL)notationListShouldChange:(id)session { return YES; }
- (void)notationListMightChange:(id)session {}
- (void)notationListDidChange:(id)session {
    // Model the NSTableView reload's selection rebuild without inventing user events.
    reloadingNotesList = YES; [notesTableView deselectAll:nil]; reloadingNotesList = NO;
}
- (BOOL)horizontalLayout { return NO; }
- (void)setupSearchControls {}
- (void)setDualFieldIsVisible:(BOOL)visible {}
- (void)selectSearchField { window->responder = field->editor; }
- (void)updateSearchAffordance {}
- (void)refreshSearchHighlights {}
- (BOOL)displayContentsForNoteAtIndex:(NSUInteger)row {
    if (![notationController searchResultsAreCurrent]) return NO;
    NoteObject *note = [notationController noteObjectAtFilteredIndex:row]; if (!note) return NO;
    currentNote = note; textView->value = [[note contentString] string];
    [selectedSearchRowKey release]; selectedSearchRowKey = [[notationController rowKeyAtIndex:row] copy]; return YES;
}
- (void)processChangedSelectionForTable:(id)table {
    if (reloadingNotesList || ![notationController searchResultsAreCurrent]) return;
    if ([[notationController notesAtIndexes:[notesTableView selectedRowIndexes]] count] == 1)
        [self displayContentsForNoteAtIndex:[notesTableView primarySelectedRow]];
    else currentNote = nil;
}
- (void)_setCurrentNote:(NoteObject *)note { currentNote = note; if (!note) textView->value = @""; }
- (void)_setCurrentNote:(NoteObject *)note finishingEditing:(BOOL)finish { [self _setCurrentNote:note]; }
- (void)setEmptyViewState:(BOOL)empty {}
- (NoteObject *)createNoteIfNecessary {
    if (!currentNote) { creations++; [createdTitles addObject:[field stringValue]]; }
    return currentNote;
}
- (void)focusNoteBody { bodyFocuses++; window->responder = textView; }
- (void)setTableAllowsMultipleSelection {}
- (void)commitNoteMetadata {}
- (void)cancelMultiTagEditing {}
- (void)finishEditing {}
- (void)discardViewer {}
- (void)unregisterBrowserObservers { closed = YES; }
- (void)setupViewsAfterAppAwakened {}
- (void)setViewingNote:(BOOL)value { viewingNote = value; }
- (void)setNotesListHeight:(CGFloat)height {}
- (void)restoreNotesListHeight {}
- (void)updateBodyPresentation {}
- (void)revealToolbar {}
#include "production-methods.inc"
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [notationController setDelegate:nil]; [notationController release];
    [field release]; [window release]; [notesTableView release]; [createdTitles release];
    [self cancelSearchIntents]; [typedString release]; [selectedSearchRowKey release];
    [noteSelections release]; [noteBodyStates release]; [selectedViewerIdentifier release]; [super dealloc];
}
@end

static StateController *Controller(TestLibrary *library, NVSearchService *service) {
    StateController *controller = [[[StateController alloc] init] autorelease];
    controller->notationController = [[NVBrowserSession alloc] initWithLibrary:(id)library];
    [controller->notationController setSearchService:service];
    [controller->notationController setSearchMode:@"fuzzy"];
    [controller->notationController setDelegate:controller]; return controller;
}
static void Pending(StateController *controller, NSString *query) {
    [controller searchForString:query mode:@"fuzzy"];
    Check([controller->notationController searchPending] && ![controller->notationController searchResultsAreCurrent], "query pending before main-queue completion");
}
static void Complete(StateController *controller) {
    Check(Spin(^BOOL { return [controller->notationController searchResultsAreCurrent]; }), "current production search completes");
}
static void PrintState(NSString *name, StateController *controller) {
    printf("%s: query=%s current=%d key=%d field_focus=%d creations=%lu selected=%s pending_return=%s\n",
        [name UTF8String], [[controller->notationController searchString] UTF8String],
        [controller->notationController searchResultsAreCurrent], [controller->window isKeyWindow], [controller searchFieldHasFocus],
        (unsigned long)controller->creations, [[controller->notationController rowKeyAtIndex:[controller->notesTableView primarySelectedRow]] UTF8String] ?: "none",
        [controller->pendingSearchReturnQuery UTF8String] ?: "none");
}
