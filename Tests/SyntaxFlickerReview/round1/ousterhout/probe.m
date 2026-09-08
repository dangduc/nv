#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

static NSUInteger Checks, HighlighterDeaths, ParserDeaths;
static void Check(BOOL value, NSString *message) {
    Checks++;
    if (!value) { fprintf(stderr, "FAIL %lu: %s\n", (unsigned long)Checks, [message UTF8String]); exit(1); }
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static BOOL Await(BOOL (^predicate)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:4];
    while (!predicate() && [limit timeIntervalSinceNow] > 0) Pump();
    return predicate();
}
@interface NVSourceHighlighter (ReviewEntry)
- (void)analyze;
@end
static void Pause(NVSourceHighlighter *owner) {
    [NSObject cancelPreviousPerformRequestsWithTarget:owner selector:@selector(analyze) object:nil];
}
static NSString *Kind(NSLayoutManager *layout, NSUInteger index) {
    return [layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:NULL];
}

// This parser produces a real initial parse. The next request deliberately waits,
// then returns a successful obsolete capture even after cancellation. That isolates
// the highlighter's ownership and close guards from parser cancellation behavior.
@interface HeldParser : NVSourceParser {
    dispatch_semaphore_t entered, resume;
    BOOL hold;
}
- (void)holdNext;
- (BOOL)awaitWorker;
- (void)resumeWorker;
@end
@implementation HeldParser
- (id)initWithQueryDirectory:(NSString *)directory {
    if ((self = [super initWithQueryDirectory:directory])) {
        entered = dispatch_semaphore_create(0); resume = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)holdNext { hold = YES; }
- (BOOL)awaitWorker { return !dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)); }
- (void)resumeWorker { dispatch_semaphore_signal(resume); }
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)value {
    if (hold) {
        hold = NO; dispatch_semaphore_signal(entered);
        if (dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC))) return nil;
        return @[@{@"range": [NSValue valueWithRange:NSMakeRange(2, 3)], @"kind": @"review.retired"}];
    }
    return [super capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:value];
}
- (void)dealloc { ParserDeaths++; dispatch_release(entered); dispatch_release(resume); [super dealloc]; }
@end
@interface LifetimeHighlighter : NVSourceHighlighter
- (HeldParser *)worker;
@end
@implementation LifetimeHighlighter
- (id)initWithTextStorage:(NSTextStorage *)text syntaxIdentifier:(NSString *)syntax queryDirectory:(NSString *)directory {
    if ((self = [super initWithTextStorage:text syntaxIdentifier:syntax queryDirectory:directory])) {
        [parser release]; parser = [[HeldParser alloc] initWithQueryDirectory:directory];
    }
    return self;
}
- (HeldParser *)worker { return (HeldParser *)parser; }
- (void)dealloc { HighlighterDeaths++; [super dealloc]; }
@end

