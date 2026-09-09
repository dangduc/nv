/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "NVFZF.h"
#include "fzf.h"
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern int reference_search(const NVFZFCandidate *, size_t, const char *,
                            NVFZFQueryMode, NVFZFSearchResult *);
extern int reference_rank_boundary_check(void);
static size_t checks;
#define CHECK(condition, ...) do { \
  checks++; \
  if (!(condition)) { \
    fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); \
    fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); exit(1); \
  } \
} while (0)

/* These hooks intercept bridge-owned allocations only. The upstream parser
   and scorer use the independent matcher allocation domain below. */
static _Atomic size_t alloc_calls;
static _Atomic size_t fail_call;
static _Atomic size_t cancel_call;
static NVFZFCancel *allocation_cancel;
static int allocation_event(void) {
  size_t call = atomic_fetch_add(&alloc_calls, 1) + 1;
  if (call == atomic_load(&cancel_call)) nvfzf_cancel_set(allocation_cancel);
  return call != atomic_load(&fail_call);
}
void *nvfzf_test_malloc(size_t size) { return allocation_event() ? malloc(size) : NULL; }
void *nvfzf_test_calloc(size_t count, size_t size) {
  return allocation_event() ? calloc(count, size) : NULL;
}
void *nvfzf_test_realloc(void *pointer, size_t size) {
  return allocation_event() ? realloc(pointer, size) : NULL;
}
static void reset_allocations(size_t failure, size_t cancellation, NVFZFCancel *token) {
  atomic_store(&alloc_calls, 0); atomic_store(&fail_call, failure);
  allocation_cancel = token; atomic_store(&cancel_call, cancellation);
}

/* Upstream allocations use a separate domain. The reference sees these hooks
   too, but every oracle call runs with injection disabled. Scoring/ranking
   code remains unchanged, and bridge faults cannot affect this domain. */
static _Atomic size_t matcher_alloc_calls;
static _Atomic size_t matcher_fail_call;
typedef struct { const char *file; int line; bool failed; } MatcherSite;
static MatcherSite matcher_sites[64];
static size_t matcher_site_count;
static bool record_matcher_sites;
static bool matcher_allocation_event(const char *file, int line) {
  size_t call = atomic_fetch_add(&matcher_alloc_calls, 1) + 1;
  bool failed = call == atomic_load(&matcher_fail_call);
  /* Site recording is enabled only for the serial fault sweeps. */
  if (record_matcher_sites) {
    size_t i;
    for (i = 0; i < matcher_site_count; i++)
      if (matcher_sites[i].line == line && !strcmp(matcher_sites[i].file, file)) break;
    if (i == matcher_site_count) {
      CHECK(i < sizeof matcher_sites / sizeof matcher_sites[0], "allocation site capacity");
      matcher_sites[matcher_site_count++] = (MatcherSite){file, line, false};
    }
    if (failed) matcher_sites[i].failed = true;
  }
  return !failed;
}
void *nvfzf_matcher_malloc(size_t size, const char *file, int line) {
  return matcher_allocation_event(file, line) ? malloc(size) : NULL;
}
void *nvfzf_matcher_calloc(size_t count, size_t size, const char *file, int line) {
  return matcher_allocation_event(file, line) ? calloc(count, size) : NULL;
}
void *nvfzf_matcher_realloc(void *pointer, size_t size, const char *file, int line) {
  return matcher_allocation_event(file, line) ? realloc(pointer, size) : NULL;
}
static void reset_matcher_allocations(size_t failure) {
  atomic_store(&matcher_alloc_calls, 0);
  atomic_store(&matcher_fail_call, failure);
}

static void compare_result(const NVFZFSearchResult *actual,
                           const NVFZFSearchResult *expected, const char *label) {
  CHECK(actual->count == expected->count, "%s: count %zu != %zu", label,
        actual->count, expected->count);
  for (size_t i = 0; i < expected->count; i++) {
    NVFZFMatch a = actual->matches[i], e = expected->matches[i];
    CHECK(a.candidate_index == e.candidate_index && a.public_score == e.public_score &&
          a.rank_score == e.rank_score && a.trimmed_length == e.trimmed_length,
          "%s at %zu: actual id=%zu public=%d rank=%u length=%u; "
          "reference id=%zu public=%d rank=%u length=%u", label, i,
          a.candidate_index, a.public_score, a.rank_score, a.trimmed_length,
          e.candidate_index, e.public_score, e.rank_score, e.trimmed_length);
  }
}

