#import <Cocoa/Cocoa.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "AttributedPlainText.h"
#import "NVSourceAnalysis.h"

NSString * const NVNoteWordCountDidChangeNotification = @"ProbeWordCount";
static double Now(void) {
    static mach_timebase_info_data_t scale;
    if (!scale.denom) mach_timebase_info(&scale);
    return mach_absolute_time() * (double)scale.numer / scale.denom / 1e9;
}
static void Check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
@interface FixtureNote : NSObject
@end
@implementation FixtureNote
- (NSString *)sourceSyntaxIdentifier { return @"plain"; }
@end

// Only the delegate's environment is a fixture. The included method body is
// extracted byte-for-byte from NVNoteEditingSession.m by run.py.
@interface FixtureSession : NSObject {
@public
    BOOL closed;
    uint64_t sourceGeneration, wordCountGeneration;
    NSTextStorage *textStorage;
    FixtureNote *note;
    NVSourceAnalysis *sourceAnalysis;
    NSHashTable *wordCountClients;
    NSUInteger wordCount;
}
@end
@implementation FixtureSession
#include "publication.inc"
@end

static NSString *FixtureOfKind(NSUInteger links, BOOL web) {
    NSMutableString *source = [NSMutableString string];
    for (NSUInteger i = 0; i < links; i++)
        [source appendFormat:web ? @"https://example.com/reference/%05lu summary\n" : @"[[Reference %05lu]] text\n", (unsigned long)i];
    [source appendString:@"editing this short last line\n"];
    return source;
}
static NSString *Fixture(NSUInteger links) { return FixtureOfKind(links, NO); }

static void Scaling(void) {
    (void)NVSourceLinkRuns(@"[[warmup]]", @"plain");
    printf("case,links,utf16,record_hash,unique_record_hashes,extract_ms,first_publish_ms,unchanged_publish_ms,legacy_changed_line_ms\n");
    for (NSArray *fixture in @[@[@NO, @100], @[@NO, @500], @[@NO, @1000], @[@NO, @2000], @[@NO, @4000],
                              @[@YES, @500], @[@YES, @1000], @[@YES, @2000]]) {
        @autoreleasepool {
            NSUInteger count = [fixture[1] unsignedIntegerValue];
            BOOL web = [fixture[0] boolValue];
            NSString *source = FixtureOfKind(count, web);
            double started = Now();
            NSArray *links = NVSourceLinkRuns(source, @"plain");
            double extraction = (Now() - started) * 1000;
            Check(links.count == count, @"all fixture links extracted");
            NSMutableSet *hashes = [NSMutableSet set];
            for (NSDictionary *record in links) [hashes addObject:@(record.hash)];
            FixtureSession *session = [[FixtureSession alloc] init];
            session->sourceGeneration = 1;
            session->note = [[FixtureNote alloc] init];
            session->textStorage = [[NSTextStorage alloc] initWithString:source];
            NSDictionary *result = @{@"generation":@1, @"syntax":@"plain", @"linkRuns":links};
            started = Now();
            [session sourceAnalysis:nil didFinish:result];
            double first = (Now() - started) * 1000;
            [session->textStorage replaceCharactersInRange:NSMakeRange(source.length - 1, 0) withString:@"x"];
            session->sourceGeneration++;
            // The inserted character is after every link, so a complete fresh
            // analysis returns the exact same ranges and URLs for generation 2.
            result = @{@"generation":@2, @"syntax":@"plain", @"linkRuns":links};
            started = Now();
            [session sourceAnalysis:nil didFinish:result];
            double unchanged = (Now() - started) * 1000;
            __block NSUInteger applied = 0;
            [session->textStorage enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, source.length) options:0
                usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) applied++; }];
            Check(applied == count, @"publication preserved every link");
            // These are precisely the old sourceCharactersChanged: line-range
            // operations, exercised on the same storage after one final-line edit.
            NSRange changed = [[session->textStorage string] lineRangeForRange:NSMakeRange(source.length - 1, 1)];
            started = Now();
            [session->textStorage removeAttribute:NSLinkAttributeName range:changed];
            [session->textStorage addLinkAttributesForRange:changed syntaxIdentifier:@"plain"];
            double legacy = (Now() - started) * 1000;
            printf("%s,%lu,%lu,%lu,%lu,%.3f,%.3f,%.3f,%.3f\n", web ? "web" : "wiki", count, source.length, [links[0] hash], hashes.count,
                extraction, first, unchanged, legacy);
            fflush(stdout);
            [session->textStorage release]; [session->note release]; [session release];
        }
    }
}

