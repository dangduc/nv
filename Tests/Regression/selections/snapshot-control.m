#import <Cocoa/Cocoa.h>
#import "NVNoteEditingSession.h"

@interface SnapshotNote : NSObject {
    NSMutableAttributedString *contents;
    NSUndoManager *history;
}
- (NSAttributedString *)contentString;
- (NSUndoManager *)undoManager;
- (void)setContentString:(NSAttributedString *)value;
@end
@implementation SnapshotNote
- (id)init {
    if ((self = [super init])) {
        contents = [[NSMutableAttributedString alloc] initWithString:@"AAcoreZZ"];
        history = [NSUndoManager new];
    }
    return self;
}
- (NSAttributedString *)contentString { return contents; }
- (NSUndoManager *)undoManager { return history; }
- (void)setContentString:(NSAttributedString *)value {
    [contents setAttributedString:value];
    [[NSNotificationCenter defaultCenter] postNotificationName:NVNoteContentsDidChangeNotification object:self];
}
- (void)dealloc { [contents release]; [history release]; [super dealloc]; }
@end

@interface SnapshotObserver : NSObject <NSTextStorageDelegate> {
@public
    NSUInteger characterEdits;
    BOOL changedProtectedText;
}
@end
@implementation SnapshotObserver
- (void)textStorage:(NSTextStorage *)storage didProcessEditing:(NSTextStorageEditActions)actions range:(NSRange)range changeInLength:(NSInteger)delta {
    if (actions & NSTextStorageEditedCharacters) {
        characterEdits++;
        if (NSIntersectionRange(range, NSMakeRange(2,4)).length) changedProtectedText = YES;
        printf("character edit: location=%lu length=%lu delta=%ld\n", (unsigned long)range.location, (unsigned long)range.length, (long)delta);
    }
}
@end

int main(void) {
    @autoreleasepool {
        SnapshotNote *note = [SnapshotNote new];
        NVNoteEditingSession *session = [[NVNoteEditingSession alloc] initWithNote:(id)note];
        SnapshotObserver *observer = [SnapshotObserver new];
        [[session textStorage] setDelegate:observer];
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"BBcoreYY"] autorelease]];
        BOOL correct = [[[session textStorage] string] isEqualToString:@"BBcoreYY"];
        BOOL preservesInterior = !observer->changedProtectedText && observer->characterEdits == 2;
        printf("body_correct=%d edits=%lu preserves_interior=%d\n", correct, (unsigned long)observer->characterEdits, preservesInterior);
        [[session textStorage] setDelegate:nil];
        [session close]; [observer release]; [session release]; [note release];
        return correct && preservesInterior ? 0 : 1;
    }
}
