#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <tree_sitter/parser.h>
#include <wctype.h>

#define MAX(a, b) ((a) > (b) ? (a) : (b))

#define VEC_RESIZE(vec, _cap)                                                  \
    {                                                                          \
        (vec)->data = realloc((vec)->data, (_cap) * sizeof((vec)->data[0]));   \
        assert((vec)->data != NULL);                                           \
        (vec)->cap = (_cap);                                                   \
    }

#define VEC_PUSH(vec, el)                                                      \
    {                                                                          \
        if ((vec)->cap == (vec)->len) {                                        \
            VEC_RESIZE((vec), MAX(16, (vec)->len * 2));                        \
        }                                                                      \
        (vec)->data[(vec)->len++] = (el);                                      \
    }

#define VEC_POP(vec) (vec)->len--;

#define VEC_BACK(vec) ((vec)->data[(vec)->len - 1])

#define VEC_FREE(vec)                                                          \
    {                                                                          \
        if ((vec)->data != NULL)                                               \
            free((vec)->data);                                                 \
    }

#define VEC_CLEAR(vec)                                                         \
    {                                                                          \
        (vec)->len = 0;                                                        \
    }

enum TokenType {
    LISTSTART,
    LISTEND,
    LISTITEMEND,
    BULLET,
    HLSTARS,
    SECTIONEND,
    ENDOFFILE,
    LINKOPEN,
    LATEX_MATH_SINGLE_DOLLAR,
    TEXT_DOLLAR,
    ERROR_SENTINEL
};

typedef enum {
    NOTABULLET,
    DASH,
    PLUS,
    STAR,
    LOWERDOT,
    UPPERDOT,
    LOWERPAREN,
    UPPERPAREN,
    NUMDOT,
    NUMPAREN,
} Bullet;

typedef struct {
    uint32_t len;
    uint32_t cap;
    int16_t *data;
} stack;

typedef struct {
    stack *indent_length_stack;
    stack *bullet_stack;
    stack *section_stack;
    bool in_dollar_math;
    bool failed;
} Scanner;

// nvALT local patch: failures must survive scanner restoration during a parse,
// but must not affect other editing-session workers.
static _Thread_local bool nv_org_parse_failed;
void nv_org_scanner_begin_parse(void) { nv_org_parse_failed = false; }
bool nv_org_scanner_did_fail(void) { return nv_org_parse_failed; }

static void fail(Scanner *scanner) {
    scanner->failed = true;
    nv_org_parse_failed = true;
}

static inline void advance(TSLexer *lexer) { lexer->advance(lexer, false); }

static inline void skip(TSLexer *lexer) { lexer->advance(lexer, true); }

