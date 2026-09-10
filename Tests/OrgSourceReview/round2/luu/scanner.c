// Exercise only ordinary valid scanner states. No unpatched scanner is built.
#include "ThirdParty/TreeSitter/org/src/scanner.c"
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000000000.0 + t.tv_nsec; }
int main(void) {
    unsigned depths[] = {0, 1, 4, 16, 32};
    for (unsigned group = 0; group < 5; group++) {
        unsigned depth = depths[group];
        Scanner *source = tree_sitter_org_external_scanner_create();
        Scanner *target = tree_sitter_org_external_scanner_create();
        for (unsigned i = 1; i <= depth; i++) {
            VEC_PUSH(source->indent_length_stack, (int16_t)(2 * i));
            VEC_PUSH(source->bullet_stack, DASH);
            VEC_PUSH(source->section_stack, (int16_t)i);
        }
        char buffer[TREE_SITTER_SERIALIZATION_BUFFER_SIZE];
        nv_org_scanner_begin_parse();
        const unsigned iterations = 200000;
        double start = now();
        unsigned length = 0;
        for (unsigned i = 0; i < iterations; i++) {
            length = serialize(source, buffer);
            deserialize(target, buffer, length);
        }
        double ns = (now() - start) / iterations;
        if (nv_org_scanner_did_fail() || length != 8 + 6 * depth ||
            target->section_stack->len != depth + 1 || target->indent_length_stack->len != depth + 1 ||
            target->bullet_stack->len != depth + 1) return 2;
        for (unsigned i = 1; i <= depth; i++) {
            if (target->section_stack->data[i] != i || target->indent_length_stack->data[i] != 2 * i ||
                target->bullet_stack->data[i] != DASH) return 3;
        }
        printf("valid_scanner_state depth=%u bytes=%u iterations=%u encode_decode_mean_ns=%.3f\n", depth, length, iterations, ns);
        tree_sitter_org_external_scanner_destroy(source);
        tree_sitter_org_external_scanner_destroy(target);
    }
    puts("PASS: 5 valid scanner states retain all values after 1,000,000 encode/decode pairs");
    return 0;
}
