/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Unchanged upstream scoring and sorting, including independent synchronous path. */
typedef struct {
  uint16_t score;
  uint16_t first;
  uint16_t second;
} FzfRankKeys;

static bool fzf_rank_is_space(utf8proc_int32_t codepoint) {
  return (codepoint >= 0x09 && codepoint <= 0x0d) ||
         codepoint == 0x20 || codepoint == 0x85 || codepoint == 0xa0 ||
         codepoint == 0x1680 ||
         (codepoint >= 0x2000 && codepoint <= 0x200a) ||
         codepoint == 0x2028 || codepoint == 0x2029 ||
         codepoint == 0x202f || codepoint == 0x205f ||
         codepoint == 0x3000;
}

static uint16_t fzf_rank_u16(size_t value) {
  return value > UINT16_MAX ? UINT16_MAX : (uint16_t)value;
}

static uint16_t fzf_rank_score(int64_t score) {
  if (score <= 0) return 0;
  return score > UINT16_MAX ? UINT16_MAX : (uint16_t)score;
}

static uint64_t fzf_rank_sort_key(FzfRankKeys rank) {
  return ((uint64_t)(UINT16_MAX - rank.score) << 32) |
         ((uint64_t)rank.first << 16) | (uint64_t)rank.second;
}

/* Each scheme uses an upper portion of the packed rank key.  LSD sorting can
   skip the lower bytes that are constant for the scheme: history has only
   score, default adds one secondary key, and path uses all three keys. */
static unsigned fzf_rank_radix_first_pass(fzf_score_scheme_t scheme) {
  if (scheme == FZF_SCORE_SCHEME_HISTORY) return 4;
  if (scheme == FZF_SCORE_SCHEME_DEFAULT) return 2;
  return 0;
}

/* Build the non-score sort keys used by pinned fzf.  Default ranks by the
   Unicode-trimmed character count.  Path ranks by the distance from the last
   slash or backslash, then by that count.  History has no extra key. */
static FzfRankKeys fzf_rank_keys_preclassified(
    const char *text, size_t text_len, bool input_is_ascii,
    const fzf_score_bounds_t *bounds, fzf_score_scheme_t scheme) {
  FzfRankKeys keys = {0};
  keys.score = fzf_rank_score(bounds ? bounds->raw_score : 0);
  if (scheme == FZF_SCORE_SCHEME_HISTORY) return keys;

  /* For ASCII, rune indexes are byte indexes and fzf's Unicode trim length
     is the byte span after removing ASCII whitespace at the two edges. */
  if (input_is_ascii) {
    size_t first = 0, end = text_len;
    while (first < end &&
           fzf_rank_is_space((unsigned char)text[first]))
      first++;
    while (end > first &&
           fzf_rank_is_space((unsigned char)text[end - 1]))
      end--;
    size_t trim_length = end - first;
    if (scheme == FZF_SCORE_SCHEME_DEFAULT) {
      keys.first = fzf_rank_u16(trim_length);
      return keys;
    }

    ptrdiff_t last_delimiter = -1;
    for (size_t i = text_len; i > 0; i--) {
      if (text[i - 1] == '/' || text[i - 1] == '\\') {
        last_delimiter = (ptrdiff_t)(i - 1);
        break;
      }
    }
    keys.first = UINT16_MAX;
    if (bounds && bounds->valid && bounds->min_begin >= 0 &&
        last_delimiter <= bounds->min_begin) {
      size_t distance = (size_t)((ptrdiff_t)bounds->min_begin -
                                 last_delimiter);
      keys.first = fzf_rank_u16(distance);
    }
    keys.second = fzf_rank_u16(trim_length);
    return keys;
  }

  size_t offset = 0, rune_index = 0;
  size_t first_nonspace = SIZE_MAX, last_nonspace = 0;
  ptrdiff_t last_delimiter = -1;
  while (offset < text_len) {
    utf8proc_int32_t codepoint = 0;
    utf8proc_ssize_t width = utf8proc_iterate(
        (const utf8proc_uint8_t *)text + offset,
        (utf8proc_ssize_t)(text_len - offset), &codepoint);
    if (width <= 0) {
      codepoint = (unsigned char)text[offset];
      width = 1;
    }
    if (!fzf_rank_is_space(codepoint)) {
      if (first_nonspace == SIZE_MAX) first_nonspace = rune_index;
      last_nonspace = rune_index;
    }
    if (codepoint == '/' || codepoint == '\\')
      last_delimiter = (ptrdiff_t)rune_index;
    offset += (size_t)width;
    rune_index++;
  }

  size_t trim_length = first_nonspace == SIZE_MAX
                           ? 0 : last_nonspace - first_nonspace + 1;
  if (scheme == FZF_SCORE_SCHEME_DEFAULT) {
    keys.first = fzf_rank_u16(trim_length);
  } else if (scheme == FZF_SCORE_SCHEME_PATH) {
    keys.first = UINT16_MAX;
    if (bounds && bounds->valid && bounds->min_begin >= 0 &&
        last_delimiter <= bounds->min_begin) {
      size_t distance = (size_t)((ptrdiff_t)bounds->min_begin -
                                 last_delimiter);
      keys.first = fzf_rank_u16(distance);
    }
    keys.second = fzf_rank_u16(trim_length);
  }
  return keys;
}

/* A single positive term has the same public and raw scores unless the
   public scorer clamps a non-positive raw score to the match sentinel 1.
   Path ranking always needs match bounds. */