// Version, flags, and three little-endian uint16 counts form the header.
// Every payload value occupies two bytes. Base stack entries are implicit.
enum { NV_ORG_STATE_VERSION = 1, NV_ORG_STATE_HEADER = 8, NV_ORG_INVALID_STATE = 255 };
static uint16_t read_u16(const char *buffer) {
    return (uint16_t)((uint8_t)buffer[0] | ((uint16_t)(uint8_t)buffer[1] << 8));
}
static void write_u16(char *buffer, uint16_t value) {
    buffer[0] = (char)(value & 255);
    buffer[1] = (char)(value >> 8);
}
static void reset(Scanner *scanner) {
    VEC_CLEAR(scanner->section_stack);
    VEC_PUSH(scanner->section_stack, 0);
    VEC_CLEAR(scanner->indent_length_stack);
    VEC_PUSH(scanner->indent_length_stack, -1);
    VEC_CLEAR(scanner->bullet_stack);
    VEC_PUSH(scanner->bullet_stack, NOTABULLET);
    scanner->in_dollar_math = false;
    scanner->failed = false;
}
static bool valid_stack(stack *values, int16_t base, int16_t minimum, int16_t maximum) {
    if (!values || !values->len || values->len > values->cap || !values->data ||
        values->data[0] != base || values->len - 1 > UINT16_MAX) return false;
    for (uint32_t i = 1; i < values->len; i++) {
        if (values->data[i] < minimum || values->data[i] > maximum) return false;
    }
    return true;
}
static unsigned serialize(Scanner *scanner, char *buffer) {
    stack *indent = scanner->indent_length_stack, *bullets = scanner->bullet_stack,
          *sections = scanner->section_stack;
    if (scanner->failed || nv_org_parse_failed ||
        !valid_stack(indent, -1, 0, INT16_MAX) ||
        !valid_stack(bullets, NOTABULLET, DASH, NUMPAREN) ||
        !valid_stack(sections, 0, 1, INT16_MAX) || indent->len != bullets->len) {
        fail(scanner);
        buffer[0] = (char)NV_ORG_INVALID_STATE;
        return 1;
    }
    uint16_t counts[] = {(uint16_t)(indent->len - 1), (uint16_t)(bullets->len - 1),
                         (uint16_t)(sections->len - 1)};
    size_t required = NV_ORG_STATE_HEADER + 2 * ((size_t)counts[0] + counts[1] + counts[2]);
    // Check the complete representation before the first normal-format write.
    if (required > TREE_SITTER_SERIALIZATION_BUFFER_SIZE) {
        fail(scanner);
        buffer[0] = (char)NV_ORG_INVALID_STATE;
        return 1;
    }
    buffer[0] = NV_ORG_STATE_VERSION;
    buffer[1] = scanner->in_dollar_math ? 1 : 0;
    for (unsigned i = 0; i < 3; i++) write_u16(buffer + 2 + 2 * i, counts[i]);
    stack *stacks[] = {indent, bullets, sections};
    size_t offset = NV_ORG_STATE_HEADER;
    for (unsigned group = 0; group < 3; group++) {
        for (uint32_t i = 1; i < stacks[group]->len; i++, offset += 2)
            write_u16(buffer + offset, (uint16_t)stacks[group]->data[i]);
    }
    return (unsigned)required;
}
static void deserialize(Scanner *scanner, const char *buffer, unsigned length) {
    if (length == 0) { reset(scanner); return; }
    if (!buffer || length < NV_ORG_STATE_HEADER || length > TREE_SITTER_SERIALIZATION_BUFFER_SIZE ||
        (uint8_t)buffer[0] != NV_ORG_STATE_VERSION || (uint8_t)buffer[1] > 1) {
        fail(scanner);
        return;
    }
    uint16_t counts[] = {read_u16(buffer + 2), read_u16(buffer + 4), read_u16(buffer + 6)};
    size_t required = NV_ORG_STATE_HEADER + 2 * ((size_t)counts[0] + counts[1] + counts[2]);
    if (counts[0] != counts[1] || required != length) { fail(scanner); return; }
    // Validate every value before changing any stack. A rejected payload never
    // leaves a partially restored state that subsequent callbacks can accept.
    size_t offset = NV_ORG_STATE_HEADER;
    for (unsigned group = 0; group < 3; group++) {
        for (uint32_t i = 0; i < counts[group]; i++, offset += 2) {
            uint16_t value = read_u16(buffer + offset);
            if (value > INT16_MAX || (group == 1 && (value < DASH || value > NUMPAREN)) ||
                (group == 2 && !value)) { fail(scanner); return; }
        }
    }
    reset(scanner);
    stack *stacks[] = {scanner->indent_length_stack, scanner->bullet_stack, scanner->section_stack};
    offset = NV_ORG_STATE_HEADER;
    for (unsigned group = 0; group < 3; group++) {
        for (uint32_t i = 0; i < counts[group]; i++, offset += 2)
            VEC_PUSH(stacks[group], (int16_t)read_u16(buffer + offset));
    }
    scanner->in_dollar_math = buffer[1] != 0;
}

static bool add_indent(Scanner *scanner, int16_t *indent, int16_t amount) {
    if (*indent > INT16_MAX - amount) { fail(scanner); return false; }
    *indent += amount;
    return true;
}

static bool dedent(Scanner *scanner, TSLexer *lexer) {
    if (scanner->indent_length_stack->len <= 1 || scanner->bullet_stack->len <= 1) {
        fail(scanner);
        return false;
    }
    VEC_POP(scanner->indent_length_stack);
    VEC_POP(scanner->bullet_stack);
    lexer->result_symbol = LISTEND;
    return true;
}

