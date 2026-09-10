#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

// Observe production request and completion state without replacing captures.
@interface CountingParser : NVSourceParser {
    NSLock *lock;
    NSUInteger requests;
    NSUInteger lastCount;
}
- (NSUInteger)requestCount;
- (NSUInteger)captureCount;
@end
@implementation CountingParser
- (id)initWithQueryDirectory:(NSString *)directory {
    if ((self = [super initWithQueryDirectory:directory])) lock = [[NSLock alloc] init];
    return self;
}
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)generation {
    NSArray *result = [super capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:generation];
    [lock lock]; requests++; lastCount = [result count]; [lock unlock];
    return result;
}
- (NSUInteger)requestCount { [lock lock]; NSUInteger value = requests; [lock unlock]; return value; }
- (NSUInteger)captureCount { [lock lock]; NSUInteger value = lastCount; [lock unlock]; return value; }
- (void)dealloc { [lock release]; [super dealloc]; }
@end

@interface ObservedHighlighter : NVSourceHighlighter
- (void)useParser:(CountingParser *)replacement;
- (BOOL)isAnalyzing;
@end
@implementation ObservedHighlighter
- (void)useParser:(CountingParser *)replacement { [parser release]; parser = [replacement retain]; }
- (BOOL)isAnalyzing { return analyzing; }
@end

static NSUInteger checks;
static void Check(BOOL pass, NSString *label) {
    checks++;
    if (!pass) { NSLog(@"FAIL: %@", label); exit(1); }
    NSLog(@"PASS: %@", label);
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:4];
    while (!condition() && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    return condition();
}
static void Completed(ObservedHighlighter *owner, CountingParser *parser, NSUInteger count) {
    Check(Await(^BOOL { return [parser requestCount] >= count && ![owner isAnalyzing]; }), @"production request completes and its main-thread callback runs");
    Check([parser requestCount] == count, @"one analysis serves this state transition");
}
static ObservedHighlighter *Owner(NSTextStorage *storage, NSString *directory, CountingParser *parser) {
    ObservedHighlighter *owner = [[ObservedHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"org" queryDirectory:directory];
    [owner useParser:parser]; [owner layoutsChanged];
    return owner;
}
static BOOL Kind(NSLayoutManager *layout, NSUInteger location, NSString *kind) {
    return NVSourceCapturesAreCurrent(layout) &&
        [[layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:location effectiveRange:NULL] isEqual:kind];
}
static BOOL HasSourceAttributes(NSTextStorage *storage) {
    __block BOOL found = NO;
    [storage enumerateAttribute:NVSourceCaptureAttributeName inRange:NSMakeRange(0, [storage length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) { found = YES; *stop = YES; }
    }];
    return found;
}
static BOOL HasTemporaryCaptures(NSLayoutManager *layout, NSUInteger length) {
    for (NSUInteger index = 0; index < length;) {
        NSRange range;
        if ([layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:&range]) return YES;
        index = MAX(index + 1, NSMaxRange(range));
    }
    return NO;
}

static void TestDisplayBudgetRecovery(NSString *directory) {
    NSLog(@"CASE: cached Org revision crosses the aggregate display budget as a peer joins and leaves");
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < 700; i++) [text appendFormat:@"* TODO Heading %lu\n", (unsigned long)i];
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text];
    NSLayoutManager *first = [[NSLayoutManager alloc] init], *peer = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:first];
    CountingParser *parser = [[CountingParser alloc] initWithQueryDirectory:directory];
    ObservedHighlighter *owner = Owner(storage, directory, parser);
    Completed(owner, parser, 1);
    NSUInteger captureCount = [parser captureCount];
    NSLog(@"EVIDENCE: %lu UTF-16 units, %lu real Org captures", (unsigned long)[storage length], (unsigned long)captureCount);
    Check(captureCount > 2048 && captureCount <= 4096, @"fixture fits one layout and exceeds the aggregate budget with two");
    Check(Kind(first, 2, @"keyword.todo"), @"one layout publishes current TODO captures");
    [first addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(0, 1)];
    [storage addLayoutManager:peer];
    [peer addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor cyanColor] forCharacterRange:NSMakeRange(0, 1)];
    uint64_t generation = [owner generation];
    [owner layoutsChanged];
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer), @"joining peer makes both layouts use plain display atomically");
    Check(!HasTemporaryCaptures(first, [storage length]) && !HasTemporaryCaptures(peer, [storage length]), @"budget fallback leaves no partial syntax attributes in either layout");
    Check([parser requestCount] == 1 && [owner generation] == generation, @"layout budget transition reuses the cached result without analysis or generation change");
    Check([[first temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] isEqual:[NSColor yellowColor]] &&
          [[peer temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] isEqual:[NSColor cyanColor]], @"budget fallback preserves both independent search backgrounds");

    [storage removeLayoutManager:peer]; [owner layoutsChanged];
    Check(Kind(first, 2, @"keyword.todo"), @"remaining layout recovers current colors from the cached revision when its peer leaves");
    Check(!NVSourceCapturesCanDisplay(peer), @"detached peer cannot display the recovered storage revision");
    Check([parser requestCount] == 1 && [owner generation] == generation, @"budget recovery also needs no parser request or source edit");
    [storage addLayoutManager:peer]; [owner layoutsChanged];
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer), @"a second attachment repeats whole-revision fallback");
    [storage removeLayoutManager:peer]; [owner layoutsChanged];
    Check(Kind(first, 2, @"keyword.todo"), @"a second detachment recovers the same current revision");
    Check([[storage string] isEqual:text] && !HasSourceAttributes(storage), @"layout churn preserves source characters and persistent attributes");
    [owner close];
    Check(!NVSourceCapturesCanDisplay(first) && !HasTemporaryCaptures(first, [storage length]), @"close clears the recovered revision");
    [owner release]; [parser release];
    [storage removeLayoutManager:first]; [first release]; [peer release]; [storage release];
}

