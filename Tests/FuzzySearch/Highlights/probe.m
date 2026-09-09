#import <Cocoa/Cocoa.h>

@interface SearchEditor : NSObject {
    NSTextStorage *_storage;
}
@property NSUInteger clears;
- (id)initWithStorage:(NSTextStorage *)storage;
- (NSTextStorage *)textStorage;
- (void)removeHighlightedTerms;
@end
@implementation SearchEditor
- (id)initWithStorage:(NSTextStorage *)storage {
    if ((self = [super init])) _storage = [storage retain];
    return self;
}
- (void)dealloc { [_storage release]; [super dealloc]; }
- (NSTextStorage *)textStorage { return _storage; }
- (void)removeHighlightedTerms { ++_clears; }
@end

@interface SearchBrowser : NSObject {
@public
    SearchEditor *textView;
    NSUInteger searchHighlightGeneration;
}
- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification;
@end
@implementation SearchBrowser
#include "callback.inc"
@end

static NSUInteger checks;
static void Check(BOOL condition, const char *message) {
    ++checks;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSTextStorage *shared = [[[NSTextStorage alloc] initWithString:@"meeting"] autorelease];
        NSTextStorage *other = [[[NSTextStorage alloc] initWithString:@"other"] autorelease];
        SearchBrowser *first = [[[SearchBrowser alloc] init] autorelease];
        SearchBrowser *peer = [[[SearchBrowser alloc] init] autorelease];
        first->textView = [[[SearchEditor alloc] initWithStorage:shared] autorelease];
        peer->textView = [[[SearchEditor alloc] initWithStorage:shared] autorelease];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        for (SearchBrowser *browser in @[first, peer])
            [center addObserver:browser selector:@selector(searchSourceStorageWillProcessEditing:) name:NSTextStorageWillProcessEditingNotification object:shared];
        [shared replaceCharactersInRange:NSMakeRange(0, 0) withString:@"x"];
        Check(first->textView.clears == 1, "origin clears before a model commit");
        Check(peer->textView.clears == 1, "peer clears before a model commit");
        Check(first->searchHighlightGeneration == 1 && peer->searchHighlightGeneration == 1, "both reject old position callbacks");
        [shared addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, 1)];
        Check(first->textView.clears == 1 && peer->textView.clears == 1, "attribute-only changes preserve search state");
        [first searchSourceStorageWillProcessEditing:[NSNotification notificationWithName:NSTextStorageWillProcessEditingNotification object:other]];
        Check(first->textView.clears == 1, "unrelated storage cannot clear this browser");
        [center removeObserver:first name:NSTextStorageWillProcessEditingNotification object:shared];
        [shared replaceCharactersInRange:NSMakeRange(0, 1) withString:@"y"];
        Check(first->textView.clears == 1 && peer->textView.clears == 2, "detached browser stops observing shared edits");
        Check([[shared attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:[NSColor redColor]], "character invalidation preserves foreground attributes");
        [center removeObserver:peer];
        printf("PASS: %lu shared-source highlight checks\n", (unsigned long)checks);
    }
    return 0;
}
