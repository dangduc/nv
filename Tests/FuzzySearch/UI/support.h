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
static void FuzzySelect(AppController *browser, NSUInteger row) {
    NotesTableView *table = [browser valueForKey:@"notesTableView"];
    [table selectRowAndScroll:row]; [browser displayContentsForNoteAtIndex:row];
}
