/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "NVFZF.h"
#include "fzf-private.h"
#include "fzf-simd-prefilter.h"

#include <ctype.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define MIN(X, Y) ((X) < (Y) ? (X) : (Y))
#include "NativeRanking.inc"
#undef MIN
#include "NativePattern.inc"

struct NVFZFEngine { fzf_slab_t *slab; };
struct NVFZFCancel { _Atomic bool requested; };
struct NVFZFJob {
    const NVFZFCandidate *candidates;
    size_t count, next, matched;
    fzf_pattern_t *pattern;
    ScoredStr *matches;
    NVFZFCancel *cancel;
    NVFZFStatus status;
    bool empty, can_reuse, consumed;
};

static _Atomic bool *stop_flag(NVFZFCancel *cancel) {
    return cancel ? &cancel->requested : NULL;
}

static bool cancelled(NVFZFCancel *cancel) {
    return async_stop_requested(stop_flag(cancel));
}

NVFZFEngine *nvfzf_engine_create(void) {
    NVFZFEngine *engine = calloc(1, sizeof *engine);
    if (!engine) return NULL;
    engine->slab = fzf_make_default_slab();
    if (!engine->slab) { free(engine); return NULL; }
    return engine;
}

void nvfzf_engine_free(NVFZFEngine *engine) {
    if (!engine) return;
    fzf_free_slab(engine->slab);
    free(engine);
}

NVFZFCancel *nvfzf_cancel_create(void) {
    NVFZFCancel *cancel = malloc(sizeof *cancel);
    if (cancel) atomic_init(&cancel->requested, false);
    return cancel;
}

void nvfzf_cancel_set(NVFZFCancel *cancel) {
    if (cancel) atomic_store_explicit(&cancel->requested, true, memory_order_relaxed);
}

bool nvfzf_cancel_is_set(const NVFZFCancel *cancel) {
    return cancel && atomic_load_explicit(&cancel->requested, memory_order_relaxed);
}

void nvfzf_cancel_free(NVFZFCancel *cancel) { free(cancel); }

static bool valid_candidate(NVFZFCandidate candidate) {
    return (candidate.bytes || candidate.length == 0) && candidate.length <= INT32_MAX;
}

static NVFZFStatus parse_query(const char *query, size_t length,
                              NVFZFQueryMode mode, fzf_pattern_t **pattern) {
    *pattern = NULL;
    if ((!query && length) || length > NVFZF_MAX_QUERY_BYTES ||
        (mode != NVFZF_NATIVE_FUZZY && mode != NVFZF_NATIVE_EXACT) ||
        (length && memchr(query, 0, length))) return NVFZF_INVALID_INPUT;
    char *copy = malloc(length + 1);
    if (!copy) return NVFZF_OUT_OF_MEMORY;
    if (length) memcpy(copy, query, length);
    copy[length] = 0;
    *pattern = fzf_parse_pattern_with_direction(
        CaseIgnore, false, copy, mode == NVFZF_NATIVE_FUZZY, true);
    free(copy);
    return *pattern ? NVFZF_OK : NVFZF_OUT_OF_MEMORY;
}

