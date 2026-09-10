#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
#include <tree_sitter/api.h>
extern void nv_org_scanner_begin_parse(void);
extern bool nv_org_scanner_did_fail(void);
extern void *tree_sitter_org_external_scanner_create(void);
extern void tree_sitter_org_external_scanner_deserialize(void *, const char *, unsigned);
extern void tree_sitter_org_external_scanner_destroy(void *);
static BOOL injectFailure;
static unsigned checks;
static void Check(BOOL value, NSString *label) {
    checks++;
    if (!value) { NSLog(@"FAIL: %@", label); exit(1); }
}
// Only the highlighter translation unit substitutes this entry point. The
// production parser still runs on ordinary Org text. Injecting a scanner-status
// failure afterward checks the adapter without an unsafe document or old code.
TSTree *NVScannerProbeParse(TSParser *parser, const TSTree *old, TSInput input, TSParseOptions options) {
    TSTree *tree = ts_parser_parse_with_options(parser, old, input, options);
    if (injectFailure) {
        void *scanner = tree_sitter_org_external_scanner_create();
        const char marker = (char)255;
        tree_sitter_org_external_scanner_deserialize(scanner, &marker, 1);
        tree_sitter_org_external_scanner_destroy(scanner);
    }
    return tree;
}
int main(int argc, char **argv) { @autoreleasepool {
    NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:@(argv[1])];
    NSString *source = @"* TODO Heading 😀\n- [ ] ordinary item\nBody *bold*.\n";
    NSArray *first = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    Check([first count] > 0 && !nv_org_scanner_did_fail(), @"ordinary Org parsing produces captures without scanner failure");
    injectFailure = YES;
    NSArray *failed = [parser capturesForString:[source stringByAppendingString:@"More text.\n"] syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    Check(failed == nil && nv_org_scanner_did_fail(), @"scanner failure rejects an otherwise successful Org tree");
    injectFailure = NO;
    NSArray *recovered = [parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0];
    Check([first isEqual:recovered] && !nv_org_scanner_did_fail(), @"next request clears failed parser state and recovers original captures");
    injectFailure = YES;
    Check([parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0] == nil, @"repeat scanner failure still rejects source captures");
    injectFailure = NO;
    Check([[parser capturesForString:@"{\"key\":true}" syntaxIdentifier:@"json" cancellationToken:NULL generation:0] count] > 0, @"Org status cannot suppress another language");
    Check([[parser capturesForString:source syntaxIdentifier:@"org" cancellationToken:NULL generation:0] isEqual:first], @"Org recovers after a different syntax request");
    [parser release];
    NSLog(@"PASS: %u scanner adapter checks", checks);
}}