static void parity(NVFZFEngine *engine, NVFZFCandidate *items, size_t count,
                   const char *query, NVFZFQueryMode mode) {
  NVFZFSearchResult expected = {0}, actual = {0};
  reference_search(items, count, query, mode, &expected);
  CHECK(nvfzf_search(engine, items, count, query, strlen(query), mode, NULL, &actual)
        == NVFZF_OK, "search query '%s' mode %d", query, mode);
  char label[160]; snprintf(label, sizeof(label), "query '%s' mode %d", query, mode);
  compare_result(&actual, &expected, label);
  nvfzf_search_result_free(&actual); free(expected.matches);
}

static uint32_t random_state = UINT32_C(0x93c27d18);
static uint32_t random_value(void) {
  uint32_t x = random_state; x ^= x << 13; x ^= x >> 17; x ^= x << 5;
  return random_state = x;
}

static size_t make_corpus(NVFZFCandidate *items, char **owned) {
  static const char *fixed[] = {
    "alpha", "ALPHA", " alpha ", "\talpha\n", "alpha beta", "alphabet",
    "beta alpha", "alpha\nbeta", "delta gamma", "prefix/alpha", "alpha.json",
    "alpha-beta gamma", "aardvark", ("\xC2\xA0" "alpha" "\xE3\x80\x80"),
    ("\xE2\x80\x89" "alpha beta\t"), "😀 alpha café", "CAFÉ", "cafe\xCC\x81",
    "Straße", "STRASSE", "東京 alpha", "[alpha]", "alpha$", "'alpha'", "",
    "   \t\n", "!alpha", "alpha | beta", "alpha\\ beta", "a b", "ab", "abc"
  };
  size_t count = 0;
  for (size_t i = 0; i < sizeof(fixed) / sizeof(fixed[0]); i++)
    items[count++] = (NVFZFCandidate){ fixed[i], strlen(fixed[i]) };
  static const char *words[] = {"alpha", "beta", "gamma", "delta", "ALPHA", "café",
                               "東京", "😀", "[x]", "aardvark", "one", "two"};
  for (size_t i = 0; i < 320; i++) {
    char *text = malloc(512); CHECK(text, "corpus allocation");
    size_t used = 0, terms = 1 + random_value() % 12;
    for (size_t j = 0; j < terms; j++) {
      const char *word = words[random_value() % (sizeof(words) / sizeof(words[0]))];
      used += (size_t)snprintf(text + used, 512 - used, "%s%s", j ? " " : "", word);
    }
    owned[count] = text; items[count++] = (NVFZFCandidate){ text, used };
  }
  /* Equal score and length ties must retain producer order above radix size. */
  for (size_t i = 0; i < 80; i++) items[count++] = (NVFZFCandidate){ "alpha", 5 };
  return count;
}

