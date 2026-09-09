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

int main(void) {
    @autoreleasepool {
        Autocomplete = YES;
        NoteObject *road = Note(@"Road map", @"road planning"), *body = Note(@"Other", @"road copper lantern"), *gaps = Note(@"Rivet", @"r---o---a---d");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, body, gaps]] autorelease];
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;
        StateController *controller = Controller(library, service);
        Pending(controller, @"road"); [controller performSearchReturn];
        Check(controller->creations == 0 && controller->pendingSearchReturnQuery != nil, "pending Return records intent without creation");
        Complete(controller);
        Check(controller->currentNote == road && controller->creations == 0 && controller->bodyFocuses == 1, "pending Return opens completed first title occurrence");
        NVBrowserSession *session = controller->notationController;
        Check([session resultCount] == 4 && [session distinctResultNoteCount] == 3, "title-first result keeps duplicate UUID occurrence");
        Check([session noteObjectAtFilteredIndex:0] == road && [[session matchKindAtIndex:0] isEqual:@"title"], "literal title starts full results");
        NSMutableArray *tail = [NSMutableArray array];
        for (NSUInteger i = 1; i < [session resultCount]; i++) { Check([[session matchKindAtIndex:i] isEqual:@"fuzzy"], "every tail row is a native occurrence"); [tail addObject:UUID([session noteObjectAtFilteredIndex:i])]; }
        Check([tail isEqual:[session.searchResult fuzzyNoteUUIDs]], "complete native order and membership preserved including title overlap");

        Pending(controller, @"no-result-zero-create"); [controller performSearchReturn]; Complete(controller);
        Check(controller->creations == 1 && [[controller->createdTitles lastObject] isEqual:@"no-result-zero-create"], "current zero completion authorizes exactly one creation");
        [controller browserSessionSearchDidComplete:session];
        Check(controller->creations == 1, "redelivery does not repeat deferred creation");

        Pending(controller, @"obsolete-zero-query"); [controller performSearchReturn]; Pending(controller, @"road"); Complete(controller);
        Check(controller->creations == 1, "new query cancels old zero Return");
        Pending(controller, @"focus-departure-zero"); [controller performSearchReturn];
        controller->window->responder = controller->textView;
        [controller controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:controller->field]];
        controller->window->responder = controller->field->editor; Complete(controller);
        Check(controller->creations == 1, "field exit cancels Return even when focus returns before completion");

        Pending(controller, @"composition-zero"); [controller performSearchReturn];
        controller->field->editor->marked = YES;
        [controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:controller->field userInfo:@{@"NSFieldEditor":controller->field->editor}]];
        Check(controller->searchHasPendingComposition && controller->pendingSearchReturnQuery == nil && ![session searchResultsAreCurrent], "composition invalidates search and Return");
        [controller performSearchReturn]; Check(controller->creations == 1 && !controller->pendingSearchReturnQuery, "composition Return cannot create or defer");
        controller->field->editor->marked = NO; [controller->field setStringValue:@"road"];
        [controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:controller->field userInfo:@{@"NSFieldEditor":controller->field->editor}]];
        Complete(controller); Check(controller->creations == 1 && !controller->searchHasPendingComposition, "committed composition resumes fresh query without obsolete Return");

        NSUInteger fuzzyRow = [session indexForRowKey:[NSString stringWithFormat:@"fuzzy:%@", [[[session rowKeyAtIndex:0] componentsSeparatedByString:@":"] lastObject]]];
        NSString *fuzzyKey = [[session rowKeyAtIndex:fuzzyRow] copy];
        NSMutableIndexSet *occurrences = [NSMutableIndexSet indexSetWithIndex:0]; [occurrences addIndex:fuzzyRow];
        Check([[session notesAtIndexes:occurrences] isEqual:@[road]], "document actions deduplicate title and fuzzy occurrences by UUID");
        [controller->notesTableView selectRowAndScroll:fuzzyRow]; [controller selectSearchField]; [controller performSearchReturn];
        Check(controller->currentNote == road && [controller->selectedSearchRowKey isEqual:fuzzyKey], "Return keeps the explicitly selected fuzzy occurrence");
        NSDictionary *state = @{@"search":@"road", @"searchMode":@"fuzzy", @"note":[NSString uuidStringWithBytes:*[road uniqueNoteIDBytes]], @"searchRowKey":fuzzyKey, @"selection":NSStringFromRange(NSMakeRange(1, 2))};
        StateController *restored = Controller(library, service); [restored restoreBrowserWindowState:state];
        Check(restored->pendingSearchRestoration != nil, "restoration defers while matching is pending");
