/* SPDX-License-Identifier: MIT */
/* Unchanged helpers from fzf.c at 4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d. */
static char *str_tolower(const char *str, size_t size) {
  // Check if string is pure ASCII for fast path
  if (is_ascii_utf8proc(str, size)) {
    // Fast ASCII path
    if (size == SIZE_MAX) return NULL;
    char *lower_str = (char *)malloc(size + 1);
    if (!lower_str) return NULL;
    for (size_t i = 0; i < size; i++) {
      lower_str[i] = (char)tolower((uint8_t)str[i]);
    }
    lower_str[size] = '\0';
    return lower_str;
  }
  
  // UTF-8 path: need to handle multibyte characters
  // Allocate worst case (each char could expand to 4 bytes)
  if (size > (SIZE_MAX - 1) / 4) return NULL;
  char *lower_str = (char *)malloc(size * 4 + 1);
  if (!lower_str) return NULL;
  size_t out_pos = 0;
  size_t in_pos = 0;
  
  while (in_pos < size) {
    utf8proc_int32_t codepoint;
    utf8proc_ssize_t bytes = utf8proc_iterate(
      (const utf8proc_uint8_t*)(str + in_pos),
      size - in_pos, &codepoint);
    
    if (bytes <= 0) {
      // Invalid UTF-8, copy byte as-is
      lower_str[out_pos++] = str[in_pos++];
      continue;
    }
    
    // Apply case folding
    utf8proc_int32_t folded = utf8proc_case_fold(codepoint);
    
    // Encode back to UTF-8
    utf8proc_ssize_t out_bytes = utf8proc_encode_char(
      folded, (utf8proc_uint8_t*)(lower_str + out_pos));
    
    if (out_bytes > 0) {
      out_pos += out_bytes;
    } else {
      // Encoding failed, copy original
      memcpy(lower_str + out_pos, str + in_pos, bytes);
      out_pos += bytes;
    }
    
    in_pos += bytes;
  }
  
  lower_str[out_pos] = '\0';
  
  // Resize to actual size
  char *result = (char *)realloc(lower_str, out_pos + 1);
  return result ? result : lower_str;
}

static fzf_string_t *make_pattern_text(const char *data, size_t size,
                                       bool case_sensitive) {
  size_t count = utf8_strlen(data, size);
  size_t plan_pattern_size =
      is_ascii_utf8proc(data, size) && size >= 2 &&
              size <= FZF_SIMD_MAX_PATTERN
          ? size
          : 0;
  size_t plan_size = fzf_ascii_query_plan_size(plan_pattern_size);
#if FZF_HAVE_SIMD_PREFILTER
  if (plan_size == 0) return NULL;
#endif
  if (count > (SIZE_MAX - sizeof(fzf_string_t)) /
                  sizeof(utf8proc_int32_t))
    return NULL;
  size_t codepoint_bytes = count * sizeof(utf8proc_int32_t);
  size_t plan_offset = sizeof(fzf_string_t) + codepoint_bytes;
#if FZF_HAVE_SIMD_PREFILTER
  size_t alignment = FZF_SIMD_PLAN_ALIGNMENT;
  size_t remainder = plan_offset % alignment;
  if (remainder != 0) {
    size_t padding = alignment - remainder;
    if (padding > SIZE_MAX - plan_offset) return NULL;
    plan_offset += padding;
  }
#endif
  if (plan_size > SIZE_MAX - plan_offset) return NULL;
  fzf_string_t *text = malloc(plan_offset + plan_size);
  if (!text) return NULL;
  utf8proc_int32_t *codepoints = (utf8proc_int32_t *)(text + 1);
#if FZF_HAVE_SIMD_PREFILTER
  fzf_ascii_query_plan_t *plan =
      (fzf_ascii_query_plan_t *)((unsigned char *)text + plan_offset);
  fzf_ascii_query_plan_init(plan, data, plan_pattern_size, case_sensitive);
#endif
  *text = (fzf_string_t){
      .data = data,
      .size = size,
      .codepoints = codepoints,
      .codepoint_count = count,
      .codepoints_case_folded = !case_sensitive,
  };
  size_t byte_pos = 0;
  for (size_t i = 0; i < count; i++) {
    utf8proc_ssize_t width = utf8_iterate_lossy(
        (const utf8proc_uint8_t *)data + byte_pos,
        (utf8proc_ssize_t)(size - byte_pos), &codepoints[i]);
    if (!case_sensitive) codepoints[i] = utf8proc_case_fold(codepoints[i]);
    byte_pos += (size_t)width;
  }
  return text;
}
