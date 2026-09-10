// Defensive contract checks for the patched scanner only. This test never
// compiles an upstream scanner or constructs a crashing document.
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include "../../../ThirdParty/TreeSitter/org/src/scanner.c"
static unsigned checks;
static void check(bool value, const char *label) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}
static void equal(const stack *a, const stack *b) {
    check(a->len == b->len && !memcmp(a->data, b->data, a->len * sizeof(int16_t)), "stack values round-trip exactly");
}
static void round_trip(Scanner *a, Scanner *b) {
    unsigned char storage[TREE_SITTER_SERIALIZATION_BUFFER_SIZE + 2];
    memset(storage, 0xA5, sizeof(storage));
    unsigned length = serialize(a, (char *)storage + 1);
    check(length >= NV_ORG_STATE_HEADER && length <= TREE_SITTER_SERIALIZATION_BUFFER_SIZE, "valid state stays within serialization capacity");
    check(storage[0] == 0xA5 && storage[sizeof(storage) - 1] == 0xA5, "state encoding preserves adjacent canaries");
    deserialize(b, (char *)storage + 1, length);
    check(!b->failed && !nv_org_scanner_did_fail(), "valid round-trip has no failure latch");
    equal(a->indent_length_stack, b->indent_length_stack);
    equal(a->bullet_stack, b->bullet_stack);
    equal(a->section_stack, b->section_stack);
    check(a->in_dollar_math == b->in_dollar_math, "math flag round-trips exactly");
}
static void rejected(Scanner *scanner, const char *bytes, unsigned length) {
    nv_org_scanner_begin_parse();
    reset(scanner);
    VEC_PUSH(scanner->section_stack, 42);
    deserialize(scanner, bytes, length);
    check(scanner->failed && nv_org_scanner_did_fail(), "invalid format sets scanner and per-parse failure");
    check(scanner->section_stack->len == 2 && scanner->section_stack->data[1] == 42 &&
          scanner->indent_length_stack->len == 1 && scanner->bullet_stack->len == 1,
          "invalid decode leaves all prior stack values intact");
    deserialize(scanner, NULL, 0);
    check(nv_org_scanner_did_fail(), "later empty restoration does not clear failure for this parse");
    bool valid_symbols[ERROR_SENTINEL + 1] = {false};
    check(!scan(scanner, NULL, valid_symbols), "latched failure prevents subsequent scanning before any lexer access");
}
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static bool failed_worker_ready, healthy_worker_checked, isolated;
static void *failed_worker(void *unused) {
    (void)unused;
    nv_org_scanner_begin_parse();
    Scanner *s = tree_sitter_org_external_scanner_create();
    const char marker = (char)NV_ORG_INVALID_STATE;
    deserialize(s, &marker, 1);
    pthread_mutex_lock(&lock);
    failed_worker_ready = true;
    pthread_cond_broadcast(&condition);
    while (!healthy_worker_checked) pthread_cond_wait(&condition, &lock);
    isolated = nv_org_scanner_did_fail();
    pthread_mutex_unlock(&lock);
    tree_sitter_org_external_scanner_destroy(s);
    return NULL;
}
int main(void) {
    nv_org_scanner_begin_parse();
    Scanner *a = tree_sitter_org_external_scanner_create();
    Scanner *b = tree_sitter_org_external_scanner_create();
    round_trip(a, b);
    VEC_PUSH(a->indent_length_stack, 0); VEC_PUSH(a->bullet_stack, DASH);
    VEC_PUSH(a->indent_length_stack, 300); VEC_PUSH(a->bullet_stack, NUMPAREN);
    VEC_PUSH(a->section_stack, 2); VEC_PUSH(a->section_stack, 512);
    a->in_dollar_math = true;
    round_trip(a, b);
    VEC_PUSH(a->indent_length_stack, INT16_MAX); VEC_PUSH(a->bullet_stack, STAR);
    VEC_PUSH(a->section_stack, INT16_MAX);
    round_trip(a, b);

    // Exercise the patched format's documented capacity, using direct state
    // construction. Every write is checked against this implementation only.
    reset(a);
    unsigned entries = (TREE_SITTER_SERIALIZATION_BUFFER_SIZE - NV_ORG_STATE_HEADER) / 2;
    for (unsigned i = 0; i < entries; i++) VEC_PUSH(a->section_stack, 1);
    round_trip(a, b);
    VEC_PUSH(a->section_stack, 1);
    unsigned char storage[TREE_SITTER_SERIALIZATION_BUFFER_SIZE + 2];
    memset(storage, 0xA5, sizeof(storage));
    unsigned length = serialize(a, (char *)storage + 1);
    check(length == 1 && storage[1] == NV_ORG_INVALID_STATE && nv_org_scanner_did_fail(), "unsupported capacity emits only the invalid marker and latches failure");
    bool unchanged = true;
    for (unsigned i = 0; i < sizeof(storage); i++) if (i != 1 && storage[i] != 0xA5) unchanged = false;
    check(unchanged, "unsupported state performs no partial payload writes");

    const char version[] = {2, 0, 0, 0, 0, 0, 0, 0};
    const char flags[] = {1, 2, 0, 0, 0, 0, 0, 0};
    const char counts[] = {1, 0, 1, 0, 0, 0, 0, 0, 0, 0};
    const char payload[] = {1, 0, 0, 0, 0, 0, 1, 0, 2, 0};
    rejected(b, version, sizeof(version));
    rejected(b, flags, sizeof(flags));
    rejected(b, counts, sizeof(counts));
    for (unsigned size = 1; size < sizeof(payload); size++) rejected(b, payload, size);
    rejected(b, NULL, NV_ORG_STATE_HEADER);
    rejected(b, payload, TREE_SITTER_SERIALIZATION_BUFFER_SIZE + 1);
    char bad_value[sizeof(payload)]; memcpy(bad_value, payload, sizeof(payload));
    bad_value[8] = 0; rejected(b, bad_value, sizeof(bad_value));
    bad_value[9] = (char)0x80; rejected(b, bad_value, sizeof(bad_value));
    nv_org_scanner_begin_parse();
    reset(b);
    int16_t indent = INT16_MAX - 1;
    check(add_indent(b, &indent, 1) && indent == INT16_MAX, "largest indentation value remains representable");
    check(!add_indent(b, &indent, 1) && indent == INT16_MAX && nv_org_scanner_did_fail(), "indent increment refuses narrowing and preserves prior value");
    nv_org_scanner_begin_parse();
    reset(b); indent = INT16_MAX - 4;
    check(!add_indent(b, &indent, 8) && nv_org_scanner_did_fail(), "tab increment refuses narrowing");
    nv_org_scanner_begin_parse();
    reset(b);
    TSLexer unused_lexer = {0};
    check(!dedent(b, &unused_lexer) && nv_org_scanner_did_fail(), "base stack entries cannot be popped");

    nv_org_scanner_begin_parse();
    pthread_t worker;
    check(pthread_create(&worker, NULL, failed_worker, NULL) == 0, "parallel scanner worker starts");
    pthread_mutex_lock(&lock);
    while (!failed_worker_ready) pthread_cond_wait(&condition, &lock);
    check(!nv_org_scanner_did_fail(), "worker failure does not affect the healthy thread");
    reset(a); reset(b); round_trip(a, b);
    healthy_worker_checked = true;
    pthread_cond_broadcast(&condition);
    pthread_mutex_unlock(&lock);
    pthread_join(worker, NULL);
    check(isolated && !nv_org_scanner_did_fail(), "healthy operations do not clear another worker's failure");
    tree_sitter_org_external_scanner_destroy(a);
    tree_sitter_org_external_scanner_destroy(b);
    printf("PASS: %u patched scanner contract checks\n", checks);
}
