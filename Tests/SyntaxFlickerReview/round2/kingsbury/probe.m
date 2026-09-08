#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

// Kyle Kingsbury-inspired scheduling histories, not a review by him.
static NSUInteger Checks;
static void Check(BOOL ok, NSString *message) {
    Checks++;
    if (!ok) { fprintf(stderr, "FAIL %lu: %s\n", (unsigned long)Checks, [message UTF8String]); exit(1); }
}
static void Await(BOOL (^done)(void), NSString *message) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    Check(done(), message);
}
static id Kind(NSLayoutManager *layout, NSUInteger index) {
    return [layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:NULL];
}

@interface AutomaticParser : NVSourceParser {
    dispatch_semaphore_t entered, resume;
    BOOL armed;
    NSString *heldSource, *heldSyntax, *latestSource, *latestSyntax;
    uint64_t heldGeneration, latestGeneration;
    NSUInteger calls;
}
- (void)arm;
- (BOOL)entered;
- (void)resume;
- (NSString *)heldSource;
- (NSString *)heldSyntax;
- (uint64_t)heldGeneration;
- (NSString *)latestSource;
- (NSString *)latestSyntax;
- (uint64_t)latestGeneration;
- (NSUInteger)calls;
@end
@implementation AutomaticParser
- (id)initWithQueryDirectory:(NSString *)directory {
    if ((self = [super initWithQueryDirectory:directory])) {
        entered = dispatch_semaphore_create(0); resume = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)arm { @synchronized(self) { armed = YES; } }
- (BOOL)entered { return dispatch_semaphore_wait(entered, DISPATCH_TIME_NOW) == 0; }
- (void)resume { dispatch_semaphore_signal(resume); }
- (NSString *)heldSource { @synchronized(self) { return [[heldSource retain] autorelease]; } }
- (NSString *)heldSyntax { @synchronized(self) { return [[heldSyntax retain] autorelease]; } }
- (uint64_t)heldGeneration { @synchronized(self) { return heldGeneration; } }
- (NSString *)latestSource { @synchronized(self) { return [[latestSource retain] autorelease]; } }
- (NSString *)latestSyntax { @synchronized(self) { return [[latestSyntax retain] autorelease]; } }
- (uint64_t)latestGeneration { @synchronized(self) { return latestGeneration; } }
- (NSUInteger)calls { @synchronized(self) { return calls; } }
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)revision {
    BOOL gate;
    @synchronized(self) {
        calls++;
        [latestSource release]; latestSource = [source copy];
        [latestSyntax release]; latestSyntax = [syntax copy]; latestGeneration = revision;
        gate = armed; armed = NO;
        if (gate) {
            // Retain the actual production argument. Copying here would conceal
            // a mutable snapshot bug in the owner.
            [heldSource release]; heldSource = [source retain];
            [heldSyntax release]; heldSyntax = [syntax retain]; heldGeneration = revision;
        }
    }
    if (!gate) return [super capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:revision];
    dispatch_semaphore_signal(entered);
    if (dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC))) abort();
    // Intentionally ignore cancellation to test the publication fence.
    return @[@{@"range": [NSValue valueWithRange:NSMakeRange(1, 1)], @"kind": @"review.obsolete"}];
}
- (void)dealloc {
    [heldSource release]; [heldSyntax release]; [latestSource release]; [latestSyntax release];
    dispatch_release(entered); dispatch_release(resume); [super dealloc];
}
@end

@interface NVSourceHighlighter (SchedulingProbe)
- (void)analyze;
- (void)applyCaptures;
@end
@interface ObservedHighlighter : NVSourceHighlighter {
    NSUInteger attempts, busyAttempts, publications;
}
- (AutomaticParser *)worker;
- (NSUInteger)attempts;
- (NSUInteger)busyAttempts;
- (NSUInteger)publications;
- (BOOL)busy;
@end
@implementation ObservedHighlighter
- (id)initWithTextStorage:(NSTextStorage *)text syntaxIdentifier:(NSString *)syntax queryDirectory:(NSString *)directory {
    if ((self = [super initWithTextStorage:text syntaxIdentifier:syntax queryDirectory:directory])) {
        [parser release]; parser = [[AutomaticParser alloc] initWithQueryDirectory:directory];
    }
    return self;
}
- (AutomaticParser *)worker { return (AutomaticParser *)parser; }
- (NSUInteger)attempts { return attempts; }
- (NSUInteger)busyAttempts { return busyAttempts; }
- (NSUInteger)publications { return publications; }
- (BOOL)busy { return analyzing; }
- (void)analyze { attempts++; if (analyzing) busyAttempts++; [super analyze]; }
- (void)applyCaptures {
    for (NSDictionary *capture in captures)
        Check(![capture[@"kind"] isEqual:@"review.obsolete"], @"no obsolete synthetic result reaches publication");
    publications++;
    [super applyCaptures];
}
@end

