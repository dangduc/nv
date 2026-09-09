#import <Cocoa/Cocoa.h>

@class NoteObject, GlobalPrefs;

/* Legacy controller retained for archive compatibility. The application uses
   BookmarksController; this controller is not an application target source. */
@interface SavedSearch : NSObject {
    NSString *searchString, *lowercaseSearchString, *searchMode, *resultRowKey;
    CFUUIDBytes uuidBytes;
    NoteObject *selectedNote;
    NSUInteger hashValue;
    BOOL needsMenuUpdate;
    id delegate;
}
- (id)initWithDictionary:(NSDictionary *)dictionary;
- (id)initWithSearchString:(NSString *)string;
- (id)initWithSearchString:(NSString *)string searchMode:(NSString *)mode;
- (NSString *)searchString;
- (NSString *)searchMode;
- (NSString *)resultRowKey;
- (NSString *)lowercaseString;
- (NSDictionary *)dictionaryRep;
- (NoteObject *)selectedNote;
- (void)setSelectedNote:(NoteObject *)note;
- (void)setSelectedNote:(NoteObject *)note resultRowKey:(NSString *)rowKey;
- (BOOL)needsMenuUpdate;
- (void)setNeedsMenuUpdate:(BOOL)value;
- (void)setDelegate:(id)delegate;
- (id)delegate;
@end

@interface SavedSearchesController : NSObject {
    NSMutableArray *searches;
    NSMutableSet *searchSet;
    NSArray *notes;
    GlobalPrefs *prefsController;
    BOOL isSelectingProgrammatically, isRestoringSearch, autosaveNotesForSavedSearches;
    IBOutlet NSTableView *searchesTableView;
    IBOutlet NSPanel *window;
    IBOutlet NSButton *addSearchButton, *removeSearchButton, *rememberLastNoteButton;
    id revealTarget, delegate;
    SEL revealAction;
}
- (id)initWithSearches:(NSArray *)array;
- (NSArray *)dictionaryReps;
- (NoteObject *)noteWithUUIDBytes:(CFUUIDBytes)bytes;
- (BOOL)restoreSavedSearch:(SavedSearch *)search;
- (BOOL)addSearchString:(NSString *)string selectedNote:(NoteObject *)note;
- (void)setLastSelectedNote:(NoteObject *)note forSearchString:(NSString *)string;
- (void)setSelectedNoteForCurrentSearch:(NoteObject *)note;
- (SavedSearch *)setNote:(NoteObject *)note forSearchString:(NSString *)string;
- (SavedSearch *)savedSearchWithString:(NSString *)string;
- (SavedSearch *)savedSearchAtIndex:(int)index;
- (NSString *)effectiveDelegateSearchString;
- (NSString *)effectiveDelegateSearchMode;
- (NSString *)effectiveDelegateResultRowKey;
- (BOOL)setSearchString:(NSString *)string atIndex:(unsigned int)index;
- (void)removeSearch:(id)sender;
- (void)setRevealTarget:(id)target selector:(SEL)selector;
- (void)setDelegate:(id)delegate;
- (id)delegate;
@end
