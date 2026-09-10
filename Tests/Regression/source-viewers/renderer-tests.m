#import <Foundation/Foundation.h>
#import "NVNoteContentSnapshot.h"
#import "NVMarkupRenderer.h"
#import <unistd.h>

static NSUInteger Checks = 0;
static void Check(BOOL value, NSString *message) {
    Checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
}
static NVNoteContentSnapshot *Snapshot(NSString *source, NSString *title, NSUInteger generation) {
    return [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:@"test-library" noteIdentifier:@"test-note" generation:generation title:title source:source contentType:@"public.plain-text" assetRootURL:nil] autorelease];
}
static void PumpUntil(BOOL (^condition)(void), NSTimeInterval limit) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:limit];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(condition(), @"asynchronous request completes within the test deadline");
}
static NVMarkupRenderResult *Render(NVMarkupRenderer *renderer, NVNoteContentSnapshot *snapshot, NSString *viewer, NSError **failure) {
    __block BOOL done = NO;
    __block NVMarkupRenderResult *result = nil;
    __block NSError *error = nil;
    [renderer renderSnapshot:snapshot viewerIdentifier:viewer completion:^(NVMarkupRenderResult *rendered, NSError *renderError) {
        Check([NSThread isMainThread], @"completion reaches the main thread");
        result = [rendered retain]; error = [renderError retain]; done = YES;
    }];
    PumpUntil(^BOOL{ return done; }, 8);
    if (failure) *failure = [error autorelease]; else [error release];
    return [result autorelease];
}
static void SetHelper(NSString *path, NSString *script) {
    Check([script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write disposable helper fixture");
    Check([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:path error:NULL], @"fixture executable permission");
}
static NSString *ChunkedHTML(NSUInteger bytes) {
    NSMutableString *HTML = [NSMutableString stringWithString:@"<p>START_SENTINEL</p>"];
    NSString *chunk = [NSString stringWithFormat:@"<p>%@</p>", [@"x" stringByPaddingToLength:1024*1024 withString:@"x" startingAtIndex:0]];
    NSString *end = @"END_SENTINEL</p>";
    while ([HTML length] + [chunk length] + 3 + [end length] <= bytes) [HTML appendString:chunk];
    [HTML appendString:@"<p>"];
    [HTML appendString:[@"x" stringByPaddingToLength:bytes - [HTML length] - [end length] withString:@"x" startingAtIndex:0]];
    [HTML appendString:end];
    return HTML;
}
static void CheckHTMLParserLimits(NVMarkupRenderer *renderer) {
    for (NSNumber *size in @[@(9*1024*1024), @(11*1024*1024), @(15*1024*1024)]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *body = [@"x" stringByPaddingToLength:[size unsignedIntegerValue] withString:@"x" startingAtIndex:0];
        NSString *source = [NSString stringWithFormat:@"<main><p>START_SENTINEL%@END_SENTINEL</p><section>After paragraph</section></main>", body];
        NSError *error = nil;
        NVMarkupRenderResult *result = Render(renderer, Snapshot(source, @"Parser text limit", 22), @"html", &error);
        if ([size unsignedIntegerValue] == 9*1024*1024) {
            Check(result && !error && [[result HTML] containsString:@"START_SENTINEL"] && [[result HTML] containsString:@"END_SENTINEL"] && [[result HTML] containsString:@"After paragraph"], @"9 MiB paragraph preserves both boundaries despite recoverable HTML5 diagnostics");
        } else {
            Check(!result && [[error domain] isEqual:NVMarkupRendererErrorDomain] && [error code] == NVMarkupLimitExceeded, @"11 and 15 MiB paragraphs fail explicitly instead of returning truncated HTML");
        }
        [pool drain];
    }
    // Separate text nodes remain within libxml's limit even at our full input
    // budget. Rejecting every source above one text-node limit is unnecessary.
    for (NSUInteger bytes = 16*1024*1024; bytes <= 16*1024*1024 + 1; bytes++) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *source = ChunkedHTML(bytes);
        Check([source lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == bytes, @"chunked fixture meets the exact source-byte boundary");
        NSError *error = nil;
        NVMarkupRenderResult *result = Render(renderer, Snapshot(source, @"Source byte limit", 23), @"html", &error);
        if (bytes == 16*1024*1024)
            Check(result && !error && [[result HTML] containsString:@"START_SENTINEL"] && [[result HTML] containsString:@"END_SENTINEL"], @"16 MiB split across bounded text nodes retains all content");
        else
            Check(!result && [error code] == NVMarkupLimitExceeded, @"one byte above the source limit returns a structured failure");
        [pool drain];
    }
    for (NSNumber *depth in @[@240, @300]) {
        NSMutableString *source = [NSMutableString string];
        for (NSUInteger index = 0; index < [depth unsignedIntegerValue]; index++) [source appendString:@"<div>"];
        [source appendString:@"DEPTH_SENTINEL"];
        for (NSUInteger index = 0; index < [depth unsignedIntegerValue]; index++) [source appendString:@"</div>"];
        [source appendString:@"<section>After nesting</section>"];
        NSError *error = nil;
        NVMarkupRenderResult *result = Render(renderer, Snapshot(source, @"Parser depth limit", 24), @"html", &error);
        if ([depth unsignedIntegerValue] == 240)
            Check(result && !error && [[result HTML] containsString:@"DEPTH_SENTINEL"] && [[result HTML] containsString:@"After nesting"], @"nesting below the parser limit preserves inner and following text");
        else
            Check(!result && [error code] == NVMarkupLimitExceeded, @"excessive nesting fails instead of exporting a partial tree");
    }
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Check(argc == 2, @"disposable resource bundle argument");
    NSString *bundlePath = [NSString stringWithUTF8String:argv[1]];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    Check(bundle != nil, @"load isolated converter resource bundle");
    NVMarkupRenderer *renderer = [[[NVMarkupRenderer alloc] initWithResourceBundle:bundle] autorelease];
    [renderer setTimeLimit:4];
    NSMutableString *source = [NSMutableString stringWithString:@"  # Heading\r\n\t日本語 😀\n\n"];
    NVNoteContentSnapshot *snapshot = Snapshot(source, @"A <title> & one", 12);
    [source appendString:@"changed"];
    Check(![[snapshot source] hasSuffix:@"changed"], @"snapshot owns an immutable source copy");
    Check([[snapshot source] hasSuffix:@"\n\n"] && [[snapshot source] containsString:@"\r\n\t"], @"snapshot preserves line endings and whitespace");
    Check([snapshot generation] == 12 && [[snapshot libraryIdentifier] isEqual:@"test-library"], @"snapshot records explicit identity and generation");
    NSError *error = nil;
    NVMarkupRenderResult *result = Render(renderer, snapshot, @"markdown", &error);
    Check(result != nil && error == nil, @"bundled MultiMarkdown renders asynchronously");
    Check([[result HTML] containsString:@"Heading"] && [[result HTML] containsString:@"日本語 😀"], @"Markdown output preserves Unicode");
    Check([[result HTML] containsString:@"A &lt;title&gt; &amp; one"], @"rendered title comes from the explicit request and is escaped");
    Check([result snapshot] == snapshot && [[result viewerIdentifier] isEqual:@"markdown"], @"render result retains the source request identity");
    Check(![[snapshot source] containsString:@"<html"], @"rendering never rewrites the source snapshot");
    result = Render(renderer, Snapshot(@"h1. Textile\n\n*emphasis* café", @"Textile title", 13), @"textile", &error);
    Check(result && !error && [[result HTML] containsString:@"<h1>Textile"] && [[result HTML] containsString:@"café"], @"bundled Textile renders Unicode with the matching title");
    NSString *org = [NSString stringWithContentsOfFile:[[bundle resourcePath] stringByAppendingPathComponent:@"org-fixture.org"] encoding:NSUTF8StringEncoding error:NULL];
    Check(org != nil, @"load the complete Org fixture");
    NVNoteContentSnapshot *orgSnapshot = Snapshot(org, @"Org & notes", 14);
    result = Render(renderer, orgSnapshot, @"org", &error);
    Check(result && !error, @"bundled Org helper renders a Plain Text source snapshot");
    Check([result snapshot] == orgSnapshot && [[result viewerIdentifier] isEqual:@"org"], @"Org result retains the request identity and selected viewer");
    Check([[orgSnapshot source] isEqual:org] && [[orgSnapshot contentType] isEqual:@"public.plain-text"], @"Org preview preserves source text and source syntax");
    NSString *orgHTML = [result HTML];
    Check([orgHTML containsString:@"TODO"] && [orgHTML containsString:@"DONE"] && [orgHTML containsString:@"[#A]"] && [orgHTML containsString:@":work:"], @"Org preview preserves task state, priorities, and heading tags");
    Check([orgHTML containsString:@"<ol>"] && [orgHTML containsString:@"<ul>"] && [orgHTML containsString:@"[X]"] && [orgHTML containsString:@"[ ]"], @"Org preview preserves ordered lists and readonly checkbox state");
    Check([orgHTML containsString:@"<table>"] && [orgHTML containsString:@"日本語 👩‍💻"] && [orgHTML containsString:@"&lt;tag&gt;"], @"Org tables, Unicode, and literal source blocks survive sanitization");
    Check([orgHTML containsString:@"href=\"picture.png\""] && [orgHTML containsString:@"Org &amp; notes"] && [orgHTML containsString:@"script-src 'none'"], @"Org HTML export retains scoped relative links, explicit title, and resource policy");
    NSString *orgLinks = @"[[*Release plan][Starred]]\n[[Release plan][Exact]]\n[[#release-alias][Alias]]\n\n* TODO Release plan\n:PROPERTIES:\n:CUSTOM_ID: release-plan\n:ID: release-alias\n:END:\n";
    result = Render(renderer, Snapshot(orgLinks, @"Org heading links", 17), @"org", &error);
    Check(result && !error && [[result HTML] containsString:@"id=\"release-plan\""], @"Org heading anchor survives the document sanitizer");
    Check([[result HTML] containsString:@"href=\"#release-plan\">Starred</a>"] && [[result HTML] containsString:@"href=\"#release-plan\">Exact</a>"] && [[result HTML] containsString:@"href=\"#release-plan\">Alias</a>"], @"Org heading and ID alias links remain same-document fragments after sanitization");
    Check([[[result snapshot] source] isEqual:orgLinks], @"Org heading resolution leaves the source snapshot unchanged");
    NSString *orgInert = @"#+BEGIN_EXPORT html\n<script>document.title='unexpected'</script><p onclick='ignored()'>Org HTML</p>\n#+END_EXPORT\n";
    result = Render(renderer, Snapshot(orgInert, @"Inert Org", 15), @"org", &error);
    Check(result && !error && [[result HTML] containsString:@"Org HTML"] && ![[result HTML] containsString:@"<script"] && ![[result HTML] containsString:@"onclick"], @"Org raw HTML uses the same inert document sanitizer");
    result = Render(renderer, Snapshot(@"", @"Empty Org", 16), @"org", &error);
    Check(result && !error, @"empty Org source produces a valid viewer document");
    NSString *HTML = @"<!doctype html><html><head><title>wrong note</title><script>document.title='BAD'</script><style>p{color:red}</style></head><body onload='BAD()' contenteditable='true'><form action='https://example.invalid/post'><input value='data'><textarea>text</textarea><button>Submit</button></form><iframe src='https://example.invalid/'></iframe><p>Native HTML &amp; 😀</p><img src='image.png'><a href='https://example.invalid/'>Link</a></body></html>";
    result = Render(renderer, Snapshot(HTML, @"Correct note", 14), @"html", &error);
    Check(result && !error, @"direct HTML viewer accepts complete documents");
    NSString *rendered = [result HTML];
    Check([rendered containsString:@"Correct note"] && ![rendered containsString:@"wrong note"], @"HTML output uses the explicit snapshot title");
    Check(![rendered containsString:@"<script"] && ![rendered containsString:@"onload"] && ![rendered containsString:@"contenteditable"] && ![rendered containsString:@"<iframe"], @"document scripts and editing affordances are removed");
    Check([rendered containsString:@"disabled"] && ![rendered containsString:@"action=\"https"], @"form controls are disabled and submission targets removed");
    Check([rendered containsString:@"default-src 'none'"] && [rendered containsString:@"script-src 'none'"] && [rendered containsString:@"form-action 'none'"], @"export includes the same inert document resource policy");
    Check([rendered containsString:@"image.png"] && [rendered containsString:@"p{color:red}"] && [rendered containsString:@"Native HTML"], @"passive local assets, styles, and rendered content survive");
    result = Render(renderer, Snapshot(@"<main><article><section><h2>HTML5</h2><svg viewBox='0 0 20 20'><circle cx='10' cy='10' r='5'/></svg></section></article></main>", @"Modern HTML", 15), @"html", &error);
    Check(result && !error && [[result HTML] containsString:@"<article>"] && [[result HTML] containsString:@"<svg"] && [[result HTML] containsString:@"<circle"], @"HTML5 structure and inline SVG survive sanitization");
    result = Render(renderer, Snapshot(@"<p>unfinished <b>HTML", @"Malformed", 15), @"html", &error);
    Check(result && !error && [[result HTML] containsString:@"unfinished"], @"malformed HTML is recovered as read-only content");
    result = Render(renderer, Snapshot(@"", @"Empty", 16), @"html", &error);
    Check(result && !error, @"empty source has a valid empty viewer document");
    result = Render(renderer, Snapshot(@"Archive:\n@taskpaper ordinary text", @"No implicit dialect", 17), @"markdown", &error);
    Check(result && !error && [[result HTML] containsString:@"@taskpaper"], @"TaskPaper markers remain ordinary Markdown source");
    result = Render(renderer, Snapshot(@"anything", @"Unsupported", 18), @"pdf", &error);
    Check(!result && [error code] == NVMarkupUnsupportedContent, @"unsupported viewers report a structured error");
    result = Render(renderer, Snapshot(nil, @"Native bytes", 19), @"html", &error);
    Check(!result && [error code] == NVMarkupUnsupportedContent, @"text provider rejects a native-only payload");
    CheckHTMLParserLimits(renderer);

    NSString *helper = [[bundle resourcePath] stringByAppendingPathComponent:@"multimarkdown"];
    NSData *original = [NSData dataWithContentsOfFile:helper];
    Check(original != nil, @"retain disposable bundled converter bytes");
    SetHelper(helper, @"#!/bin/sh\nprintf 'converter failed' >&2\nexit 7\n");
    result = Render(renderer, snapshot, @"markdown", &error);
    Check(!result && [error code] == NVMarkupHelperFailed && [[error localizedDescription] containsString:@"status 7"] && [[error localizedDescription] containsString:@"converter failed"], @"failed helper exit and drained stderr reach the error result");
    SetHelper(helper, @"#!/bin/sh\nprintf '\\377'\n");
    result = Render(renderer, snapshot, @"markdown", &error);
    Check(!result && [error code] == NVMarkupInvalidOutput, @"invalid UTF-8 output is rejected");
    SetHelper(helper, @"#!/bin/sh\nexec /bin/sleep 5\n");
    [renderer setTimeLimit:.1];
    result = Render(renderer, snapshot, @"markdown", &error);
    Check(!result && [error code] == NVMarkupTimedOut, @"slow helpers terminate at the request deadline");
    [renderer setTimeLimit:4];
    __block BOOL cancelled = NO;
    NSOperation *token = [renderer renderSnapshot:snapshot viewerIdentifier:@"markdown" completion:^(NVMarkupRenderResult *renderedResult, NSError *renderError) {
        Check(!renderedResult && [renderError code] == NVMarkupCancelled, @"running request cancellation produces no render result"); cancelled = YES;
    }];
    NSDate *start = [NSDate dateWithTimeIntervalSinceNow:.08];
    while ([start timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:start];
    [token cancel];
    PumpUntil(^BOOL{ return cancelled; }, 2);
    __block NSUInteger cancellationCallbacks = 0;
    NSMutableArray *blockers = [NSMutableArray array];
    for (NSUInteger index = 0; index < 2; index++) {
        [blockers addObject:[renderer renderSnapshot:snapshot viewerIdentifier:@"markdown" completion:^(NVMarkupRenderResult *renderedResult, NSError *renderError) {
            Check(!renderedResult && [renderError code] == NVMarkupCancelled, @"running blocker receives one cancellation callback"); cancellationCallbacks++;
        }]];
    }
    PumpUntil(^BOOL{ return [[blockers objectAtIndex:0] isExecuting] && [[blockers objectAtIndex:1] isExecuting]; }, 2);
    __block BOOL queuedCancelled = NO;
    NSOperation *queued = [renderer renderSnapshot:snapshot viewerIdentifier:@"html" completion:^(NVMarkupRenderResult *renderedResult, NSError *renderError) {
        Check(!renderedResult && [renderError code] == NVMarkupCancelled, @"queued cancellation receives a terminal callback before execution"); queuedCancelled = YES; cancellationCallbacks++;
    }];
    Check(![queued isExecuting], @"fixture request waits behind both occupied renderer slots");
    [queued cancel];
    PumpUntil(^BOOL{ return queuedCancelled; }, 2);
    [blockers makeObjectsPerformSelector:@selector(cancel)];
    PumpUntil(^BOOL{ return cancellationCallbacks == 3; }, 2);
    PumpUntil(^BOOL{ return [[blockers objectAtIndex:0] isFinished] && [[blockers objectAtIndex:1] isFinished]; }, 2);
    Check(cancellationCallbacks == 3, @"each cancelled request completes exactly once");
    SetHelper(helper, @"#!/usr/bin/perl\nprint STDERR 'E' x (2*1024*1024); print '<p>' . ('x' x (2*1024*1024)) . '</p>'; local $/; my $input = <STDIN>;\n");
    NSString *largeSource = [@"z" stringByPaddingToLength:2*1024*1024 withString:@"z" startingAtIndex:0];
    result = Render(renderer, Snapshot(largeSource, @"Large pipes", 20), @"markdown", &error);
    Check(result && !error && [[result HTML] length] > 2*1024*1024, @"converter drains stdout and stderr while feeding large stdin");
    SetHelper(helper, @"#!/usr/bin/perl\nprint 'x' x (34*1024*1024);\n");
    result = Render(renderer, snapshot, @"markdown", &error);
    Check(!result && [error code] == NVMarkupLimitExceeded, @"excessive converter output is bounded");
    [[NSFileManager defaultManager] removeItemAtPath:helper error:NULL];
    result = Render(renderer, snapshot, @"markdown", &error);
    Check(!result && [error code] == NVMarkupHelperUnavailable, @"missing converter has an explicit error");
    Check([original writeToFile:helper atomically:YES], @"restore disposable converter");
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:helper error:NULL];
    NSString *oversized = [@"z" stringByPaddingToLength:17*1024*1024 withString:@"z" startingAtIndex:0];
    result = Render(renderer, Snapshot(oversized, @"Too large", 21), @"html", &error);
    Check(!result && [error code] == NVMarkupLimitExceeded, @"source input size is bounded before parsing");
    __block NSUInteger completed = 0;
    for (NSUInteger generation = 30; generation < 34; generation++) {
        NSString *title = [NSString stringWithFormat:@"Explicit %lu", (unsigned long)generation];
        [renderer renderSnapshot:Snapshot(@"# Concurrent", title, generation) viewerIdentifier:@"markdown" completion:^(NVMarkupRenderResult *concurrent, NSError *renderError) {
            Check(concurrent && !renderError && [[concurrent HTML] containsString:title] && [[concurrent snapshot] generation] == generation, @"concurrent requests preserve their own title and generation"); completed++;
        }];
    }
    PumpUntil(^BOOL{ return completed == 4; }, 5);
    fprintf(stdout, "PASS: %lu source viewer renderer checks\n", (unsigned long)Checks);
    [pool drain];
    return 0;
}