static BOOL Await(BOOL (^condition)(void), double seconds) {
    double end = Now() + seconds;
    while (!condition() && Now() < end)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    return condition();
}

@interface Client : NSObject <NVSourceAnalysisDelegate> {
@public
    NSString *source;
    NSUInteger publications;
    double publishedAt;
}
@end
@implementation Client
- (NSDictionary *)snapshotForSourceAnalysis:(NVSourceAnalysis *)analysis {
    return @{@"source":source, @"syntax":@"plain", @"generation":@1, @"links":@YES, @"words":@NO};
}
- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:(NSDictionary *)result {
    publications++; publishedAt = Now();
}
@end

// Observe real decoration without delaying it. Cancellation is issued only
// after the large job has entered the non-cancellable production helper.
static IMP originalDecoration;
static atomic_bool watchLarge, enteredLarge, finishedLarge;
static double largeEnd;
static void ObserveDecoration(id receiver, SEL selector, NSRange range, NSString *syntax) {
    BOOL observed = atomic_exchange(&watchLarge, false);
    if (observed) atomic_store(&enteredLarge, true);
    ((void (*)(id, SEL, NSRange, NSString *))originalDecoration)(receiver, selector, range, syntax);
    if (observed) { largeEnd = Now(); atomic_store(&finishedLarge, true); }
}

static void Contention(void) {
    Client *small = [[Client alloc] init]; small->source = @"https://example.com small note";
    NVSourceAnalysis *smallAnalysis = [[NVSourceAnalysis alloc] initWithDelegate:small];
    double requested = Now(); [smallAnalysis request];
    Check(Await(^BOOL { return small->publications == 1; }, 5), @"idle short request completes");
    double idle = (small->publishedAt - requested) * 1000;

    Method method = class_getInstanceMethod([NSMutableAttributedString class], @selector(addLinkAttributesForRange:syntaxIdentifier:));
    originalDecoration = method_setImplementation(method, (IMP)ObserveDecoration);
    Client *large = [[Client alloc] init]; large->source = [Fixture(20000) copy];
    NVSourceAnalysis *largeAnalysis = [[NVSourceAnalysis alloc] initWithDelegate:large];
    atomic_store(&watchLarge, true);
    [largeAnalysis request];
    Check(Await(^BOOL { return atomic_load(&enteredLarge); }, 5), @"large extraction starts on real worker");
    double canceled = Now();
    [largeAnalysis close];
    requested = Now(); [smallAnalysis request];
    Check(Await(^BOOL { return small->publications == 2; }, 45), @"short request eventually completes behind canceled extraction");
    Check(atomic_load(&finishedLarge), @"large helper finished before small callback");
    Check(large->publications == 0, @"closed large job never publishes");
    printf("contention large_links=20000 utf16=%lu idle_short_ms=%.3f short_behind_closed_ms=%.3f closed_worker_remaining_ms=%.3f\n",
        large->source.length, idle, (small->publishedAt - requested)*1000, (largeEnd - canceled)*1000);
    [smallAnalysis close]; [smallAnalysis release]; [largeAnalysis release];
    [large->source release]; [large release]; [small release];
    method_setImplementation(method, originalDecoration);
}

int main(void) { @autoreleasepool {
    Scaling(); Contention(); printf("PASS: production publication scaling and canceled-job contention probes\n");
} return 0; }
