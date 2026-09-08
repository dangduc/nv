#import <Cocoa/Cocoa.h>
#import "NVNoteEditingSession.h"

// This native probe isolates the real snapshot algorithm. Font rendering,
// link detection and parser layouts are covered by copied-app integration tests.
NSString *const NVNoteSyntaxDidChangeNotification = @"NVNoteSyntaxDidChangeNotification";
NSString *titleOfNote(id note) { return @"Snapshot fixture"; }
NSString *labelsOfNote(id note) { return @""; }
@interface GlobalPrefs : NSObject
+ (id)defaultPrefs;
- (NSDictionary*)noteBodyAttributes;
- (NSFont*)noteBodyFont;
@end
@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (NSDictionary*)noteBodyAttributes { return @{}; }
- (NSFont*)noteBodyFont { return nil; }
@end
@interface NVSourceHighlighter : NSObject
@end
@implementation NVSourceHighlighter
@end
@implementation NSMutableAttributedString (SnapshotLinks)
- (void)addLinkAttributesForRange:(NSRange)range { }
@end

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
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"BBcoreYY" attributes:@{NSUnderlineStyleAttributeName: @1}] autorelease]];
        BOOL correct = [[[session textStorage] string] isEqualToString:@"BBcoreYY"];
        BOOL preservesInterior = !observer->changedProtectedText && observer->characterEdits == 2;
        BOOL sourceOnly = [[session textStorage] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] == nil;
        NSUInteger characterEditsBeforeStyle = observer->characterEdits;
        [note setContentString:[[[NSAttributedString alloc] initWithString:@"BBcoreYY" attributes:@{NSUnderlineStyleAttributeName: @2}] autorelease]];
        BOOL ignoredStyleChange = observer->characterEdits == characterEditsBeforeStyle;
        printf("body_correct=%d edits=%lu preserves_interior=%d source_only=%d ignored_style_change=%d\n", correct, (unsigned long)observer->characterEdits, preservesInterior, sourceOnly, ignoredStyleChange);
        [[session textStorage] setDelegate:nil];
        [session close]; [observer release]; [session release]; [note release];
        return correct && preservesInterior && sourceOnly && ignoredStyleChange ? 0 : 1;
    }
}
