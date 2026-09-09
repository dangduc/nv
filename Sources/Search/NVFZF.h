/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef NV_FZF_H
#define NV_FZF_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NVFZFEngine NVFZFEngine;
typedef struct NVFZFCancel NVFZFCancel;
typedef struct NVFZFJob NVFZFJob;
#define NVFZF_MAX_QUERY_BYTES ((size_t)65536)

typedef enum {
    NVFZF_OK = 0,
    NVFZF_CANCELLED = 1,
    NVFZF_INVALID_INPUT = 2,
    NVFZF_OUT_OF_MEMORY = 3
} NVFZFStatus;

/* Both modes use the native fzf extended query grammar. Case is ignored;
   Latin accent normalization is disabled; direction and scheme are default.
   The GUI supplies NFC copies if canonical normalization is desired. */
typedef enum {
    NVFZF_NATIVE_FUZZY = 0,
    NVFZF_NATIVE_EXACT = 1
} NVFZFQueryMode;

typedef struct {
    const char *bytes;
    size_t length;
} NVFZFCandidate;

typedef enum {
    NVFZF_TERM_FUZZY = 0,
    NVFZF_TERM_EXACT = 1
} NVFZFTermKind;

/* Already parsed by nv. Every nonempty term must match. Bytes are literal,
   including whitespace and native operator punctuation. No escaping occurs.
   Case is ignored; NFC normalization remains the caller's responsibility. */
typedef struct {
    const char *bytes;
    size_t length;
    NVFZFTermKind kind;
} NVFZFTerm;

typedef struct {
    size_t candidate_index;
    int32_t public_score;
    uint16_t rank_score;
    uint16_t trimmed_length;
} NVFZFMatch;

typedef struct {
    NVFZFMatch *matches;
    size_t count;
} NVFZFSearchResult;

typedef struct {
    uint32_t *offsets;
    size_t count;
    bool matched;
} NVFZFPositions;

/* Engine/slab ownership is serial: no overlapping calls on one engine.
   Calls are synchronous; run them on a worker. Input bytes remain owned by
   the caller and must remain unchanged until the call returns. */
NVFZFEngine *nvfzf_engine_create(void);
void nvfzf_engine_free(NVFZFEngine *engine);

/* Cancellation may be set from another thread. Never free a token while
   any engine call can still access it. Tokens cannot be reset/reused. */
NVFZFCancel *nvfzf_cancel_create(void);
void nvfzf_cancel_set(NVFZFCancel *cancel);
bool nvfzf_cancel_is_set(const NVFZFCancel *cancel);
void nvfzf_cancel_free(NVFZFCancel *cancel);

/* Complete matching set, in native default order, without an application
   rerank. Producer order is the candidate array order. Embedded NUL is
   accepted in candidates but rejected in the query by the native parser.
   Outputs are initialized on every call; failure publishes no partial list.
   Native indexes constrain each candidate to at most INT32_MAX bytes and
   a collection to at most UINT32_MAX entries. Queries are limited to
   NVFZF_MAX_QUERY_BYTES. Zero-byte queries bypass ranking and return
   public_score=1, rank_score=0, trimmed_length=0 in producer order. */
NVFZFStatus nvfzf_search(NVFZFEngine *engine,
                       const NVFZFCandidate *candidates, size_t count,
                       const char *query, size_t query_length,
                       NVFZFQueryMode mode, NVFZFCancel *cancel,
                       NVFZFSearchResult *result);
void nvfzf_search_result_free(NVFZFSearchResult *result);

/* Production entry point. Typed terms bypass native query syntax entirely.
   Terms must be nonempty and contain no NUL. Their combined byte length must
   not exceed NVFZF_MAX_QUERY_BYTES. Zero terms return producer order. */
NVFZFStatus nvfzf_search_terms(NVFZFEngine *engine,
                             const NVFZFCandidate *candidates, size_t count,
                             const NVFZFTerm *terms, size_t term_count,
                             NVFZFCancel *cancel, NVFZFSearchResult *result);

/* Resumable full-corpus scoring, followed by one native sort. The job copies
   terms but borrows candidate array/bytes and cancellation token until free.
   Step scores at most max_candidates (> 0); finished means scoring is done.
   A job may move between serial engines between steps, never concurrently.
   Finish requires completed scoring and transfers a complete result once.
   Cancellation/error is terminal and never exposes partial results.
   A single candidate's scorer remains uninterruptible; batches bound the
   candidate count, not elapsed time. Sorting checks cancellation internally. */
NVFZFStatus nvfzf_job_create_terms(const NVFZFCandidate *candidates, size_t count,
                                 const NVFZFTerm *terms, size_t term_count,
                                 NVFZFCancel *cancel, NVFZFJob **job);
NVFZFStatus nvfzf_job_step(NVFZFEngine *engine, NVFZFJob *job,
                         size_t max_candidates, bool *finished);
NVFZFStatus nvfzf_job_finish(NVFZFJob *job, NVFZFSearchResult *result);
void nvfzf_job_free(NVFZFJob *job);

/* Ascending, unique logical Unicode codepoint offsets for one candidate.
   These are not UTF-8 bytes, UTF-16 units, or grapheme indexes. Native
   inverse-only queries can match with no positive highlight positions.
   Candidate/query bounds and ownership are the same as nvfzf_search. */
NVFZFStatus nvfzf_positions(NVFZFEngine *engine, NVFZFCandidate candidate,
                          const char *query, size_t query_length,
                          NVFZFQueryMode mode, NVFZFCancel *cancel,
                          NVFZFPositions *positions);
NVFZFStatus nvfzf_positions_terms(NVFZFEngine *engine, NVFZFCandidate candidate,
                                const NVFZFTerm *terms, size_t term_count,
                                NVFZFCancel *cancel, NVFZFPositions *positions);
void nvfzf_positions_free(NVFZFPositions *positions);
const char *nvfzf_status_message(NVFZFStatus status);
const char *nvfzf_upstream_revision(void);

#ifdef __cplusplus
}
#endif
#endif
