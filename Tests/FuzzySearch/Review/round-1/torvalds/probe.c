/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Independent review checks. This file imports no production ranking helper. */
#include "NVFZF.h"
#include "utf8proc-2.10.0/utf8proc.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int reference_search(const NVFZFCandidate *, size_t, const char *,
                            NVFZFQueryMode, NVFZFSearchResult *);
static unsigned long checks;
#define CHECK(c) do { checks++; if (!(c)) { \
  fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
static unsigned state = 0x752f813b;
static unsigned rnd(void) { state ^= state << 13; state ^= state >> 17; state ^= state << 5; return state; }
static unsigned char lower(unsigned char c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }
static int literal_member(NVFZFCandidate c, NVFZFTerm t) {
  if (t.kind == NVFZF_TERM_FUZZY) {
    size_t p = 0;
    for (size_t i = 0; i < c.length && p < t.length; i++)
      if (lower(c.bytes[i]) == lower(t.bytes[p])) p++;
    return p == t.length;
  }
  for (size_t i = 0; i <= c.length && t.length <= c.length - i; i++) {
    size_t j = 0;
    while (j < t.length && lower(c.bytes[i + j]) == lower(t.bytes[j])) j++;
    if (j == t.length) return 1;
  }
  return 0;
}
static void same(const NVFZFSearchResult *a, const NVFZFSearchResult *b) {
  CHECK(a->count == b->count);
  for (size_t i = 0; i < a->count; i++) {
    CHECK(a->matches[i].candidate_index == b->matches[i].candidate_index);
    CHECK(a->matches[i].public_score == b->matches[i].public_score);
    CHECK(a->matches[i].rank_score == b->matches[i].rank_score);
    CHECK(a->matches[i].trimmed_length == b->matches[i].trimmed_length);
  }
}
static void literals(NVFZFEngine *engine) {
  const char alphabet[] = "abAB !|^$'\\\t\n";
  for (size_t round = 0; round < 1500; round++) {
    char term_bytes[3][5] = {{0}}, bytes[32][64];
    NVFZFTerm terms[3]; NVFZFCandidate items[32];
    size_t term_count = round % 17 ? 1 + rnd() % 3 : 0;
    for (size_t t = 0; t < term_count; t++) {
      size_t n = 1 + rnd() % 4;
      for (size_t j = 0; j < n; j++) term_bytes[t][j] = alphabet[rnd() % (sizeof alphabet - 1)];
      terms[t] = (NVFZFTerm){term_bytes[t], n, rnd() & 1 ? NVFZF_TERM_EXACT : NVFZF_TERM_FUZZY};
    }
    for (size_t i = 0; i < 32; i++) {
      size_t n = rnd() % 45;
      for (size_t j = 0; j < n; j++) bytes[i][j] = rnd() % 29 ? alphabet[rnd() % (sizeof alphabet - 1)] : 0;
      if (i % 4 == 0) for (size_t t = 0; t < term_count; t++) {
        memcpy(bytes[i] + n, terms[t].bytes, terms[t].length); n += terms[t].length;
      }
      items[i] = (NVFZFCandidate){bytes[i], n};
    }
    NVFZFSearchResult actual = {0};
    CHECK(nvfzf_search_terms(engine, items, 32, terms, term_count, NULL, &actual) == NVFZF_OK);
    int seen[32] = {0};
    for (size_t i = 0; i < actual.count; i++) {
      NVFZFMatch m = actual.matches[i]; CHECK(m.candidate_index < 32); CHECK(!seen[m.candidate_index]++);
      if (i && term_count) {
        NVFZFMatch p = actual.matches[i - 1];
        CHECK(p.rank_score > m.rank_score || (p.rank_score == m.rank_score &&
          (p.trimmed_length < m.trimmed_length || (p.trimmed_length == m.trimmed_length && p.candidate_index < m.candidate_index))));
      }
      if (!term_count) CHECK(m.candidate_index == i && m.public_score == 1 && !m.rank_score && !m.trimmed_length);
    }
    for (size_t i = 0; i < 32; i++) {
      int expected = 1;
      for (size_t t = 0; t < term_count; t++) expected &= literal_member(items[i], terms[t]);
      CHECK(seen[i] == expected);
      NVFZFPositions positions = {0};
      CHECK(nvfzf_positions_terms(engine, items[i], terms, term_count, NULL, &positions) == NVFZF_OK);
      CHECK(positions.matched == expected);
      if (!expected || !term_count) CHECK(positions.count == 0);
      if (expected && term_count) CHECK(positions.count > 0);
      for (size_t p = 0; p < positions.count; p++) {
        CHECK(positions.offsets[p] < items[i].length);
        if (p) CHECK(positions.offsets[p - 1] < positions.offsets[p]);
      }
      if (expected && term_count == 1) {
        CHECK(positions.count == terms[0].length);
        for (size_t p = 0; p < positions.count; p++) {
          CHECK(lower(items[i].bytes[positions.offsets[p]]) == lower(terms[0].bytes[p]));
          if (p && terms[0].kind == NVFZF_TERM_EXACT) CHECK(positions.offsets[p] == positions.offsets[p - 1] + 1);
        }
      }
      nvfzf_positions_free(&positions);
    }
    nvfzf_search_result_free(&actual);
  }
  puts("PASS: 1,500 generated typed-literal corpora, 48,000 membership and position comparisons.");
}
static void native_parity(NVFZFEngine *engine) {
  const char *atoms[] = {"a", "B", "é", "É", "東京", "😀", " ", "\t", "/", "|", "\xc2\xa0"};
  for (size_t round = 0; round < 300; round++) {
    char bytes[40][256], query[128] = {0}; NVFZFCandidate items[40]; NVFZFTerm terms[3];
    for (size_t i = 0; i < 40; i++) {
      size_t n = 0, count = 1 + rnd() % 20;
      for (size_t j = 0; j < count; j++) { const char *s = atoms[rnd() % 11]; size_t k = strlen(s); memcpy(bytes[i] + n, s, k); n += k; }
      items[i] = (NVFZFCandidate){bytes[i], n};
    }
    size_t n = 0, count = 1 + rnd() % 3;
    for (size_t t = 0; t < count; t++) {
      const char *s = atoms[rnd() % 6]; NVFZFTermKind kind = rnd() & 1 ? NVFZF_TERM_EXACT : NVFZF_TERM_FUZZY;
      terms[t] = (NVFZFTerm){s, strlen(s), kind};
      if (t) query[n++] = ' ';
      if (kind == NVFZF_TERM_EXACT) query[n++] = '\'';
      memcpy(query + n, s, strlen(s)); n += strlen(s); query[n] = 0;
    }
    NVFZFSearchResult actual = {0}, expected = {0};
    CHECK(!reference_search(items, 40, query, NVFZF_NATIVE_FUZZY, &expected));
    CHECK(nvfzf_search_terms(engine, items, 40, terms, count, NULL, &actual) == NVFZF_OK);
    same(&actual, &expected); nvfzf_search_result_free(&actual); free(expected.matches);
  }
  puts("PASS: 300 generated mixed Unicode corpora match independent upstream order and all score diagnostics.");
}
static char *nfc(const char *s, size_t *length) {
  utf8proc_uint8_t *out = NULL;
  utf8proc_ssize_t n = utf8proc_map((const utf8proc_uint8_t *)s, strlen(s), &out, UTF8PROC_STABLE | UTF8PROC_COMPOSE);
  CHECK(n >= 0); *length = (size_t)n; return (char *)out;
}
static void normalization(NVFZFEngine *engine) {
  const char *raw[] = {"cafe\xcc\x81", "\xe1\x84\x80\xe1\x85\xa1", "a\xcc\x95\xcc\x80"};
  const char *canonical[] = {"café", "가", "à\xcc\x95"};
  const size_t counts[] = {4, 1, 2};
  for (size_t i = 0; i < 3; i++) {
    size_t n; char *c = nfc(raw[i], &n); CHECK(n == strlen(canonical[i]) && !memcmp(c, canonical[i], n));
    for (int kind = NVFZF_TERM_FUZZY; kind <= NVFZF_TERM_EXACT; kind++) {
      NVFZFTerm term = {canonical[i], strlen(canonical[i]), kind}; NVFZFPositions p = {0};
      CHECK(nvfzf_positions_terms(engine, (NVFZFCandidate){c, n}, &term, 1, NULL, &p) == NVFZF_OK);
      CHECK(p.matched && p.count == counts[i]);
      for (size_t j = 0; j < p.count; j++) CHECK(p.offsets[j] == j);
      nvfzf_positions_free(&p);
    }
    free(c);
  }
  NVFZFTerm accent = {"cafe", 4, NVFZF_TERM_EXACT}; NVFZFSearchResult r = {0};
  NVFZFCandidate candidate = {"café", strlen("café")};
  CHECK(nvfzf_search_terms(engine, &candidate, 1, &accent, 1, NULL, &r) == NVFZF_OK && !r.count); nvfzf_search_result_free(&r);
  puts("PASS: NFC composition, Hangul composition, canonical mark ordering, codepoint offsets, and accent preservation.");
}
static void jobs(NVFZFEngine *engine) {
  NVFZFEngine *second = nvfzf_engine_create(); CHECK(second);
  NVFZFCandidate candidates[] = {{"alpha", 5}, {"beta", 4}, {"alpha beta", 10}};
  char term_bytes[] = "alp"; NVFZFTerm term = {term_bytes, 3, NVFZF_TERM_FUZZY};
  NVFZFJob *job = NULL; NVFZFSearchResult result = {0}; bool done = true;
  CHECK(nvfzf_job_create_terms(candidates, 3, &term, 1, NULL, &job) == NVFZF_OK);
  memset(term_bytes, 'z', 3);
  CHECK(nvfzf_job_finish(job, &result) == NVFZF_INVALID_INPUT && !result.matches && !result.count);
  CHECK(nvfzf_job_step(engine, job, 1, &done) == NVFZF_OK && !done);
  CHECK(nvfzf_job_step(second, job, SIZE_MAX, &done) == NVFZF_OK && done);
  CHECK(nvfzf_job_finish(job, &result) == NVFZF_OK && result.count == 2);
  CHECK(result.matches[0].candidate_index == 0 && result.matches[1].candidate_index == 2);
  nvfzf_search_result_free(&result);
  CHECK(nvfzf_job_finish(job, &result) == NVFZF_INVALID_INPUT);
  CHECK(nvfzf_job_step(engine, job, 1, &done) == NVFZF_INVALID_INPUT && !done); nvfzf_job_free(job);
  NVFZFCancel *cancel = nvfzf_cancel_create(); CHECK(cancel);
  term = (NVFZFTerm){"a", 1, NVFZF_TERM_FUZZY};
  CHECK(nvfzf_job_create_terms(candidates, 3, &term, 1, cancel, &job) == NVFZF_OK);
  CHECK(nvfzf_job_step(engine, job, 1, &done) == NVFZF_OK && !done); nvfzf_cancel_set(cancel);
  CHECK(nvfzf_job_step(second, job, 1, &done) == NVFZF_CANCELLED && !done);
  CHECK(nvfzf_job_finish(job, &result) == NVFZF_CANCELLED && !result.matches && !result.count);
  nvfzf_job_free(job); nvfzf_cancel_free(cancel); nvfzf_engine_free(second);
  puts("PASS: copied terms, serial engine migration, finish states, and cancellation after one scored candidate.");
}
static void limits(NVFZFEngine *engine) {
  char *bytes = malloc(NVFZF_MAX_QUERY_BYTES + 1); CHECK(bytes);
  memset(bytes, 'a', NVFZF_MAX_QUERY_BYTES + 1);
  NVFZFTerm term = {bytes, NVFZF_MAX_QUERY_BYTES, NVFZF_TERM_EXACT};
  NVFZFCandidate candidate = {bytes, NVFZF_MAX_QUERY_BYTES}; NVFZFSearchResult r = {0};
  CHECK(nvfzf_search_terms(engine, &candidate, 1, &term, 1, NULL, &r) == NVFZF_OK && r.count == 1);
  CHECK(r.matches[0].public_score > UINT16_MAX && r.matches[0].rank_score == UINT16_MAX);
  CHECK(r.matches[0].trimmed_length == UINT16_MAX); nvfzf_search_result_free(&r);
  term.length++;
  CHECK(nvfzf_search_terms(engine, &candidate, 1, &term, 1, NULL, &r) == NVFZF_INVALID_INPUT && !r.matches && !r.count);
  term = (NVFZFTerm){"a", 1, NVFZF_TERM_FUZZY};
  NVFZFCandidate bad[] = {{"a", 1}, {"a", (size_t)INT32_MAX + 1}};
  CHECK(nvfzf_search_terms(engine, bad, 2, &term, 1, NULL, &r) == NVFZF_INVALID_INPUT && !r.matches && !r.count);
  CHECK(nvfzf_search_terms(engine, &candidate, (size_t)UINT32_MAX + 1, &term, 1, NULL, &r) == NVFZF_INVALID_INPUT && !r.matches && !r.count);
  candidate = (NVFZFCandidate){"a", 1};
  CHECK(nvfzf_search_terms(engine, &candidate, 1, &term, 1, NULL, &r) == NVFZF_OK && r.count == 1);
  nvfzf_search_result_free(&r); free(bytes);
  puts("PASS: maximum query length, rank saturation, invalid candidate/collection bounds, and engine recovery.");
}
int main(void) {
  NVFZFEngine *engine = nvfzf_engine_create(); CHECK(engine);
  literals(engine); native_parity(engine); normalization(engine); jobs(engine); limits(engine);
  nvfzf_engine_free(engine); printf("PASS: %lu independent review assertions.\n", checks); return 0;
}
