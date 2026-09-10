#import <Cocoa/Cocoa.h>
#import <mach/mach_time.h>
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

static NSDictionary *Run(NSUInteger location, NSUInteger length, NSString *target) {
    return @{@"range":[NSValue valueWithRange:NSMakeRange(location, length)], @"url":[NSURL URLWithString:target]};
}
static NSArray *ReadRuns(NSAttributedString *storage) {
    NSMutableArray *runs = [NSMutableArray array];
    [storage enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, storage.length) options:0
        usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value) [runs addObject:@{@"range":[NSValue valueWithRange:range], @"url":value}];
        }];
    return runs;
}
static void PutRuns(NSMutableAttributedString *storage, NSArray *runs) {
    for (NSDictionary *run in runs)
        [storage addAttribute:NSLinkAttributeName value:run[@"url"] range:[run[@"range"] rangeValue]];
}
static void Correctness(void) {
    NSString *a = @"https://example.com/a", *b = @"https://example.com/b", *c = @"https://example.com/c";
    NSArray *cases = @[
        @[@"unchanged", @[Run(2, 6, a), Run(20, 5, b)], @[Run(2, 6, a), Run(20, 5, b)]],
        @[@"same range, changed target", @[Run(2, 6, a)], @[Run(2, 6, b)]],
        @[@"one new run overlaps two old runs", @[Run(2, 10, a), Run(18, 6, b)], @[Run(4, 17, c)]],
        @[@"shifted", @[Run(2, 5, a)], @[Run(3, 5, a)]],
        @[@"merge adjacent runs", @[Run(2, 3, a), Run(5, 4, b)], @[Run(2, 7, c)]],
        @[@"split a run", @[Run(2, 7, a)], @[Run(2, 3, b), Run(5, 4, c)]],
        @[@"insert between preserved runs", @[Run(2, 3, a), Run(20, 4, b)], @[Run(2, 3, a), Run(10, 5, c), Run(20, 4, b)]],
        @[@"remove between preserved runs", @[Run(2, 3, a), Run(10, 5, c), Run(20, 4, b)], @[Run(2, 3, a), Run(20, 4, b)]],
        @[@"empty to links", @[], @[Run(2, 5, a)]],
        @[@"links to empty", @[Run(2, 5, a)], @[]],
        @[@"empty to empty", @[], @[]],
    ];
    NSString *source = @"abcdefghijklmnopqrstuvwxyz0123456789";
    for (NSArray *test in cases) {
        @autoreleasepool {
            FixtureSession *session = [[FixtureSession alloc] init];
            session->sourceGeneration = 1;
            session->note = [[FixtureNote alloc] init];
            session->textStorage = [[NSTextStorage alloc] initWithString:source attributes:@{@"ProbeUnrelated":@"preserved"}];
            PutRuns(session->textStorage, test[1]);
            NSMutableAttributedString *expected = [[[NSMutableAttributedString alloc] initWithString:source] autorelease];
            PutRuns(expected, test[2]);
            __block NSUInteger edits = 0;
            id observation = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSTextStorageDidProcessEditingNotification object:session->textStorage queue:nil
                usingBlock:^(NSNotification *notification) { edits++; }];
            [session sourceAnalysis:nil didFinish:@{@"generation":@1, @"syntax":@"plain", @"linkRuns":test[2]}];
            Check([ReadRuns(session->textStorage) isEqual:ReadRuns(expected)], [test[0] stringByAppendingString:@": exact final link runs"]);
            Check([[session->textStorage string] isEqual:source], @"publication preserves characters");
            for (NSUInteger i = 0; i < source.length; i++)
                Check([[session->textStorage attribute:@"ProbeUnrelated" atIndex:i effectiveRange:NULL] isEqual:@"preserved"], @"publication preserves unrelated attributes");
            if ([test[0] isEqual:@"unchanged"] || [test[0] isEqual:@"empty to empty"])
                Check(edits == 0, @"identical runs cause no text-storage edit notification");
            NSUInteger editsBeforeRepeat = edits;
            [session sourceAnalysis:nil didFinish:@{@"generation":@1, @"syntax":@"plain", @"linkRuns":test[2]}];
            Check(edits == editsBeforeRepeat, @"repeated publication has no attribute edits");
            [[NSNotificationCenter defaultCenter] removeObserver:observation];
            printf("PASS semantic: %s\n", [test[0] UTF8String]);
            [session->textStorage release]; [session->note release]; [session release];
        }
    }
}

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

int main(void) { @autoreleasepool {
    Correctness(); Scaling(); printf("PASS: production link-publication semantics and scaling probes\n");
} return 0; }