static bool fzf_rank_can_reuse_public_score(
    const fzf_pattern_t *pattern, fzf_score_scheme_t scheme) {
  return scheme != FZF_SCORE_SCHEME_PATH && pattern &&
      pattern->size == 1 && pattern->ptr[0]->size == 1 &&
      !pattern->ptr[0]->ptr[0].inv;
}

static int fzf_score_and_rank(
    const char *text, size_t text_len, bool input_is_ascii,
    fzf_pattern_t *pattern, fzf_slab_t *slab,
    fzf_score_scheme_t scheme, bool can_reuse_public_score,
    FzfRankKeys *rank) {
  fzf_score_bounds_t bounds = {0};
  int score;
  if (can_reuse_public_score) {
    score = fzf_get_score_bytes_preclassified(
        text, text_len, input_is_ascii, pattern, slab);
    if (score == 1) {
      /* One is ambiguous: it can be a real raw score or the clamped value
         of a valid non-positive v1 match.  Re-score only this rare case. */
      score = fzf_get_score_with_bounds_bytes_preclassified(
          text, text_len, input_is_ascii, pattern, slab, &bounds);
    } else {
      bounds.raw_score = score;
    }
  } else {
    score = fzf_get_score_with_bounds_bytes_preclassified(
        text, text_len, input_is_ascii, pattern, slab, &bounds);
  }
  if (score > 0 && rank)
    *rank = fzf_rank_keys_preclassified(
        text, text_len, input_is_ascii, &bounds, scheme);
  return score;
}

struct Candidate {
  emacs_value value;
  struct Str s;
  int score;
  FzfRankKeys rank;
  size_t idx;
};

static int candidate_order(const struct Candidate *left,
                           const struct Candidate *right) {
  uint16_t left_score = left->rank.score;
  uint16_t right_score = right->rank.score;
  if (left_score != right_score) return left_score > right_score ? -1 : 1;
  if (left->rank.first != right->rank.first)
    return left->rank.first < right->rank.first ? -1 : 1;
  if (left->rank.second != right->rank.second)
    return left->rank.second < right->rank.second ? -1 : 1;
  if (left->idx != right->idx) return left->idx < right->idx ? -1 : 1;
  return 0;
}

static int cmp_candidate(const void *a, const void *b) {
  return candidate_order(a, b);
}

static void insertion_sort_candidates(struct Candidate *xs, size_t n) {
  for (size_t i = 1; i < n; i++) {
    struct Candidate candidate = xs[i];
    size_t j = i;
    while (j > 0 && candidate_order(&xs[j - 1], &candidate) > 0) {
      xs[j] = xs[j - 1];
      j--;
    }
    xs[j] = candidate;
  }
}

/* Stable radix sort of xs[0..n-1] by the packed fzf rank key.  The input is
   in producer order, so an exact key tie already has the final index order.
   Allocation failure uses the same total comparator through qsort. */
static void counting_sort_candidates(struct Candidate *xs, size_t n,
                                     fzf_score_scheme_t scheme) {
  if (n <= 1) return;
  /* Avoid the radix scratch allocation for tiny inputs. */
  if (n < 64) { insertion_sort_candidates(xs, n); return; }
  unsigned first_pass = fzf_rank_radix_first_pass(scheme);
  uint64_t first_key = fzf_rank_sort_key(xs[0].rank);
  uint64_t varying_bits = 0;
  for (size_t i = 1; i < n; i++)
    varying_bits |= fzf_rank_sort_key(xs[i].rank) ^ first_key;
  varying_bits &= UINT64_MAX << (first_pass * 8);
  if (varying_bits == 0) return;

  struct Candidate *out = malloc(n * sizeof *out);
  if (!out) { qsort(xs, n, sizeof *xs, cmp_candidate); return; }

  unsigned active_passes[6];
  size_t active_count = 0;
  size_t counts[6][256];
  for (unsigned pass = first_pass; pass < 6; pass++) {
    if ((varying_bits & (UINT64_C(0xff) << (pass * 8))) != 0) {
      active_passes[active_count] = pass;
      memset(counts[active_count], 0, sizeof counts[active_count]);
      active_count++;
    }
  }
  if (active_count == 2) {
    unsigned first_shift = active_passes[0] * 8;
    unsigned second_shift = active_passes[1] * 8;
    for (size_t i = 0; i < n; i++) {
      uint64_t key = fzf_rank_sort_key(xs[i].rank);
      counts[0][(key >> first_shift) & 0xff]++;
      counts[1][(key >> second_shift) & 0xff]++;
    }
  } else {
    for (size_t i = 0; i < n; i++) {
      uint64_t key = fzf_rank_sort_key(xs[i].rank);
      for (size_t active = 0; active < active_count; active++) {
        unsigned shift = active_passes[active] * 8;
        counts[active][(key >> shift) & 0xff]++;
      }
    }
  }

  struct Candidate *src = xs, *dst = out;
  for (size_t active = 0; active < active_count; active++) {
    unsigned pass = active_passes[active];
    unsigned shift = pass * 8;
    size_t offset[256];
    offset[0] = 0;
    for (size_t i = 1; i < 256; i++)
      offset[i] = offset[i - 1] + counts[active][i - 1];
    for (size_t i = 0; i < n; i++) {
      size_t byte = (fzf_rank_sort_key(src[i].rank) >> shift) & 0xff;
      dst[offset[byte]++] = src[i];
    }
    struct Candidate *swap = src;
    src = dst;
    dst = swap;
  }
  if (src != xs) memcpy(xs, src, n * sizeof *xs);
  free(out);
}