static void AttachDetachHistory(NSString *directory, NSUInteger iteration) {
    NSTextStorage *a = [[NSTextStorage alloc] initWithString:@"{\"key\": 42, \"next\": true}"];
    NSTextStorage *b = [[NSTextStorage alloc] initWithString:@"plain text has no JSON captures"];
    NSLayoutManager *one = [NSLayoutManager new], *two = [NSLayoutManager new], *three = [NSLayoutManager new];
    [a addLayoutManager:one]; [a addLayoutManager:two];
    NVSourceHighlighter *owner = [[NVSourceHighlighter alloc] initWithTextStorage:a syntaxIdentifier:@"json" queryDirectory:directory];
    [owner layoutsChanged];
    Check(Await(^BOOL { return NVSourceCapturesAreCurrent(one) && NVSourceCapturesAreCurrent(two); }), @"initial revision reaches both attached layouts");
    [one addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(2, 3)];
    [a replaceCharactersInRange:NSMakeRange(0, 0) withString:@" "]; Pause(owner);
    Check(!NVSourceCapturesAreCurrent(one) && !NVSourceCapturesAreCurrent(two), @"pending source has no current semantics");
    Check(NVSourceCapturesCanDisplay(one) && NVSourceCapturesCanDisplay(two), @"pending source keeps display permission");
    Check([Kind(one, 3) isEqual:@"string.special.key"] && [Kind(two, 3) isEqual:@"string.special.key"], @"both layout caches shift retained capture to edited range");
    [a addLayoutManager:three]; [owner layoutsChanged]; Pause(owner);
    Check(!NVSourceCapturesCanDisplay(three) && !Kind(three, 3), @"new layout does not acquire obsolete absolute captures");
    Check(NVSourceCapturesCanDisplay(one) && NVSourceCapturesCanDisplay(two), @"attaching third layout preserves existing peer display");
    [a removeLayoutManager:two]; [b addLayoutManager:two];
    Check(!NVSourceCapturesCanDisplay(two) && !NVSourceCapturesAreCurrent(two), @"borrowed storage identity rejects capture on another note");
    [owner setSyntaxIdentifier:@"plain"]; Pause(owner);
    Check(!NVSourceCapturesCanDisplay(one) && !NVSourceCapturesCanDisplay(three) && !Kind(one, 3), @"syntax change invalidates attached revision and clears its colors");
    Check(!NVSourceCapturesCanDisplay(two), @"syntax invalidation also retires the detached revision");
    Check([one temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:3 effectiveRange:NULL] != nil, @"syntax replacement preserves independent search background");
    [b removeLayoutManager:two]; [a addLayoutManager:two];
    Check(!NVSourceCapturesCanDisplay(two), @"returning to original storage cannot revive retired token");
    [owner setSyntaxIdentifier:@"json"]; [owner layoutsChanged];
    Check(Await(^BOOL { return NVSourceCapturesAreCurrent(one) && NVSourceCapturesAreCurrent(two) && NVSourceCapturesAreCurrent(three); }), @"fresh analysis unifies all three layouts under current revision");
    [a replaceCharactersInRange:NSMakeRange(0, 1) withString:@""]; Pause(owner);
    [a removeLayoutManager:one]; [a removeLayoutManager:two]; [a removeLayoutManager:three];
    [owner close]; [owner close]; [owner release];
    [a addLayoutManager:one];
    Check(!NVSourceCapturesCanDisplay(one) && !NVSourceCapturesAreCurrent(one), @"last-layout close invalidates detached revision even on original storage");
    NVSourceHighlighter *fresh = [[NVSourceHighlighter alloc] initWithTextStorage:a syntaxIdentifier:@"json" queryDirectory:directory];
    [fresh layoutsChanged];
    Check(Await(^BOOL { return NVSourceCapturesAreCurrent(one); }), @"new highlighter can replace retained retired association");
    Check([[a string] isEqual:@"{\"key\": 42, \"next\": true}"], @"attach detach and display changes preserve exact source");
    Check([a attribute:NVSourceCaptureAttributeName atIndex:2 effectiveRange:NULL] == nil, @"capture never enters authored text storage");
    [fresh close]; [fresh release]; [a removeLayoutManager:one];
    [one release]; [two release]; [three release]; [a release]; [b release];
    printf("PASS attachment history %lu\n", (unsigned long)iteration);
}

static void CloseInFlight(NSString *directory) {
    __block NSUInteger deaths = HighlighterDeaths, parserDeaths = ParserDeaths;
    NSTextStorage *source = [[NSTextStorage alloc] initWithString:@"{\"key\": 42}"];
    NSLayoutManager *layout = [NSLayoutManager new]; [source addLayoutManager:layout];
    LifetimeHighlighter *owner = [[LifetimeHighlighter alloc] initWithTextStorage:source syntaxIdentifier:@"json" queryDirectory:directory];
    [owner layoutsChanged];
    Check(Await(^BOOL { return NVSourceCapturesAreCurrent(layout); }), @"close fixture starts with a real parse");
    HeldParser *worker = [[owner worker] retain]; [worker holdNext];
    [source replaceCharactersInRange:NSMakeRange(0, 0) withString:@" "]; Pause(owner); [owner analyze];
    Check([worker awaitWorker], @"worker is positively blocked inside a new parse");
    Check(NVSourceCapturesCanDisplay(layout) && !NVSourceCapturesAreCurrent(layout), @"blocked parse retains display only");
    [source removeLayoutManager:layout]; [owner close]; [owner release];
    Check(HighlighterDeaths == deaths, @"in-flight worker retains closed owner until completion");
    [source addLayoutManager:layout];
    Check(!NVSourceCapturesCanDisplay(layout), @"close invalidates borrowed storage token before asynchronous completion");
    [source removeLayoutManager:layout]; [source release];
    [worker resumeWorker]; [worker release];
    Check(Await(^BOOL { return HighlighterDeaths == deaths + 1 && ParserDeaths == parserDeaths + 1; }), @"closed owner and parser both deallocate after obsolete completion");
    Check(!NVSourceCapturesCanDisplay(layout) && !NVSourceCapturesAreCurrent(layout), @"completion cannot revive retired revision after source is released");
    [layout release];
    printf("PASS close during blocked successful parse\n");
}
int main(int argc, char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"query directory argument supplied");
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        for (NSUInteger index = 0; index < 12; index++) { @autoreleasepool { AttachDetachHistory(directory, index + 1); } }
        CloseInFlight(directory);
        printf("PASS %lu checks; 12 attachment histories; closed highlighters=%lu parsers=%lu\n", (unsigned long)Checks, (unsigned long)HighlighterDeaths, (unsigned long)ParserDeaths);
    }
    return 0;
}