#if NV_REVIEW_EXPECT_FIXED
        restored->window->key = NO;
        [restored windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:restored->window]];
        [restored controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:restored->field]];
        Check(restored->pendingSearchRestoration != nil, "focus departure preserves programmatic restoration");
#endif
        Complete(restored);
        Check(restored->currentNote == road && [restored->selectedSearchRowKey isEqual:fuzzyKey] && NSEqualRanges(restored->textView->selection, NSMakeRange(1, 2)), "restoration resolves duplicate occurrence and caret after completion");
        NSMutableDictionary *legacy = [[state mutableCopy] autorelease]; [legacy removeObjectForKey:@"searchMode"];
        [restored restoreBrowserWindowState:legacy];
        Check([[restored searchMode] isEqual:@"exact"] && [restored->notationController resultCount] == 2, "mode-less restoration is Exact");
        [fuzzyKey release];

        Pending(controller, @"copper"); [controller revealNote:road options:0];
        Check([[session searchString] isEqual:@"copper"] && controller->pendingSearchReveal != nil, "pending single reveal preserves query until membership completes");
        controller->window->key = NO; Complete(controller);
        Check([[session searchString] isEqual:@""] && controller->currentNote == road, "single reveal clears excluded query in a background browser");
        controller->window->key = YES;

        // Regression witness: resigning the key window preserves its field
        // editor. Run the actual resignation handler before completion.
        Pending(controller, @"key-loss-zero"); [controller performSearchReturn];
        NSUInteger beforeKeyLoss = controller->creations;
        controller->window->key = NO;
        [controller windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:controller->window]];
        PrintState(@"key-loss-before-completion", controller); Complete(controller); PrintState(@"key-loss-after-completion", controller);
        Check(controller->creations == beforeKeyLoss + (NV_REVIEW_EXPECT_FIXED ? 0 : 1),
              NV_REVIEW_EXPECT_FIXED ? "deferred zero Return is canceled by key-window focus loss" : "WITNESS: deferred zero Return creates after key-window focus loss");

        controller->window->key = YES; Pending(controller, @"key-loss-return-zero"); [controller performSearchReturn];
        NSUInteger beforeKeyReturn = controller->creations;
        controller->window->key = NO;
        [controller windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:controller->window]];
        controller->window->key = YES; Complete(controller); PrintState(@"key-loss-and-return", controller);
        Check(controller->creations == beforeKeyReturn + (NV_REVIEW_EXPECT_FIXED ? 0 : 1),
              NV_REVIEW_EXPECT_FIXED ? "deferred zero Return stays canceled after a key-window round trip" : "WITNESS: a key-window round trip does not cancel deferred zero Return");

        // Regression witness: plural Reveal still routes query clearing through
        // cancelOperation:, which intentionally ignores non-key windows.
        controller->window->key = YES; Pending(controller, @"copper");
        [controller notation:(id)session revealNotes:@[road, body, road]];
        controller->window->key = NO;
#if NV_REVIEW_EXPECT_FIXED
        [controller windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:controller->window]];
        Check([[controller->pendingSearchReveal objectForKey:@"notes"] count] == 2 && !controller->searchAutocompletePending,
              "key resignation preserves unique plural Reveal targets and cancels autocomplete");
