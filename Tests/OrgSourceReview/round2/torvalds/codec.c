// Property checks for the patched version-1 codec. No original scanner is built.
#include <stdio.h>
#include <string.h>
#include "../../../../ThirdParty/TreeSitter/org/src/scanner.c"
static unsigned checks, cases;
static void require(bool ok, const char *label) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL case %u: %s\n", cases, label); exit(1); }
}
static void put(unsigned char *bytes, unsigned *offset, unsigned value) {
    // Independent expected encoder: division and remainder, without production helpers.
    bytes[(*offset)++] = value % 256;
    bytes[(*offset)++] = value / 256;
}
static void compare(const stack *a, const stack *b) {
    require(a->len == b->len, "stack lengths preserved");
    require(!memcmp(a->data, b->data, sizeof(int16_t) * a->len), "all signed stack values preserved");
}
int main(void) {
    Scanner *a = tree_sitter_org_external_scanner_create();
    Scanner *b = tree_sitter_org_external_scanner_create();
    Scanner *c = tree_sitter_org_external_scanner_create();
    // Legal, modest states cover all bullet values, values above one byte,
    // empty and populated stacks, both math flags, and independent stack counts.
    const unsigned depths[] = {0, 1, 2, 7, 31, 70};
    const unsigned offsets[] = {0, 1, 255, 256, 1024};
    for (unsigned i = 0; i < sizeof(depths)/sizeof(depths[0]); i++)
    for (unsigned j = 0; j < sizeof(depths)/sizeof(depths[0]); j++)
    for (unsigned bias = 0; bias < sizeof(offsets)/sizeof(offsets[0]); bias++)
    for (unsigned math = 0; math < 2; math++) {
        cases++;
        nv_org_scanner_begin_parse(); reset(a); reset(b); reset(c);
        for (unsigned n = 0; n < depths[i]; n++) {
            VEC_PUSH(a->indent_length_stack, (int16_t)(offsets[bias] + n * 4));
            VEC_PUSH(a->bullet_stack, (int16_t)(DASH + n % NUMPAREN));
        }
        for (unsigned n = 0; n < depths[j]; n++) VEC_PUSH(a->section_stack, (int16_t)(offsets[bias] + n + 1));
        a->in_dollar_math = math;
        unsigned char expected[TREE_SITTER_SERIALIZATION_BUFFER_SIZE] = {1, math};
        unsigned offset = 2;
        put(expected, &offset, depths[i]); put(expected, &offset, depths[i]); put(expected, &offset, depths[j]);
        for (unsigned n = 0; n < depths[i]; n++) put(expected, &offset, offsets[bias] + n * 4);
        for (unsigned n = 0; n < depths[i]; n++) put(expected, &offset, DASH + n % NUMPAREN);
        for (unsigned n = 0; n < depths[j]; n++) put(expected, &offset, offsets[bias] + n + 1);
        unsigned char actual[TREE_SITTER_SERIALIZATION_BUFFER_SIZE + 2];
        memset(actual, 0xA5, sizeof(actual));
        unsigned count = serialize(a, (char *)actual + 1);
        require(count == offset, "representation length matches independent encoding");
        require(!memcmp(actual + 1, expected, offset), "bytes match explicit little-endian format");
        bool untouched = actual[0] == 0xA5;
        for (unsigned n = count + 1; n < sizeof(actual); n++) untouched &= actual[n] == 0xA5;
        require(untouched, "encoder writes exactly its returned byte count");
        deserialize(b, (char *)actual + 1, count);
        compare(a->indent_length_stack, b->indent_length_stack);
        compare(a->bullet_stack, b->bullet_stack);
        compare(a->section_stack, b->section_stack);
        require(a->in_dollar_math == b->in_dollar_math && !nv_org_scanner_did_fail(), "legal state preserves math flag and stays healthy");
        unsigned char second[TREE_SITTER_SERIALIZATION_BUFFER_SIZE];
        require(serialize(b, (char *)second) == count && !memcmp(second, expected, count), "decode then encode is canonical");
        // Restore into a previously used object; base entries and retained vector
        // capacity must not affect semantics.
        deserialize(c, (char *)second, count);
        deserialize(c, NULL, 0);
        require(c->indent_length_stack->len == 1 && c->indent_length_stack->data[0] == -1 &&
                c->bullet_stack->len == 1 && c->section_stack->len == 1 && !c->in_dollar_math,
                "empty restoration resets the entire prior state");
        deserialize(c, (char *)expected, count);
        compare(a->section_stack, c->section_stack);
    }
    tree_sitter_org_external_scanner_destroy(a);
    tree_sitter_org_external_scanner_destroy(b);
    tree_sitter_org_external_scanner_destroy(c);
    printf("PASS: %u legal codec states, %u property checks; char signedness %s\n", cases, checks, (char)-1 < 0 ? "signed" : "unsigned");
}
