#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#include <time.h>

@interface NVSourceHighlighter (BoundaryReview)
- (void)applyCaptures;
- (void)clearDisplayCaptures;
@end

static NSUInteger Checks, Writes, Removes, UnsafeChanges;
static void Check(BOOL pass, const char *name) {
    Checks++;
    if (!pass) { fprintf(stderr, "FAIL: %s\n", name); exit(1); }
}
static double Clock(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1000000.0;
}
@interface ReviewLayout : NSLayoutManager
@end
@implementation ReviewLayout
- (void)addTemporaryAttribute:(NSAttributedStringKey)name value:(id)value forCharacterRange:(NSRange)range {
    if ([name isEqual:NVSourceCaptureAttributeName]) {
        Writes++;
        if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeChanges++;
    }
    [super addTemporaryAttribute:name value:value forCharacterRange:range];
}
- (void)removeTemporaryAttribute:(NSAttributedStringKey)name forCharacterRange:(NSRange)range {
    if ([name isEqual:NVSourceCaptureAttributeName]) {
        Removes++;
        if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeChanges++;
    }
    [super removeTemporaryAttribute:name forCharacterRange:range];
}
@end
static ReviewLayout *Attach(NSTextStorage *storage) {
    ReviewLayout *layout = [[[ReviewLayout alloc] init] autorelease];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(500, CGFLOAT_MAX)] autorelease];
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    return layout;
}
static void Pump(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}
static NSString *HTML(NSUInteger rows) {
    NSMutableString *source = [NSMutableString string];
    for (NSUInteger i = 0; i < rows; i++) [source appendFormat:@"<p id=\"key%lu\">value %lu</p>\n", i, i];
    return source;
}
static void DisplayBoundaries(NSString *directory) {
    printf("case,rows,captures,layouts,first_writes,first_removes,first_ms,reapply_writes,reapply_removes,reapply_ms,clear_removes,clear_ms\n");
    for (NSNumber *n in @[@1, @2, @3, @4, @20]) {
        NSUInteger count = [n unsignedIntegerValue];
        NSUInteger rowsAt = 4096 / (8 * count);
        for (NSNumber *r in @[@(rowsAt), @(rowsAt + 1)]) {
            @autoreleasepool {
                NSString *source = HTML([r unsignedIntegerValue]);
                NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
                NSArray *result = [parser capturesForString:source syntaxIdentifier:@"html" cancellationToken:NULL generation:0];
                Check([result count] == [r unsignedIntegerValue] * 8, "real HTML capture count");
                NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source];
                NSMutableArray *layouts = [NSMutableArray array];
                for (NSUInteger i = 0; i < count; i++) [layouts addObject:Attach(storage)];
                for (NSLayoutManager *layout in layouts)
                    [layout addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(0, 1)];
                NSAttributedString *original = [storage copy];
                NVSourceHighlighter *highlighter = [[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"html" queryDirectory:directory];
                [highlighter setValue:result forKey:@"captures"];
                NSUInteger expected = [result count] * count <= 4096 ? [result count] * count : 0;
                Writes = Removes = 0;
                double start = Clock(); [highlighter applyCaptures]; double firstMs = Clock() - start;
                NSUInteger firstWrites = Writes, firstRemoves = Removes;
                Check(Writes == expected && Removes == 0, "first application independently bounded");
                for (NSLayoutManager *layout in layouts) Check(NVSourceCapturesAreCurrent(layout) == !!expected, "current revision agrees with display fallback");
                Writes = Removes = 0;
                start = Clock(); [highlighter applyCaptures]; double againMs = Clock() - start;
                NSUInteger againWrites = Writes, againRemoves = Removes;
                Check(Writes == expected, "reapplication independently bounded");
                Check(Removes == (expected ? count : 0), "reapplication clears only prior captures");
                Writes = Removes = 0;
                start = Clock(); [highlighter close]; double clearMs = Clock() - start;
                Check(Writes == 0 && Removes == (expected ? count : 0), "close clears one range per highlighted layout");
                Check([storage isEqualToAttributedString:original], "budget transitions preserve stored attributes");
                for (NSLayoutManager *layout in layouts)
                    Check([[layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] isEqual:[NSColor yellowColor]], "search background survives fallback and close");
                printf("boundary,%lu,%lu,%lu,%lu,%lu,%.3f,%lu,%lu,%.3f,%lu,%.3f\n", [r unsignedIntegerValue], [result count], count, firstWrites, firstRemoves, firstMs, againWrites, againRemoves, againMs, Removes, clearMs);
                [highlighter release]; [original release]; [parser release];
                for (NSLayoutManager *layout in layouts) [storage removeLayoutManager:layout];
                [storage release];
            }
        }
    }
}
static void Transitions(NSString *directory) {
    NSString *source = HTML(128); // 1,024 captures: exactly 4,096 writes on four layouts.
    NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
    NSArray *result = [parser capturesForString:source syntaxIdentifier:@"html" cancellationToken:NULL generation:0];
    Check([result count] == 1024, "transition fixture capture count");
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source];
    NSMutableArray *layouts = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++) [layouts addObject:Attach(storage)];
    NVSourceHighlighter *h = [[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"html" queryDirectory:directory];
    [h setValue:result forKey:@"captures"]; [h layoutsChanged];
    Check(NVSourceCapturesAreCurrent(layouts[0]), "four-layout boundary initially highlighted");
    ReviewLayout *extra = [Attach(storage) retain];
    Writes = Removes = 0;
    double start = Clock(); [h layoutsChanged]; double over = Clock() - start;
    Check(Writes == 0 && Removes == 4, "fifth layout triggers whole-revision plain fallback");
    for (NSLayoutManager *layout in [storage layoutManagers])
        Check(!NVSourceCapturesAreCurrent(layout), "fallback invalidates all layout semantics");
    [storage removeLayoutManager:extra];
    Writes = Removes = 0;
    start = Clock(); [h layoutsChanged]; double restored = Clock() - start;
    Check(Writes == 4096 && Removes == 0, "detach restores cached captures without parser work");
    Check(!NVSourceCapturesAreCurrent(extra), "detached fallback layout is not current");
    ReviewLayout *first = [layouts[0] retain];
    [storage removeLayoutManager:first];
    Writes = Removes = 0; [h layoutsChanged];
    Check(Writes == 3072 && Removes == 3, "highlighted detach reapplies to remaining layouts");
    Check(!NVSourceCapturesAreCurrent(first), "detached old revision invalidated");
    [storage addLayoutManager:first];
    Writes = Removes = 0; [h layoutsChanged];
    Check(Writes == 4096 && Removes == 4, "reattach removes detached old attributes before new revision");
    Writes = Removes = UnsafeChanges = 0;
    uint64_t generation = [h generation];
    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:@"{\"next\":true}"];
    Check([h generation] > generation && UnsafeChanges == 0 && Removes == 0, "shortening edit invalidates without in-notification TextKit operations");
    for (NSLayoutManager *layout in layouts) Check(!NVSourceCapturesAreCurrent(layout), "shortening edit invalidates revision immediately");
    Pump(0.015); // The reparse is delayed 60ms; the zero-delay cleanup must run first.
    Check(Removes == 4 && Writes == 0, "deferred cleanup clears all four old layouts before analysis");
    [h setSyntaxIdentifier:@"json"];
    Pump(0.4);
    Check(NVSourceCapturesAreCurrent(first), "new source parses after deferred cleanup");
    Check(Writes > 0 && Writes <= 4096 && UnsafeChanges == 0, "asynchronous new revision stays within independent write bound");
    printf("transitions: fifth_layout_fallback_ms=%.3f four_layout_restore_ms=%.3f asynchronous_json_writes=%lu unsafe_changes=%lu\n", over, restored, Writes, UnsafeChanges);
    [h close]; [h release];
    for (NSLayoutManager *layout in layouts) [storage removeLayoutManager:layout];
    [extra release]; [first release]; [storage release]; [parser release];
}
static void WorkerFallbacks(NSString *directory) {
    NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
    uint64_t token = 2;
    double start = Clock();
    NSArray *result = [parser capturesForString:HTML(512) syntaxIdentifier:@"html" cancellationToken:&token generation:1];
    double cancelled = Clock() - start;
    Check(result == nil, "obsolete generation cancels before parsing");
    NSString *tooLarge = [@"" stringByPaddingToLength:524289 withString:@"a" startingAtIndex:0];
    start = Clock(); result = [parser capturesForString:tooLarge syntaxIdentifier:@"html" cancellationToken:NULL generation:0];
    double lengthMs = Clock() - start;
    Check(result != nil && [result count] == 0, "length bound returns plain fallback");
    NSString *largeHTML = HTML(4000);
    start = Clock(); result = [parser capturesForString:largeHTML syntaxIdentifier:@"html" cancellationToken:NULL generation:0];
    double captureMs = Clock() - start;
    Check(result == nil, "capture/work bound rejects 32,000-capture HTML");
    NSMutableString *markdown = [NSMutableString string];
    for (NSUInteger i = 0; i < 6000; i++) [markdown appendString:@"## Title\n\nThis is **bold** with `code`.\n\n"];
    start = Clock(); result = [parser capturesForString:markdown syntaxIdentifier:@"markdown" cancellationToken:NULL generation:0];
    double markdownMs = Clock() - start;
    Check(result == nil, "worker bound rejects costly Markdown");
    result = [parser capturesForString:@"{\"ok\":true}" syntaxIdentifier:@"json" cancellationToken:NULL generation:0];
    Check([result count] > 0, "small result recovers after worker fallbacks");
    [parser release];
    parser = [[NVSourceParser alloc] initWithQueryDirectory:[directory stringByAppendingPathComponent:@"missing"]];
    result = [parser capturesForString:@"{\"ok\":true}" syntaxIdentifier:@"json" cancellationToken:NULL generation:0];
    Check(result == nil, "missing query uses plain fallback");
    [parser release];
    printf("worker: cancelled_ms=%.3f length_ms=%.3f capture_limit_ms=%.3f markdown_budget_ms=%.3f\n", cancelled, lengthMs, captureMs, markdownMs);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, "query directory supplied");
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        DisplayBoundaries(directory);
        Transitions(directory);
        WorkerFallbacks(directory);
        Check(UnsafeChanges == 0, "no temporary attributes changed during character processing");
        printf("PASS: %lu checks\n", Checks);
    }
    return 0;
}