#endif
        Complete(controller); PrintState(@"background-plural-reveal", controller);
        NSIndexSet *revealed = [session indexesOfNotes:@[road, body]];
        if (NV_REVIEW_EXPECT_FIXED) {
            NSArray *selectedNotes = [session notesAtIndexes:[controller->notesTableView selectedRowIndexes]];
            Check([[session searchString] isEqual:@""] && [revealed count] == 2 && [selectedNotes count] == 2 &&
                  [[NSSet setWithArray:selectedNotes] isEqualToSet:[NSSet setWithArray:@[road, body]]],
                  "plural Reveal selects all target notes after its browser resigns key");
        } else {
            Check([[session searchString] isEqual:@"copper"] && [revealed count] == 1 &&
                  [[session notesAtIndexes:[controller->notesTableView selectedRowIndexes]] isEqual:@[body]],
                  "WITNESS: plural Reveal loses the excluded target after its browser resigns key");
        }

#if NV_REVIEW_EXPECT_FIXED
        Pending(controller, @"road"); Complete(controller);
        NSUInteger backgroundFocuses = controller->bodyFocuses;
        [controller notation:(id)session revealNotes:@[road, body, road]];
        Check([[session searchString] isEqual:@"road"] && [[session notesAtIndexes:[controller->notesTableView selectedRowIndexes]] count] == 2 &&
              ![controller->window isKeyWindow] && controller->bodyFocuses == backgroundFocuses,
              "duplicate plural Reveal keeps an inclusive query and does not activate a background browser");
        controller->window->key = YES; Pending(controller, @"Rivet");
        Check(controller->searchAutocompletePending, "typed fuzzy query has transient autocomplete intent");
        controller->window->key = NO;
        [controller windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:controller->window]];
        controller->window->key = YES;
        Check(!controller->searchAutocompletePending, "autocomplete stays canceled after leaving and returning to the browser");
        Complete(controller);
#endif

        controller->window->key = YES; Pending(controller, @"mutation-zero"); [controller performSearchReturn];
        NSUInteger beforeMutation = controller->creations;
        [session invalidateSearch]; [session refilterNotes]; Complete(controller);
        Check(controller->creations == beforeMutation && controller->pendingSearchReturnQuery == nil, "request invalidation cancels deferred Return");

        Pending(controller, @"closure-zero"); [controller performSearchReturn];
        NSUInteger beforeClosure = controller->creations;
        [controller windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:controller->window]];
        Check(controller->closed && controller->pendingSearchReturnQuery == nil && ![session searchResultsAreCurrent], "actual closure clears pending Return and invalidates membership");
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        Check(controller->creations == beforeClosure && ClosedWindows == 1, "closed browser does not run deferred creation");

        StateController *switched = Controller(library, service); Pending(switched, @"switch-zero"); [switched performSearchReturn];
        TestLibrary *replacement = [[[TestLibrary alloc] initWithNotes:@[Note(@"fresh", @"fresh body")]] autorelease];
        NVSearchService *newService = [[[NVSearchService alloc] init] autorelease]; Capture(newService, replacement); ActiveSearchService = newService;
        [switched attachLibrary:(id)replacement finishingOldLibrary:YES]; Complete(switched);
        Check(switched->pendingSearchReturnQuery == nil && switched->creations == 0 && [switched sharedNotationController] == (id)replacement, "actual library attachment cannot carry old Return into new library");

        StateController *failed = Controller(library, nil); [failed searchForString:@"unavailable-search" mode:@"fuzzy"];
        [failed performSearchReturn];
        Check([failed->notationController searchError] != nil && ![failed->notationController searchResultsAreCurrent] &&
              failed->creations == 0 && failed->pendingSearchReturnQuery == nil, "failed result cannot authorize creation or defer Return");

        [newService invalidate];
        [service invalidate];
        printf("STATE REVIEW: %lu checks passed\n", (unsigned long)Checks);
    }
    return 0;
}
