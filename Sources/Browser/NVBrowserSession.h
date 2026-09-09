#import <Cocoa/Cocoa.h>
#import "NotationController.h"

@class NVSearchService, NVSearchResult;

// A view of one library. This object never opens files or owns library persistence.
@interface NVBrowserSession : NSObject {
    NotationController *library;
    id delegate;
    FastListDataSource *dataSource;
    NSMutableArray *visibleNotes;
    NSMutableArray *matchingNotes;
    NSArray *searchTerms;
    NSString *searchString;
    NoteAttributeColumn *sortColumn;
    BOOL reverseSorted;
    BOOL refreshing;
    BOOL candidatesValid;
    NSMutableDictionary *previewCache;
    NVSearchService *searchService;
    NVSearchResult *searchResult;
    NVSearchResult *deferredSearchResult;
    NSMutableArray *rowKeys;
    NSMutableDictionary *rowIndexesByKey, *firstRowIndexesByUUID;
    NSString *searchMode;
    NSError *searchError;
    NSUInteger searchGeneration, serviceRequestID;
    NSUInteger resultCount, distinctResultNoteCount;
    BOOL searchPending, resultsCurrent, compositionSuspended, keepEditorForRequest, searchHasTerms;
    NSMutableDictionary *excerptPositions;
    NSMutableArray *excerptQueue;
    NSObject *excerptOwner;
    NSString *activeExcerptKey;
    NSTableView *excerptTable; // non-owning; cleared when the browser detaches
    NSRange excerptVisibleRows;
}
- (id)initWithLibrary:(NotationController *)aLibrary;
- (NotationController *)library;
- (void)setDelegate:(id)aDelegate;
- (id)delegate;
- (NSString *)searchString;
- (void)setSearchService:(NVSearchService *)service;
- (NSString *)searchMode;
- (void)setSearchMode:(NSString *)mode;
- (NSUInteger)searchGeneration;
- (BOOL)searchPending;
- (NSError *)searchError;
- (BOOL)searchResultsAreCurrent;
- (BOOL)hasSearchTerms;
- (NSUInteger)resultCount;
- (NSUInteger)distinctResultNoteCount;
- (NVSearchResult *)searchResult;
- (void)invalidateSearch;
- (void)suspendSearchForComposition:(BOOL)suspended;
// Keys identify the occurrence (kind + UUID), not the request that produced it.
- (NSString *)rowKeyAtIndex:(NSUInteger)index;
- (NSArray *)rowKeysAtIndexes:(NSIndexSet *)indexes;
- (NSUInteger)indexForRowKey:(NSString *)key;
- (NSIndexSet *)indexesForRowKeys:(NSArray *)keys;
- (NSString *)matchKindAtIndex:(NSUInteger)index;
- (NSString *)accessibilityDescriptionForRow:(NSUInteger)index;
- (id)previewForRow:(NSUInteger)index inTable:(NSTableView *)table;
- (void)requestSourceHighlightsForRow:(NSUInteger)index completion:(void (^)(NSArray *ranges, NSString *source))completion;
- (void)libraryDidChange;
- (void)refilterNotes;
- (BOOL)filterNotesFromString:(NSString *)string;
- (BOOL)filterNotesFromUTF8String:(const char *)string forceUncached:(BOOL)force;
- (id)notesListDataSource;
- (id)labelsListDataSource;
- (NSArray *)notesAtIndexes:(NSIndexSet *)indexes;
- (NSIndexSet *)indexesOfNotes:(NSArray *)notes;
- (NSUInteger)indexInFilteredListForNoteIdenticalTo:(NoteObject *)note;
- (NoteObject *)noteObjectAtFilteredIndex:(NSUInteger)index;
- (NSUInteger)preferredSelectedNoteIndex;
- (NSUInteger)totalNoteCount;
- (NoteAttributeColumn *)sortColumn;
- (void)setSortColumn:(NoteAttributeColumn *)column;
- (void)setSortColumn:(NoteAttributeColumn *)column reversed:(BOOL)reversed;
- (BOOL)reverseSorted;
- (void)sortAndRedisplayNotes;
- (void)resortAllNotes;
- (void)removeNotesAtIndexes:(NSIndexSet *)indexes;
- (id)previewForNote:(NoteObject *)note inTable:(NSTableView *)table;
- (void)regenerateAllPreviews;
- (void)regeneratePreviewsForColumn:(NSTableColumn *)column visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force;
@end
