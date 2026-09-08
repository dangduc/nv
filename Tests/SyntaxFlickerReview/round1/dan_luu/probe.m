#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#include <time.h>

static NSUInteger Checks;
static uint64_t ParserCalls;
static NSUInteger Adds, Removes;
static void Check(BOOL ok, NSString *reason) {
    Checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", [reason UTF8String]); exit(1); }
}
static double Now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}
static void Pump(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do { [[NSRunLoop currentRunLoop] runUntilDate:end]; } while ([end timeIntervalSinceNow] > 0);
}
static uint64_t Calls(void) { return __atomic_load_n(&ParserCalls, __ATOMIC_RELAXED); }
@interface CountingParser : NVSourceParser @end
@implementation CountingParser
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax
            cancellationToken:(const uint64_t *)token generation:(uint64_t)g {
    __atomic_fetch_add(&ParserCalls, 1, __ATOMIC_RELAXED);
    return [super capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:g];
}
@end
@interface CountingLayout : NSLayoutManager @end
@implementation CountingLayout
- (void)addTemporaryAttribute:(NSString *)name value:(id)value forCharacterRange:(NSRange)range {
    if ([name isEqual:NVSourceCaptureAttributeName]) Adds++;
    [super addTemporaryAttribute:name value:value forCharacterRange:range];
}
- (void)removeTemporaryAttribute:(NSString *)name forCharacterRange:(NSRange)range {
    if ([name isEqual:NVSourceCaptureAttributeName]) Removes++;
    [super removeTemporaryAttribute:name forCharacterRange:range];
}
@end
@interface NVSourceHighlighter (ProbeMethods)
- (void)applyCaptures;
@end
@interface CountingHighlighter : NVSourceHighlighter
- (void)forceCaptureCount:(NSUInteger)count;
@end
@implementation CountingHighlighter
- (id)initWithTextStorage:(NSTextStorage *)text syntaxIdentifier:(NSString *)syntax queryDirectory:(NSString *)directory {
    if ((self = [super initWithTextStorage:text syntaxIdentifier:syntax queryDirectory:directory])) {
        [parser release]; parser = [[CountingParser alloc] initWithQueryDirectory:directory];
    }
    return self;
}
- (void)forceCaptureCount:(NSUInteger)count {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++)
        [list addObject:@{@"range": [NSValue valueWithRange:NSMakeRange(0, 1)], @"kind": @"fixture"}];
    [captures release]; captures = [list copy];
    [self applyCaptures];
}
@end
static BOOL Current(NSArray *layouts) {
    for (NSLayoutManager *layout in layouts) if (!NVSourceCapturesAreCurrent(layout)) return NO;
    return YES;
}
static void WaitCurrent(NSArray *layouts) {
    double deadline = Now() + 3;
    while (!Current(layouts) && Now() < deadline) Pump(.005);
    Check(Current(layouts), @"analysis settles to current captures");
}
static NSUInteger Runs(NSLayoutManager *layout, BOOL coloredOnly) {
    NSUInteger count = 0, index = 0, length = [[layout textStorage] length];
    id previous = nil;
    BOOL first = YES;
    while (index < length) {
        NSRange range;
        // effectiveRange can return adjacent equal-valued cache segments.
        // Coalesce equal neighbors when counting distinct capture runs.
        id value = [layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:&range];
        Check(range.length > 0 && NSMaxRange(range) > index, @"temporary range traversal advances");
        if ((first || !(previous == value || [previous isEqual:value])) && (!coloredOnly || value)) count++;
        previous = value; first = NO;
        index = NSMaxRange(range);
    }
    return count;
}
static NSMutableArray *Layouts(NSTextStorage *storage, NSUInteger count) {
    NSMutableArray *layouts = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        CountingLayout *layout = [[[CountingLayout alloc] init] autorelease];
        [storage addLayoutManager:layout]; [layouts addObject:layout];
    }
    return layouts;
}
static void Typing(NSString *directory, NSUInteger layoutCount) {
    NSMutableString *source = [NSMutableString stringWithString:@"{\"long\":\""];
    [source appendString:[@"" stringByPaddingToLength:300 withString:@"a" startingAtIndex:0]];
    [source appendString:@"\""];
    for (NSUInteger i = 0; i < 100; i++) [source appendFormat:@",\"key%lu\":%lu", (unsigned long)i, (unsigned long)i];
    [source appendString:@"}"];
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:source] autorelease];
    NSArray *layouts = Layouts(storage, layoutCount);
    CountingHighlighter *analysis = [[[CountingHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory] autorelease];
    [analysis layoutsChanged]; WaitCurrent(layouts);
    NSUInteger initialColored = Runs(layouts[0], YES), initialAll = Runs(layouts[0], NO);
    uint64_t callsBefore = Calls(); Adds = Removes = 0;
    double totalEdit = 0, maxEdit = 0, start = Now();
    for (NSUInteger edit = 0; edit < 120; edit++) {
        double t = Now();
        [storage replaceCharactersInRange:NSMakeRange(10 + 2 * edit, 0) withString:@"x"];
        t = Now() - t; totalEdit += t; if (t > maxEdit) maxEdit = t;
        Check(!Current(layouts), @"every edit immediately invalidates semantic captures");
        for (NSLayoutManager *layout in layouts)
            Check(NVSourceCapturesCanDisplay(layout), @"every existing layout retains provisional display");
        Pump(.008);
    }
    double burstSeconds = Now() - start;
    NSUInteger editAdds = Adds, editRemoves = Removes;
    uint64_t burstCalls = Calls() - callsBefore;
    NSUInteger pendingColored = Runs(layouts[0], YES), pendingAll = Runs(layouts[0], NO);
    Check(burstCalls == 0, @"paced sub-debounce edits coalesce without parser dispatch");
    Check(editAdds == 0 && editRemoves == 0, @"highlighter performs no temporary capture writes during sustained edits");
    Check(pendingColored <= initialColored + 120 && pendingAll <= initialAll + 240,
          @"one-character insertions add at most one colored and two total runs each");
    for (NSLayoutManager *layout in layouts) {
        Check(Runs(layout, YES) == pendingColored, @"peer layouts have identical pending fragmentation");
        Check([layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:10 effectiveRange:NULL] == nil,
              @"new source character waits for fresh analysis");
    }
    WaitCurrent(layouts);
    NSUInteger settledColored = Runs(layouts[0], YES), settledAll = Runs(layouts[0], NO);
    Check(Calls() - callsBefore == 1, @"burst produces exactly one parser request after debounce");
    Check(Adds > 0 && Adds <= 4096 && Removes == layoutCount, @"settling replaces one revision within display-write budget");
    printf("fragmentation observation initial=%lu/%lu pending=%lu/%lu settled=%lu/%lu\n", (unsigned long)initialColored, (unsigned long)initialAll, (unsigned long)pendingColored, (unsigned long)pendingAll, (unsigned long)settledColored, (unsigned long)settledAll);
    Check(settledColored == initialColored && settledAll == initialAll, @"replacement result removes temporary fragmentation");
    Check([storage length] == [source length] + 120, @"syntax display preserves inserted source");
    printf("typing layouts=%lu source_utf16=%lu edits=120 elapsed_ms=%.3f synchronous_edit_total_ms=%.3f synchronous_edit_max_ms=%.3f burst_parser_calls=%llu burst_adds=%lu burst_removes=%lu pending_colored_runs=%lu->%lu settled=%lu pending_all_runs=%lu->%lu settled=%lu settle_adds=%lu settle_removes=%lu\n",
        (unsigned long)layoutCount, (unsigned long)[storage length], burstSeconds*1000, totalEdit*1000, maxEdit*1000,
        burstCalls, (unsigned long)editAdds, (unsigned long)editRemoves, (unsigned long)initialColored,
        (unsigned long)pendingColored, (unsigned long)settledColored, (unsigned long)initialAll,
        (unsigned long)pendingAll, (unsigned long)settledAll, (unsigned long)Adds, (unsigned long)Removes);
    [analysis close];
    Check(!NVSourceCapturesCanDisplay(layouts[0]), @"close invalidates display permission");
    Check(Runs(layouts[0], YES) == 0, @"close removes provisional display attributes");
}
static void Budget(NSString *directory, NSUInteger layoutCount) {
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:@"{}"] autorelease];
    NSArray *layouts = Layouts(storage, layoutCount);
    CountingHighlighter *analysis = [[[CountingHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory] autorelease];
    NSUInteger captures = 4096 / layoutCount;
    Adds = Removes = 0; [analysis forceCaptureCount:captures];
    Check(Adds == captures * layoutCount && Current(layouts), @"exact display-operation boundary colors every layout");
    NSUInteger exactAdds = Adds;
    Adds = Removes = 0; [analysis forceCaptureCount:captures + 1];
    Check(Adds == 0 && Removes == layoutCount && !Current(layouts), @"one capture beyond aggregate budget clears prior revision without partial writes");
    for (NSLayoutManager *layout in layouts) {
        Check(!NVSourceCapturesCanDisplay(layout), @"budget fallback revokes provisional permission in each layout");
        Check(Runs(layout, YES) == 0, @"budget fallback leaves no residual colors");
    }
    printf("budget layouts=%lu exact_captures=%lu exact_adds=%lu overflow_captures=%lu overflow_adds=%lu overflow_removes=%lu\n", (unsigned long)layoutCount, (unsigned long)captures, (unsigned long)exactAdds, (unsigned long)(captures+1), (unsigned long)Adds, (unsigned long)Removes);
    [analysis close];
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"syntax query directory supplied");
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        Typing(directory, 1); Typing(directory, 4);
        Budget(directory, 1); Budget(directory, 4);
        printf("PASS %lu checks\n", (unsigned long)Checks);
    }
    return 0;
}