static void test_corpus(NVFZFEngine *engine) {
  NVFZFCandidate items[512] = {0}; char *owned[512] = {0};
  size_t count = make_corpus(items, owned);
  const char *queries[] = { "", " ", "a", "ab", "alpha", "ALPHA", "aa", "東京",
    "😀", "café", "cafe", "strasse", "^alpha", "alpha$", "^alpha$", "'alpha",
    "'alpha'", "!alpha", "!absent", "!alpha !beta", "!alpha | !beta",
    "alpha beta", "alpha | beta", "alpha | beta gamma", "!delta alpha",
    "[x]", "\\", "'alpha beta", "alpha\\ beta", "^", "'", "!", "|" };
  for (int mode = NVFZF_NATIVE_FUZZY; mode <= NVFZF_NATIVE_EXACT; mode++)
    for (size_t i = 0; i < sizeof(queries) / sizeof(queries[0]); i++)
      parity(engine, items, count, queries[i], (NVFZFQueryMode)mode);

  NVFZFSearchResult expected = {0}, actual = {0};
  reference_search(items, count, "a", NVFZF_NATIVE_FUZZY, &expected);
  CHECK(expected.count >= 64, "corpus must exercise native radix sort");
  reset_allocations(0, 0, NULL);
  CHECK(nvfzf_search(engine, items, count, "a", 1, NVFZF_NATIVE_FUZZY, NULL, &actual)
        == NVFZF_OK, "baseline structural allocation search");
  size_t calls = atomic_load(&alloc_calls);
  nvfzf_search_result_free(&actual);
  CHECK(calls >= 4, "expected query/list/sort/result allocations, got %zu", calls);
  size_t failures = 0, successful_fallbacks = 0;
  for (size_t i = 1; i <= calls; i++) {
    reset_allocations(i, 0, NULL);
    actual = (NVFZFSearchResult){ (void *)(uintptr_t)1, 42 };
    NVFZFStatus status = nvfzf_search(engine, items, count, "a", 1,
                                     NVFZF_NATIVE_FUZZY, NULL, &actual);
    if (status == NVFZF_OK) {
      compare_result(&actual, &expected, "allocation fallback"); successful_fallbacks++;
    } else {
      CHECK(status == NVFZF_OUT_OF_MEMORY, "allocation %zu status %d", i, status);
      CHECK(!actual.matches && !actual.count, "OOM must discard partial results"); failures++;
    }
    nvfzf_search_result_free(&actual);
  }
  reset_allocations(0, 0, NULL);
  CHECK(failures >= 3 && successful_fallbacks >= 1,
        "sweep must reach fatal allocations and allocationless native sorter fallback");
  /* Cancellation is injected after scoring, during the native sort's scratch
     allocation. This deterministically tests post-scoring publication guards. */
  NVFZFCancel *token = nvfzf_cancel_create(); CHECK(token, "sort cancellation token");
  reset_allocations(0, calls - 1, token);
  CHECK(nvfzf_search(engine, items, count, "a", 1, NVFZF_NATIVE_FUZZY, token, &actual)
        == NVFZF_CANCELLED, "cancellation during sort must discard results");
  CHECK(!actual.matches && !actual.count, "sort cancellation has no partial output");
  reset_allocations(0, 0, NULL); nvfzf_cancel_free(token);
  free(expected.matches);
  for (size_t i = 0; i < count; i++) free(owned[i]);
  printf("Corpus parity: %zu candidates, %zu queries, both native modes; "
         "%zu structural OOM cases, %zu sorter fallback.\n", count,
         sizeof(queries) / sizeof(queries[0]), failures, successful_fallbacks);
}

static void test_long_candidates(NVFZFEngine *engine) {
  NVFZFCandidate items[4]; char *owned[4];
  const size_t lengths[] = {65534, 65535, 65536, 90000};
  for (size_t i = 0; i < 4; i++) {
    owned[i] = malloc(lengths[i] + 1); CHECK(owned[i], "long candidate allocation");
    memset(owned[i], 'x', lengths[i]); owned[i][lengths[i]] = 0;
    owned[i][0] = 'a'; owned[i][lengths[i] - 1] = 'b';
    items[i] = (NVFZFCandidate){owned[i], lengths[i]};
  }
  parity(engine, items, 4, "ab", NVFZF_NATIVE_FUZZY);
  parity(engine, items, 4, "!not-present", NVFZF_NATIVE_FUZZY);
  NVFZFSearchResult result = {0};
  CHECK(nvfzf_search(engine, items, 4, "ab", 2, NVFZF_NATIVE_FUZZY, NULL, &result)
        == NVFZF_OK && result.count == 4, "long-gap matches retain membership");
  for (size_t i = 0; i < result.count; i++) {
    CHECK(result.matches[i].public_score == 1 && result.matches[i].rank_score == 0,
          "nonpositive greedy raw score has public sentinel 1 and native rank 0");
    CHECK(result.matches[i].trimmed_length == (i == 0 ? 65534 : 65535),
          "trimmed length saturates at UINT16_MAX");
    CHECK(result.matches[i].candidate_index == i, "saturated ties preserve producer order");
  }
  nvfzf_search_result_free(&result);
  /* Many exact positive terms exceed native 16-bit rank without relying on
     the fuzzy algorithm's int16 scratch arithmetic. */
  char query[16000] = {0}; size_t used = 0;
  for (size_t i = 0; i < 1200; i++) used += (size_t)snprintf(query + used,
      sizeof(query) - used, "%s'alpha", i ? " " : "");
  NVFZFCandidate saturated[] = {{"alpha", 5}, {"alpha alpha", 11}, {"alpha", 5}};
  parity(engine, saturated, 3, query, NVFZF_NATIVE_FUZZY);
  CHECK(nvfzf_search(engine, saturated, 3, query, used, NVFZF_NATIVE_FUZZY, NULL, &result)
        == NVFZF_OK && result.count == 3, "score saturation search");
  CHECK(result.matches[0].rank_score == UINT16_MAX &&
        result.matches[0].public_score > UINT16_MAX,
        "positive compound raw score clamps only native rank");
  CHECK(result.matches[0].candidate_index == 0 && result.matches[1].candidate_index == 2 &&
        result.matches[2].candidate_index == 1, "saturated score ties use length then producer");
  nvfzf_search_result_free(&result);
  for (size_t i = 0; i < 4; i++) free(owned[i]);
  puts("Long-candidate parity: nonpositive greedy matches and both rank saturation boundaries.");
}

