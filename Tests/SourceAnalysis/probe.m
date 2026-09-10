#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "AttributedPlainText.h"
#import "NVSourceAnalysis.h"

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return condition();
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.15]];
}
static NSArray *Labels(NSString *source, NSString *syntax) {
    NSMutableArray *labels = [NSMutableArray array];
    for (NSDictionary *run in NVSourceLinkRuns(source, syntax)) {
        NSRange range = [run[@"range"] rangeValue];
        Check(range.location <= source.length && range.length <= source.length - range.location,
              @"link ranges stay inside the immutable UTF-16 source");
        [labels addObject:@[[source substringWithRange:range], [run[@"url"] absoluteString]]];
    }
    return labels;
}

// The gate pauses the real production decorator only on its worker. The main
// run loop stays free so the test can replace requests or destroy their owner.
static atomic_bool gateNext, workerEntered, workerExited, workerUsedMain;
static dispatch_semaphore_t gate;
static IMP decorate;
static void GatedDecoration(id receiver, SEL selector, NSRange range, NSString *syntax) {
    if (atomic_exchange(&gateNext, false)) {
        atomic_store(&workerUsedMain, [NSThread isMainThread]);
        atomic_store(&workerEntered, true);
        if (dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC))) abort();
        ((void (*)(id, SEL, NSRange, NSString *))decorate)(receiver, selector, range, syntax);
        atomic_store(&workerExited, true);
    } else ((void (*)(id, SEL, NSRange, NSString *))decorate)(receiver, selector, range, syntax);
}
static void ArmGate(void) {
    atomic_store(&workerEntered, false); atomic_store(&workerExited, false);
    atomic_store(&workerUsedMain, false); atomic_store(&gateNext, true);
}

@interface Client : NSObject <NVSourceAnalysisDelegate> {
@public
    NSMutableString *source;
    NSString *syntax;
    NSUInteger generation, captures, publications;
    NSDictionary *latest;
    BOOL wantsWords, wantsLinks;
    BOOL *destroyedOnMain;
}
@end
@implementation Client
- (id)init {
    if ((self = [super init])) {
        source = [@"first words https://example.com" mutableCopy];
        syntax = [@"plain" retain]; generation = 1; wantsWords = YES; wantsLinks = YES;
    }
    return self;
}
- (NSDictionary *)snapshotForSourceAnalysis:(NVSourceAnalysis *)analysis {
    Check([NSThread isMainThread], @"snapshot capture stays on main"); captures++;
    return @{@"source": [[source copy] autorelease], @"syntax": syntax,
             @"generation": @(generation), @"links": @(wantsLinks), @"words": @(wantsWords)};
}
- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:(NSDictionary *)result {
    Check([NSThread isMainThread], @"publication stays on main"); publications++;
    [latest release]; latest = [result copy];
}
- (void)dealloc {
    if (destroyedOnMain) *destroyedOnMain = [NSThread isMainThread];
    [source release]; [syntax release]; [latest release]; [super dealloc];
}
@end

static void CheckLinksAndWords(void) {
    NSArray *fixtures = @[
        @"", @"     ", @"one two three", @"line one\nline two", @"don't rock'n'roll co-operate foo_bar",
        @"café café tiếng Việt", @"你好世界 日本語の文章", @"مرحبا بالعالم",
        @"👩🏽‍💻 👨‍👩‍👧‍👦 word", @"123 12.3 -7", @"[[Other note]] [[https://example.com][Org label]]",
        @"https://example.com/a?q=1 person@example.com", @"one\u00a0two\u200bthree",
        @"file:///tmp/fixture.txt file:///.file/id=123", @"{\"title\":\"one two\",\"enabled\":true}"
    ];
    NSMutableArray *reference = [NSMutableArray array];
    for (NSString *source in fixtures) {
        @autoreleasepool {
            NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:source] autorelease];
            [reference addObject:@([[storage words] count])];
        }
    }
    NSArray *expected = [reference copy];
    __block BOOL done = NO;
    __block NSString *failure = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
        if ([NSThread isMainThread]) failure = [@"word fixture ran on main" retain];
        for (NSUInteger i = 0; i < fixtures.count; i++) {
            if (NVSourceWordCount(fixtures[i]) != [expected[i] unsignedIntegerValue]) {
                failure = [[NSString stringWithFormat:@"legacy word count differs for %@", fixtures[i]] retain]; break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    }});
    Check(Await(^BOOL { return done; }), @"worker word fixtures complete without blocking main");
    Check(!failure, failure ?: @"worker-private storage preserves all 15 legacy word fixtures");
    [failure release]; [expected release];

    Check([Labels(@"😀 prefix https://example.com/a?q=1, person@example.com and [[Other note]]", @"plain")
        isEqual:@[@[@"https://example.com/a?q=1", @"https://example.com/a?q=1"],
                  @[@"person@example.com", @"mailto:person@example.com"],
                  @[@"Other note", @"nvalt://find/Other%20note"]]], @"URL punctuation, UTF-16, email, and wiki semantics survive extraction");
    Check([Labels(@"file:///tmp/fixture.txt file:///.file/id=123", @"plain")
        isEqual:@[@[@"file:///tmp/fixture.txt", @"file:///tmp/fixture.txt"]]], @"file reference targets remain excluded");
    Check([Labels(@"[[https://example.com/path?q=1#part][Résumé 😀 中文]]", @"org")
        isEqual:@[@[@"Résumé 😀 中文", @"https://example.com/path?q=1#part"]]], @"Org labels retain exact target and Unicode range");
    for (NSString *target in @[@"file:agenda.org", @"id:example", @"#heading", @"Another note", @"agenda.org", @"", @" https://example.com", @"https://example.com path", @"javascript:alert(1)"]) {
        for (NSString *suffix in @[@"]]", @"][Label]]"])
            Check(![Labels([NSString stringWithFormat:@"[[%@%@", target, suffix], @"org") count], @"unsupported Org targets stay inert");
    }
    Check([Labels(@"[[file:agenda.org\nhttps://example.com", @"org")
        isEqual:@[@[@"https://example.com", @"https://example.com"]]], @"unfinished Org target suppresses only its line");
    Check(![Labels(@"prefix [[https://example.com][Label suffix", @"org") count], @"deleted Org closer makes the old target inert");
    Check(![Labels(@"[[]] [[ incomplete ]]", @"plain") count], @"empty and whitespace wiki interiors remain safe");
}

