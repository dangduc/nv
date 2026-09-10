#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

// Test-only delivery control. The superclass computes the real Org/JSON
// captures, then this parser delays their return to the real worker owner.
@interface DeliveryGateParser : NVSourceParser {
    dispatch_semaphore_t delivery;
    NSLock *lock;
    NSMutableArray *requests;
}
- (NSUInteger)requestCount;
- (NSDictionary *)lastRequest;
- (void)deliver;
@end

@implementation DeliveryGateParser
- (id)initWithQueryDirectory:(NSString *)directory {
    if ((self = [super initWithQueryDirectory:directory])) {
        delivery = dispatch_semaphore_create(0);
        lock = [[NSLock alloc] init];
        requests = [[NSMutableArray alloc] init];
    }
    return self;
}
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)generation {
    NSArray *result = [[super capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:generation] retain];
    [lock lock];
    [requests addObject:@{@"source": source, @"syntax": syntax, @"generation": @(generation), @"count": @([result count]), @"completed": @(result != nil)}];
    [lock unlock];
    // A finite bound turns a harness failure into an explicit failure.
    if (dispatch_semaphore_wait(delivery, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC))) {
        NSLog(@"FAIL: test did not release a pending parser result");
        exit(2);
    }
    return [result autorelease];
}
- (NSUInteger)requestCount {
    [lock lock]; NSUInteger count = [requests count]; [lock unlock]; return count;
}
- (NSDictionary *)lastRequest {
    [lock lock]; NSDictionary *request = [[[requests lastObject] copy] autorelease]; [lock unlock]; return request;
}
- (void)deliver { dispatch_semaphore_signal(delivery); }
- (void)dealloc { dispatch_release(delivery); [requests release]; [lock release]; [super dealloc]; }
@end