static void positions_case(NVFZFEngine *engine, const char *candidate, size_t length,
                           const char *query, NVFZFQueryMode mode, bool matched,
                           const uint32_t *offsets, size_t count, const char *label) {
  NVFZFPositions found = { (void *)(uintptr_t)1, 42, !matched };
  CHECK(nvfzf_positions(engine, (NVFZFCandidate){candidate, length}, query, strlen(query),
        mode, NULL, &found) == NVFZF_OK, "%s position status", label);
  CHECK(found.matched == matched && found.count == count, "%s position membership/count", label);
  for (size_t i = 0; i < count; i++) CHECK(found.offsets[i] == offsets[i],
        "%s position %zu: %u != %u", label, i, found.offsets[i], offsets[i]);
  nvfzf_positions_free(&found);
  CHECK(!found.offsets && !found.count && !found.matched, "%s free resets output", label);
}

static void test_positions(NVFZFEngine *engine) {
  const char *unicode = "😀 café"; const uint32_t cafe[] = {2, 3, 4, 5};
  positions_case(engine, unicode, strlen(unicode), "café", NVFZF_NATIVE_FUZZY,
                 true, cafe, 4, "Unicode codepoints, not bytes or UTF16");
  const char nul[] = {'A', 0, 'b', 'C'}; const uint32_t bc[] = {2, 3};
  positions_case(engine, nul, sizeof(nul), "bc", NVFZF_NATIVE_FUZZY,
                 true, bc, 2, "bounded embedded NUL");
  const uint32_t unioned[] = {0, 1, 2};
  positions_case(engine, "abc", 3, "ab bc", NVFZF_NATIVE_FUZZY,
                 true, unioned, 3, "positive term positions are sorted unique");
  positions_case(engine, "beta alpha", 10, "alpha | beta", NVFZF_NATIVE_FUZZY,
                 true, (const uint32_t[]){5,6,7,8,9}, 5, "OR keeps native first positive match");
  positions_case(engine, "alpha", 5, "!beta", NVFZF_NATIVE_FUZZY,
                 true, NULL, 0, "inverse membership without positive highlights");
  positions_case(engine, "alpha", 5, "!alpha", NVFZF_NATIVE_FUZZY,
                 false, NULL, 0, "inverse rejection");
  positions_case(engine, "alpha", 5, "", NVFZF_NATIVE_FUZZY,
                 true, NULL, 0, "empty query");
  positions_case(engine, "alpha", 5, "al !alpha", NVFZF_NATIVE_FUZZY,
                 false, NULL, 0, "late rejection discards earlier positions");
  positions_case(engine, "a b", 3, "ab", NVFZF_NATIVE_EXACT,
                 false, NULL, 0, "exact mode prevents fuzzy match");
  positions_case(engine, "a b", 3, "'ab", NVFZF_NATIVE_EXACT,
                 true, (const uint32_t[]){0,2}, 2, "quote toggles exact mode term to fuzzy");
  /* Unicode v1 fallback rewrites its position buffer from bytes to logical
     indexes. Earlier positive-term indexes must never be remapped by a later
     term. The second term is deliberately over the default DP slab bound. */
  size_t repeats = 60000, size = 4 + 2 + repeats * 2 + 1;
  char *large = malloc(size + 1); CHECK(large, "compound fallback allocation");
  memcpy(large, "😀za", 6);
  for (size_t i = 0; i < repeats; i++) memcpy(large + 6 + i * 2, "é", 2);
  large[size - 1] = 'b'; large[size] = 0;
  positions_case(engine, large, size, "'z ab", NVFZF_NATIVE_FUZZY, true,
                 (const uint32_t[]){1,2,60003}, 3, "compound Unicode v1 fallback");
  free(large);
  puts("Position checks: Unicode, NUL, OR/AND/inverse, exact toggle, and compound v1 fallback.");
}

