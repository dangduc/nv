#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "NoteAttributeColumn.h"
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "NSString_NV.h"
#import "NVSearchService.h"
#import "NotesTableView.h"

@interface NSObject (NVBrowserSessionOwner)
- (NoteObject *)selectedNoteObject;
- (BOOL)horizontalLayout;
- (void)performLibraryInvocation:(NSInvocation *)invocation fromBrowser:(id)browser;
- (void)browserSessionSearchStateDidChange:(NVBrowserSession *)session;
- (void)browserSessionSearchDidComplete:(NVBrowserSession *)session;
@end

@interface NVBrowserSession ()
- (void)rebuildSingleRows;
- (void)rebuildRowIndexes;
- (void)notifySearchStateChanged;
- (void)beginFuzzySearchKeepingCurrentNote:(BOOL)keepCurrent;
- (void)publishFuzzyResult:(NVSearchResult *)result;
- (void)publishDeferredSearchResult;
- (void)updateExcerptRowsInTable:(NSTableView *)table;
- (void)startNextExcerpt;
@end

// The table's C callbacks and inline editors continue to receive NoteObjects.
// Occurrence metadata lives beside this projection, never behind a model cast.
@interface NVBrowserListDataSource : FastListDataSource {
    NVBrowserSession *session;
}
- (id)initWithSession:(NVBrowserSession *)browser;
@end
@implementation NVBrowserListDataSource
- (id)initWithSession:(NVBrowserSession *)browser {
    if ((self = [super init])) session = browser;
    return self;
}
- (NSArray *)objectsAtFilteredIndexes:(NSIndexSet *)indexes { return [session notesAtIndexes:indexes]; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return row >= 0 && (NSUInteger)row < [self count] ? [super tableView:table objectValueForTableColumn:column row:row] : nil;
}
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NoteObject *editingNote = [(NotesTableView *)table noteForInlineEditAtRow:row inSession:session];
    if (editingNote) {
        SEL setter = [(NotesTableView *)table attributeSetterForColumn:(NoteAttributeColumn *)column];
        if (setter) [editingNote performSelector:setter withObject:value];
    } else if (![(NotesTableView *)table hasInlineEditTarget] && [session searchResultsAreCurrent] && row >= 0 && (NSUInteger)row < [self count])
        [super tableView:table setObjectValue:value forTableColumn:column row:row];
}
@end

static NSData *NVBrowserNoteUUID(NoteObject *note) {
    return [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
}
static NSString *NVBrowserRowKey(NoteObject *note, NSString *kind) {
    const unsigned char *bytes = (const unsigned char *)[note uniqueNoteIDBytes];
    const char *digits = "0123456789abcdef";
    char hex[33];
    for (NSUInteger i = 0; i < sizeof(CFUUIDBytes); i++) { hex[i * 2] = digits[bytes[i] >> 4]; hex[i * 2 + 1] = digits[bytes[i] & 15]; }
    hex[32] = 0;
    return [NSString stringWithFormat:@"%@:%s", kind, hex];
}

static NSArray *NVSearchTerms(NSString *query) {
    NSMutableArray *terms = [NSMutableArray array];
    NSMutableString *term = [NSMutableString string];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" :\t\r\n"];
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < [query length]; i++) {
        unichar c = [query characterAtIndex:i];
        if (c == '"' || (!quoted && [separators characterIsMember:c])) {
            if ([term length]) { [terms addObject:[[term copy] autorelease]]; [term setString:@""]; }
            if (c == '"') quoted = !quoted;
        } else {
            [term appendFormat:@"%C", c];
        }
    }
    if ([term length]) [terms addObject:term];
    return terms;
}