static NVFZFStatus build_terms(const NVFZFTerm *terms, size_t count,
                              NVFZFCancel *cancel, fzf_pattern_t **output) {
    *output = NULL;
    if ((!terms && count) || count > NVFZF_MAX_QUERY_BYTES)
        return NVFZF_INVALID_INPUT;
    size_t bytes = 0;
    for (size_t i = 0; i < count; i++) {
        if (cancelled(cancel)) return NVFZF_CANCELLED;
        NVFZFTerm term = terms[i];
        if (!term.bytes || !term.length || term.length > NVFZF_MAX_QUERY_BYTES - bytes ||
            (term.kind != NVFZF_TERM_FUZZY && term.kind != NVFZF_TERM_EXACT) ||
            memchr(term.bytes, 0, term.length)) return NVFZF_INVALID_INPUT;
        bytes += term.length;
    }
    fzf_pattern_t *pattern = calloc(1, sizeof *pattern);
    if (!pattern) return NVFZF_OUT_OF_MEMORY;
    pattern->forward = true;
    pattern->has_positive_term = count > 0;
    pattern->ptr = count ? calloc(count, sizeof *pattern->ptr) : NULL;
    if (count && !pattern->ptr) { fzf_free_pattern(pattern); return NVFZF_OUT_OF_MEMORY; }
    pattern->cap = count;
    NVFZFStatus status = NVFZF_OK;
    for (size_t i = 0; i < count; i++) {
        if (cancelled(cancel)) { status = NVFZF_CANCELLED; break; }
        fzf_term_set_t *set = calloc(1, sizeof *set);
        if (!set) { status = NVFZF_OUT_OF_MEMORY; break; }
        pattern->ptr[pattern->size++] = set;
        set->ptr = calloc(1, sizeof *set->ptr);
        if (!set->ptr) { status = NVFZF_OUT_OF_MEMORY; break; }
        set->size = set->cap = 1;
        fzf_term_t *term = set->ptr;
        term->ptr = str_tolower(terms[i].bytes, terms[i].length);
        if (!term->ptr) { status = NVFZF_OUT_OF_MEMORY; break; }
        size_t length = strlen(term->ptr);
        term->text = make_pattern_text(term->ptr, length, false);
        if (!term->text) { status = NVFZF_OUT_OF_MEMORY; break; }
        bool ascii = is_ascii_utf8proc(term->ptr, length);
        term->fn = terms[i].kind == NVFZF_TERM_FUZZY ?
            (ascii ? fzf_fuzzy_match_v2 : fzf_fuzzy_match_v2_utf8) :
            (ascii ? fzf_exact_match_naive : fzf_exact_match_utf8);
    }
    if (status != NVFZF_OK) { fzf_free_pattern(pattern); return status; }
    *output = pattern;
    return NVFZF_OK;
}

void nvfzf_search_result_free(NVFZFSearchResult *result) {
    if (!result) return;
    free(result->matches);
    *result = (NVFZFSearchResult){0};
}

static bool valid_collection(const NVFZFCandidate *candidates, size_t count) {
    return (candidates || count == 0) && count <= UINT32_MAX &&
        count <= SIZE_MAX / sizeof(ScoredStr) && count <= SIZE_MAX / sizeof(NVFZFMatch);
}

/* Takes pattern ownership even on failure. */
static NVFZFStatus create_job(const NVFZFCandidate *candidates, size_t count,
                             fzf_pattern_t *pattern, bool empty,
                             NVFZFCancel *cancel, NVFZFJob **output) {
    NVFZFJob *job = calloc(1, sizeof *job);
    if (!job) { fzf_free_pattern(pattern); return NVFZF_OUT_OF_MEMORY; }
    job->pattern = pattern;
    job->candidates = candidates;
    job->count = count;
    job->cancel = cancel;
    job->empty = empty;
    job->can_reuse = pattern->ptr &&
        fzf_rank_can_reuse_public_score(pattern, FZF_SCORE_SCHEME_DEFAULT);
    job->matches = count ? malloc(count * sizeof *job->matches) : NULL;
    if (count && !job->matches) { nvfzf_job_free(job); return NVFZF_OUT_OF_MEMORY; }
    *output = job;
    return NVFZF_OK;
}

NVFZFStatus nvfzf_job_create_terms(const NVFZFCandidate *candidates, size_t count,
                                 const NVFZFTerm *terms, size_t term_count,
                                 NVFZFCancel *cancel, NVFZFJob **output) {
    if (!output) return NVFZF_INVALID_INPUT;
    *output = NULL;
    if (!valid_collection(candidates, count)) return NVFZF_INVALID_INPUT;
    if (cancelled(cancel)) return NVFZF_CANCELLED;
    fzf_pattern_t *pattern = NULL;
    NVFZFStatus status = build_terms(terms, term_count, cancel, &pattern);
    if (status != NVFZF_OK) return status;
    return create_job(candidates, count, pattern, term_count == 0, cancel, output);
}

void nvfzf_job_free(NVFZFJob *job) {
    if (!job) return;
    fzf_free_pattern(job->pattern);
    free(job->matches);
    free(job);
}