@interface Typist : NSObject {
@public
    NSTextStorage *text;
    NSArray *layouts;
    NSUInteger count;
}
- (void)type:(NSTimer *)timer;
@end
@implementation Typist
- (void)type:(NSTimer *)timer {
    [text replaceCharactersInRange:NSMakeRange([text length], 0) withString:@" "];
    for (NSLayoutManager *layout in layouts) {
        Check(NVSourceCapturesCanDisplay(layout), @"typing retains peer display permission");
        Check(!NVSourceCapturesAreCurrent(layout), @"typing revokes semantic permission synchronously");
        Check([Kind(layout, 3) isEqual:@"string.special.key"], @"typing retains the existing JSON key color");
    }
    if (++count == 12) [timer invalidate];
}
@end

static BOOL AllCurrent(NSArray *layouts) {
    for (NSLayoutManager *layout in layouts) if (!NVSourceCapturesAreCurrent(layout)) return NO;
    return YES;
}
static void Latest(ObservedHighlighter *h, NSTextStorage *text, NSArray *layouts, NSString *syntax) {
    Await(^BOOL { return ![h busy] && AllCurrent(layouts); }, @"latest captures become current in every layout within three seconds");
    Check([[[h worker] latestSource] isEqual:[text string]], @"completed request contains the exact final source");
    Check([[[h worker] latestSyntax] isEqual:syntax], @"completed request uses the final syntax");
    Check([[h worker] latestGeneration] == [h generation], @"completed request matches the current generation");
}
static void Edit(NSTextStorage *text) { [text replaceCharactersInRange:NSMakeRange([text length], 0) withString:@" "]; }
static void Gate(ObservedHighlighter *h, NSTextStorage *text) {
    [[h worker] arm]; Edit(text);
    __block BOOL entered = NO;
    Await(^BOOL { if (!entered) entered = [[h worker] entered]; return entered; }, @"a production timer starts the gated worker within three seconds");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSString *directory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"Resources/Syntax";
        NSTextStorage *text = [[NSTextStorage alloc] initWithString:@"{\"key\":42}\n"];
        NSLayoutManager *a = [[NSLayoutManager alloc] init], *b = [[NSLayoutManager alloc] init], *c = [[NSLayoutManager alloc] init];
        [text addLayoutManager:a]; [text addLayoutManager:b];
        NSArray *two = @[a,b], *three = @[a,b,c];
        ObservedHighlighter *h = [[ObservedHighlighter alloc] initWithTextStorage:text syntaxIdentifier:@"json" queryDirectory:directory];
        [h layoutsChanged]; Latest(h, text, two, @"json");
        uint64_t original = [h generation];
        Typist *typist = [[Typist alloc] init]; typist->text = text; typist->layouts = two;
        [NSTimer scheduledTimerWithTimeInterval:0.01 target:typist selector:@selector(type:) userInfo:nil repeats:YES];
        Await(^BOOL { return typist->count == 12; }, @"all twelve timer-driven edits execute within three seconds");
        Latest(h, text, two, @"json");
        Check([h generation] == original+12, @"each bounded typing edit advances the generation once");
        Check([[text string] isEqual:@"{\"key\":42}\n            "], @"bounded typing preserves all twelve exact source edits");
        [typist release];
        printf("PASS bounded typing: 12 edits, parser calls=%lu\n", (unsigned long)[[h worker] calls]);

        // A pending debounce request really fires while its older worker waits.
        Gate(h, text);
        NSString *snapshot = [[[h worker] heldSource] copy];
        uint64_t held = [[h worker] heldGeneration];
        NSUInteger busyBefore = [h busyAttempts];
        Edit(text); Edit(text); Edit(text);
        [text addLayoutManager:c]; [h layoutsChanged];
        Check(!NVSourceCapturesCanDisplay(c), @"new layout has no borrowed stale captures");
        Check(NVSourceCapturesCanDisplay(a) && NVSourceCapturesCanDisplay(b), @"new attachment preserves existing provisional peer colors");
        Await(^BOOL { return [h busyAttempts] > busyBefore; }, @"production debounce fires while the prior worker is held");
        Check([[[h worker] heldSource] isEqual:snapshot], @"the retained worker argument stays immutable across three source edits");
        Check([h generation] == held+3, @"attachment does not alter source generation");
        [[h worker] resume]; Latest(h, text, three, @"json");
        Check([Kind(c, 3) isEqual:@"string.special.key"], @"newly attached layout eventually receives real JSON captures");
        [snapshot release];
        printf("PASS consumed debounce and new attachment: busy timer attempts=%lu\n", (unsigned long)[h busyAttempts]);

        // Release immediately after an edit schedules its timer. Completion and
        // that timer may arrive in either order; both must converge automatically.
        Gate(h, text); Edit(text);
        NSUInteger attemptsBefore = [h attempts];
        [[h worker] resume]; Latest(h, text, three, @"json");
        printf("PASS completion near queued debounce: further timer attempts=%lu\n", (unsigned long)([h attempts]-attemptsBefore));

        Gate(h, text);
        Check([[[h worker] heldSyntax] isEqual:@"json"], @"in-flight request captures JSON before syntax change");
        [h setSyntaxIdentifier:@"html"];
        [text replaceCharactersInRange:NSMakeRange(0, [text length]) withString:@"<b>new</b>\n"];
        for (NSLayoutManager *layout in three)
            Check(!NVSourceCapturesCanDisplay(layout) && Kind(layout, 1)==nil, @"syntax change clears provisional JSON display immediately");
        busyBefore = [h busyAttempts];
        Await(^BOOL { return [h busyAttempts] > busyBefore; }, @"HTML debounce fires while obsolete JSON work waits");
        [[h worker] resume]; Latest(h, text, three, @"html");
        for (NSLayoutManager *layout in three)
            Check([Kind(layout, 1) isEqual:@"tag"], @"all three layouts receive the final real HTML tag capture");
        printf("PASS syntax change during work: final generation=%llu\n", (unsigned long long)[h generation]);

        // With no layouts, the timer runs but cannot start a parser request.
        NSUInteger callsBefore = [[h worker] calls]; attemptsBefore = [h attempts];
        Edit(text);
        for (NSLayoutManager *layout in three) [text removeLayoutManager:layout];
        [h layoutsChanged];
        Await(^BOOL { return [h attempts] > attemptsBefore; }, @"pending timer runs after the last layout detaches");
        Check([[h worker] calls] == callsBefore && ![h busy], @"no-layout timer launches no parser work");
        [text addLayoutManager:a]; [h layoutsChanged]; Latest(h, text, @[a], @"html");
        printf("PASS last detach before timer and automatic reattachment\n");

        // Close after last detach while old work waits; the moved layout then
        // receives another owner's colors before the old completion is released.
        Gate(h, text);
        [text removeLayoutManager:a]; [h close];
        NSTextStorage *other = [[NSTextStorage alloc] initWithString:@"{\"peer\":false}\n"];
        [other addLayoutManager:a];
        ObservedHighlighter *peer = [[ObservedHighlighter alloc] initWithTextStorage:other syntaxIdentifier:@"json" queryDirectory:directory];
        [peer layoutsChanged]; Latest(peer, other, @[a], @"json");
        NSUInteger publicationsBefore = [h publications];
        [[h worker] resume];
        Await(^BOOL { return ![h busy]; }, @"closed owner's held worker completion drains within three seconds");
        Check([h publications] == publicationsBefore, @"closed owner publishes no late result");
        Check(NVSourceCapturesAreCurrent(a) && [Kind(a, 9) isEqual:@"constant.builtin"], @"late closed-owner completion preserves the new note's current colors");
        Check([[text string] isEqual:@"<b>new</b>\n  "] && [[other string] isEqual:@"{\"peer\":false}\n"], @"detach and close histories preserve both exact note sources");
        [peer close];
        Check(!NVSourceCapturesCanDisplay(a) && Kind(a, 9)==nil, @"closing an attached owner removes current display colors");
        printf("PASS last detach and close during work: no late publication\n");
        [peer release]; [h release];
        [other removeLayoutManager:a];
        [a release]; [b release]; [c release]; [text release]; [other release];
        printf("PASS %lu assertions across six automatic scheduling histories; every eventual wait bounded at 3 seconds\n", (unsigned long)Checks);
    }
    return 0;
}