static BOOL NVNoteMatchesTerms(NoteObject *note, NSArray *terms) {
    // Search positions are local to this call, never cached on a shared note.
    for (NSString *term in terms) {
        BOOL found = NO;
        for (NSString *text in @[note->titleString ?: @"", [[note contentString] string] ?: @"", note->labelString ?: @""]) {
            if ([text rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
                found = YES;
                break;
            }
        }
        if (!found) return NO;
    }
    return YES;
}

static BOOL NVSearchRefinesTerms(NSArray *previous, NSArray *next) {
    // Compare parsed terms: changing quotes can broaden a textual prefix.
    // Every old requirement must still be implied by a new search term.
    for (NSString *oldTerm in previous) {
        BOOL constrained = NO;
        for (NSString *newTerm in next) {
            if ([newTerm rangeOfString:oldTerm options:NSCaseInsensitiveSearch].location != NSNotFound) {
                constrained = YES;
                break;
            }
        }
        if (!constrained) return NO;
    }
    return YES;
}

@implementation NVBrowserSession
- (id)initWithLibrary:(NotationController *)aLibrary {
    if ((self = [super init])) {
        library = [aLibrary retain];
        dataSource = [[NVBrowserListDataSource alloc] initWithSession:self];
        visibleNotes = [[NSMutableArray alloc] init];
        matchingNotes = [[NSMutableArray alloc] init];
        previewCache = [[NSMutableDictionary alloc] init];
        searchString = [@"" copy];
        searchMode = [@"exact" copy];
        rowKeys = [[NSMutableArray alloc] init];
        rowIndexesByKey = [[NSMutableDictionary alloc] init];
        firstRowIndexesByUUID = [[NSMutableDictionary alloc] init];
        excerptPositions = [[NSMutableDictionary alloc] init];
        excerptQueue = [[NSMutableArray alloc] init];
        excerptOwner = [[NSObject alloc] init];
        excerptVisibleRows = NSMakeRange(NSNotFound, 0);
        resultsCurrent = YES;
        reverseSorted = [[GlobalPrefs defaultPrefs] tableIsReverseSorted];
        [self refilterNotes];
    }
    return self;
}
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [searchService cancelRequestsForOwner:self];
    [searchService release];
    [searchResult release];
    [deferredSearchResult release];
    [searchMode release];
    [searchError release];
    [rowKeys release];
    [rowIndexesByKey release];
    [firstRowIndexesByUUID release];
    [excerptPositions release];
    [excerptQueue release];
    [excerptOwner release];
    [activeExcerptKey release];
    [library release];
    [dataSource release];
    [visibleNotes release];
    [matchingNotes release];
    [searchTerms release];
    [previewCache release];
    [searchString release];
    [sortColumn release];
    [super dealloc];
}
- (NotationController *)library { return library; }
- (id)delegate { return delegate; }
- (void)setDelegate:(id)aDelegate {
    delegate = aDelegate;
    if (!delegate) { excerptTable = nil; [self invalidateSearch]; }
}
- (NSString *)searchString { return searchString; }
- (NSString *)searchMode { return searchMode; }
- (NSUInteger)searchGeneration { return searchGeneration; }
- (BOOL)searchPending { return searchPending; }
- (NSError *)searchError { return searchError; }
- (BOOL)hasSearchTerms { return searchHasTerms; }
- (NSUInteger)resultCount { return [self searchResultsAreCurrent] ? resultCount : 0; }
- (NSUInteger)distinctResultNoteCount { return [self searchResultsAreCurrent] ? distinctResultNoteCount : 0; }
- (NVSearchResult *)searchResult { return [self searchResultsAreCurrent] ? searchResult : nil; }
- (BOOL)searchResultsAreCurrent {
    if (compositionSuspended || !resultsCurrent) return NO;
    return !([searchMode isEqualToString:@"fuzzy"] && [self hasSearchTerms]) ||
        [searchService isRequestCurrent:serviceRequestID forOwner:self];
}
- (void)notifySearchStateChanged {
    if ([delegate respondsToSelector:@selector(browserSessionSearchStateDidChange:)])
        [delegate browserSessionSearchStateDidChange:self];
}
- (void)invalidateSearch {
    searchGeneration++;
    [searchService cancelRequestsForOwner:self];
    [excerptPositions removeAllObjects];
    [excerptQueue removeAllObjects];
    [activeExcerptKey release]; activeExcerptKey = nil;
    serviceRequestID = 0;
    [searchResult release]; searchResult = nil;
    [deferredSearchResult release]; deferredSearchResult = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(publishDeferredSearchResult) object:nil];
    [searchError release]; searchError = nil;
    searchPending = compositionSuspended || ([searchMode isEqualToString:@"fuzzy"] && [self hasSearchTerms]);
    resultsCurrent = !searchPending;
    [self notifySearchStateChanged];
}
- (void)setSearchService:(NVSearchService *)service {
    if (searchService == service) return;
    [self invalidateSearch];
    [searchService release]; searchService = [service retain];
    [self refilterNotes];
}
- (void)setSearchMode:(NSString *)mode {
    NSString *next = [mode isEqualToString:@"fuzzy"] ? @"fuzzy" : @"exact";
    if ([searchMode isEqualToString:next]) return;
    [searchMode release]; searchMode = [next copy];
    [self refilterNotes];
}
- (void)suspendSearchForComposition:(BOOL)suspended {
    if (compositionSuspended == suspended) return;
    compositionSuspended = suspended;
    [self invalidateSearch];
    if (!suspended) [self refreshKeepingCurrentNote:NO];
}
- (NSString *)rowKeyAtIndex:(NSUInteger)index { return index < [rowKeys count] ? [rowKeys objectAtIndex:index] : nil; }
- (NSArray *)rowKeysAtIndexes:(NSIndexSet *)indexes {
    NSMutableArray *keys = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        NSString *key = [self rowKeyAtIndex:index];
        if (key) [keys addObject:key];
    }];
    return keys;
}
- (NSUInteger)indexForRowKey:(NSString *)key {
    if (![key isKindOfClass:[NSString class]]) return NSNotFound;
    NSNumber *found = [rowIndexesByKey objectForKey:key];
    if (found) return [found unsignedIntegerValue];
    NSRange separator = [key rangeOfString:@":"];
    if (separator.location == NSNotFound) return NSNotFound;
    NSString *suffix = [key substringFromIndex:separator.location];
    found = [firstRowIndexesByUUID objectForKey:suffix];
    return found ? [found unsignedIntegerValue] : NSNotFound;
}
- (NSIndexSet *)indexesForRowKeys:(NSArray *)keys {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSString *key in keys) {
        NSUInteger index = [self indexForRowKey:key];
        if (index != NSNotFound) [indexes addIndex:index];
    }
    return indexes;
}
- (NSString *)matchKindAtIndex:(NSUInteger)index {
    NSString *key = [self rowKeyAtIndex:index];
    NSRange separator = [key rangeOfString:@":"];
    return key && separator.location != NSNotFound ? [key substringToIndex:separator.location] : nil;
}
- (NSString *)accessibilityDescriptionForRow:(NSUInteger)index {
    NSString *kind = [self matchKindAtIndex:index];
    if ([kind isEqualToString:@"title"]) return NSLocalizedString(@"Title match", nil);
    if ([kind isEqualToString:@"fuzzy"]) return NSLocalizedString(@"Fuzzy match", nil);
    if ([kind isEqualToString:@"retained"]) return NSLocalizedString(@"Current note outside search results", nil);
    return @"";
}
- (void)rebuildSingleRows {
    [rowKeys removeAllObjects];
    NSHashTable *members = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NoteObject *note in matchingNotes) [members addObject:note];
    for (NoteObject *note in visibleNotes)
        [rowKeys addObject:NVBrowserRowKey(note, [members containsObject:note] ? @"exact" : @"retained")];
    [self rebuildRowIndexes];
}
- (void)rebuildRowIndexes {
    [rowIndexesByKey removeAllObjects];
    [firstRowIndexesByUUID removeAllObjects];
    for (NSUInteger index = 0; index < [rowKeys count]; index++) {
        NSString *key = [rowKeys objectAtIndex:index];
        NSNumber *value = [NSNumber numberWithUnsignedInteger:index];
        [rowIndexesByKey setObject:value forKey:key];
        NSString *uuid = [key substringFromIndex:[key rangeOfString:@":"].location];
        if (![firstRowIndexesByUUID objectForKey:uuid]) [firstRowIndexesByUUID setObject:value forKey:uuid];
    }
}
- (void)beginFuzzySearchKeepingCurrentNote:(BOOL)keepCurrent {
    keepEditorForRequest = keepCurrent;
    candidatesValid = NO;
    [searchResult release]; searchResult = nil;
    [searchError release]; searchError = nil;
    resultsCurrent = NO;
    searchPending = YES;
    [self notifySearchStateChanged];
    if (!searchService) {
        searchPending = NO;
        searchError = [[NSError errorWithDomain:@"NVBrowserSearch" code:1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Search is unavailable. Retry after the library opens.", nil)}] retain];
        [self notifySearchStateChanged];
        return;
    }
    NSUInteger generation = searchGeneration;
    serviceRequestID = [searchService requestForOwner:self query:searchString completion:^(NVSearchResult *result, NSError *error) {
        if (generation != searchGeneration || compositionSuspended ||
            ![searchService isRequestCurrent:serviceRequestID forOwner:self]) return;
        if (error || !result) {
            searchPending = NO;
            resultsCurrent = NO;
            [searchError release];
            searchError = [error retain];
            [self notifySearchStateChanged];
            if ([delegate respondsToSelector:@selector(browserSessionSearchDidComplete:)]) [delegate browserSessionSearchDidComplete:self];
            return;
        }
        if ([result requestID] != serviceRequestID) return;
        [deferredSearchResult release]; deferredSearchResult = [result retain];
        [self publishDeferredSearchResult];
    }];
}
- (void)publishDeferredSearchResult {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:_cmd object:nil];
    if (!deferredSearchResult || compositionSuspended ||
        ![searchService isRequestCurrent:[deferredSearchResult requestID] forOwner:self]) return;
    if (delegate && ![delegate notationListShouldChange:(id)self]) {
        [self performSelector:_cmd withObject:nil afterDelay:0.2];
        return;
    }
    NVSearchResult *result = [[deferredSearchResult retain] autorelease];
    [deferredSearchResult release]; deferredSearchResult = nil;
    [self publishFuzzyResult:result];
    if ([self searchResultsAreCurrent] && [delegate respondsToSelector:@selector(browserSessionSearchDidComplete:)])
        [delegate browserSessionSearchDidComplete:self];
}
- (void)publishFuzzyResult:(NVSearchResult *)result {
    if (refreshing || !result || compositionSuspended ||
        ![searchService isRequestCurrent:[result requestID] forOwner:self]) return;
    NSUInteger generation = searchGeneration;
    NSDictionary *notesByUUID;
    NSMutableDictionary *lookup = [NSMutableDictionary dictionary];
    for (NoteObject *note in [library allNotes]) [lookup setObject:note forKey:NVBrowserNoteUUID(note)];
    notesByUUID = lookup;
    NSMutableArray *titles = [NSMutableArray array], *fuzzy = [NSMutableArray array];
    for (NSData *uuid in [result titleNoteUUIDs]) { NoteObject *note = [notesByUUID objectForKey:uuid]; if (note) [titles addObject:note]; }
    for (NSData *uuid in [result fuzzyNoteUUIDs]) { NoteObject *note = [notesByUUID objectForKey:uuid]; if (note) [fuzzy addObject:note]; }
    if ([titles count] != [[result titleNoteUUIDs] count] || [fuzzy count] != [[result fuzzyNoteUUIDs] count]) {
        resultsCurrent = NO;
        searchPending = NO;
        [searchError release];
        searchError = [[NSError errorWithDomain:@"NVBrowserSearch" code:2 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"The notes changed before search finished. Retry the search.", nil)}] retain];
        [self notifySearchStateChanged];
        return;
    }
    [self sortNotes:titles];
    refreshing = YES;
    [delegate notationListMightChange:(id)self];
    // Delegate hooks can commit edits or replace the query. Fence again before publication.
    if (generation != searchGeneration || ![searchService isRequestCurrent:[result requestID] forOwner:self]) { refreshing = NO; return; }
    NoteObject *current = keepEditorForRequest ? [delegate selectedNoteObject] : nil;
    [visibleNotes setArray:titles]; [visibleNotes addObjectsFromArray:fuzzy];
    [rowKeys removeAllObjects];
    for (NoteObject *note in titles) [rowKeys addObject:NVBrowserRowKey(note, @"title")];
    for (NoteObject *note in fuzzy) [rowKeys addObject:NVBrowserRowKey(note, @"fuzzy")];
    resultCount = [visibleNotes count];
    NSMutableSet *unique = [NSMutableSet set];
    for (NoteObject *note in visibleNotes) [unique addObject:NVBrowserNoteUUID(note)];
    distinctResultNoteCount = [unique count];
    if (current && [lookup objectForKey:NVBrowserNoteUUID(current)] == current && [visibleNotes indexOfObjectIdenticalTo:current] == NSNotFound) {
        [visibleNotes addObject:current]; [rowKeys addObject:NVBrowserRowKey(current, @"retained")];
    }
    [self rebuildRowIndexes];
    [matchingNotes removeAllObjects];
    [dataSource fillArrayFromArray:visibleNotes];
    [searchResult autorelease]; searchResult = [result retain];
    searchPending = NO;
    resultsCurrent = YES;
    [previewCache removeAllObjects];
    [delegate notationListDidChange:(id)self];
    refreshing = NO;
    [self notifySearchStateChanged];
}
- (void)requestSourceHighlightsForRow:(NSUInteger)index completion:(void (^)(NSArray *, NSString *))completion {
    if (!completion || ![self searchResultsAreCurrent]) return;
    NoteObject *note = [self noteObjectAtFilteredIndex:index];
    if (!note) return;
    if (![[self matchKindAtIndex:index] isEqualToString:@"fuzzy"]) {
        completion(@[], [[note contentString] string]);
        return;
    }
    NSUInteger generation = searchGeneration;
    NSString *key = [self rowKeyAtIndex:index];
    [searchService requestPositionsForNoteUUID:NVBrowserNoteUUID(note) requestID:serviceRequestID owner:self completion:^(NVSearchPositions *positions, NSError *error) {
        if (!error && positions && generation == searchGeneration && [self searchResultsAreCurrent] &&
            [[self rowKeyAtIndex:index] isEqualToString:key]) completion([positions sourceRanges], [[positions snapshot] source]);
    }];
}
- (id)notesListDataSource { return dataSource; }
- (id)labelsListDataSource { return [library labelsListDataSource]; }
- (NSUInteger)totalNoteCount { return [library totalNoteCount]; }
- (NSArray *)notesAtIndexes:(NSIndexSet *)indexes {
    if (![self searchResultsAreCurrent]) return @[];
    NSMutableArray *notes = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        NoteObject *note = [self noteObjectAtFilteredIndex:index];
        if (!note) return;
        NSData *uuid = NVBrowserNoteUUID(note);
        if (![seen containsObject:uuid]) { [seen addObject:uuid]; [notes addObject:note]; }
    }];
    return notes;
}
- (NSUInteger)indexInFilteredListForNoteIdenticalTo:(NoteObject *)note { return [dataSource indexOfObjectIdenticalTo:note]; }
- (NoteObject *)noteObjectAtFilteredIndex:(NSUInteger)index { return index < [visibleNotes count] ? [visibleNotes objectAtIndex:index] : nil; }
- (NSIndexSet *)indexesOfNotes:(NSArray *)notes {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NoteObject *note in notes) {
        NSUInteger index = [visibleNotes indexOfObjectIdenticalTo:note];
        if (index != NSNotFound) [indexes addIndex:index];
    }
    return indexes;
}
- (NSUInteger)preferredSelectedNoteIndex {
    if (![self searchResultsAreCurrent]) return NSNotFound;
    BOOL fuzzy = [searchMode isEqualToString:@"fuzzy"] && [self hasSearchTerms];
    if ([searchString length] && [[GlobalPrefs defaultPrefs] autoCompleteSearches]) {
        NSUInteger best = NSNotFound, length = NSUIntegerMax;
        for (NSUInteger i = 0; i < [visibleNotes count]; i++) {
            if (fuzzy && ![[self matchKindAtIndex:i] isEqualToString:@"title"]) continue;
            NSString *title = ((NoteObject *)[visibleNotes objectAtIndex:i])->titleString;
            if ([title rangeOfString:searchString options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == 0 && [title length] < length) {
                best = i;
                length = [title length];
            }
        }
        return best != NSNotFound ? best : (fuzzy && resultCount ? 0 : NSNotFound);
    }
    return NSNotFound;
}
- (void)sortNotes:(NSMutableArray *)notes {
    NSInteger (*compare)(id *, id *) = reverseSorted ? [sortColumn reverseSortFunction] : [sortColumn sortFunction];
    [notes sortUsingComparator:^NSComparisonResult(NoteObject *a, NoteObject *b) {
        id left = a, right = b;
        NSInteger result = compare ? compare(&left, &right) : 0;
        if (!result) {
            result = [a->titleString localizedCaseInsensitiveCompare:b->titleString];
            if (reverseSorted) result = -result;
        }
        if (!result) result = memcmp([a uniqueNoteIDBytes], [b uniqueNoteIDBytes], sizeof(CFUUIDBytes));
        return result < 0 ? NSOrderedAscending : result > 0 ? NSOrderedDescending : NSOrderedSame;
    }];
}
- (void)sortVisibleNotes {
    [self sortNotes:matchingNotes];
    if ([visibleNotes count] == [matchingNotes count]) [visibleNotes setArray:matchingNotes];
    else [self sortNotes:visibleNotes];
    [self rebuildSingleRows];
    [dataSource fillArrayFromArray:visibleNotes];
}
- (void)refreshKeepingCurrentNote:(BOOL)keepCurrent {
    if (refreshing || compositionSuspended) return;
    if ([searchMode isEqualToString:@"fuzzy"] && [self hasSearchTerms]) {
        [self beginFuzzySearchKeepingCurrentNote:keepCurrent];
        return;
    }
    refreshing = YES;
    [delegate notationListMightChange:(id)self];
    NSArray *terms = NVSearchTerms(searchString);
    BOOL refining = candidatesValid && NVSearchRefinesTerms(searchTerms, terms);
    NSArray *candidates = refining ? [[matchingNotes copy] autorelease] : [library allNotes];
    NoteObject *current = keepCurrent ? [delegate selectedNoteObject] : nil;
    [matchingNotes removeAllObjects];
    for (NoteObject *note in candidates) {
        if (NVNoteMatchesTerms(note, terms)) [matchingNotes addObject:note];
    }
    // Filtering a sorted candidate list preserves its order.
    if (!refining) [self sortNotes:matchingNotes];
    [visibleNotes setArray:matchingNotes];
    // A pinned editor row is display state, never a search candidate.
    if (current && [candidates indexOfObjectIdenticalTo:current] != NSNotFound &&
        [matchingNotes indexOfObjectIdenticalTo:current] == NSNotFound) {
        [visibleNotes addObject:current];
        [self sortNotes:visibleNotes];
    }
    [self rebuildSingleRows];
    [dataSource fillArrayFromArray:visibleNotes];
    resultCount = [matchingNotes count];
    distinctResultNoteCount = resultCount;
    searchPending = NO;
    resultsCurrent = YES;
    [searchTerms release];
    searchTerms = [terms copy];
    candidatesValid = YES;
    [previewCache removeAllObjects];
    [delegate notationListDidChange:(id)self];
    refreshing = NO;
    [self notifySearchStateChanged];
}
- (void)libraryDidChange {
    candidatesValid = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:_cmd object:nil];
    BOOL fuzzy = [searchMode isEqualToString:@"fuzzy"] && [self hasSearchTerms];
    if (fuzzy && [searchService isRequestCurrent:serviceRequestID forOwner:self]) {
        // Font, preview, and repeated model notifications do not create a new search identity.
        [previewCache removeAllObjects];
        if ([self searchResultsAreCurrent]) {
            if (delegate && ![delegate notationListShouldChange:(id)self]) [self performSelector:_cmd withObject:nil afterDelay:0.2];
            else [self publishFuzzyResult:searchResult];
        }
        return;
    }
    if (serviceRequestID || (!fuzzy && !compositionSuspended)) [self invalidateSearch];
    if (delegate && ![delegate notationListShouldChange:(id)self]) {
        [self performSelector:_cmd withObject:nil afterDelay:0.2];
        return;
    }
    [self refreshKeepingCurrentNote:YES];
}
- (void)refilterNotes { candidatesValid = NO; [self invalidateSearch]; [self refreshKeepingCurrentNote:NO]; }
- (BOOL)filterNotesFromString:(NSString *)string {
    if ([searchString isEqualToString:string ?: @""] && [searchMode isEqualToString:@"fuzzy"] &&
        [self hasSearchTerms] && [searchService isRequestCurrent:serviceRequestID forOwner:self]) return YES;
    NSString *nextString = [(string ?: @"") copy];
    [searchString release];
    searchString = nextString;
    searchHasTerms = [NVSearchTerms(searchString) count] != 0;
    [self invalidateSearch];
    [self refreshKeepingCurrentNote:NO];
    return YES;
}
- (BOOL)filterNotesFromUTF8String:(const char *)string forceUncached:(BOOL)force {
    if (force) { candidatesValid = NO; [self invalidateSearch]; }
    return [self filterNotesFromString:string ? [NSString stringWithUTF8String:string] : @""];
}
- (NoteAttributeColumn *)sortColumn { return sortColumn; }
- (BOOL)reverseSorted { return reverseSorted; }
- (void)setSortColumn:(NoteAttributeColumn *)column { [self setSortColumn:column reversed:reverseSorted]; }
- (void)setSortColumn:(NoteAttributeColumn *)column reversed:(BOOL)reversed {
    [sortColumn autorelease];
    sortColumn = [column retain];
    reverseSorted = reversed;
    [self sortAndRedisplayNotes];
}
- (void)sortAndRedisplayNotes {
    if ([searchMode isEqualToString:@"fuzzy"] && [self hasSearchTerms]) {
        if ([self searchResultsAreCurrent]) [self libraryDidChange];
        return;
    }
    [delegate notationListMightChange:(id)self];
    [self sortVisibleNotes];
    [delegate notationListDidChange:(id)self];
}
- (void)resortAllNotes { [self sortAndRedisplayNotes]; }
- (void)removeNotesAtIndexes:(NSIndexSet *)indexes { [library removeNotes:[self notesAtIndexes:indexes]]; }
- (void)regenerateAllPreviews { [previewCache removeAllObjects]; }
- (void)regeneratePreviewsForColumn:(NSTableColumn *)column visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force {
    [previewCache removeAllObjects];
}
- (void)updateExcerptRowsInTable:(NSTableView *)table {
    if (![self searchResultsAreCurrent] || ![searchMode isEqualToString:@"fuzzy"] || ![self hasSearchTerms]) return;
    NSRange range = [table rowsInRect:[table visibleRect]];
    if (excerptTable != table || !NSEqualRanges(excerptVisibleRows, range)) [previewCache removeAllObjects];
    excerptTable = table;
    excerptVisibleRows = range;
    NSUInteger end = range.location != NSNotFound ? MIN(NSMaxRange(range), [rowKeys count]) : 0;
    NSMutableSet *wanted = [NSMutableSet set];
    [excerptQueue removeAllObjects];
    for (NSUInteger index = range.location; index < end; index++) {
        if (![[self matchKindAtIndex:index] isEqualToString:@"fuzzy"]) continue;
        NSString *key = [self rowKeyAtIndex:index];
        [wanted addObject:key];
        if (![excerptPositions objectForKey:key] && ![activeExcerptKey isEqualToString:key]) [excerptQueue addObject:key];
    }
    for (NSString *key in [[[excerptPositions allKeys] copy] autorelease])
        if (![wanted containsObject:key]) [excerptPositions removeObjectForKey:key];
    if (activeExcerptKey && ![wanted containsObject:activeExcerptKey]) {
        [searchService cancelPositionRequestsForOwner:excerptOwner];
        [activeExcerptKey release]; activeExcerptKey = nil;
    }
    [self startNextExcerpt];
}
- (void)startNextExcerpt {
    if (activeExcerptKey || ![excerptQueue count] || !excerptTable || ![self searchResultsAreCurrent]) return;
    activeExcerptKey = [[excerptQueue objectAtIndex:0] copy];
    [excerptQueue removeObjectAtIndex:0];
    NSUInteger index = [self indexForRowKey:activeExcerptKey];
    NoteObject *note = [self noteObjectAtFilteredIndex:index];
    if (!note) { [activeExcerptKey release]; activeExcerptKey = nil; [self startNextExcerpt]; return; }
    NSUInteger generation = searchGeneration;
    NSString *key = activeExcerptKey;
    NSTableView *table = excerptTable;
    [searchService requestPositionsForNoteUUID:NVBrowserNoteUUID(note) requestID:serviceRequestID owner:self positionOwner:excerptOwner completion:^(NVSearchPositions *positions, NSError *error) {
        if (generation != searchGeneration || ![self searchResultsAreCurrent] || ![activeExcerptKey isEqualToString:key]) return;
        [activeExcerptKey release]; activeExcerptKey = nil;
        NSUInteger row = [self indexForRowKey:key];
        NSRange visible = [table rowsInRect:[table visibleRect]];
        if (row != NSNotFound && NSLocationInRange(row, visible)) {
            // Mark a failed position lookup too, so repainting cannot start an endless retry loop.
            [excerptPositions setObject:positions ?: (id)[NSNull null] forKey:key];
            [previewCache removeAllObjects];
            NSInteger column = [table columnWithIdentifier:NoteTitleColumnString];
            if (column >= 0) [table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)column]];
        }
        [self startNextExcerpt];
    }];
}
- (id)previewForRow:(NSUInteger)index inTable:(NSTableView *)table {
    NoteObject *note = [self noteObjectAtFilteredIndex:index];
    if (!note) return @"";
    NSString *context = [self accessibilityDescriptionForRow:index];
    if (![context length]) return [self previewForNote:note inTable:table];
    GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
    if ([prefs tableColumnsShowPreview]) [self updateExcerptRowsInTable:table];
    NSTableColumn *column = [table tableColumnWithIdentifier:NoteTitleColumnString];
    CGFloat width = MAX(1.0, [column width] - [NSScroller scrollerWidth]);
    NSString *key = [NSString stringWithFormat:@"row:%@:%lu:%.1f:%d:%d", [self rowKeyAtIndex:index], (unsigned long)searchGeneration,
        width, [delegate horizontalLayout], [prefs tableColumnsShowPreview]];
    id preview = [previewCache objectForKey:key];
    if (preview) return preview;
    NSString *source = [[note contentString] string] ?: @"";
    id cachedPositions = [excerptPositions objectForKey:[self rowKeyAtIndex:index]];
    NSUInteger first = 0;
    if (cachedPositions && cachedPositions != [NSNull null]) {
        NVSearchPositions *positions = cachedPositions;
        source = [[positions snapshot] source];
        NSArray *ranges = [positions sourceRanges];
        if ([ranges count]) first = [[ranges objectAtIndex:0] rangeValue].location;
    }
    NSUInteger start = first > 45 ? first - 45 : 0;
    NSRange excerpt = [source rangeOfComposedCharacterSequencesForRange:NSMakeRange(start, MIN((NSUInteger)220, [source length] - start))];
    source = [NSString stringWithFormat:@"%@%@%@", excerpt.location ? @"…" : @"", [source substringWithRange:excerpt], NSMaxRange(excerpt) < [source length] ? @"…" : @""];
    // Match context is metadata beside the real title. It never becomes a note or an editable title.
    if ([prefs tableColumnsShowPreview]) {
        NSAttributedString *body = [[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ · %@", context, source]] autorelease];
        preview = [delegate horizontalLayout] ? [note->titleString attributedMultiLinePreviewFromBodyText:body upToWidth:width intrusionWidth:0] :
            [note->titleString attributedSingleLinePreviewFromBodyText:body upToWidth:width];
    } else {
        NSMutableAttributedString *title = [[[note->titleString attributedSingleLineTitle] mutableCopy] autorelease];
        NSAttributedString *label = [[[NSAttributedString alloc] initWithString:[@"  · " stringByAppendingString:context]
            attributes:@{NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}] autorelease];
        [title appendAttributedString:label];
        preview = title;
    }
    if (preview) [previewCache setObject:preview forKey:key];
    return preview ?: note->titleString;
}
- (id)previewForNote:(NoteObject *)note inTable:(NSTableView *)table {
    GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
    NSTableColumn *column = [table tableColumnWithIdentifier:NoteTitleColumnString];
    CGFloat width = MAX(1.0, [column width] - [NSScroller scrollerWidth]);
    NSString *key = [NSString stringWithFormat:@"%p:%.1f:%d:%d", note, width, [delegate horizontalLayout], [prefs tableColumnsShowPreview]];
    id preview = [previewCache objectForKey:key];
    if (!preview) {
        if ([prefs tableColumnsShowPreview]) {
            if ([delegate horizontalLayout]) {
                CGFloat labelsWidth = ColumnIsSet(NoteLabelsColumn, [prefs tableColumnsBitmap]) ? [note sizeOfLabelBlocks].width : 0;
                preview = [note->titleString attributedMultiLinePreviewFromBodyText:[note contentString] upToWidth:width intrusionWidth:labelsWidth];
            } else {
                preview = [note->titleString attributedSingleLinePreviewFromBodyText:[note contentString] upToWidth:width];
            }
        } else {
            preview = [note->titleString attributedSingleLineTitle];
        }
        if (preview) [previewCache setObject:preview forKey:key];
    }
    return preview ?: note->titleString;
}
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [library respondsToSelector:selector];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [super methodSignatureForSelector:selector] ?: [library methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    if ([library respondsToSelector:[invocation selector]]) {
        id coordinator = [library delegate];
        if ([coordinator respondsToSelector:@selector(performLibraryInvocation:fromBrowser:)]) {
            [coordinator performLibraryInvocation:invocation fromBrowser:delegate];
        } else {
            [invocation invokeWithTarget:library];
        }
    } else {
        [self doesNotRecognizeSelector:[invocation selector]];
    }
}
@end