NVFZFStatus nvfzf_job_step(NVFZFEngine *engine, NVFZFJob *job,
                         size_t max_candidates, bool *finished) {
    if (finished) *finished = false;
    if (!engine || !job || !finished || !max_candidates || job->consumed)
        return NVFZF_INVALID_INPUT;
    if (job->status != NVFZF_OK) return job->status;
    size_t remaining = job->count - job->next;
    size_t end = job->next + (max_candidates < remaining ? max_candidates : remaining);
    for (; job->next < end; job->next++) {
        if (cancelled(job->cancel)) return job->status = NVFZF_CANCELLED;
        NVFZFCandidate input = job->candidates[job->next];
        if (!valid_candidate(input)) return job->status = NVFZF_INVALID_INPUT;
        const char *text = input.bytes ? input.bytes : "";
        ScoredStr candidate = {.str = (char *)text, .idx = (uint32_t)job->next, .score = 1};
        if (!job->empty) {
            bool ascii = is_ascii_utf8proc(text, input.length);
            candidate.score = fzf_score_and_rank(
                text, input.length, ascii, job->pattern, engine->slab,
                FZF_SCORE_SCHEME_DEFAULT, job->can_reuse, &candidate.rank);
            if (fzf_allocation_failed()) return job->status = NVFZF_OUT_OF_MEMORY;
        }
        if (candidate.score > 0) job->matches[job->matched++] = candidate;
    }
    if (cancelled(job->cancel)) return job->status = NVFZF_CANCELLED;
    *finished = job->next == job->count;
    return NVFZF_OK;
}

NVFZFStatus nvfzf_job_finish(NVFZFJob *job, NVFZFSearchResult *result) {
    if (!result) return NVFZF_INVALID_INPUT;
    *result = (NVFZFSearchResult){0};
    if (!job || job->consumed) return NVFZF_INVALID_INPUT;
    if (job->status != NVFZF_OK) return job->status;
    if (cancelled(job->cancel)) return job->status = NVFZF_CANCELLED;
    if (job->next != job->count) return NVFZF_INVALID_INPUT;
    job->consumed = true;
    /* Compaction preserves producer order. The unchanged native stable radix
       sorter relies on that order for equal-key candidates. */
    if (job->pattern->has_positive_term &&
        !counting_sort_scored_abortable(job->matches, job->matched, stop_flag(job->cancel),
                                       FZF_SCORE_SCHEME_DEFAULT))
        return job->status = NVFZF_CANCELLED;
    NVFZFMatch *output = job->matched ? malloc(job->matched * sizeof *output) : NULL;
    if (job->matched && !output) return job->status = NVFZF_OUT_OF_MEMORY;
    for (size_t i = 0; i < job->matched; i++) {
        if ((i & 0xff) == 0 && cancelled(job->cancel)) {
            free(output); return job->status = NVFZF_CANCELLED;
        }
        output[i] = (NVFZFMatch){
            .candidate_index = job->matches[i].idx,
            .public_score = job->matches[i].score,
            .rank_score = job->matches[i].rank.score,
            .trimmed_length = job->matches[i].rank.first
        };
    }
    if (cancelled(job->cancel)) { free(output); return job->status = NVFZF_CANCELLED; }
    result->matches = output;
    result->count = job->matched;
    return NVFZF_OK;
}

static NVFZFStatus run_job(NVFZFEngine *engine, NVFZFJob *job, NVFZFSearchResult *result) {
    bool finished = false;
    NVFZFStatus status = nvfzf_job_step(engine, job, SIZE_MAX, &finished);
    if (status == NVFZF_OK) status = nvfzf_job_finish(job, result);
    nvfzf_job_free(job);
    return status;
}

NVFZFStatus nvfzf_search_terms(NVFZFEngine *engine,
                             const NVFZFCandidate *candidates, size_t count,
                             const NVFZFTerm *terms, size_t term_count,
                             NVFZFCancel *cancel, NVFZFSearchResult *result) {
    if (!result) return NVFZF_INVALID_INPUT;
    *result = (NVFZFSearchResult){0};
    if (!engine) return NVFZF_INVALID_INPUT;
    NVFZFJob *job = NULL;
    NVFZFStatus status = nvfzf_job_create_terms(candidates, count, terms, term_count, cancel, &job);
    return status == NVFZF_OK ? run_job(engine, job, result) : status;
}

NVFZFStatus nvfzf_search(NVFZFEngine *engine,
                       const NVFZFCandidate *candidates, size_t count,
                       const char *query, size_t query_length,
                       NVFZFQueryMode mode, NVFZFCancel *cancel,
                       NVFZFSearchResult *result) {
    if (!result) return NVFZF_INVALID_INPUT;
    *result = (NVFZFSearchResult){0};
    if (!engine || !valid_collection(candidates, count)) return NVFZF_INVALID_INPUT;
    if (cancelled(cancel)) return NVFZF_CANCELLED;
    fzf_pattern_t *pattern = NULL;
    NVFZFStatus status = parse_query(query, query_length, mode, &pattern);
    if (status != NVFZF_OK) return status;
    NVFZFJob *job = NULL;
    status = create_job(candidates, count, pattern, query_length == 0, cancel, &job);
    return status == NVFZF_OK ? run_job(engine, job, result) : status;
}

