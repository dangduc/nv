#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "NoteAttributeColumn.h"
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "NSString_NV.h"

@interface NSObject (NVBrowserSessionOwner)
- (NoteObject *)selectedNoteObject;
- (BOOL)horizontalLayout;
- (void)performLibraryInvocation:(NSInvocation *)invocation fromBrowser:(id)browser;
@end

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
        dataSource = [[FastListDataSource alloc] init];
        visibleNotes = [[NSMutableArray alloc] init];
        matchingNotes = [[NSMutableArray alloc] init];
        previewCache = [[NSMutableDictionary alloc] init];
        searchString = [@"" copy];
        reverseSorted = [[GlobalPrefs defaultPrefs] tableIsReverseSorted];
        [self refilterNotes];
    }
    return self;
}
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
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
- (void)setDelegate:(id)aDelegate { delegate = aDelegate; }
- (NSString *)searchString { return searchString; }
- (id)notesListDataSource { return dataSource; }
- (id)labelsListDataSource { return [library labelsListDataSource]; }
- (NSUInteger)totalNoteCount { return [library totalNoteCount]; }
- (NSArray *)notesAtIndexes:(NSIndexSet *)indexes { return [dataSource objectsAtFilteredIndexes:indexes]; }
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
    if ([searchString length] && [[GlobalPrefs defaultPrefs] autoCompleteSearches]) {
        NSUInteger best = NSNotFound, length = NSUIntegerMax;
        for (NSUInteger i = 0; i < [visibleNotes count]; i++) {
            NSString *title = ((NoteObject *)[visibleNotes objectAtIndex:i])->titleString;
            if ([title rangeOfString:searchString options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == 0 && [title length] < length) {
                best = i;
                length = [title length];
            }
        }
        return best;
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
        return result < 0 ? NSOrderedAscending : result > 0 ? NSOrderedDescending : NSOrderedSame;
    }];
}
- (void)sortVisibleNotes {
    [self sortNotes:matchingNotes];
    if ([visibleNotes count] == [matchingNotes count]) [visibleNotes setArray:matchingNotes];
    else [self sortNotes:visibleNotes];
    [dataSource fillArrayFromArray:visibleNotes];
}
- (void)refreshKeepingCurrentNote:(BOOL)keepCurrent {
    if (refreshing) return;
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
    [dataSource fillArrayFromArray:visibleNotes];
    [searchTerms release];
    searchTerms = [terms copy];
    candidatesValid = YES;
    [previewCache removeAllObjects];
    [delegate notationListDidChange:(id)self];
    refreshing = NO;
}
- (void)libraryDidChange {
    candidatesValid = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:_cmd object:nil];
    if (delegate && ![delegate notationListShouldChange:(id)self]) {
        [self performSelector:_cmd withObject:nil afterDelay:0.2];
        return;
    }
    [self refreshKeepingCurrentNote:YES];
}
- (void)refilterNotes { candidatesValid = NO; [self refreshKeepingCurrentNote:NO]; }
- (BOOL)filterNotesFromString:(NSString *)string {
    NSString *nextString = [(string ?: @"") copy];
    [searchString release];
    searchString = nextString;
    [self refreshKeepingCurrentNote:NO];
    return YES;
}
- (BOOL)filterNotesFromUTF8String:(const char *)string forceUncached:(BOOL)force {
    if (force) candidatesValid = NO;
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
