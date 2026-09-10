#import "NVSourceHighlighter.h"
#include "../../ThirdParty/TreeSitter/runtime/include/tree_sitter/api.h"
#include <time.h>
#import <objc/runtime.h>

NSString * const NVSourceCaptureAttributeName = @"NVSourceCapture";
// Every layout retains the revision token, not the analysis owner or storage.
// Invalidating one token also covers a layout just detached from its old note.
@interface NVSourceCaptureRevision : NSObject {
@public
    BOOL valid;
    BOOL current;
    NSTextStorage *sourceStorage; // Borrowed; used only for identity comparison.
}
@end
@implementation NVSourceCaptureRevision
@end
static char NVSourceCaptureRevisionKey;
BOOL NVSourceCapturesCanDisplay(NSLayoutManager *layout) {
    NVSourceCaptureRevision *revision = objc_getAssociatedObject(layout, &NVSourceCaptureRevisionKey);
    return revision && revision->valid && revision->sourceStorage == [layout textStorage];
}
BOOL NVSourceCapturesAreCurrent(NSLayoutManager *layout) {
    NVSourceCaptureRevision *revision = objc_getAssociatedObject(layout, &NVSourceCaptureRevisionKey);
    return NVSourceCapturesCanDisplay(layout) && revision->current;
}

extern const TSLanguage *tree_sitter_org(void);
extern void nv_org_scanner_begin_parse(void);
extern bool nv_org_scanner_did_fail(void);
extern const TSLanguage *tree_sitter_json(void);
extern const TSLanguage *tree_sitter_html(void);
extern const TSLanguage *tree_sitter_markdown(void);
extern const TSLanguage *tree_sitter_markdown_inline(void);

