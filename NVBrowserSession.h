#import <Cocoa/Cocoa.h>
#import "NotationController.h"

// A view of one library. This object never opens files or starts synchronization.
@interface NVBrowserSession : NSObject {
    NotationController *library;
    id delegate;
    FastListDataSource *dataSource;
    NSMutableArray *visibleNotes;
    NSString *searchString;
    NoteAttributeColumn *sortColumn;
    BOOL reverseSorted;
    BOOL refreshing;
    NSMutableDictionary *previewCache;
}
- (id)initWithLibrary:(NotationController *)aLibrary;
- (NotationController *)library;
- (void)setDelegate:(id)aDelegate;
- (id)delegate;
- (NSString *)searchString;
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
