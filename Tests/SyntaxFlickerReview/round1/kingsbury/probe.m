#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"

// Kyle Kingsbury-inspired state-history review. This is not a review by him.
static NSUInteger Checks;
static void Check(BOOL condition, NSString *message) {
    Checks++;
    if (!condition) { fprintf(stderr, "FAIL %lu: %s\n", (unsigned long)Checks, [message UTF8String]); exit(1); }
}
static id Kind(NSLayoutManager *layout, NSUInteger index) {
    return [layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:NULL];
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]]; }
@interface NVSourceHighlighter (Probe)
- (void)analyze;
@end

// Semaphore handoffs make the snapshot-before-edit / completion-after-edit
// ordering explicit. The synthetic answer deliberately ignores cancellation.
@interface GatedParser : NVSourceParser {
    dispatch_semaphore_t started, resume;
    NSUInteger gateMode;
    NSString *seenSource, *seenSyntax;
    uint64_t seenGeneration;
}
- (void)gate:(NSUInteger)mode;
- (void)awaitStart;
- (void)resume;
- (NSString *)seenSource;
- (NSString *)seenSyntax;
- (uint64_t)seenGeneration;
@end
@implementation GatedParser
- (id)initWithQueryDirectory:(NSString *)directory {
    if ((self = [super initWithQueryDirectory:directory])) {
        started = dispatch_semaphore_create(0); resume = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)gate:(NSUInteger)mode { gateMode = mode; }
- (void)awaitStart { Check(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC)) == 0, @"worker reaches its gated snapshot"); }
- (void)resume { dispatch_semaphore_signal(resume); }
- (NSString *)seenSource { return seenSource; }
- (NSString *)seenSyntax { return seenSyntax; }
- (uint64_t)seenGeneration { return seenGeneration; }
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)generation {
    if (!gateMode) return [super capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:generation];
    NSUInteger mode = gateMode; gateMode = 0;
    [seenSource release]; seenSource = [source copy];
    [seenSyntax release]; seenSyntax = [syntax copy]; seenGeneration = generation;
    dispatch_semaphore_signal(started);
    if (dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC))) abort();
    if (mode == 2) return nil;
    if (mode == 3) return @[];
    return @[@{@"range": [NSValue valueWithRange:NSMakeRange(1, 1)], @"kind": @"review.stale"}];
}
- (void)dealloc { [seenSource release]; [seenSyntax release]; dispatch_release(started); dispatch_release(resume); [super dealloc]; }
@end
@interface ControlledHighlighter : NVSourceHighlighter
- (GatedParser *)gate;
- (BOOL)busy;
@end
@implementation ControlledHighlighter
- (id)initWithTextStorage:(NSTextStorage *)textStorage syntaxIdentifier:(NSString *)syntax queryDirectory:(NSString *)directory {
    if ((self = [super initWithTextStorage:textStorage syntaxIdentifier:syntax queryDirectory:directory])) {
        [parser release]; parser = [[GatedParser alloc] initWithQueryDirectory:directory];
    }
    return self;
}
- (GatedParser *)gate { return (GatedParser *)parser; }
- (BOOL)busy { return analyzing; }
@end