static void TestLengthFallbackAndNewPeer(NSString *directory) {
    NSLog(@"CASE: new peer joins pending edit, then empty and oversized source recover to Org");
    NSString *source = @"* TODO Heading 😀\n#travel *book tickets*\n# real comment\nBody /italic/.\n";
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source];
    NSLayoutManager *first = [[NSLayoutManager alloc] init], *peer = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:first];
    CountingParser *parser = [[CountingParser alloc] initWithQueryDirectory:directory];
    ObservedHighlighter *owner = Owner(storage, directory, parser);
    Completed(owner, parser, 1);
    Check(Kind(first, 2, @"keyword.todo"), @"initial source has current captures");
    [storage replaceCharactersInRange:NSMakeRange(2, 4) withString:@"DONE"];
    Check(NVSourceCapturesCanDisplay(first) && !NVSourceCapturesAreCurrent(first), @"edited layout retains provisional display while semantic captures become stale");
    [storage addLayoutManager:peer]; [owner layoutsChanged];
    Check(NVSourceCapturesCanDisplay(first) && !NVSourceCapturesAreCurrent(first), @"new peer attachment retains the existing layout's provisional colors");
    Check(!NVSourceCapturesCanDisplay(peer) && !HasTemporaryCaptures(peer, [storage length]), @"new peer never receives stale absolute ranges from the prior source");
    Completed(owner, parser, 2);
    Check(Kind(first, 2, @"constant.done") && Kind(peer, 2, @"constant.done"), @"both layouts converge to the completed DONE source");
    NSUInteger hashtag = [[storage string] rangeOfString:@"book tickets"].location;
    NSUInteger comment = [[storage string] rangeOfString:@"real comment"].location;
    Check(Kind(first, hashtag, @"text.strong") && Kind(peer, hashtag, @"text.strong"), @"both layouts use fixed hashtag-prose classification after incremental parsing");
    Check(Kind(first, comment, @"comment") && Kind(peer, comment, @"comment"), @"both layouts keep actual comment classification after incremental parsing");

    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:@""];
    Completed(owner, parser, 3);
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer) && [parser captureCount] == 0, @"empty source retires both layouts' capture tokens");
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:source];
    Completed(owner, parser, 4);
    Check(Kind(first, 2, @"keyword.todo") && Kind(peer, 2, @"keyword.todo"), @"inserting source after empty fallback recovers both layouts");

    NSString *large = [@"x" stringByPaddingToLength:512 * 1024 + 1 withString:@"x" startingAtIndex:0];
    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:large];
    Completed(owner, parser, 5);
    Check([storage length] == 512 * 1024 + 1 && [[storage string] isEqual:large], @"source above the analysis length bound remains complete and editable");
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer) && [parser captureCount] == 0, @"oversized source leaves both layouts in bounded plain display");
    Check(!HasTemporaryCaptures(first, [storage length]) && !HasTemporaryCaptures(peer, [storage length]), @"oversized-source fallback clears every surviving provisional syntax attribute");
    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:source];
    Completed(owner, parser, 6);
    Check(Kind(first, 2, @"keyword.todo") && Kind(peer, 2, @"keyword.todo"), @"shrinking oversized source recovers Org colors without reopening the note");
    Check(Kind(first, [source rangeOfString:@"book tickets"].location, @"text.strong") && Kind(peer, [source rangeOfString:@"real comment"].location, @"comment"), @"fresh recovery preserves corrected prose and comment semantics");
    Check([[storage string] isEqual:source] && !HasSourceAttributes(storage), @"all fallback and recovery transitions preserve source and keep syntax out of persistent attributes");
    [owner close]; [owner release]; [parser release];
    [storage removeLayoutManager:first]; [storage removeLayoutManager:peer];
    [first release]; [peer release]; [storage release];
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    NSString *directory = [NSString stringWithUTF8String:argv[1]];
    TestDisplayBudgetRecovery(directory);
    TestLengthFallbackAndNewPeer(directory);
    NSLog(@"PASS: %lu Org publication-budget and recovery checks", (unsigned long)checks);
    return 0;
} }