// Plain-source fallback bounds memory, queue work, and display-attribute work.
static const NSUInteger NVSourceMaximumLength = 512 * 1024;
static const NSUInteger NVSourceMaximumCaptures = 30000;
// Parsing and TextKit have separate budgets. Apply a whole revision only when
// its capture writes fit across every attached layout; otherwise display plain.
static const NSUInteger NVSourceMaximumDisplayOperations = 4096;
typedef struct {
    TSParser *parser;
    TSTree *tree;
    NSString *source;
    NSString *syntax;
    TSQuery *query;
    TSParser *inlineParser;
    TSQuery *inlineQuery;
} NVParserState;
typedef struct {
    const uint64_t *token;
    uint64_t generation;
    uint64_t deadline;
    BOOL stopped;
} NVSourceBudget;
static uint64_t NVClock(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ULL + now.tv_nsec;
}
static BOOL NVStop(NVSourceBudget *budget) {
    if (budget->stopped || (budget->token && __atomic_load_n(budget->token, __ATOMIC_RELAXED) != budget->generation) || NVClock() > budget->deadline)
        budget->stopped = YES;
    return budget->stopped;
}
static bool NVParseProgress(TSParseState *state) { return NVStop(state->payload); }
static bool NVQueryProgress(TSQueryCursorState *state) { return NVStop(state->payload); }
static const char *NVRead(void *payload, uint32_t offset, TSPoint point, uint32_t *length) {
    NSData *bytes = (NSData *)payload;
    *length = offset < [bytes length] ? (uint32_t)[bytes length] - offset : 0;
    return *length ? (const char *)[bytes bytes] + offset : NULL;
}
static TSPoint NVPoint(NSString *source, NSUInteger end) {
    TSPoint point = {0, 0};
    for (NSUInteger i = 0; i < end; i++) {
        if ([source characterAtIndex:i] == '\n') { point.row++; point.column = 0; }
        else point.column += 2;
    }
    return point;
}
static void NVClearParser(NVParserState *state) {
    ts_tree_delete(state->tree); state->tree = NULL;
    ts_parser_delete(state->parser); state->parser = NULL;
    ts_parser_delete(state->inlineParser); state->inlineParser = NULL;
    ts_query_delete(state->query); state->query = NULL;
    ts_query_delete(state->inlineQuery); state->inlineQuery = NULL;
    [state->source release]; state->source = nil;
    [state->syntax release]; state->syntax = nil;
}
static TSQuery *NVLoadQuery(NSString *directory, NSString *name, const TSLanguage *language) {
    if (![directory length]) return NULL;
    NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"scm"]]];
    if (!data || [data length] > UINT32_MAX) return NULL;
    uint32_t errorOffset = 0;
    TSQueryError error = TSQueryErrorNone;
    TSQuery *query = ts_query_new(language, [data bytes], (uint32_t)[data length], &errorOffset, &error);
    if (!query) return NULL;
    // The pinned query subset has no predicates/directives. Never interpret a
    // future upstream predicate as an unconditional match in the C API.
    for (uint32_t i = 0; i < ts_query_pattern_count(query); i++) {
        uint32_t count = 0;
        ts_query_predicates_for_pattern(query, i, &count);
        if (count) { ts_query_delete(query); return NULL; }
    }
    return query;
}
static BOOL NVCaptureTree(TSTree *tree, TSQuery *query, NSMutableArray *captures, NSUInteger length, NVSourceBudget *budget) {
    TSQueryCursor *cursor = ts_query_cursor_new();
    ts_query_cursor_set_match_limit(cursor, 4096);
    TSQueryCursorOptions options = {.payload = budget, .progress_callback = NVQueryProgress};
    ts_query_cursor_exec_with_options(cursor, query, ts_tree_root_node(tree), &options);
    TSQueryMatch match;
    uint32_t captureIndex;
    while (ts_query_cursor_next_capture(cursor, &match, &captureIndex)) {
        if (NVStop(budget) || [captures count] >= NVSourceMaximumCaptures) { budget->stopped = YES; break; }
        TSQueryCapture capture = match.captures[captureIndex];
        uint32_t start = ts_node_start_byte(capture.node), end = ts_node_end_byte(capture.node);
        if (end < start || start % 2 || end % 2 || end / 2 > length) { budget->stopped = YES; break; }
        if (end == start) continue;
        uint32_t nameLength;
        const char *name = ts_query_capture_name_for_id(query, capture.index, &nameLength);
        NSString *kind = [[[NSString alloc] initWithBytes:name length:nameLength encoding:NSUTF8StringEncoding] autorelease];
        [captures addObject:@{@"range": [NSValue valueWithRange:NSMakeRange(start / 2, (end - start) / 2)], @"kind": kind}];
    }
    BOOL valid = !budget->stopped && !ts_query_cursor_did_exceed_match_limit(cursor);
    ts_query_cursor_delete(cursor);
    return valid;
}
static NSData *NVInlineRanges(TSTree *tree, NVSourceBudget *budget) {
    NSMutableData *ranges = [NSMutableData data];
    TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node(tree));
    NSUInteger count = 0;
    BOOL done = NO;
    while (!done) {
        TSNode node = ts_tree_cursor_current_node(&cursor);
        if (++count > 100000 || NVStop(budget)) { budget->stopped = YES; break; }
        if (!strcmp(ts_node_type(node), "inline")) {
            TSRange range = {ts_node_start_point(node), ts_node_end_point(node), ts_node_start_byte(node), ts_node_end_byte(node)};
            if (range.end_byte > range.start_byte) [ranges appendBytes:&range length:sizeof(range)];
        } else if (ts_tree_cursor_goto_first_child(&cursor)) continue;
        while (!ts_tree_cursor_goto_next_sibling(&cursor)) {
            if (!ts_tree_cursor_goto_parent(&cursor)) { done = YES; break; }
        }
    }
    ts_tree_cursor_delete(&cursor);
    return budget->stopped ? nil : ranges;
}