static Bullet getbullet(TSLexer *lexer) {
    if (lexer->lookahead == '-') {
        advance(lexer);
        if (iswspace(lexer->lookahead))
            return DASH;
    } else if (lexer->lookahead == '+') {
        advance(lexer);
        if (iswspace(lexer->lookahead))
            return PLUS;
    } else if (lexer->lookahead == '*') {
        advance(lexer);
        if (iswspace(lexer->lookahead))
            return STAR;
    } else if ('a' <= lexer->lookahead && lexer->lookahead <= 'z') {
        advance(lexer);
        if (lexer->lookahead == '.') {
            advance(lexer);
            if (iswspace(lexer->lookahead))
                return LOWERDOT;
        } else if (lexer->lookahead == ')') {
            advance(lexer);
            if (iswspace(lexer->lookahead))
                return LOWERPAREN;
        }
    } else if ('A' <= lexer->lookahead && lexer->lookahead <= 'Z') {
        advance(lexer);
        if (lexer->lookahead == '.') {
            advance(lexer);
            if (iswspace(lexer->lookahead))
                return UPPERDOT;
        } else if (lexer->lookahead == ')') {
            advance(lexer);
            if (iswspace(lexer->lookahead))
                return UPPERPAREN;
        }
    } else if ('0' <= lexer->lookahead && lexer->lookahead <= '9') {
        do {
            advance(lexer);
        } while ('0' <= lexer->lookahead && lexer->lookahead <= '9');
        if (lexer->lookahead == '.') {
            advance(lexer);
            if (iswspace(lexer->lookahead))
                return NUMDOT;
        } else if (lexer->lookahead == ')') {
            advance(lexer);
            if (iswspace(lexer->lookahead))
                return NUMPAREN;
        }
    }
    return NOTABULLET;
}

static bool scan(Scanner *scanner, TSLexer *lexer, const bool *valid_symbols) {
    if (scanner->failed || nv_org_parse_failed) return false;
    // Error recovery
    if (valid_symbols[ERROR_SENTINEL]) {
        return false;
    }

    // - Section ends
    int16_t indent_length = 0;
    lexer->mark_end(lexer);
    for (;;) {
        if (lexer->lookahead == ' ') {
            if (!add_indent(scanner, &indent_length, 1)) return false;
        } else if (lexer->lookahead == '\t') {
            if (!add_indent(scanner, &indent_length, 8)) return false;
        } else if (lexer->lookahead == '\0') {
            if (valid_symbols[LISTEND]) {
                lexer->result_symbol = LISTEND;
            } else if (valid_symbols[SECTIONEND]) {
                lexer->result_symbol = SECTIONEND;
            } else if (valid_symbols[ENDOFFILE]) {
                lexer->result_symbol = ENDOFFILE;
            } else
                return false;

            return true;
        } else {
            break;
        }
        skip(lexer);
    }

    // - Listiem ends
    // Listend -> end of a line, looking for:
    // 1. dedent
    // 2. same indent, not a bullet
    // 3. two eols
    int16_t newlines = 0;
    if (valid_symbols[LISTEND] || valid_symbols[LISTITEMEND]) {
        for (;;) {
            if (lexer->lookahead == ' ') {
                if (!add_indent(scanner, &indent_length, 1)) return false;
            } else if (lexer->lookahead == '\t') {
                if (!add_indent(scanner, &indent_length, 8)) return false;
            } else if (lexer->lookahead == '\0') {
                return dedent(scanner, lexer);
            } else if (lexer->lookahead == '\n') {
                if (++newlines > 1)
                    return dedent(scanner, lexer);
                indent_length = 0;
            } else {
                break;
            }
            skip(lexer);
        }

        if (indent_length < VEC_BACK(scanner->indent_length_stack)) {
            return dedent(scanner, lexer);
        } else if (indent_length == VEC_BACK(scanner->indent_length_stack)) {
            if (getbullet(lexer) == VEC_BACK(scanner->bullet_stack)) {
                lexer->result_symbol = LISTITEMEND;
                return true;
            }
            return dedent(scanner, lexer);
        }
    }

    // - Col=0 star
    if (indent_length == 0 && lexer->lookahead == '*') {
        lexer->mark_end(lexer);
        int16_t stars = 1;
        skip(lexer);
        while (lexer->lookahead == '*') {
            if (stars == INT16_MAX) { fail(scanner); return false; }
            stars++;
            skip(lexer);
        }

        if (lexer->lookahead == '\n') {
            return false;
        }

        if (valid_symbols[SECTIONEND] && iswspace(lexer->lookahead) &&
            stars > 0 && stars <= VEC_BACK(scanner->section_stack)) {
            if (scanner->section_stack->len <= 1) { fail(scanner); return false; }
            VEC_POP(scanner->section_stack);
            lexer->result_symbol = SECTIONEND;
            return true;
        } else if (valid_symbols[HLSTARS] && iswspace(lexer->lookahead)) {
            VEC_PUSH(scanner->section_stack, stars);
            lexer->result_symbol = HLSTARS;
            return true;
        }
        return false;
    }

    // - Liststart and bullets
    if ((valid_symbols[LISTSTART] || valid_symbols[BULLET]) && newlines == 0) {
        Bullet bullet = getbullet(lexer);

        if (valid_symbols[BULLET] &&
            bullet == VEC_BACK(scanner->bullet_stack) &&
            indent_length == VEC_BACK(scanner->indent_length_stack)) {
            lexer->mark_end(lexer);
            lexer->result_symbol = BULLET;
            return true;
        } else if (valid_symbols[LISTSTART] && bullet != NOTABULLET &&
                   indent_length > VEC_BACK(scanner->indent_length_stack)) {
            VEC_PUSH(scanner->indent_length_stack, indent_length);
            VEC_PUSH(scanner->bullet_stack, bullet);
            lexer->result_symbol = LISTSTART;
            return true;
        }
    }

    if (valid_symbols[LINKOPEN] && lexer->lookahead == '[') {
        advance(lexer);
        if (lexer->lookahead == '[') {
            advance(lexer);
            lexer->mark_end(lexer);
            bool has_content = false;
            while (lexer->lookahead != '\n' && lexer->lookahead != '\0') {
                int32_t prev_lookahead = lexer->lookahead;
                advance(lexer);
                if (prev_lookahead == ']' && lexer->lookahead == ']') {
                    advance(lexer);
                    if (!has_content) {
                        return false;
                    }
                    lexer->result_symbol = LINKOPEN;
                    return true;
                }
                has_content = true;
            }
        }
    }

    // $ LaTeX math delimiters
    if (lexer->lookahead == '$') {
        advance(lexer);
        lexer->mark_end(lexer);
        if (scanner->in_dollar_math &&
            valid_symbols[LATEX_MATH_SINGLE_DOLLAR]) {
            // look for closing dollar
            scanner->in_dollar_math = false;
            lexer->result_symbol = LATEX_MATH_SINGLE_DOLLAR;
            return true;
        }

        if (valid_symbols[LATEX_MATH_SINGLE_DOLLAR]) {
            // look for opening dollar
            if (lexer->lookahead == '$') {
                return false; // ignore $$ (handled by grammar)
            }
            while (lexer->lookahead != '\n' && !lexer->eof(lexer)) {
                // check until EOL for closing dollar
                advance(lexer);
                if (lexer->lookahead == '$') {
                    advance(lexer);
                    if (('0' <= lexer->lookahead && lexer->lookahead <= '9') ||
                        ('A' <= lexer->lookahead && lexer->lookahead <= 'Z') ||
                        ('a' <= lexer->lookahead && lexer->lookahead <= 'z')) {
                        // next dollar is part of word
                        if (valid_symbols[TEXT_DOLLAR]) {
                            lexer->result_symbol = TEXT_DOLLAR;
                            return true;
                        }
                    } else {
                        if (valid_symbols[LATEX_MATH_SINGLE_DOLLAR]) {
                            scanner->in_dollar_math = true;
                            lexer->result_symbol = LATEX_MATH_SINGLE_DOLLAR;
                            return true;
                        }
                    }
                }
            }

            // didn't find closing dollar
            if (valid_symbols[TEXT_DOLLAR]) {
                lexer->result_symbol = TEXT_DOLLAR;
                return true;
            }
        }
    }

    return false; // default
}

