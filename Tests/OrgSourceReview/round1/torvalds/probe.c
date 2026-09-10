#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern const TSLanguage *tree_sitter_org(void);
static unsigned checks;

static void check(bool value, const char *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

static TSPoint endpoint(const char *text) {
    TSPoint point = {0, 0};
    for (; *text; text++) {
        if (*text == '\n') { point.row++; point.column = 0; }
        else point.column++;
    }
    return point;
}

static void bounds(TSNode node, size_t length) {
    check(ts_node_start_byte(node) <= ts_node_end_byte(node), "node start precedes its end");
    check(ts_node_end_byte(node) <= length, "node stays within the source bytes");
    for (uint32_t i = 0; i < ts_node_child_count(node); i++)
        bounds(ts_node_child(node, i), length);
}

int main(void) {
    const TSLanguage *language = tree_sitter_org();
    check(ts_language_abi_version(language) == 14, "Org language uses the recorded ABI");
    check(ts_language_abi_version(language) >= TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION &&
          ts_language_abi_version(language) <= TREE_SITTER_LANGUAGE_VERSION,
          "bundled runtime accepts the grammar ABI");
    const char *fixtures[] = {
        "* TODO Review\nText\n** DONE Item :work:\nMore text\n",
        "#+TITLE: Notebook\n\n# comment\n\n* Heading\nText\n",
        "- first\n  - child\n    - grandchild\n  - sibling\n- last\n",
        "1. first\n2. second\n   - [ ] task\n   - [X] done\n",
        "* Item\nSCHEDULED: <2026-09-09 Wed>\n:PROPERTIES:\n:ID: id\n:END:\nText\n",
        "* Table\n| Name | Value |\n|------+-------|\n| A | 1 |\n",
        "#+BEGIN_SRC json\n{\"value\": true}\n#+END_SRC\n",
        "#+BEGIN_EXAMPLE\n* ordinary text\n#+END_EXAMPLE\n",
        "Links [[https://example.com][Example]] and [[file:notes.org]].\n",
        "Paragraph *bold* /italic/ =literal= ~code~ src_json{true}.\n",
        "* Unicode caf\303\251 \360\237\230\200 \346\227\245\346\234\254\350\252\236\nText e\314\201.\n",
        "* CRLF\r\nText\r\n- one\r\n- two\r\n",
        "* Heading without final newline"
    };
    const char *suffix = "\n* Review check\nText\n";
    for (unsigned i = 0; i < sizeof(fixtures) / sizeof(fixtures[0]); i++) {
        TSParser *parser = ts_parser_new();
        check(ts_parser_set_language(parser, language), "production grammar attaches to the production runtime");
        const char *original = fixtures[i];
        size_t old_length = strlen(original), new_length = old_length + strlen(suffix);
        TSTree *tree = ts_parser_parse_string(parser, NULL, original, (uint32_t)old_length);
        check(tree != NULL, "ordinary fixture parses");
        check(!ts_node_has_error(ts_tree_root_node(tree)), "ordinary fixture has no parse error");
        bounds(ts_tree_root_node(tree), old_length);
        char *changed = malloc(new_length + 1);
        memcpy(changed, original, old_length);
        memcpy(changed + old_length, suffix, strlen(suffix) + 1);
        TSInputEdit edit = {
            .start_byte = (uint32_t)old_length, .old_end_byte = (uint32_t)old_length,
            .new_end_byte = (uint32_t)new_length, .start_point = endpoint(original),
            .old_end_point = endpoint(original), .new_end_point = endpoint(changed)
        };
        ts_tree_edit(tree, &edit);
        TSTree *incremental = ts_parser_parse_string(parser, tree, changed, (uint32_t)new_length);
        TSParser *fresh_parser = ts_parser_new();
        check(ts_parser_set_language(fresh_parser, language), "fresh comparison parser attaches");
        TSTree *fresh = ts_parser_parse_string(fresh_parser, NULL, changed, (uint32_t)new_length);
        check(incremental && fresh, "incremental and fresh parses both complete");
        char *incremental_shape = ts_node_string(ts_tree_root_node(incremental));
        char *fresh_shape = ts_node_string(ts_tree_root_node(fresh));
        check(strcmp(incremental_shape, fresh_shape) == 0, "incremental tree equals fresh tree after source append");
        bounds(ts_tree_root_node(incremental), new_length);
        free(incremental_shape); free(fresh_shape); free(changed);
        ts_tree_delete(fresh); ts_parser_delete(fresh_parser);
        ts_tree_delete(incremental); ts_tree_delete(tree); ts_parser_delete(parser);
    }
    printf("PASS: %u native ABI, ordinary source, node-bound and incremental checks across 13 fixtures\n", checks);
    return 0;
}