static BOOL NVOrgCapture(NSMutableArray *captures, NSRange range, NSString *kind, NVSourceBudget *budget) {
    if (NVStop(budget) || [captures count] >= NVSourceMaximumCaptures) { budget->stopped = YES; return NO; }
    [captures addObject:@{@"range": [NSValue valueWithRange:range], @"kind": kind}];
    return YES;
}
static BOOL NVOrgWhitespace(unichar c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}
static BOOL NVOrgOpeningBoundary(const unichar *text, NSUInteger index) {
    if (!index) return YES;
    unichar c = text[index - 1];
    return NVOrgWhitespace(c) || c == '-' || c == '(' || c == '\'' || c == '"' || c == '{';
}
static BOOL NVOrgClosingBoundary(const unichar *text, NSUInteger index, NSUInteger length) {
    if (index + 1 == length) return YES;
    unichar c = text[index + 1];
    return NVOrgWhitespace(c) || c == '-' || c == '.' || c == ',' || c == ';' || c == ':' ||
        c == '!' || c == '?' || c == '\'' || c == '"' || c == ')' || c == '}' || c == '[';
}
static BOOL NVOrgProtectedNode(const char *type) {
    return !strcmp(type, "block") || !strcmp(type, "dynamic_block") || !strcmp(type, "drawer") ||
        !strcmp(type, "property_drawer") || !strcmp(type, "comment") || !strcmp(type, "directive") ||
        !strcmp(type, "link") || !strcmp(type, "link_desc") || !strcmp(type, "inline_code_block") ||
        !strcmp(type, "inline_math_block") || !strcmp(type, "display_math_block") ||
        !strcmp(type, "latex_env") || !strcmp(type, "citation") || !strcmp(type, "timestamp") || !strcmp(type, "priority");
}
// The grammar exposes ordinary emphasis and TODO words as generic expressions.
// Interpret only this fixed Org subset; query predicates remain unsupported.
// All passes are linear, share the parser budget, and use UTF-16 source indices.
static BOOL NVOrgCaptures(TSTree *tree, NSString *source, NSMutableArray *captures, NVSourceBudget *budget) {
    NSUInteger length = [source length];
    NSMutableData *characters = [NSMutableData dataWithLength:length * sizeof(unichar)];
    unichar *text = [characters mutableBytes];
    [source getCharacters:text range:NSMakeRange(0, length)];
    NSMutableData *prose = [NSMutableData dataWithLength:length];
    unsigned char *eligible = [prose mutableBytes];
    TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node(tree));
    NSUInteger nodes = 0;
    BOOL done = NO;
    while (!done) {
        TSNode node = ts_tree_cursor_current_node(&cursor);
        if (++nodes > 100000 || NVStop(budget)) { budget->stopped = YES; break; }
        uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
        if (end < start || start % 2 || end % 2 || end / 2 > length) { budget->stopped = YES; break; }
        NSRange range = NSMakeRange(start / 2, (end - start) / 2);
        const char *type = ts_node_type(node);
        BOOL protected = NVOrgProtectedNode(type);
        if (protected) memset(eligible + range.location, 0, range.length);
        else if (!strcmp(type, "paragraph") || !strcmp(type, "item") || !strcmp(type, "cell") || !strcmp(type, "description")) {
            memset(eligible + range.location, 1, range.length);
            if (!strcmp(type, "item") && range.length >= 4 &&
                (range.length == 4 || NVOrgWhitespace(text[range.location + 4]))) {
                NSString *word = [source substringWithRange:NSMakeRange(range.location, 4)];
                if ([word isEqualToString:@"TODO"] || [word isEqualToString:@"DONE"]) {
                    if (!NVOrgCapture(captures, NSMakeRange(range.location, 4),
                        [word isEqualToString:@"TODO"] ? @"keyword.todo" : @"constant.done", budget)) break;
                }
            }
        }
        if (!protected && ts_tree_cursor_goto_first_child(&cursor)) continue;
        while (!ts_tree_cursor_goto_next_sibling(&cursor)) {
            if (!ts_tree_cursor_goto_parent(&cursor)) { done = YES; break; }
        }
    }
    ts_tree_cursor_delete(&cursor);
    if (budget->stopped) return NO;

    // A comment directly after a directive can be parsed as paragraph text.
    // Recognize its line prefix without treating block contents as comments.
    for (NSUInteger line = 0; line < length;) {
        if (NVStop(budget)) return NO;
        NSUInteger end = line;
        while (end < length && text[end] != '\n' && text[end] != '\r') {
            if (!(end % 256) && NVStop(budget)) return NO;
            end++;
        }
        NSUInteger start = line;
        while (start < end && (text[start] == ' ' || text[start] == '\t')) start++;
        if (start < end && eligible[start] && text[start] == '#' &&
            (start + 1 == end || NVOrgWhitespace(text[start + 1]))) {
            if (!NVOrgCapture(captures, NSMakeRange(start, end - start), @"comment", budget)) return NO;
            memset(eligible + line, 0, end - line);
        }
        line = end + 1;
    }

    // Literal spans take precedence over every ordinary emphasis marker.
    NSUInteger literal = NSNotFound, literalLines = 0;
    for (NSUInteger i = 0; i < length; i++) {
        if (!(i % 256) && NVStop(budget)) return NO;
        if (!eligible[i]) { literal = NSNotFound; continue; }
        if (text[i] == '\n' && literal != NSNotFound && ++literalLines > 1) literal = NSNotFound;
        if (text[i] != '=' && text[i] != '~') continue;
        if (literal != NSNotFound) {
            if (text[i] == text[literal] && i > literal + 1 && !NVOrgWhitespace(text[i - 1]) && NVOrgClosingBoundary(text, i, length)) {
                NSRange range = NSMakeRange(literal, i - literal + 1);
                if (!NVOrgCapture(captures, range, @"text.literal", budget)) return NO;
                // Keep an enclosing emphasis span open across literal text,
                // while ignoring emphasis markers inside that literal span.
                memset(eligible + range.location, 2, range.length);
                literal = NSNotFound;
            }
        } else if (NVOrgOpeningBoundary(text, i) && i + 1 < length && eligible[i + 1] && !NVOrgWhitespace(text[i + 1])) {
            literal = i; literalLines = 0;
        }
    }
    const unichar markers[] = {'*', '/', '_', '+'};
    NSString *kinds[] = {@"text.strong", @"text.emphasis", @"text.underline", @"text.strike"};
    NSUInteger openings[] = {NSNotFound, NSNotFound, NSNotFound, NSNotFound};
    NSUInteger newlines[] = {0, 0, 0, 0};
    for (NSUInteger i = 0; i < length; i++) {
        if (!(i % 256) && NVStop(budget)) return NO;
        for (NSUInteger marker = 0; marker < 4; marker++) {
            if (!eligible[i] || (text[i] == '\n' && openings[marker] != NSNotFound && ++newlines[marker] > 1)) openings[marker] = NSNotFound;
            if (eligible[i] != 1 || text[i] != markers[marker]) continue;
            if (openings[marker] != NSNotFound && i > openings[marker] + 1 && !NVOrgWhitespace(text[i - 1]) && NVOrgClosingBoundary(text, i, length)) {
                if (!NVOrgCapture(captures, NSMakeRange(openings[marker], i - openings[marker] + 1), kinds[marker], budget)) return NO;
                openings[marker] = NSNotFound;
            } else if (openings[marker] == NSNotFound && NVOrgOpeningBoundary(text, i) &&
                       i + 1 < length && eligible[i + 1] && !NVOrgWhitespace(text[i + 1])) {
                openings[marker] = i; newlines[marker] = 0;
            }
        }
    }
    return !NVStop(budget);
}

