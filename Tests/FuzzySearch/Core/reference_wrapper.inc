/* SPDX-License-Identifier: GPL-3.0-or-later */
/* This driver calls the native scorer and complete synchronous native sorter
   extracted above. Only candidate transport replaces Emacs-owned values. */
int reference_search(const NVFZFCandidate *input, size_t count, const char *query,
                     NVFZFQueryMode mode, NVFZFSearchResult *result) {
  *result = (NVFZFSearchResult){0};
  char *copy = strdup(query);
  fzf_clear_allocation_failure();
  fzf_pattern_t *pattern = fzf_parse_pattern_with_direction(
      CaseIgnore, false, copy, mode == NVFZF_NATIVE_FUZZY, true);
  free(copy);
  fzf_slab_t *slab = fzf_make_default_slab();
  if (!pattern || !slab || fzf_allocation_failed()) abort();
  struct Candidate *xs = calloc(count ? count : 1, sizeof(*xs));
  if (!xs) abort();
  size_t size = 0;
  bool reuse = fzf_rank_can_reuse_public_score(pattern, FZF_SCORE_SCHEME_DEFAULT);
  for (size_t i = 0; i < count; i++) {
    FzfRankKeys rank = {0};
    int score = 1;
    /* The native module preserves the untouched collection for an empty
       query. It has no ranking diagnostics for this path. */
    if (query[0])
      score = fzf_score_and_rank(input[i].bytes, input[i].length,
          is_ascii_utf8proc(input[i].bytes, input[i].length), pattern, slab,
          FZF_SCORE_SCHEME_DEFAULT, reuse, &rank);
    if (fzf_allocation_failed()) abort();
    if (score > 0) xs[size++] = (struct Candidate){
      .s = { input[i].bytes, input[i].length }, .score = score, .rank = rank, .idx = i
    };
  }
  if (pattern->has_positive_term)
    counting_sort_candidates(xs, size, FZF_SCORE_SCHEME_DEFAULT);
  result->matches = calloc(size ? size : 1, sizeof(*result->matches));
  if (!result->matches) abort();
  result->count = size;
  for (size_t i = 0; i < size; i++) result->matches[i] = (NVFZFMatch){
    xs[i].idx, xs[i].score, xs[i].rank.score, xs[i].rank.first
  };
  free(xs);
  fzf_free_pattern(pattern);
  fzf_free_slab(slab);
  return 0;
}

/* The native rank has a 16-bit saturation boundary independent of the
   matcher's int16 scratch. Exercise that boundary with synthetic raw scores. */
int reference_rank_boundary_check(void) {
  const int64_t raw[] = { INT64_MIN, -1, 0, 1, 65534, 65535, 65536, INT64_MAX };
  const uint16_t expected[] = { 0, 0, 0, 1, 65534, 65535, 65535, 65535 };
  for (size_t i = 0; i < sizeof(raw) / sizeof(raw[0]); i++)
    if (fzf_rank_score(raw[i]) != expected[i]) return 0;
  return fzf_rank_u16(65534) == 65534 && fzf_rank_u16(65535) == 65535 &&
         fzf_rank_u16(SIZE_MAX) == 65535;
}