static void Pause(ControlledHighlighter *h) { [NSObject cancelPreviousPerformRequestsWithTarget:h selector:@selector(analyze) object:nil]; }
static void Complete(ControlledHighlighter *h) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([h busy] && [end timeIntervalSinceNow] > 0) Pump();
    Check(![h busy], @"main-thread completion drains"); Pause(h);
}
static void Refresh(ControlledHighlighter *h, NSLayoutManager *layout) {
    Pause(h); [h analyze]; Complete(h);
    Check(NVSourceCapturesAreCurrent(layout), @"latest real parse supplies current semantics");
}
static void Start(ControlledHighlighter *h, NSUInteger mode) {
    Pause(h); [[h gate] gate:mode]; [h analyze]; [[h gate] awaitStart];
}
static void CheckNoStale(NSLayoutManager *layout, NSTextStorage *storage) {
    for (NSUInteger i=0; i<[storage length]; i++) Check(![Kind(layout, i) isEqual:@"review.stale"], @"obsolete worker cannot publish synthetic capture");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSString *directory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"Resources/Syntax";
        NSTextStorage *storage = [[NSTextStorage alloc] initWithString:@"{\"key\":42}\n"];
        NSTextStorage *other = [[NSTextStorage alloc] initWithString:@"{\"peer\":false}\n"];
        NSLayoutManager *a = [[NSLayoutManager alloc] init], *b = [[NSLayoutManager alloc] init];
        [storage addLayoutManager:a]; [storage addLayoutManager:b];
        ControlledHighlighter *h = [[ControlledHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory];
        Refresh(h, a);
        Check([Kind(a, 3) isEqual:@"string.special.key"] && [Kind(b, 3) isEqual:@"string.special.key"], @"two peers start with real JSON captures");
        // Three obsolete outcomes must preserve provisional colors alike.
        for (NSUInteger mode=1; mode<=3; mode++) {
            Start(h, mode);
            NSString *snapshot = [[storage string] copy]; uint64_t before = [h generation];
            [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@" "];
            Pause(h);
            Check([[h gate] seenGeneration] == before && [[[h gate] seenSource] isEqual:snapshot], @"in-flight request owns exact prior snapshot and generation");
            Check([h generation] == before+1 && NVSourceCapturesCanDisplay(a) && !NVSourceCapturesAreCurrent(a), @"edit advances generation and preserves display without current semantics");
            [[h gate] resume]; Complete(h);
            Check(NVSourceCapturesCanDisplay(a) && NVSourceCapturesCanDisplay(b) && !NVSourceCapturesAreCurrent(a), @"obsolete positive, nil, or empty outcome leaves provisional display untouched");
            Check([Kind(a, 3) isEqual:@"string.special.key"] && [Kind(b, 3) isEqual:@"string.special.key"], @"old outcome never clears surviving peer colors");
            CheckNoStale(a, storage); CheckNoStale(b, storage);
            Refresh(h, a); [snapshot release];
            printf("PASS obsolete worker mode %lu\n", (unsigned long)mode);
        }
        // Matching syntax text after A->B->A is insufficient: generation must win.
        Start(h, 1);
        [h setSyntaxIdentifier:@"html"]; [h setSyntaxIdentifier:@"json"]; Pause(h);
        Check([[[h gate] seenSyntax] isEqual:@"json"], @"gated syntax captured before A-to-B-to-A change");
        Check(!NVSourceCapturesCanDisplay(a) && Kind(a, 3)==nil, @"syntax transition clears all provisional colors immediately");
        [[h gate] resume]; Complete(h);
        Check(!NVSourceCapturesCanDisplay(a) && Kind(a, 1)==nil, @"old matching syntax cannot survive A-to-B-to-A generation change");
        Refresh(h, a); printf("PASS syntax A-to-B-to-A\n");

        // A detached layout can join another note while the old worker is held.
        Start(h, 1);
        [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@" "]; Pause(h);
        [storage removeLayoutManager:b]; [other addLayoutManager:b];
        ControlledHighlighter *peer = [[ControlledHighlighter alloc] initWithTextStorage:other syntaxIdentifier:@"json" queryDirectory:directory];
        Refresh(peer, b);
        Check([Kind(b, 9) isEqual:@"constant.builtin"], @"migrated layout displays the second note's current result");
        [[h gate] resume]; Complete(h);
        Check(NVSourceCapturesAreCurrent(b) && [Kind(b, 9) isEqual:@"constant.builtin"], @"obsolete first-note completion cannot clear second-note colors");
        Refresh(h, a);
        Check(NVSourceCapturesAreCurrent(b) && [Kind(b, 9) isEqual:@"constant.builtin"], @"latest first-note completion cannot replace second-note colors");
        [h close];
        Check(NVSourceCapturesAreCurrent(b) && [Kind(b, 9) isEqual:@"constant.builtin"], @"closing first note cannot invalidate second-note token");
        [h release]; printf("PASS layout migration to independent note\n");

        // Closing while a worker is held must dominate every result outcome.
        for (NSUInteger mode=1; mode<=3; mode++) {
            h = [[ControlledHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory];
            Refresh(h, a); Start(h, mode);
            [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@" "]; Pause(h);
            Check(NVSourceCapturesCanDisplay(a), @"closing fixture starts with provisional display");
            [h close];
            Check(!NVSourceCapturesCanDisplay(a) && Kind(a, 3)==nil, @"close synchronously revokes provisional display");
            [[h gate] resume]; Complete(h);
            Check(!NVSourceCapturesCanDisplay(a) && Kind(a, 1)==nil, @"post-close positive, nil, or empty result cannot resurrect captures");
            [h release]; printf("PASS close worker mode %lu\n", (unsigned long)mode);
        }
        // Current fallback, unlike obsolete fallback, is allowed to clear colors.
        for (NSUInteger mode=2; mode<=3; mode++) {
            h = [[ControlledHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory];
            Refresh(h, a);
            [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@" "]; Pause(h);
            Check(NVSourceCapturesCanDisplay(a), @"current fallback fixture starts with provisional colors");
            Start(h, mode); [[h gate] resume]; Complete(h);
            Check(!NVSourceCapturesCanDisplay(a) && Kind(a, 3)==nil, @"current nil or empty result clears provisional colors");
            Refresh(h, a); [h close]; [h release];
            printf("PASS current fallback mode %lu\n", (unsigned long)mode);
        }
        Check([[storage string] isEqual:@"{\"key\":42}\n         "], @"all nine source edits survive every worker history exactly");
        Check([[other string] isEqual:@"{\"peer\":false}\n"], @"independent note source remains unchanged");
        [peer close]; [peer release];
        [storage removeLayoutManager:a]; [other removeLayoutManager:b];
        [a release]; [b release]; [storage release]; [other release];
        printf("PASS %lu assertions across ten gated worker histories\n", (unsigned long)Checks);
    }
    return 0;
}
