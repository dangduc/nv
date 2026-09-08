#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#include <dlfcn.h>
#include <time.h>

// The same probe links against either implementation. It calls only common API.
static NSUInteger Checks, Adds, Removes;
static uint64_t ParserCalls;
static BOOL HasProvisionalDisplay;
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
            cancellationToken:(const uint64_t *)token generation:(uint64_t)generation {
    __atomic_fetch_add(&ParserCalls, 1, __ATOMIC_RELAXED);
    return [super capturesForString:source syntaxIdentifier:syntax cancellationToken:token generation:generation];
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
@interface CountingHighlighter : NVSourceHighlighter @end
@implementation CountingHighlighter
- (id)initWithTextStorage:(NSTextStorage *)text syntaxIdentifier:(NSString *)syntax queryDirectory:(NSString *)directory {
    if ((self = [super initWithTextStorage:text syntaxIdentifier:syntax queryDirectory:directory])) {
        [parser release]; parser = [[CountingParser alloc] initWithQueryDirectory:directory];
    }
    return self;
}
@end
static BOOL Current(NSArray *layouts) {
    for (NSLayoutManager *layout in layouts) if (!NVSourceCapturesAreCurrent(layout)) return NO;
    return YES;
}
static void WaitCurrent(NSArray *layouts) {
    double end = Now() + 3;
    while (!Current(layouts) && Now() < end) Pump(.005);
    Check(Current(layouts), @"latest analysis reaches every attached layout");
}
typedef struct { NSUInteger raw, rawColored, distinct, distinctColored; } Segments;
static Segments CountSegments(NSLayoutManager *layout) {
    Segments result = {0};
    NSUInteger index = 0, length = [[layout textStorage] length];
    id previous = nil;
    BOOL first = YES;
    while (index < length) {
        NSRange range;
        id value = [layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:&range];
        Check(range.length && range.location <= index && NSMaxRange(range) > index,
              @"effective-range traversal advances through valid source positions");
        result.raw++; if (value) result.rawColored++;
        if (first || !(previous == value || [previous isEqual:value])) {
            result.distinct++; if (value) result.distinctColored++;
        }
        previous = value; first = NO; index = NSMaxRange(range);
    }
    return result;
}
static void PrintSegments(const char *phase, Segments s) {
    printf(" %s_raw=%lu/%lu %s_distinct=%lu/%lu", phase,
           (unsigned long)s.rawColored, (unsigned long)s.raw, phase,
           (unsigned long)s.distinctColored, (unsigned long)s.distinct);
}
static int CompareDoubles(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}
static void Workload(NSString *directory, NSUInteger layoutCount) {
    NSMutableString *original = [NSMutableString stringWithString:@"{\"long\":\""];
    [original appendString:[@"" stringByPaddingToLength:300 withString:@"a" startingAtIndex:0]];
    [original appendString:@"\""];
    for (NSUInteger i = 0; i < 100; i++) [original appendFormat:@",\"key%lu\":%lu", (unsigned long)i, (unsigned long)i];
    [original appendString:@"}"];
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:original] autorelease];
    NSMutableArray *layouts = [NSMutableArray array];
    for (NSUInteger i = 0; i < layoutCount; i++) {
        CountingLayout *layout = [[[CountingLayout alloc] init] autorelease];
        [storage addLayoutManager:layout]; [layouts addObject:layout];
    }
    CountingHighlighter *analysis = [[[CountingHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory] autorelease];
    [analysis layoutsChanged]; WaitCurrent(layouts);
    Segments initial = CountSegments(layouts[0]);
    printf("initial layouts=%lu utf16=%lu", (unsigned long)layoutCount, (unsigned long)[storage length]);
    PrintSegments("initial", initial); printf("\n");
    double samples[720], totalSynchronous = 0, totalElapsed = 0;
    NSUInteger sampleCount = 0, burstAdds = 0, burstRemoves = 0, settledAdds = 0, settledRemoves = 0;
    uint64_t totalParserCalls = 0;
    for (NSUInteger cycle = 0; cycle < 6; cycle++) {
        for (NSUInteger deleting = 0; deleting < 2; deleting++) {
            Segments before = CountSegments(layouts[0]);
            Adds = Removes = 0;
            uint64_t callsBefore = Calls();
            double start = Now(), totalEdit = 0, maxEdit = 0;
            NSUInteger synchronousAdds = 0, synchronousRemoves = 0;
            for (NSUInteger edit = 0; edit < 60; edit++) {
                // Reverse deletions remove exactly the scattered inserted characters.
                NSUInteger position = 10 + 2 * (deleting ? 59 - edit : edit);
                NSUInteger addsBefore = Adds, removesBefore = Removes;
                double t = Now();
                [storage replaceCharactersInRange:NSMakeRange(position, deleting ? 1 : 0)
                                       withString:deleting ? @"" : @"x"];
                t = Now() - t;
                samples[sampleCount++] = t; totalEdit += t; if (t > maxEdit) maxEdit = t;
                synchronousAdds += Adds - addsBefore; synchronousRemoves += Removes - removesBefore;
                Check(!Current(layouts), @"character edits invalidate semantic captures immediately");
                Pump(.008);
                NSRange key = [[storage string] rangeOfString:@"key90"];
                Check(key.location != NSNotFound, @"unmodified suffix remains present");
                for (NSLayoutManager *layout in layouts) {
                    id value = [layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:key.location effectiveRange:NULL];
                    Check((value != nil) == HasProvisionalDisplay,
                          @"fixed build retains unchanged colors; base reproduces deferred clearing");
                }
            }
            double elapsed = Now() - start;
            NSUInteger editAdds = Adds, editRemoves = Removes;
            uint64_t editCalls = Calls() - callsBefore;
            Segments pending = CountSegments(layouts[0]);
            Check(editCalls == 0, @"sub-debounce burst dispatches no parser request");
            Check(synchronousAdds == 0 && synchronousRemoves == 0, @"neither implementation writes captures inside the edit call");
            Check(editAdds == 0 && editRemoves == (HasProvisionalDisplay ? 0 : layoutCount),
                  @"fixed burst retains attributes; base clears each layout once after its first edit");
            for (NSLayoutManager *layout in layouts) {
                Segments peer = CountSegments(layout);
                Check(peer.distinct == pending.distinct && peer.distinctColored == pending.distinctColored,
                      @"attached layouts have the same distinct provisional runs");
            }
            WaitCurrent(layouts);
            Segments settled = CountSegments(layouts[0]);
            Check(Calls() - callsBefore == 1, @"each completed burst requires exactly one parser request");
            Check(settled.distinct == initial.distinct && settled.distinctColored == initial.distinctColored,
                  @"fresh parsing restores original distinct syntax runs");
            Check(Adds - editAdds == 303 * layoutCount && Removes - editRemoves == (HasProvisionalDisplay ? layoutCount : 0),
                  @"replacement uses the same capture additions with clearing at the expected phase");
            Check([storage length] == [original length] + (deleting ? 0 : 60), @"source length matches the edit history");
            if (deleting) Check([[storage string] isEqualToString:original], @"insert/delete pair restores exact original source");
            printf("burst layouts=%lu cycle=%lu operation=%s edits=60 sync_total_ms=%.3f sync_max_ms=%.3f elapsed_ms=%.3f parser=%llu+%llu writes_pending=%lu/%lu writes_settle=%lu/%lu",
                   (unsigned long)layoutCount, (unsigned long)(cycle + 1), deleting ? "delete" : "insert",
                   totalEdit * 1000, maxEdit * 1000, elapsed * 1000,
                   editCalls, Calls() - callsBefore - editCalls, (unsigned long)editAdds, (unsigned long)editRemoves,
                   (unsigned long)(Adds - editAdds), (unsigned long)(Removes - editRemoves));
            PrintSegments("before", before); PrintSegments("pending", pending); PrintSegments("settled", settled); printf("\n");
            totalSynchronous += totalEdit; totalElapsed += elapsed;
            burstAdds += editAdds; burstRemoves += editRemoves;
            settledAdds += Adds - editAdds; settledRemoves += Removes - editRemoves;
            totalParserCalls += Calls() - callsBefore;
        }
    }
    qsort(samples, sampleCount, sizeof(double), CompareDoubles);
    printf("summary layouts=%lu edits=%lu cycles=6 parser_calls=%llu burst_adds_removes=%lu/%lu settle_adds_removes=%lu/%lu sync_total_ms=%.3f sync_median_ms=%.3f sync_p95_ms=%.3f sync_max_ms=%.3f burst_elapsed_ms=%.3f\n",
           (unsigned long)layoutCount, (unsigned long)sampleCount, totalParserCalls,
           (unsigned long)burstAdds, (unsigned long)burstRemoves, (unsigned long)settledAdds, (unsigned long)settledRemoves,
           totalSynchronous * 1000, samples[sampleCount / 2] * 1000, samples[(sampleCount * 95 / 100) - 1] * 1000,
           samples[sampleCount - 1] * 1000, totalElapsed * 1000);
    [analysis close];
    Check(!Current(layouts), @"close invalidates every layout");
    for (NSLayoutManager *layout in layouts) Check(CountSegments(layout).distinctColored == 0, @"close removes all remaining captures");
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"query directory supplied");
        HasProvisionalDisplay = dlsym(RTLD_DEFAULT, "NVSourceCapturesCanDisplay") != NULL;
        printf("implementation=%s columns: segments=colored/all writes=adds/removes parser=burst/settle\n",
               HasProvisionalDisplay ? "fixed" : "base");
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        Workload(directory, 1); Workload(directory, 4);
        printf("PASS %lu checks\n", (unsigned long)Checks);
    }
    return 0;
}