static NSUInteger closedOwnersReleased;
@interface ReviewHighlighter : NVSourceHighlighter {
    BOOL recordDeallocation;
}
- (void)installDeliveryGate:(DeliveryGateParser *)replacement;
- (BOOL)isAnalyzing;
- (void)recordDeallocation;
@end
@implementation ReviewHighlighter
- (void)installDeliveryGate:(DeliveryGateParser *)replacement { [parser release]; parser = [replacement retain]; }
- (BOOL)isAnalyzing { return analyzing; }
- (void)recordDeallocation { recordDeallocation = YES; }
- (void)dealloc { if (recordDeallocation) closedOwnersReleased++; [super dealloc]; }
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *label) {
    checks++;
    if (!condition) { NSLog(@"FAIL: %@", label); exit(1); }
    NSLog(@"PASS: %@", label);
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!condition() && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    return condition();
}
static BOOL Kind(NSLayoutManager *layout, NSUInteger location, NSString *kind) {
    return NVSourceCapturesAreCurrent(layout) &&
        [[layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:location effectiveRange:NULL] isEqual:kind];
}
static void RequestReady(DeliveryGateParser *gate, NSUInteger expected) {
    Check(Await(^BOOL { return [gate requestCount] >= expected; }), @"real parser result reaches the controlled delivery gate");
    Check([gate requestCount] == expected, @"one serial worker request is pending");
    Check([[[gate lastRequest] objectForKey:@"completed"] boolValue], @"pending request completed real syntax analysis within its budget");
}
static ReviewHighlighter *MakeOwner(NSTextStorage *storage, NSString *syntax, NSString *directory, DeliveryGateParser *gate) {
    ReviewHighlighter *owner = [[ReviewHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:syntax queryDirectory:directory];
    [owner installDeliveryGate:gate];
    [owner layoutsChanged];
    return owner;
}

static void TestGenerationABA(NSString *directory) {
    NSLog(@"CASE: successful stale results across coalesced edits and Org/Plain/Org transitions");
    NSString *initial = @"* TODO Initial 😀\nBody *bold*.\n";
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:initial];
    NSLayoutManager *first = [[NSLayoutManager alloc] init], *peer = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:first]; [storage addLayoutManager:peer];
    DeliveryGateParser *gate = [[DeliveryGateParser alloc] initWithQueryDirectory:directory];
    ReviewHighlighter *owner = MakeOwner(storage, @"org", directory, gate);
    RequestReady(gate, 1);
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer), @"unpublished initial captures stay invisible in both layouts");
    [gate deliver];
    Check(Await(^BOOL { return Kind(first, 2, @"keyword.todo") && Kind(peer, 2, @"keyword.todo"); }), @"initial Org result becomes current in both layouts");
    // Keep the marked character unchanged. TextKit may discard temporary
    // backgrounds on replaced characters independently of syntax analysis.
    [first addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(0, 1)];
    [peer addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor cyanColor] forCharacterRange:NSMakeRange(0, 1)];

    [storage replaceCharactersInRange:NSMakeRange(2, 4) withString:@"DONE"];
    Check(NVSourceCapturesCanDisplay(first) && NVSourceCapturesCanDisplay(peer) && !NVSourceCapturesAreCurrent(first) && !NVSourceCapturesAreCurrent(peer), @"typing preserves provisional Org display while invalidating syntax semantics");
    RequestReady(gate, 2);
    Check([[[gate lastRequest] objectForKey:@"source"] hasPrefix:@"* DONE"], @"held result was computed for the intermediate DONE source");
    uint64_t heldGeneration = [[[gate lastRequest] objectForKey:@"generation"] unsignedLongLongValue];
    [owner setSyntaxIdentifier:@"plain"];
    [owner setSyntaxIdentifier:@"org"];
    [storage replaceCharactersInRange:NSMakeRange(2, 4) withString:@"TODO"];
    [storage replaceCharactersInRange:[[storage string] rangeOfString:@"Initial"] withString:@"Latest 日本語"];
    NSString *latest = [[storage string] copy];
    Check([owner generation] > heldGeneration, @"returning to Org still advances the publication generation");
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer), @"syntax changes invalidate old Org revisions immediately");
    [gate deliver];
    RequestReady(gate, 3);
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer), @"successful stale DONE result cannot publish after the Org/Plain/Org transition");
    Check([[[gate lastRequest] objectForKey:@"source"] isEqual:latest] && [[[gate lastRequest] objectForKey:@"syntax"] isEqual:@"org"], @"replacement request uses the latest immutable source and syntax");
    [gate deliver];
    Check(Await(^BOOL { return Kind(first, 2, @"keyword.todo") && Kind(peer, 2, @"keyword.todo"); }), @"only the latest TODO result becomes current in both layouts");
    Check([[storage string] isEqual:latest], @"analysis and syntax transitions preserve source characters");
    Check([storage attribute:NVSourceCaptureAttributeName atIndex:2 effectiveRange:NULL] == nil, @"published syntax never enters note text storage");
    Check([[first temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] isEqual:[NSColor yellowColor]] &&
          [[peer temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] isEqual:[NSColor cyanColor]], @"stale and fresh deliveries retain independent search backgrounds on unchanged text");
    [latest release];
    [owner close]; [owner release]; [gate release];
    [storage removeLayoutManager:first]; [storage removeLayoutManager:peer];
    [first release]; [peer release]; [storage release];
}