void *tree_sitter_org_external_scanner_create() {
    Scanner *scanner = (Scanner *)calloc(1, sizeof(Scanner));
    scanner->indent_length_stack = (stack *)calloc(1, sizeof(stack));
    scanner->bullet_stack = (stack *)calloc(1, sizeof(stack));
    scanner->section_stack = (stack *)calloc(1, sizeof(stack));
    deserialize(scanner, NULL, 0);
    return scanner;
}

bool tree_sitter_org_external_scanner_scan(void *payload, TSLexer *lexer,
                                           const bool *valid_symbols) {
    Scanner *scanner = (Scanner *)payload;
    return scan(scanner, lexer, valid_symbols);
}

unsigned tree_sitter_org_external_scanner_serialize(void *payload,
                                                    char *buffer) {
    Scanner *scanner = (Scanner *)payload;
    return serialize(scanner, buffer);
}

void tree_sitter_org_external_scanner_deserialize(void *payload,
                                                  const char *buffer,
                                                  unsigned length) {
    Scanner *scanner = (Scanner *)payload;
    deserialize(scanner, buffer, length);
}

void tree_sitter_org_external_scanner_destroy(void *payload) {
    Scanner *scanner = (Scanner *)payload;
    VEC_FREE(scanner->indent_length_stack);
    VEC_FREE(scanner->bullet_stack);
    VEC_FREE(scanner->section_stack);
    free(scanner->indent_length_stack);
    free(scanner->bullet_stack);
    free(scanner->section_stack);
    free(scanner);
}