/* Dispatch parsed terms through bounded public algorithms. The upstream
   position wrapper uses strlen; this adapter preserves candidate NUL bytes.
   Match scoring and ordering continue to use fzf_score_and_rank unchanged. */
static fzf_result_t term_positions(fzf_term_t *term, fzf_string_t *input,
                                  bool ascii, bool forward,
                                  fzf_position_t *positions, fzf_slab_t *slab) {
    fzf_algo_t algorithm = term->fn;
    if (!ascii) {
        if (algorithm == fzf_fuzzy_match_v1) algorithm = fzf_fuzzy_match_v1_utf8;
        else if (algorithm == fzf_fuzzy_match_v2) algorithm = fzf_fuzzy_match_v2_utf8;
        else if (algorithm == fzf_exact_match_naive) algorithm = fzf_exact_match_utf8;
        else if (algorithm == fzf_exact_match_boundary) algorithm = fzf_exact_match_boundary_utf8;
        else if (algorithm == fzf_prefix_match) algorithm = fzf_prefix_match_utf8;
        else if (algorithm == fzf_suffix_match) algorithm = fzf_suffix_match_utf8;
        else if (algorithm == fzf_equal_match) algorithm = fzf_equal_match_utf8;
    }
    fzf_string_t *query = term->text;
    bool sensitive = term->case_sensitive, normalize = term->normalize;
    if (algorithm == fzf_fuzzy_match_v1)
        return fzf_fuzzy_match_v1_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    if (algorithm == fzf_fuzzy_match_v2)
        return fzf_fuzzy_match_v2_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    if (algorithm == fzf_fuzzy_match_v1_utf8)
        return fzf_fuzzy_match_v1_utf8_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    if (algorithm == fzf_fuzzy_match_v2_utf8)
        return fzf_fuzzy_match_v2_utf8_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    if (algorithm == fzf_exact_match_naive)
        return fzf_exact_match_naive_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    if (algorithm == fzf_exact_match_boundary)
        return fzf_exact_match_boundary_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    if (algorithm == fzf_exact_match_utf8)
        return fzf_exact_match_utf8_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    if (algorithm == fzf_exact_match_boundary_utf8)
        return fzf_exact_match_boundary_utf8_with_direction(sensitive, normalize, forward, input, query, positions, slab);
    return algorithm(sensitive, normalize, input, query, positions, slab);
}

void nvfzf_positions_free(NVFZFPositions *positions) {
    if (!positions) return;
    free(positions->offsets);
    *positions = (NVFZFPositions){0};
}

static int offset_order(const void *left, const void *right) {
    uint32_t a = *(const uint32_t *)left, b = *(const uint32_t *)right;
    return (a > b) - (a < b);
}