static void test_invalid_and_precancel(NVFZFEngine *engine) {
  NVFZFCandidate item = {"alpha", 5}; NVFZFSearchResult result = {0};
  NVFZFPositions positions = {0};
  const char invalid_query[] = {'a', 0, 'b'};
  CHECK(nvfzf_search(engine, &item, 1, invalid_query, sizeof(invalid_query),
        NVFZF_NATIVE_FUZZY, NULL, &result) == NVFZF_INVALID_INPUT, "query NUL rejection");
  CHECK(!result.matches && !result.count, "query rejection resets output");
  CHECK(nvfzf_search(engine, &item, (size_t)UINT32_MAX + 1, "a", 1,
        NVFZF_NATIVE_FUZZY, NULL, &result) == NVFZF_INVALID_INPUT, "count bounds before access");
  NVFZFCandidate too_long = {"", (size_t)INT32_MAX + 1};
  CHECK(nvfzf_search(engine, &too_long, 1, "a", 1, NVFZF_NATIVE_FUZZY,
        NULL, &result) == NVFZF_INVALID_INPUT, "candidate bounds before access");
  CHECK(nvfzf_positions(engine, too_long, "a", 1, NVFZF_NATIVE_FUZZY,
        NULL, &positions) == NVFZF_INVALID_INPUT, "positions candidate bounds before access");
  CHECK(nvfzf_search(engine, &item, 1, "", 65537, NVFZF_NATIVE_FUZZY,
        NULL, &result) == NVFZF_INVALID_INPUT, "query bounds before access");
  CHECK(nvfzf_search(engine, &item, 1, "a", 1, (NVFZFQueryMode)99,
        NULL, &result) == NVFZF_INVALID_INPUT, "invalid mode");
  CHECK(nvfzf_search(engine, NULL, 1, "a", 1, NVFZF_NATIVE_FUZZY,
        NULL, &result) == NVFZF_INVALID_INPUT, "invalid collection pointer");
  CHECK(nvfzf_search(engine, NULL, 0, "a", 1, NVFZF_NATIVE_FUZZY,
        NULL, &result) == NVFZF_OK && !result.count, "empty collection");
  nvfzf_search_result_free(&result);
  NVFZFCancel *token = nvfzf_cancel_create(); CHECK(token, "pre-cancel token");
  nvfzf_cancel_set(token);
  CHECK(nvfzf_search(engine, &item, 1, "a", 1, NVFZF_NATIVE_FUZZY,
        token, &result) == NVFZF_CANCELLED, "pre-cancel search");
  CHECK(!result.matches && !result.count, "pre-cancel search publishes nothing");
  CHECK(nvfzf_positions(engine, item, "a", 1, NVFZF_NATIVE_FUZZY,
        token, &positions) == NVFZF_CANCELLED, "pre-cancel positions");
  CHECK(!positions.offsets && !positions.count && !positions.matched,
        "pre-cancel positions publishes nothing");
  nvfzf_cancel_free(token);
}

