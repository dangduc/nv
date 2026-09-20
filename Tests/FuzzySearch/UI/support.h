#import "AppController.h"
#import "NVSearchService.h"
#import "NVBrowserSession.h"
#import "NotesTableView.h"
#import "NSString_NV.h"

static BOOL FuzzyAwait(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return condition();
}
static NSUInteger FuzzyRow(NVBrowserSession *session, NoteObject *note, NSString *kind) {
    for (NSUInteger i = 0; i < [[session notesListDataSource] count]; ++i)
        if ([session noteObjectAtFilteredIndex:i] == note && [[session matchKindAtIndex:i] isEqual:kind]) return i;
    return NSNotFound;
}
static NSUInteger FuzzyFieldRow(NVBrowserSession *session, NoteObject *note, NSString *field) {
    for (NSUInteger i = 0; i < [session resultCount]; ++i) {
        NVSearchMatch *match = [[session searchResult] matchForRowKey:[session rowKeyAtIndex:i]];
        if ([session noteObjectAtFilteredIndex:i] == note && [[[match line] field] isEqual:field]) return i;
    }
    return NSNotFound;
}
static void FuzzySelect(AppController *browser, NSUInteger row) {
    NotesTableView *table = [browser valueForKey:@"notesTableView"];
    [table selectRowAndScroll:row]; [browser displayContentsForNoteAtIndex:row];
}

static BOOL FuzzyRangeIsVerticallyVisible(NSTextView *editor, NSRange range) {
    NSLayoutManager *layout = [editor layoutManager];
    [layout ensureLayoutForCharacterRange:range];
    NSRange glyphs = [layout glyphRangeForCharacterRange:range actualCharacterRange:NULL];
    NSRect rect = [layout boundingRectForGlyphRange:glyphs inTextContainer:[editor textContainer]];
    rect.origin.y += [editor textContainerOrigin].y;
    NSRect visible = [editor visibleRect];
    return NSHeight(rect) > 0 && NSMinY(rect) >= NSMinY(visible) - 1 && NSMaxY(rect) <= NSMaxY(visible) + 1;
}