static void TestNoteSwitchAndReopen(NSString *directory) {
    NSLog(@"CASE: detach, close with result in flight, reuse a layout, and reopen source analysis");
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:@"* TODO Original note\nBody.\n"];
    NSTextStorage *other = [[NSTextStorage alloc] initWithString:@"* TODO Another note\nDifferent.\n"];
    NSLayoutManager *first = [[NSLayoutManager alloc] init], *peer = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:first]; [storage addLayoutManager:peer];
    DeliveryGateParser *gate = [[DeliveryGateParser alloc] initWithQueryDirectory:directory];
    ReviewHighlighter *owner = MakeOwner(storage, @"org", directory, gate);
    RequestReady(gate, 1); [gate deliver];
    Check(Await(^BOOL { return Kind(first, 2, @"keyword.todo") && Kind(peer, 2, @"keyword.todo"); }), @"both layouts begin with current Org captures");

    [storage removeLayoutManager:peer]; [other addLayoutManager:peer];
    Check(!NVSourceCapturesCanDisplay(peer), @"a reused layout rejects the prior note's capture token before any new analysis");
    [owner layoutsChanged];
    Check(Kind(first, 2, @"keyword.todo") && !NVSourceCapturesCanDisplay(peer), @"reattachment updates the remaining owner without coloring another note");
    [storage replaceCharactersInRange:NSMakeRange(2, 4) withString:@"DONE"];
    RequestReady(gate, 2);
    Check([[[gate lastRequest] objectForKey:@"source"] hasPrefix:@"* DONE"], @"the old owner holds a successful result when its last layout closes");
    [storage removeLayoutManager:first];
    [owner recordDeallocation];
    [owner close];
    [owner release]; owner = nil;
    Check(!NVSourceCapturesCanDisplay(first) && !NVSourceCapturesCanDisplay(peer), @"closing invalidates capture tokens even on detached layouts");

    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:@"{\"current\":true}\n"];
    [storage addLayoutManager:first];
    DeliveryGateParser *reopenedGate = [[DeliveryGateParser alloc] initWithQueryDirectory:directory];
    ReviewHighlighter *reopened = MakeOwner(storage, @"json", directory, reopenedGate);
    RequestReady(reopenedGate, 1); [reopenedGate deliver];
    Check(Await(^BOOL { return Kind(first, 2, @"string.special.key"); }), @"a reopened owner publishes the current JSON note independently");
    NSAttributedString *saved = [storage copy];
    [gate deliver];
    Check(Await(^BOOL { return closedOwnersReleased == 1; }), @"a closed owner survives its callback and then deallocates");
    Check(Kind(first, 2, @"string.special.key"), @"late successful Org result cannot replace a reopened owner's JSON captures");
    Check(!NVSourceCapturesCanDisplay(peer), @"late delivery cannot color a layout attached to a different note");
    Check([storage isEqualToAttributedString:saved], @"late delivery leaves reopened source and its persistent attributes unchanged");
    [saved release];

    [other removeLayoutManager:peer]; [storage addLayoutManager:peer]; [reopened layoutsChanged];
    Check(Kind(first, 2, @"string.special.key") && Kind(peer, 2, @"string.special.key"), @"reattached peer receives the reopened owner's current revision");
    [reopened close]; [reopened release]; [gate release]; [reopenedGate release];
    [storage removeLayoutManager:first]; [storage removeLayoutManager:peer];
    [first release]; [peer release]; [storage release]; [other release];
}

static void TestSwitchToPlainDuringDelivery(NSString *directory) {
    NSLog(@"CASE: switch to Plain Text while the first Org result is awaiting delivery");
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:@"* TODO Unpublished\n*bold*\n"];
    NSLayoutManager *layout = [[NSLayoutManager alloc] init]; [storage addLayoutManager:layout];
    DeliveryGateParser *gate = [[DeliveryGateParser alloc] initWithQueryDirectory:directory];
    ReviewHighlighter *owner = MakeOwner(storage, @"org", directory, gate);
    RequestReady(gate, 1);
    Check([[[gate lastRequest] objectForKey:@"count"] unsignedIntegerValue] > 0, @"the pending Org result contains real captures");
    [owner setSyntaxIdentifier:@"plain"]; [gate deliver];
    RequestReady(gate, 2);
    Check(!NVSourceCapturesCanDisplay(layout), @"the stale first Org result remains invisible after selecting Plain Text");
    Check([[[gate lastRequest] objectForKey:@"syntax"] isEqual:@"plain"] && [[[gate lastRequest] objectForKey:@"count"] unsignedIntegerValue] == 0, @"the replacement Plain Text request has no syntax captures");
    [gate deliver];
    Check(Await(^BOOL { return ![owner isAnalyzing]; }) && !NVSourceCapturesCanDisplay(layout), @"Plain Text remains uncolored after both callbacks complete");
    Check([[storage string] isEqual:@"* TODO Unpublished\n*bold*\n"], @"switching during delivery preserves all Org source characters");
    [owner close]; [owner release]; [gate release];
    [storage removeLayoutManager:layout]; [layout release]; [storage release];
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    NSString *directory = [NSString stringWithUTF8String:argv[1]];
    TestGenerationABA(directory);
    TestNoteSwitchAndReopen(directory);
    TestSwitchToPlainDuringDelivery(directory);
    NSLog(@"PASS: %lu independent Org publication/lifecycle checks", (unsigned long)checks);
    return 0;
} }