@implementation NVSourceParser
- (id)initWithQueryDirectory:(NSString *)directory {
    if ((self = [super init])) { parserState = calloc(1, sizeof(NVParserState)); queryDirectory = [directory copy]; }
    return self;
}
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax cancellationToken:(const uint64_t *)token generation:(uint64_t)generation {
    NVParserState *state = parserState;
    const TSLanguage *language = [syntax isEqualToString:@"org"] ? tree_sitter_org() : [syntax isEqualToString:@"json"] ? tree_sitter_json() : [syntax isEqualToString:@"html"] ? tree_sitter_html() : [syntax isEqualToString:@"markdown"] ? tree_sitter_markdown() : NULL;
    if (!language || [source length] > NVSourceMaximumLength || ![source length]) { NVClearParser(state); return @[]; }
    NVSourceBudget budget = {token, generation, NVClock() + 120000000ULL, NO};
    if (NVStop(&budget)) return nil;
    if (![state->syntax isEqualToString:syntax]) {
        NVClearParser(state);
        state->syntax = [syntax copy];
        state->parser = ts_parser_new();
        if (!ts_parser_set_language(state->parser, language)) { NVClearParser(state); return nil; }
        state->query = NVLoadQuery(queryDirectory, syntax, language);
        if ([syntax isEqualToString:@"markdown"]) {
            state->inlineParser = ts_parser_new();
            if (!ts_parser_set_language(state->inlineParser, tree_sitter_markdown_inline())) { NVClearParser(state); return nil; }
            state->inlineQuery = NVLoadQuery(queryDirectory, @"markdown-inline", tree_sitter_markdown_inline());
        }
    }
    if (!state->query || (state->inlineParser && !state->inlineQuery)) { NVClearParser(state); return nil; }
    NSData *bytes = [source dataUsingEncoding:NSUTF16LittleEndianStringEncoding allowLossyConversion:NO];
    if ([bytes length] != [source length] * 2) { NVClearParser(state); return nil; }
    if (state->tree) {
        // Coalesced edits remain exact: the replacement from the prior immutable
        // snapshot is applied before reuse, including text-only equal-shape edits.
        NSUInteger start = 0, oldEnd = [state->source length], newEnd = [source length];
        while (start < oldEnd && start < newEnd && [state->source characterAtIndex:start] == [source characterAtIndex:start]) start++;
        while (oldEnd > start && newEnd > start && [state->source characterAtIndex:oldEnd - 1] == [source characterAtIndex:newEnd - 1]) { oldEnd--; newEnd--; }
        TSInputEdit edit = {(uint32_t)start * 2, (uint32_t)oldEnd * 2, (uint32_t)newEnd * 2, NVPoint(state->source, start), NVPoint(state->source, oldEnd), NVPoint(source, newEnd)};
        ts_tree_edit(state->tree, &edit);
    }
    TSInput input = {.payload = bytes, .read = NVRead, .encoding = TSInputEncodingUTF16LE};
    TSParseOptions options = {.payload = &budget, .progress_callback = NVParseProgress};
    BOOL isOrg = [syntax isEqualToString:@"org"];
    if (isOrg) nv_org_scanner_begin_parse();
    TSTree *tree = ts_parser_parse_with_options(state->parser, state->tree, input, options);
    BOOL scannerFailed = isOrg && nv_org_scanner_did_fail();
    ts_tree_delete(state->tree); state->tree = tree;
    [state->source release]; state->source = [source copy];
    if (!tree || scannerFailed || NVStop(&budget)) { NVClearParser(state); return nil; }
    NSMutableArray *captures = [NSMutableArray array];
    if (!NVCaptureTree(tree, state->query, captures, [source length], &budget)) { NVClearParser(state); return nil; }
    if ([syntax isEqualToString:@"org"] && !NVOrgCaptures(tree, source, captures, &budget)) { NVClearParser(state); return nil; }
    if (state->inlineParser) {
        NSData *ranges = NVInlineRanges(tree, &budget);
        if (!ranges) { NVClearParser(state); return nil; }
        if ([ranges length]) {
            if (!ts_parser_set_included_ranges(state->inlineParser, [ranges bytes], (uint32_t)([ranges length] / sizeof(TSRange)))) { NVClearParser(state); return nil; }
            // Inline scopes can change after a block edit; rebuild this smaller
            // tree instead of reusing an old tree with obsolete included ranges.
            TSTree *inlineTree = ts_parser_parse_with_options(state->inlineParser, NULL, input, options);
            BOOL valid = inlineTree && NVCaptureTree(inlineTree, state->inlineQuery, captures, [source length], &budget);
            ts_tree_delete(inlineTree);
            if (!valid) { NVClearParser(state); return nil; }
        }
    }
    // Broad scopes apply first. Specific JSON keys win when ranges are equal.
    [captures sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSRange ar = [a[@"range"] rangeValue], br = [b[@"range"] rangeValue];
        if (ar.length != br.length) return ar.length > br.length ? NSOrderedAscending : NSOrderedDescending;
        BOOL ak = [a[@"kind"] hasSuffix:@".key"], bk = [b[@"kind"] hasSuffix:@".key"];
        if (ak != bk) return ak ? NSOrderedDescending : NSOrderedAscending;
        return NSOrderedSame;
    }];
    return NVStop(&budget) ? nil : captures;
}
- (void)dealloc { NVClearParser(parserState); free(parserState); [queryDirectory release]; [super dealloc]; }
@end

