#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#include <time.h>
#include <sys/resource.h>

static NSUInteger checks;
static void Check(BOOL pass, NSString *message) {
    checks++;
    if (!pass) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSUInteger UnsafeTemporaryChanges;
@interface NVBoundaryCheckingLayoutManager : NSLayoutManager
@end
@implementation NVBoundaryCheckingLayoutManager
- (void)removeTemporaryAttribute:(NSAttributedStringKey)name forCharacterRange:(NSRange)range {
    if ([name isEqual:NVSourceCaptureAttributeName] && ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)) UnsafeTemporaryChanges++;
    [super removeTemporaryAttribute:name forCharacterRange:range];
}
@end

static NSArray *Parse(NVSourceParser *parser, NSString *source, NSString *syntax) {
    NSArray *result = [parser capturesForString:source syntaxIdentifier:syntax cancellationToken:NULL generation:0];
    for (NSDictionary *capture in result) {
        NSRange range = [capture[@"range"] rangeValue];
        Check(range.length && NSMaxRange(range) <= [source length], @"capture stays within UTF-16 source bounds");
    }
    return result;
}
static BOOL Has(NSArray *captures, NSString *source, NSString *kind, NSString *text) {
    for (NSDictionary *capture in captures) {
        if ([capture[@"kind"] isEqualToString:kind] && [[source substringWithRange:[capture[@"range"] rangeValue]] isEqualToString:text]) return YES;
    }
    return NO;
}
static NSArray *Canonical(NSArray *captures) {
    return [captures sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *left = [NSString stringWithFormat:@"%@:%@", a[@"range"], a[@"kind"]];
        NSString *right = [NSString stringWithFormat:@"%@:%@", b[@"range"], b[@"kind"]];
        return [left compare:right];
    }];
}
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([end timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static BOOL WaitForCapture(NSLayoutManager *layout, NSString *kind, NSUInteger index) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:3.0];
    while ([end timeIntervalSinceNow] > 0) {
        if (NVSourceCapturesAreCurrent(layout) && [[layout temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:index effectiveRange:NULL] isEqual:kind]) return YES;
        Pump(0.01);
    }
    return NO;
}
static void Benchmark(NSString *directory) {
    NSString *line = @"## Heading 😀\n\nA **bold** word and [a link](https://example.com), with `code`.\n\n";
    for (NSNumber *count in @[@100, @1500]) {
        NSString *source = [@"" stringByPaddingToLength:[count unsignedIntegerValue] * [line length] withString:line startingAtIndex:0];
        NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
        NSMutableArray *durations = [NSMutableArray array];
        NSUInteger fallback = 0;
        for (NSUInteger i = 0; i < 10; i++) {
            @autoreleasepool {
                NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
                NSArray *result = [parser capturesForString:[source stringByAppendingString:i % 2 ? @"a" : @"b"] syntaxIdentifier:@"markdown" cancellationToken:NULL generation:0];
                [durations addObject:@(([NSDate timeIntervalSinceReferenceDate] - start) * 1000.0)];
                if (!result) fallback++;
            }
        }
        [durations sortUsingSelector:@selector(compare:)];
        NSLog(@"BENCH: %lu UTF-16 units Markdown: p50 %.1f ms, max %.1f ms, %lu/10 bounded fallbacks", (unsigned long)[source length], [durations[5] doubleValue], [[durations lastObject] doubleValue], (unsigned long)fallback);
        Check([[durations lastObject] doubleValue] < 2000.0, @"large-note parser stops within a conservative responsiveness ceiling");
        [parser release];
    }
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    NSLog(@"BENCH: harness peak resident memory %.1f MiB", (double)usage.ru_maxrss / (1024.0 * 1024.0));
}
static void CheckTextKit(NSString *directory) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:@"{\"key\": 42}"];
    NSAttributedString *original = [storage copy];
    NSLayoutManager *first = [[NVBoundaryCheckingLayoutManager alloc] init], *second = [[NVBoundaryCheckingLayoutManager alloc] init];
    [storage addLayoutManager:first]; [storage addLayoutManager:second];
    NSColor *search = [NSColor yellowColor];
    [first addTemporaryAttribute:NSBackgroundColorAttributeName value:search forCharacterRange:NSMakeRange(1, 5)];
    NVSourceHighlighter *analysis = [[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"json" queryDirectory:directory];
    [analysis layoutsChanged];
    Check(WaitForCapture(first, @"string.special.key", 2), @"analysis applies semantic display capture asynchronously");
    Check(WaitForCapture(second, @"string.special.key", 2), @"peer layout receives shared analysis");
    Check([storage isEqualToAttributedString:original], @"syntax display never mutates shared or persisted attributes");
    Check([[first temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:2 effectiveRange:NULL] isEqual:search], @"syntax preserves per-window search highlight");
    Check([second temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:2 effectiveRange:NULL] == nil, @"search display remains window-local");
    uint64_t generation = [analysis generation];
    [storage addAttribute:@"fixture" value:@YES range:NSMakeRange(0, [storage length])];
    Check([analysis generation] == generation, @"attribute-only updates do not reparse");
    [storage replaceCharactersInRange:NSMakeRange(8, 2) withString:@"true"];
    Check([analysis generation] > generation, @"character edits advance analysis before model commit");
    Check(!NVSourceCapturesAreCurrent(first) && !NVSourceCapturesAreCurrent(second), @"character edit invalidates obsolete display synchronously before touching TextKit");
    Check(WaitForCapture(first, @"constant.builtin", 9), @"edited source receives current result");
    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:@"<b>Now</b>"];
    [analysis setSyntaxIdentifier:@"html"];
    Check(WaitForCapture(first, @"tag", 1), @"syntax and source switches reject obsolete requests");
    [analysis setSyntaxIdentifier:@"plain"];
    Check([first temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:1 effectiveRange:NULL] == nil, @"plain mode clears all syntax captures");
    Pump(0.2);
    Check([second temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:1 effectiveRange:NULL] == nil, @"old worker result cannot repaint plain source");
    [analysis setSyntaxIdentifier:@"html"];
    [analysis close];
    Pump(0.2);
    Check(!NVSourceCapturesAreCurrent(first) && [first temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:1 effectiveRange:NULL] == nil, @"closed analysis cancels pending work and display");
    [analysis release]; [storage removeLayoutManager:first]; [storage removeLayoutManager:second];
    [first release]; [second release]; [storage release]; [original release];
}
static void CheckLaidOutShortening(NSString *directory) {
    NSMutableString *body = [NSMutableString stringWithString:@"# Source workflow\n\nEditable **Markdown** stays in the note.\n\n"];
    for (NSUInteger line = 0; line < 80; line++) [body appendFormat:@"Paragraph %lu has source characters, café and 😀.\n\n", (unsigned long)line];
    NSString *prefix = @"An undoable source edit.\n\n";
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:[prefix stringByAppendingString:body]
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];
    NSLayoutManager *layout = [[NVBoundaryCheckingLayoutManager alloc] init];
    NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(450, CGFLOAT_MAX)];
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    NVSourceHighlighter *analysis = [[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:@"markdown" queryDirectory:directory];
    [analysis layoutsChanged];
    Check(WaitForCapture(layout, @"text.title", [prefix length] + 2), @"large source has syntax captures before Undo-style shortening");
    [layout ensureLayoutForTextContainer:container];
    NSRect oldBounds = [layout boundingRectForGlyphRange:NSMakeRange(0, [layout numberOfGlyphs]) inTextContainer:container];
    Check(NSHeight(oldBounds) > 1000, @"shortening fixture contains cached glyphs across many laid-out lines");
    [storage deleteCharactersInRange:NSMakeRange(0, [prefix length])];
    Check([[storage string] isEqual:body], @"shortening a fully laid-out highlighted source preserves exactly the remaining characters");
    Check(!NVSourceCapturesAreCurrent(layout), @"old captures stop drawing immediately after a shortening edit");
    [layout ensureLayoutForTextContainer:container];
    NSRect newBounds = [layout boundingRectForGlyphRange:NSMakeRange(0, [layout numberOfGlyphs]) inTextContainer:container];
    Check(NSHeight(newBounds) <= NSHeight(oldBounds), @"TextKit refreshes shortened glyph ranges before capture removal");
    Check(WaitForCapture(layout, @"text.title", 2), @"shortened source receives fresh captures after TextKit finishes");
    [storage insertAttributedString:[[[NSAttributedString alloc] initWithString:prefix] autorelease] atIndex:0];
    Check(WaitForCapture(layout, @"text.title", [prefix length] + 2), @"Redo-style insertion restores capture positions");
    [layout ensureLayoutForTextContainer:container];
    [storage deleteCharactersInRange:NSMakeRange(0, [storage length])];
    Check([storage length] == 0 && !NVSourceCapturesAreCurrent(layout), @"whole-document deletion invalidates captures without stale glyph reads");
    Pump(0.1);
    Check(UnsafeTemporaryChanges == 0, @"capture removal never runs before TextKit processes a character edit");
    [analysis close]; [analysis release];
    [storage removeLayoutManager:layout]; [layout removeTextContainerAtIndex:0];
    [container release]; [layout release]; [storage release];
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"query path argument");
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
        NSString *json = @"{\r\n  \"😀\": \"é\", \"value\": 123, \"ok\": true, \"nothing\": null\r\n}\n";
        NSArray *captures = Parse(parser, json, @"json");
        Check([captures count] > 8, @"JSON query produces semantic captures");
        Check(Has(captures, json, @"string.special.key", @"\"😀\""), @"surrogate-pair JSON key uses Cocoa ranges");
        Check(Has(captures, json, @"string", @"\"é\""), @"combining mark retains its source");
        Check(Has(captures, json, @"number", @"123"), @"JSON number capture");
        Check(Has(captures, json, @"constant.builtin", @"true"), @"JSON constant capture");
        NSArray *fixtures = @[@"{\"x\": \"abc\"}", @"{\"y\": \"def\"}", @"{\"y\": \"😀def\"}", @"{\"y\": \"😁def\"}", @"{\"y\": \"def\"}", @"{\r\n\"y\": \"def\"}\r\n", @"{\"y\":", @"{\"y\": [true, false, null]}", @"[]", @"42", @"{}"];
        for (NSString *source in fixtures) {
            NVSourceParser *fresh = [[NVSourceParser alloc] initWithQueryDirectory:directory];
            Check([Canonical(Parse(parser, source, @"json")) isEqual:Canonical(Parse(fresh, source, @"json"))], @"incremental captures equal fresh captures after equal-shape, Unicode, and malformed edits");
            [fresh release];
        }
        NSString *html = @"<!doctype html>\r\n<h1 id=\"😀\">Hello <em>é</em></h1><!-- note -->";
        captures = Parse(parser, html, @"html");
        Check(Has(captures, html, @"tag", @"h1"), @"HTML tag");
        Check(Has(captures, html, @"attribute", @"id"), @"HTML attribute");
        Check(Has(captures, html, @"string", @"😀"), @"HTML attribute Unicode");
        Check(Has(captures, html, @"comment", @"<!-- note -->"), @"HTML comment");
        NSString *markdown = @"# Heading 😀\r\n\r\nA **bold** and *emphasis* [link](https://example.com) with `code`.\n\n```json\n{\"raw\": 42}\n```\n\n- item\n\nTitle\n=====\n\nArchive:\n@taskpaper\n\n[^1]: MultiMarkdown footnote\n";
        captures = Parse(parser, markdown, @"markdown");
        Check(Has(captures, markdown, @"text.title", @"Heading 😀"), @"Markdown block heading");
        Check(Has(captures, markdown, @"text.strong", @"**bold**"), @"Markdown inline strong");
        Check(Has(captures, markdown, @"text.emphasis", @"*emphasis*"), @"Markdown inline emphasis");
        Check(Has(captures, markdown, @"text.literal", @"`code`"), @"Markdown code span");
        Check(Has(captures, markdown, @"text.uri", @"https://example.com"), @"Markdown link");
        Check(Has(captures, markdown, @"none", @"{\"raw\": 42}\n"), @"code fence remains uninjected source");
        for (NSString *source in @[markdown, [markdown stringByReplacingOccurrencesOfString:@"**bold**" withString:@"*small*"], @"````\n# no heading\n", @"# yes heading\n", @"Text with [unfinished](\n\n## Next\n"]) {
            NVSourceParser *fresh = [[NVSourceParser alloc] initWithQueryDirectory:directory];
            Check([Canonical(Parse(parser, source, @"markdown")) isEqual:Canonical(Parse(fresh, source, @"markdown"))], @"Markdown inline ranges refresh after block edits");
            [fresh release];
        }
        Check([Parse(parser, markdown, @"plain") count] == 0, @"plain source fallback");
        Check([Parse(parser, @"h1. Textile\n*bold*", @"textile") count] == 0, @"Textile source fallback");
        NSString *large = [@"{" stringByPaddingToLength:600000 withString:@"[" startingAtIndex:0];
        Check([Parse(parser, large, @"json") count] == 0, @"oversize source falls back without captures");
        uint64_t token = 2;
        Check([parser capturesForString:json syntaxIdentifier:@"json" cancellationToken:&token generation:1] == nil, @"cancelled request has no result");
        Check([Parse(parser, json, @"json") count] > 0, @"new request recovers after cancellation");
        uint64_t liveToken = 10;
        uint64_t *liveTokenPointer = &liveToken;
        dispatch_semaphore_t cancelled = dispatch_semaphore_create(0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            __atomic_store_n(liveTokenPointer, 11, __ATOMIC_RELAXED);
            dispatch_semaphore_signal(cancelled);
        });
        NSString *busy = [@"" stringByPaddingToLength:120000 withString:@"# Title\n\n**strong** text.\n\n" startingAtIndex:0];
        Check([parser capturesForString:busy syntaxIdentifier:@"markdown" cancellationToken:&liveToken generation:10] == nil, @"generation change cancels an in-flight parser");
        dispatch_semaphore_wait(cancelled, DISPATCH_TIME_FOREVER);
        dispatch_release(cancelled);
        Check([Parse(parser, json, @"json") count] > 0, @"parser recovers after in-flight cancellation");
        NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"((string) @string (#eq? @string \"never\"))" writeToFile:[temp stringByAppendingPathComponent:@"json.scm"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NVSourceParser *unsupported = [[NVSourceParser alloc] initWithQueryDirectory:temp];
        Check(Parse(unsupported, json, @"json") == nil, @"unsupported query predicate explicitly falls back");
        [unsupported release];
        [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
        CheckTextKit(directory);
        CheckLaidOutShortening(directory);
        Benchmark(directory);
        NSLog(@"PASS: %lu source highlighting checks", (unsigned long)checks);
        [parser release];
    }
    return 0;
}