typedef struct {
  NVFZFEngine *engine; NVFZFCancel *token; NVFZFCandidate *items; size_t count;
  _Atomic bool started; NVFZFStatus status; NVFZFSearchResult result;
} ThreadSearch;
static void *search_thread(void *opaque) {
  ThreadSearch *work = opaque; atomic_store(&work->started, true);
  work->status = nvfzf_search(work->engine, work->items, work->count, "ab", 2,
      NVFZF_NATIVE_FUZZY, work->token, &work->result);
  return NULL;
}
static void test_live_cancel(NVFZFEngine *engine) {
  size_t length = 256 * 1024, count = 1024;
  char *text = malloc(length); NVFZFCandidate *items = calloc(count, sizeof(*items));
  CHECK(text && items, "live cancel corpus allocation");
  memset(text, 'x', length); text[0] = 'a'; text[length - 1] = 'b';
  for (size_t i = 0; i < count; i++) items[i] = (NVFZFCandidate){text, length};
  NVFZFCancel *token = nvfzf_cancel_create(); CHECK(token, "live cancel token");
  reset_allocations(0, 0, NULL);
  ThreadSearch work = {.engine = engine, .token = token, .items = items, .count = count};
  pthread_t thread; CHECK(pthread_create(&thread, NULL, search_thread, &work) == 0,
                         "start independent worker");
  const struct timespec delay = {.tv_nsec = 1000000};
  while (!atomic_load(&work.started)) nanosleep(&delay, NULL);
  /* Two bridge allocations establish that search passed its entry guard and
     staged the candidate array. The cancellation token is set by this thread. */
  while (atomic_load(&alloc_calls) < 2) nanosleep(&delay, NULL);
  nanosleep(&delay, NULL); nvfzf_cancel_set(token);
  CHECK(pthread_join(thread, NULL) == 0, "join cancelled worker");
  CHECK(work.status == NVFZF_CANCELLED && !work.result.matches && !work.result.count,
        "live cancellation discards complete and partial matches");
  nvfzf_cancel_free(token); free(items); free(text);
  puts("Cancellation checks: pre-cancel, real worker cancellation, native-sort allocation boundary.");
}

static void typed_parity(NVFZFEngine *engine, NVFZFCandidate *items, size_t count,
                         NVFZFTerm *terms, size_t term_count, const char *native) {
  NVFZFSearchResult expected = {0}, actual = {0};
  CHECK(reference_search(items, count, native, NVFZF_NATIVE_FUZZY, &expected) == 0,
        "typed native reference query");
  CHECK(nvfzf_search_terms(engine, items, count, terms, term_count, NULL, &actual) == NVFZF_OK,
        "typed search query");
  compare_result(&actual, &expected, native);
  nvfzf_search_result_free(&actual);
  const size_t sizes[] = {1, 7, 255, SIZE_MAX};
  for (size_t b = 0; b < sizeof sizes / sizeof sizes[0]; b++) {
    NVFZFJob *job = NULL;
    CHECK(nvfzf_job_create_terms(items, count, terms, term_count, NULL, &job) == NVFZF_OK,
          "batch job begin");
    CHECK(nvfzf_job_finish(job, &actual) == NVFZF_INVALID_INPUT, "incomplete job cannot publish");
    bool finished = false;
    size_t steps = 0;
    while (!finished) {
      CHECK(nvfzf_job_step(engine, job, sizes[b], &finished) == NVFZF_OK, "batch step");
      steps++;
    }
    size_t expected_steps = sizes[b] == SIZE_MAX ? 1 : (count + sizes[b] - 1) / sizes[b];
    CHECK(steps == expected_steps, "bounded batch candidate count");
    CHECK(nvfzf_job_finish(job, &actual) == NVFZF_OK, "batch finalize");
    compare_result(&actual, &expected, native);
    nvfzf_search_result_free(&actual);
    CHECK(nvfzf_job_finish(job, &actual) == NVFZF_INVALID_INPUT, "result transfers once");
    nvfzf_job_free(job);
  }
  free(expected.matches);
}