@implementation NVSourceHighlighter
- (id)initWithTextStorage:(NSTextStorage *)textStorage syntaxIdentifier:(NSString *)syntax {
    return [self initWithTextStorage:textStorage syntaxIdentifier:syntax queryDirectory:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Syntax"]];
}
- (id)initWithTextStorage:(NSTextStorage *)textStorage syntaxIdentifier:(NSString *)syntax queryDirectory:(NSString *)directory {
    if ((self = [super init])) {
        storage = [textStorage retain]; syntaxIdentifier = [(syntax ?: @"plain") copy]; generation = 1;
        __atomic_store_n(&cancellationGeneration, generation, __ATOMIC_RELAXED);
        queue = dispatch_queue_create("net.notational.source-analysis", DISPATCH_QUEUE_SERIAL);
        parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storageChanged:) name:NSTextStorageDidProcessEditingNotification object:storage];
    }
    return self;
}
- (uint64_t)generation { return generation; }
- (void)invalidateCaptureRevision {
    if (captureRevision) ((NVSourceCaptureRevision *)captureRevision)->valid = NO;
    [captureRevision release]; captureRevision = nil;
}
- (void)invalidateCaptures {
    [self invalidateCaptureRevision];
    [captures release]; captures = nil;
}
- (void)clearDisplayCaptures {
    for (NSLayoutManager *layout in [storage layoutManagers]) {
        if (!objc_getAssociatedObject(layout, &NVSourceCaptureRevisionKey)) continue;
        objc_setAssociatedObject(layout, &NVSourceCaptureRevisionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [layout removeTemporaryAttribute:NVSourceCaptureAttributeName forCharacterRange:NSMakeRange(0, [storage length])];
    }
}
- (void)clearCaptures {
    [self invalidateCaptures];
    [self clearDisplayCaptures];
}
- (void)schedule {
    if (closed) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(analyze) object:nil];
    [self performSelector:@selector(analyze) withObject:nil afterDelay:0.06];
}
- (void)storageChanged:(NSNotification *)notification {
    if (!([storage editedMask] & NSTextStorageEditedCharacters) || closed) return;
    generation++;
    __atomic_store_n(&cancellationGeneration, generation, __ATOMIC_RELAXED);
    // The absolute capture ranges are obsolete, but TextKit adjusts temporary
    // attributes with each edit. Keep those colors until the replacement result
    // arrives so typing does not flash the whole source back to its base color.
    // DidProcessEditing precedes TextKit's layout-cache update: do not change
    // temporary attributes here, especially when the edit shortens the source.
    if (captureRevision) ((NVSourceCaptureRevision *)captureRevision)->current = NO;
    [captures release]; captures = nil;
    [self schedule];
}
- (void)setSyntaxIdentifier:(NSString *)syntax {
    syntax = syntax ?: @"plain";
    if ([syntaxIdentifier isEqualToString:syntax] || closed) return;
    [syntaxIdentifier release]; syntaxIdentifier = [syntax copy];
    generation++;
    __atomic_store_n(&cancellationGeneration, generation, __ATOMIC_RELAXED);
    [self clearCaptures]; [self schedule];
}
- (void)applyCaptures {
    [self invalidateCaptureRevision];
    [self clearDisplayCaptures];
    NSArray *layouts = [storage layoutManagers];
    NSUInteger layoutCount = [layouts count];
    if (![captures count] || !layoutCount || [captures count] > NVSourceMaximumDisplayOperations / layoutCount) return;
    NVSourceCaptureRevision *revision = [[NVSourceCaptureRevision alloc] init];
    revision->sourceStorage = storage;
    captureRevision = revision;
    for (NSLayoutManager *layout in layouts) {
        objc_setAssociatedObject(layout, &NVSourceCaptureRevisionKey, revision, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (NSDictionary *capture in captures) {
            NSRange range = [capture[@"range"] rangeValue];
            if (NSMaxRange(range) <= [storage length]) [layout addTemporaryAttribute:NVSourceCaptureAttributeName value:capture[@"kind"] forCharacterRange:range];
        }
    }
    revision->valid = YES;
    revision->current = YES;
    for (NSLayoutManager *layout in layouts) [layout invalidateDisplayForCharacterRange:NSMakeRange(0, [storage length])];
}
- (void)layoutsChanged {
    if (captures) [self applyCaptures];
    // A new layout can wait for fresh analysis without clearing provisional
    // colors in peers that are already displaying an edited source.
    else [self schedule];
}
- (void)analyze {
    if (closed || analyzing || ![[storage layoutManagers] count]) return;
    analyzing = YES;
    NSString *snapshot = [storage length] > NVSourceMaximumLength ? [@"" copy] : [[storage string] copy];
    NSString *syntax = [syntaxIdentifier copy];
    uint64_t requestGeneration = generation;
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSArray *result = [[parser capturesForString:snapshot syntaxIdentifier:syntax cancellationToken:&cancellationGeneration generation:requestGeneration] copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                analyzing = NO;
                if (!closed && generation == requestGeneration && [syntaxIdentifier isEqualToString:syntax]) {
                    [captures release]; captures = [result copy]; [self applyCaptures];
                } else if (!closed) [self schedule];
            });
            [result release];
        }
    });
    [snapshot release]; [syntax release];
}
- (void)close {
    if (closed) return;
    closed = YES;
    __atomic_store_n(&cancellationGeneration, ++generation, __ATOMIC_RELAXED);
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self clearCaptures];
}
- (void)dealloc {
    [self close]; [storage release]; [syntaxIdentifier release]; [parser release];
    dispatch_release(queue);
    [super dealloc];
}
@end
