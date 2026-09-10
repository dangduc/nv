#import <Cocoa/Cocoa.h>

static NSUInteger Checks;
static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
    NSLog(@"PASS: %@", message);
    Checks++;
}

// This is deliberately a storage owner, rather than an NSTextView subclass.
// It prototypes the smaller ownership boundary proposed by the review.
@interface LinkDecorationOwner : NSObject {
@public
    NSTextStorage *storage;
    NSString *syntaxIdentifier;
    NSUInteger characterNotifications;
    NSUInteger attributeNotifications;
    NSRange lastEditedRange;
    NSRange lastDecoratedRange;
}
- (id)initWithTextStorage:(NSTextStorage *)textStorage syntaxIdentifier:(NSString *)syntax;
@end

@implementation LinkDecorationOwner
- (id)initWithTextStorage:(NSTextStorage *)textStorage syntaxIdentifier:(NSString *)syntax {
    if ((self = [super init])) {
        storage = [textStorage retain];
        syntaxIdentifier = [syntax copy];
        lastEditedRange = NSMakeRange(NSNotFound, 0);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storageDidProcessEditing:)
            name:NSTextStorageDidProcessEditingNotification object:storage];
    }
    return self;
}
- (void)storageDidProcessEditing:(NSNotification *)notification {
    if (!([storage editedMask] & NSTextStorageEditedCharacters)) {
        attributeNotifications++;
        return;
    }
    characterNotifications++;
    lastEditedRange = [storage editedRange];
    lastDecoratedRange = [[storage string] lineRangeForRange:lastEditedRange];

    // Small executable stand-in for AttributedPlainText's link pass. The point
    // under test is that the storage owner has the complete post-edit line and
    // syntax identity without intercepting NSTextView's edit lifecycle.
    [storage removeAttribute:NSLinkAttributeName range:lastDecoratedRange];
    NSString *line = [[storage string] substringWithRange:lastDecoratedRange];
    NSRange open = [line rangeOfString:@"[["];
    NSRange close = [line rangeOfString:@"]]"];
    if (open.location != NSNotFound && close.location != NSNotFound &&
        close.location > NSMaxRange(open)) {
        NSRange target = NSMakeRange(lastDecoratedRange.location + NSMaxRange(open),
                                    close.location - NSMaxRange(open));
        [storage addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"nvalt://find/prototype"]
                         range:target];
    }
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [storage release];
    [syntaxIdentifier release];
    [super dealloc];
}
@end

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:@"prefix [[Targ]] suffix"] autorelease];
    LinkDecorationOwner *owner = [[LinkDecorationOwner alloc] initWithTextStorage:storage syntaxIdentifier:@"plain"];

    NSRange closing = [[storage string] rangeOfString:@"]]"];
    [storage replaceCharactersInRange:NSMakeRange(closing.location, 0) withString:@"et"];
    Check([[storage string] isEqualToString:@"prefix [[Target]] suffix"],
          @"native storage applies the character insertion");
    Check(owner->characterNotifications == 1,
          @"the storage owner receives one character-edit notification");
    Check(NSEqualRanges(owner->lastEditedRange, NSMakeRange(closing.location, 2)),
          @"AppKit supplies the exact processed insertion range");
    Check(NSEqualRanges(owner->lastDecoratedRange, NSMakeRange(0, [[storage string] length])),
          @"the processed range expands to the complete affected line");
    NSRange target = [[storage string] rangeOfString:@"Target"];
    Check([[storage attribute:NSLinkAttributeName atIndex:target.location effectiveRange:NULL] isKindOfClass:[NSURL class]],
          @"the owner can restore link display attributes from that range");
    Check([owner->syntaxIdentifier isEqualToString:@"plain"],
          @"the storage owner carries the note syntax without a controller lookup");

    NSUInteger oldAttributes = owner->attributeNotifications;
    [storage addAttribute:NSForegroundColorAttributeName value:[NSColor redColor]
                    range:NSMakeRange(0, 1)];
    Check(owner->characterNotifications == 1 && owner->attributeNotifications > oldAttributes,
          @"attribute-only display changes do not masquerade as source edits");

    [storage deleteCharactersInRange:NSMakeRange(NSMaxRange(target) - 1, 1)];
    Check(owner->characterNotifications == 2 && owner->lastEditedRange.length == 0,
          @"the same boundary reports deletion without an editor override");
    Check([[storage attribute:NSLinkAttributeName atIndex:target.location effectiveRange:NULL] isKindOfClass:[NSURL class]],
          @"the owner rebuilds decoration after deletion");

    NSLog(@"OUSTERHOUT ROUND 3 RANGE PROBE PASSED (%lu checks)", (unsigned long)Checks);
    [owner release];
    [pool drain];
    return 0;
}
