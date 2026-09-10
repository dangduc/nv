#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#include <tree_sitter/api.h>
#include <pthread.h>
extern bool nv_org_scanner_did_fail(void);
extern void *tree_sitter_org_external_scanner_create(void);
extern void tree_sitter_org_external_scanner_deserialize(void *, const char *, unsigned);
extern void tree_sitter_org_external_scanner_destroy(void *);
static _Thread_local BOOL markFailed;
static _Thread_local unsigned checks;
static NSString *queries;
static void require(BOOL ok, NSString *label) {
    checks++;
    if (!ok) { NSLog(@"FAIL: %@", label); exit(1); }
}
// Inject only the patched codec's documented invalid-state marker, after an
// ordinary successful parse. This tests adapter decisions without bad notes.
TSTree *NVReviewParse(TSParser *parser, const TSTree *old, TSInput input, TSParseOptions options) {
    TSTree *result = ts_parser_parse_with_options(parser, old, input, options);
    if (markFailed) {
        void *scanner = tree_sitter_org_external_scanner_create();
        const char marker = (char)255;
        tree_sitter_org_external_scanner_deserialize(scanner, &marker, 1);
        tree_sitter_org_external_scanner_destroy(scanner);
    }
    return result;
}
static NSArray *captures(NVSourceParser *p, NSString *source) {
    return [p capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
}
static void *worker(void *number) { @autoreleasepool {
    unsigned identifier = (unsigned)(uintptr_t)number;
    NVSourceParser *first = [[NVSourceParser alloc] initWithQueryDirectory:queries];
    NVSourceParser *second = [[NVSourceParser alloc] initWithQueryDirectory:queries];
    for (unsigned pass = 0; pass < 20; pass++) { @autoreleasepool {
        NSString *text = [NSString stringWithFormat:@"* TODO Worker %u :tag:\n- [ ] Entry %u\nBody 😀 and *bold*.\n", identifier, pass];
        NVSourceParser *fresh = [[NVSourceParser alloc] initWithQueryDirectory:queries];
        NSArray *reference = [captures(fresh, text) retain];
        require([reference count] > 0, @"fresh ordinary Org has captures");
        markFailed = YES;
        require(captures(first, text) == nil && nv_org_scanner_did_fail(), @"failed session rejects its tree");
        markFailed = NO;
        require([captures(second, text) isEqual:reference] && !nv_org_scanner_did_fail(), @"another session on the same worker is unaffected");
        require([captures(first, text) isEqual:reference] && !nv_org_scanner_did_fail(), @"failed session recovers with fresh-equivalent captures");
        uint64_t token = 1;
        require([first capturesForString:text syntaxIdentifier:@"org" cancellationToken:&token generation:0] == nil,
                @"a canceled request returns no stale capture result");
        require([captures(first, text) isEqual:reference], @"later request survives intervening cancellation");
        [reference release]; [fresh release];
    }}
    [first release]; [second release];
    return (void *)(uintptr_t)checks;
}}
int main(int argc, char **argv) { @autoreleasepool {
    queries = [@(argv[1]) copy];
    pthread_t workers[4];
    for (unsigned n = 0; n < 4; n++) if (pthread_create(&workers[n], NULL, worker, (void *)(uintptr_t)n)) return 2;
    unsigned total = 0;
    for (unsigned n = 0; n < 4; n++) { void *count; if (pthread_join(workers[n], &count)) return 2; total += (unsigned)(uintptr_t)count; }
    [queries release];
    printf("PASS: %u highlighter bridge checks across four concurrent workers and eight reused sessions\n", total);
}}