static void test_typed_terms(NVFZFEngine *engine) {
  NVFZFCandidate corpus[512] = {0}; char *owned[512] = {0};
  size_t count = make_corpus(corpus, owned);
  NVFZFTerm alpha[] = {{"alpha",5,NVFZF_TERM_FUZZY}};
  NVFZFTerm mixed[] = {{"ab",2,NVFZF_TERM_FUZZY},{"gamma",5,NVFZF_TERM_EXACT}};
  NVFZFTerm phrase[] = {{"alpha beta",10,NVFZF_TERM_EXACT}};
  NVFZFTerm unicode[] = {{"CAFÉ",5,NVFZF_TERM_FUZZY},{"東京",6,NVFZF_TERM_EXACT}};
  typed_parity(engine, corpus, count, alpha, 1, "alpha");
  typed_parity(engine, corpus, count, mixed, 2, "ab 'gamma");
  typed_parity(engine, corpus, count, phrase, 1, "'alpha\\ beta");
  typed_parity(engine, corpus, count, unicode, 2, "CAFÉ '東京");
  typed_parity(engine, corpus, count, NULL, 0, "");
  for (size_t i = 0; i < count; i++) free(owned[i]);

  const char *literal[] = {"!alpha", "^alpha", "alpha$", "'alpha", "alpha'", "|", "a\\ b", "a:b", "a\tb", "a\nb"};
  for (size_t i = 0; i < sizeof literal / sizeof literal[0]; i++) {
    const char *token = literal[i];
    char context[128]; snprintf(context, sizeof context, "prefix %s suffix", token);
    NVFZFCandidate items[] = {{"alpha",5},{context,strlen(context)},{"ab",2},{"unrelated",9}};
    for (int kind = NVFZF_TERM_FUZZY; kind <= NVFZF_TERM_EXACT; kind++) {
      NVFZFTerm term = {token,strlen(token),(NVFZFTermKind)kind};
      NVFZFSearchResult result = {0};
      CHECK(nvfzf_search_terms(engine, items, 4, &term, 1, NULL, &result) == NVFZF_OK,
            "literal operator accepted");
      CHECK(result.count == 1 && result.matches[0].candidate_index == 1,
            "operator %s kind %d stays literal", token, kind);
      nvfzf_search_result_free(&result);
      NVFZFPositions positions = {0};
      CHECK(nvfzf_positions_terms(engine, items[1], &term, 1, NULL, &positions) == NVFZF_OK,
            "literal positions query");
      CHECK(positions.matched && positions.count == term.length, "literal positions count");
      for (size_t j = 0; j < positions.count; j++)
        CHECK(positions.offsets[j] == 7 + j, "literal operator position");
      nvfzf_positions_free(&positions);
    }
  }
  NVFZFCandidate letters[] = {{"copper lantern",14},{"copper--lantern",15},{"K café",9}};
  NVFZFTerm phrase_term = {"copper lantern",14,NVFZF_TERM_EXACT};
  NVFZFSearchResult result = {0};
  CHECK(nvfzf_search_terms(engine, letters, 3, &phrase_term, 1, NULL, &result) == NVFZF_OK &&
        result.count == 1 && result.matches[0].candidate_index == 0, "phrase needs contiguous whitespace");
  nvfzf_search_result_free(&result);
  NVFZFTerm kelvin = {"K",3,NVFZF_TERM_FUZZY};
  CHECK(nvfzf_search_terms(engine, letters, 3, &kelvin, 1, NULL, &result) == NVFZF_OK &&
        result.count == 1 && result.matches[0].candidate_index == 2, "lowercase byte length change");
  nvfzf_search_result_free(&result);
  puts("Typed terms: literal punctuation/whitespace, phrase contiguity, Unicode lowercase, independent native order, batch sizes 1/7/255/all.");
}