static void CheckScheduler(void) {
    Method method = class_getInstanceMethod([NSMutableAttributedString class], @selector(addLinkAttributesForRange:syntaxIdentifier:));
    decorate = method_setImplementation(method, (IMP)GatedDecoration);
    gate = dispatch_semaphore_create(0);

    Client *client = [[Client alloc] init];
    NVSourceAnalysis *analysis = [[NVSourceAnalysis alloc] initWithDelegate:client];
    ArmGate(); [analysis request];
    Check(Await(^BOOL { return atomic_load(&workerEntered); }), @"first worker reaches controlled barrier");
    Check(!atomic_load(&workerUsedMain), @"link extraction runs off main");
    for (NSUInteger i = 2; i <= 500; i++) {
        [client->source setString:[NSString stringWithFormat:@"latest %lu https://example.net", (unsigned long)i]];
        client->generation = i;
        [analysis invalidate]; [analysis request];
    }
    Check(client->captures == 1 && client->publications == 0, @"500 requests retain one running snapshot and a pending request");
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL { return client->publications == 1; }), @"the latest replacement publishes after a canceled worker");
    Check(client->captures == 2 && [client->latest[@"generation"] unsignedIntegerValue] == 500 &&
          [client->latest[@"source"] isEqualToString:client->source], @"only the latest generation is captured and published");
    Check([client->latest[@"wordCount"] unsignedIntegerValue] == NVSourceWordCount(client->source), @"accepted job includes the complete latest word count");
    Pump(); Check(client->publications == 1 && client->captures == 2, @"no per-key work remains queued");

    ArmGate(); [analysis request];
    Check(Await(^BOOL { return atomic_load(&workerEntered); }), @"immutable source job reaches barrier");
    NSString *captured = [client->source copy];
    [client->source setString:@"mutated backing after capture"];
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL { return client->publications == 2; }), @"immutable snapshot publishes");
    Check([client->latest[@"source"] isEqualToString:captured], @"worker source does not follow a mutated caller string");
    [captured release];

    ArmGate(); [analysis request];
    Check(Await(^BOOL { return atomic_load(&workerEntered); }), @"invalidated job reaches barrier");
    [analysis invalidate]; dispatch_semaphore_signal(gate);
    Check(Await(^BOOL { return atomic_load(&workerExited); }), @"invalidated worker finishes");
    Pump(); Check(client->publications == 2, @"invalidation without replacement suppresses publication");

    ArmGate(); [analysis request];
    Check(Await(^BOOL { return atomic_load(&workerEntered); }), @"closing job reaches barrier");
    BOOL destroyedOnMain = NO; client->destroyedOnMain = &destroyedOnMain;
    [analysis close]; [analysis release]; [client release];
    Check(destroyedOnMain, @"worker does not retain or destroy the delegate");
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL { return atomic_load(&workerExited); }), @"closed worker finishes without accessing its destroyed owner");
    Pump();

    Client *wordsOnly = [[Client alloc] init]; wordsOnly->wantsLinks = NO;
    NVSourceAnalysis *counts = [[NVSourceAnalysis alloc] initWithDelegate:wordsOnly];
    [counts request];
    Check(Await(^BOOL { return wordsOnly->publications == 1; }), @"word-only requests complete");
    Check(wordsOnly->latest[@"wordCount"] && !wordsOnly->latest[@"linkRuns"], @"word-only request does not extract links");
    [counts close]; [counts release]; [wordsOnly release];
    Client *linksOnly = [[Client alloc] init]; linksOnly->wantsWords = NO;
    NVSourceAnalysis *links = [[NVSourceAnalysis alloc] initWithDelegate:linksOnly];
    [links request];
    Check(Await(^BOOL { return linksOnly->publications == 1; }), @"link-only requests complete");
    Check(linksOnly->latest[@"linkRuns"] && !linksOnly->latest[@"wordCount"], @"hidden word counter does not count words");
    [links close]; [links release]; [linksOnly release];
    method_setImplementation(method, decorate);
    dispatch_release(gate);
}

int main(void) { @autoreleasepool {
    CheckLinksAndWords(); CheckScheduler();
    printf("PASS: %lu source-analysis checks\n", (unsigned long)checks);
} return 0; }
