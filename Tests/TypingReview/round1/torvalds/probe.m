#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "AttributedPlainText.h"
#import "NVSourceAnalysis.h"

static NSUInteger checks, ownerDeaths, clientDeaths;
static BOOL badDeathThread;
static void Check(BOOL condition, const char *message) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return condition();
}
@interface TrackedAnalysis : NVSourceAnalysis @end
@implementation TrackedAnalysis
- (void)dealloc { ownerDeaths++; if (![NSThread isMainThread]) badDeathThread = YES; [super dealloc]; }
@end
@interface Client : NSObject <NVSourceAnalysisDelegate> {
@public
    NSString *source;
    NSDictionary *latest;
    NSUInteger captures, publications, generation;
    BOOL noSnapshot;
}
@end
@implementation Client
- (id)init {
    if ((self = [super init])) { source = [@"initial https://example.com [[note]]" copy]; generation = 1; }
    return self;
}
- (NSDictionary *)snapshotForSourceAnalysis:(NVSourceAnalysis *)analysis {
    Check([NSThread isMainThread], "capture on main"); captures++;
    if (noSnapshot) return nil;
    return @{@"source": [[source copy] autorelease], @"syntax": @"plain",
             @"generation": @(generation), @"links": @YES, @"words": @YES};
}
- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:(NSDictionary *)result {
    Check([NSThread isMainThread], "publication on main"); publications++;
    [latest release]; latest = [result copy];
}
- (void)dealloc {
    clientDeaths++; if (![NSThread isMainThread]) badDeathThread = YES;
    [source release]; [latest release]; [super dealloc];
}
@end

static atomic_bool armed, entered;
static dispatch_semaphore_t gate;
static IMP oldDecorate;
static void GateDecoration(id obj, SEL selector, NSRange range, NSString *syntax) {
    if (![NSThread isMainThread] && atomic_exchange(&armed, false)) {
        atomic_store(&entered, true);
        if (dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC))) abort();
    }
    ((void (*)(id, SEL, NSRange, NSString *))oldDecorate)(obj, selector, range, syntax);
}

static void CheckRanges(void) {
    NSArray *tokens = @[@"", @"a", @" ", @"[", @"]", @"[[", @"]]", @"][", @"\n", @"\r\n",
        @"😀", @"é", @"中文", @"👩🏽‍💻", @"https://example.com/a?b=c", @"www.example.net", @"person@example.org"];
    uint32_t state = 0x12345678;
    NSMutableArray *fixtures = [NSMutableArray arrayWithArray:@[@"", @"[[]]", @"[[", @"]]", @"[[a]]", @"[[a\nb]]",
        @"[[https://example.com][😀 label]]", @"[[https://example.com][]]", @"https://example.com\n"]];
    for (NSUInteger sample = 0; sample < 300; sample++) {
        NSMutableString *s = [NSMutableString string];
        for (NSUInteger n = 0; n < 24; n++) {
            state = 1664525 * state + 1013904223;
            [s appendString:tokens[state % tokens.count]];
        }
        [fixtures addObject:s];
    }
    NSUInteger runs = 0;
    for (NSString *s in fixtures) for (NSString *syntax in @[@"plain", @"org"]) @autoreleasepool {
        NSArray *links = NVSourceLinkRuns(s, syntax);
        for (NSDictionary *link in links) {
            NSRange r = [link[@"range"] rangeValue];
            Check(r.location <= s.length && r.length > 0 && r.length <= s.length - r.location,
                  "nonempty emitted link range stays inside UTF-16 source");
            Check([link[@"url"] isKindOfClass:[NSURL class]], "emitted target is an NSURL");
            (void)[s substringWithRange:r]; runs++;
        }
        NSUInteger count = NVSourceWordCount(s);
        NSTextStorage *storage = [[NSTextStorage alloc] initWithString:s];
        Check(count == [[storage words] count], "private word count equals Cocoa baseline");
        [storage release];
    }
    printf("PASS: %lu source/syntax fixtures, %lu bounded nonempty link runs\n",
           (unsigned long)(fixtures.count * 2), (unsigned long)runs);
}

static void CheckLifetime(void) {
    gate = dispatch_semaphore_create(0);
    Method method = class_getInstanceMethod([NSMutableAttributedString class], @selector(addLinkAttributesForRange:syntaxIdentifier:));
    oldDecorate = method_setImplementation(method, (IMP)GateDecoration);
    atomic_store(&armed, true);
    Client *first = [[Client alloc] init];
    TrackedAnalysis *blocked = [[TrackedAnalysis alloc] initWithDelegate:first];
    [blocked request];
    Check(Await(^BOOL { return atomic_load(&entered); }), "worker reaches bounded cancellation barrier");

    NSMutableArray *analyses = [NSMutableArray array], *clients = [NSMutableArray array];
    for (NSUInteger n = 0; n < 40; n++) {
        Client *client = [[Client alloc] init];
        TrackedAnalysis *analysis = [[TrackedAnalysis alloc] initWithDelegate:client];
        [clients addObject:client]; [analyses addObject:analysis];
        [analysis request]; [client release]; [analysis release];
    }
    Check(Await(^BOOL {
        for (Client *client in clients) if (!client->captures) return NO;
        return YES;
    }), "40 session jobs queue behind the active worker");
    for (TrackedAnalysis *analysis in analyses) { [analysis invalidate]; [analysis request]; [analysis close]; }
    [analyses removeAllObjects]; [clients removeAllObjects];
    [blocked close]; [blocked release]; [first release];
    Check(ownerDeaths == 41 && clientDeaths == 41, "close releases queued and running owners/delegates on main");

    Client *last = [[Client alloc] init];
    TrackedAnalysis *survivor = [[TrackedAnalysis alloc] initWithDelegate:last];
    last->noSnapshot = YES;
    [survivor request];
    Check(Await(^BOOL { return last->captures == 1; }), "nil snapshot clears the pending capture");
    Check(last->publications == 0, "nil snapshot cannot publish");
    last->noSnapshot = NO;
    [last->source release]; last->source = [@"" copy];
    [survivor request];
    Check(Await(^BOOL { return last->captures == 2; }), "request after nil snapshot can restart");
    // Main-thread import decoration can still run while the analysis worker is active.
    Check([NVSourceLinkRuns(@"[[main note]] https://example.net", @"plain") count] == 2,
          "main-thread detector remains usable while worker is gated");
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL { return last->publications == 1; }), "latest session publishes after canceled queued jobs drain");
    Check([last->latest[@"linkRuns"] count] == 0 && [last->latest[@"wordCount"] unsignedIntegerValue] == 0,
          "empty source publishes empty links and zero words");
    [survivor close]; [survivor release]; [last release];
    Check(ownerDeaths == 42 && clientDeaths == 42 && !badDeathThread, "all session owners and delegates die on main");
    method_setImplementation(method, oldDecorate);
    dispatch_release(gate);
    printf("PASS: 42 owner/delegate lifetimes, 40 queued cancellations, nil-snapshot restart, empty-result publication\n");
}

int main(void) { @autoreleasepool {
    CheckRanges(); CheckLifetime();
    printf("PASS: all review probes (%lu checks)\n", (unsigned long)checks);
} return 0; }