static void test_typed_failures(NVFZFEngine *engine) {
  NVFZFCandidate items[] = {{"alpha",5},{"alpha",5}};
  NVFZFTerm term = {"alpha",5,NVFZF_TERM_FUZZY};
  NVFZFSearchResult result = {0};
  reset_allocations(0, 0, NULL);
  CHECK(nvfzf_search_terms(engine, items, 2, &term, 1, NULL, &result) == NVFZF_OK,
        "measure typed allocations");
  size_t allocations = atomic_load(&alloc_calls);
  nvfzf_search_result_free(&result);
  size_t failures = 0;
  for (size_t i = 1; i <= allocations; i++) {
    reset_allocations(i, 0, NULL);
    NVFZFStatus status = nvfzf_search_terms(engine, items, 2, &term, 1, NULL, &result);
    CHECK(status == NVFZF_OK || status == NVFZF_OUT_OF_MEMORY, "typed allocation status");
    if (status == NVFZF_OUT_OF_MEMORY) {
      failures++;
      CHECK(!result.matches && !result.count, "typed OOM never publishes partial results");
    } else CHECK(result.count == 2, "typed fallback complete");
    nvfzf_search_result_free(&result);
  }
  reset_allocations(0, 0, NULL);
  CHECK(failures >= 8, "fault injection reached every builder allocation");
  NVFZFTerm invalid[] = {{"",0,NVFZF_TERM_FUZZY},{"a\0b",3,NVFZF_TERM_EXACT},
                        {"a",1,(NVFZFTermKind)99},{NULL,1,NVFZF_TERM_EXACT},
                        {"a",NVFZF_MAX_QUERY_BYTES+1,NVFZF_TERM_FUZZY}};
  for (size_t i = 0; i < sizeof invalid / sizeof invalid[0]; i++) {
    NVFZFJob *job = (void *)1;
    CHECK(nvfzf_job_create_terms(items, 2, &invalid[i], 1, NULL, &job) == NVFZF_INVALID_INPUT && !job,
          "invalid typed term rejected");
  }
  CHECK(nvfzf_search_terms(engine, items, 2, &term, NVFZF_MAX_QUERY_BYTES+1, NULL, &result) == NVFZF_INVALID_INPUT,
        "typed term count validated before access");
  NVFZFJob *job = NULL;
  NVFZFCancel *cancel = nvfzf_cancel_create(); CHECK(cancel, "typed cancel token");
  CHECK(nvfzf_job_create_terms(items, 2, &term, 1, cancel, &job) == NVFZF_OK, "cancellable typed job");
  bool finished;
  CHECK(nvfzf_job_step(engine, job, 1, &finished) == NVFZF_OK && !finished, "one candidate scored");
  nvfzf_cancel_set(cancel);
  CHECK(nvfzf_job_step(engine, job, 1, &finished) == NVFZF_CANCELLED && !finished, "cancel between batches");
  CHECK(nvfzf_job_finish(job, &result) == NVFZF_CANCELLED && !result.count && !result.matches,
        "cancelled partial job cannot publish");
  nvfzf_job_free(job); nvfzf_cancel_free(cancel);
  char query[] = "alpha";
  NVFZFTerm copied = {query,5,NVFZF_TERM_FUZZY};
  CHECK(nvfzf_job_create_terms(items, 2, &copied, 1, NULL, &job) == NVFZF_OK, "copied terms job");
  memset(query, 'z', 5);
  CHECK(nvfzf_job_step(engine, job, 0, &finished) == NVFZF_INVALID_INPUT, "zero batch rejected");
  CHECK(nvfzf_job_step(engine, job, 2, &finished) == NVFZF_OK && finished, "typed terms owned by job");
  CHECK(nvfzf_job_finish(job, &result) == NVFZF_OK && result.count == 2, "copied terms unaffected by caller edit");
  nvfzf_search_result_free(&result); nvfzf_job_free(job);
  printf("Typed ownership/errors: %zu injected OOM cases, invalid terms, copied terms, cancellation after partial scoring.\n", failures);
}

#include "matcher_oom.inc"

int main(void) {
  CHECK(!strcmp(nvfzf_upstream_revision(), "4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d"),
        "bridge upstream revision");
  CHECK(reference_rank_boundary_check(), "reference rank boundaries");
  NVFZFEngine *engine = nvfzf_engine_create(); CHECK(engine, "create engine");
  test_corpus(engine); test_long_candidates(engine); test_positions(engine);
  test_invalid_and_precancel(engine);
  reset_allocations(0, 0, NULL); test_live_cancel(engine);
  test_typed_terms(engine); test_typed_failures(engine);
  nvfzf_engine_free(engine);
  test_matcher_allocations();
  printf("PASS: %zu checks. Native scorer/radix ordering reference is independent "
         "of bridge helpers.\n", checks);
  return 0;
}
