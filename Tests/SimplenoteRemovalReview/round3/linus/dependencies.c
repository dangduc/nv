/* Review-only executable: link the app's existing parser/crypto object files.
 * Read queries from the extracted app, never from the source checkout. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tree_sitter/api.h>
#include <openssl/aes.h>
#include "pbkdf2.h"

extern const TSLanguage *tree_sitter_json(void);
extern const TSLanguage *tree_sitter_html(void);
extern const TSLanguage *tree_sitter_markdown(void);
extern const TSLanguage *tree_sitter_markdown_inline(void);
static unsigned checks;
#define CHECK(c, s) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", s); return 1; } checks++; printf("PASS: %s\n", s); } while (0)

int main(int argc, char **argv) {
    CHECK(argc == 2, "bundle resource directory supplied");
    const char *names[] = {"json", "html", "markdown", "markdown-inline"};
    const char *sources[] = {"{\"answer\":42,\"ready\":true}", "<p class=\"note\">body</p>", "# Title\n\n> quote\n", "**bold** and `code`"};
    const TSLanguage *languages[] = {tree_sitter_json(), tree_sitter_html(), tree_sitter_markdown(), tree_sitter_markdown_inline()};
    for (unsigned i = 0; i < 4; i++) {
        char path[4096]; snprintf(path, sizeof(path), "%s/Syntax/%s.scm", argv[1], names[i]);
        FILE *file = fopen(path, "rb");
        CHECK(file, "shipped syntax query opens");
        fseek(file, 0, SEEK_END); long size = ftell(file); rewind(file);
        CHECK(size > 0 && size < 65536, "shipped syntax query has bounded nonzero size");
        char *querySource = malloc((size_t)size);
        CHECK(querySource && fread(querySource, 1, (size_t)size, file) == (size_t)size, "read complete shipped syntax query");
        fclose(file);
        uint32_t offset = 0; TSQueryError error = TSQueryErrorNone;
        TSQuery *query = ts_query_new(languages[i], querySource, (uint32_t)size, &offset, &error);
        free(querySource);
        CHECK(query && error == TSQueryErrorNone, "shipped query compiles with retained grammar");
        TSParser *parser = ts_parser_new();
        CHECK(parser && ts_parser_set_language(parser, languages[i]), "retained grammar ABI accepted by retained runtime");
        TSTree *tree = ts_parser_parse_string(parser, NULL, sources[i], (uint32_t)strlen(sources[i]));
        CHECK(tree && !ts_node_has_error(ts_tree_root_node(tree)), "synthetic source parses without error");
        TSQueryCursor *cursor = ts_query_cursor_new();
        ts_query_cursor_exec(cursor, query, ts_tree_root_node(tree));
        TSQueryMatch match; uint32_t captureIndex; unsigned captures = 0;
        while (ts_query_cursor_next_capture(cursor, &match, &captureIndex)) captures++;
        CHECK(captures > 0, "shipped query produces highlighting captures");
        printf("CAPTURES: %s=%u\n", names[i], captures);
        ts_query_cursor_delete(cursor); ts_tree_delete(tree); ts_parser_delete(parser); ts_query_delete(query);
    }
    /* Fixed password/salt are public synthetic vectors, not application credentials. */
    char derived[20];
    const unsigned char expectedPBKDF[] = {0x0c,0x60,0xc8,0x0f,0x96,0x1f,0x0e,0x71,0xf3,0xa9,0xb5,0x24,0xaf,0x60,0x12,0x06,0x2f,0xe0,0x37,0xa6};
    CHECK(pbkdf2_sha1("password", 8, "salt", 4, 1, derived, sizeof(derived)), "retained Crypto PBKDF2 succeeds");
    CHECK(!memcmp(derived, expectedPBKDF, sizeof(derived)), "retained Crypto PBKDF2 matches fixed vector");
    const unsigned char key[] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
    const unsigned char plain[] = {0,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff};
    const unsigned char expectedAES[] = {0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a};
    unsigned char cipher[16], restored[16]; AES_KEY encryption, decryption;
    CHECK(!AES_set_encrypt_key(key, 128, &encryption), "retained OpenSSL accepts AES key");
    AES_encrypt(plain, cipher, &encryption);
    CHECK(!memcmp(cipher, expectedAES, sizeof(cipher)), "retained OpenSSL AES matches fixed vector");
    CHECK(!AES_set_decrypt_key(key, 128, &decryption), "retained OpenSSL accepts decryption key");
    AES_decrypt(cipher, restored, &decryption);
    CHECK(!memcmp(restored, plain, sizeof(plain)), "retained OpenSSL AES restores plaintext");
    printf("PASS: %u native dependency assertions\n", checks);
    return 0;
}