static NVFZFStatus positions_for_pattern(NVFZFEngine *engine, NVFZFCandidate candidate,
                                        fzf_pattern_t *pattern, NVFZFCancel *cancel,
                                        NVFZFPositions *positions) {
    NVFZFStatus status = NVFZF_OK;
    const char *text = candidate.bytes ? candidate.bytes : "";
    int score = fzf_get_score_bytes(text, candidate.length, pattern, engine->slab);
    if (fzf_allocation_failed()) { status = NVFZF_OUT_OF_MEMORY; goto finish; }
    if (cancelled(cancel)) { status = NVFZF_CANCELLED; goto finish; }
    if (score <= 0) goto finish;
    if (!pattern->has_positive_term) { positions->matched = true; goto finish; }
    size_t capacity = 0;
    fzf_string_t input = {.data = text, .size = candidate.length};
    bool ascii = is_ascii_utf8proc(text, candidate.length);
    for (size_t i = 0; i < pattern->size; i++) {
        fzf_term_set_t *set = pattern->ptr[i];
        for (size_t j = 0; j < set->size; j++) {
            if (cancelled(cancel)) { status = NVFZF_CANCELLED; goto finish; }
            fzf_term_t *term = &set->ptr[j];
            fzf_position_t term_offsets = {0};
            fzf_clear_allocation_failure();
            fzf_result_t match = term_positions(
                term, &input, ascii, pattern->forward,
                term->inv ? NULL : &term_offsets, engine->slab);
            if (fzf_allocation_failed()) {
                free(term_offsets.data); status = NVFZF_OUT_OF_MEMORY; goto finish;
            }
            if (cancelled(cancel)) {
                free(term_offsets.data); status = NVFZF_CANCELLED; goto finish;
            }
            if (term->inv || match.start < 0) { free(term_offsets.data); continue; }
            /* A fresh vector per term keeps the UTF8 v1 fallback from
               remapping another term's already-logical positions. */
            if (term_offsets.size > SIZE_MAX - positions->count) {
                free(term_offsets.data); status = NVFZF_OUT_OF_MEMORY; goto finish;
            }
            size_t needed = positions->count + term_offsets.size;
            if (needed > capacity) {
                if (needed > SIZE_MAX / sizeof(uint32_t)) {
                    free(term_offsets.data); status = NVFZF_OUT_OF_MEMORY; goto finish;
                }
                uint32_t *grown = realloc(positions->offsets, needed * sizeof *grown);
                if (!grown) {
                    free(term_offsets.data); status = NVFZF_OUT_OF_MEMORY; goto finish;
                }
                positions->offsets = grown;
                capacity = needed;
            }
            if (term_offsets.size)
                memcpy(positions->offsets + positions->count, term_offsets.data,
                       term_offsets.size * sizeof(uint32_t));
            positions->count = needed;
            free(term_offsets.data);
            break;
        }
    }
    if (positions->count > 1) {
        qsort(positions->offsets, positions->count, sizeof(uint32_t), offset_order);
        size_t unique = 1;
        for (size_t i = 1; i < positions->count; i++)
            if (positions->offsets[i] != positions->offsets[unique - 1])
                positions->offsets[unique++] = positions->offsets[i];
        positions->count = unique;
    }
    if (cancelled(cancel)) { status = NVFZF_CANCELLED; goto finish; }
    positions->matched = true;
finish:
    if (status != NVFZF_OK) nvfzf_positions_free(positions);
    fzf_free_pattern(pattern);
    return status;
}

NVFZFStatus nvfzf_positions(NVFZFEngine *engine, NVFZFCandidate candidate,
                          const char *query, size_t query_length,
                          NVFZFQueryMode mode, NVFZFCancel *cancel,
                          NVFZFPositions *positions) {
    if (!positions) return NVFZF_INVALID_INPUT;
    *positions = (NVFZFPositions){0};
    if (!engine || !valid_candidate(candidate)) return NVFZF_INVALID_INPUT;
    if (cancelled(cancel)) return NVFZF_CANCELLED;
    fzf_pattern_t *pattern = NULL;
    NVFZFStatus status = parse_query(query, query_length, mode, &pattern);
    return status == NVFZF_OK ? positions_for_pattern(engine, candidate, pattern, cancel, positions) : status;
}

NVFZFStatus nvfzf_positions_terms(NVFZFEngine *engine, NVFZFCandidate candidate,
                                const NVFZFTerm *terms, size_t term_count,
                                NVFZFCancel *cancel, NVFZFPositions *positions) {
    if (!positions) return NVFZF_INVALID_INPUT;
    *positions = (NVFZFPositions){0};
    if (!engine || !valid_candidate(candidate)) return NVFZF_INVALID_INPUT;
    if (cancelled(cancel)) return NVFZF_CANCELLED;
    fzf_pattern_t *pattern = NULL;
    NVFZFStatus status = build_terms(terms, term_count, cancel, &pattern);
    return status == NVFZF_OK ? positions_for_pattern(engine, candidate, pattern, cancel, positions) : status;
}

const char *nvfzf_status_message(NVFZFStatus status) {
    switch (status) {
        case NVFZF_OK: return "Search complete.";
        case NVFZF_CANCELLED: return "Search cancelled.";
        case NVFZF_INVALID_INPUT: return "Invalid input: queries must contain no NUL and be at most 65,536 UTF-8 bytes; candidate and collection size limits also apply.";
        case NVFZF_OUT_OF_MEMORY: return "Search could not allocate memory.";
    }
    return "Unknown search error.";
}

const char *nvfzf_upstream_revision(void) {
    return "4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d";
}
