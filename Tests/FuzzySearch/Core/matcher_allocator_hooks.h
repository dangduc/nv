/* Test-only hooks for fzf.c and its inline UTF-8 map allocator. This domain is
   independent of bridge allocation hooks, so existing sweeps retain meaning. */
#ifndef NVFZF_MATCHER_TEST_ALLOCATOR_H
#define NVFZF_MATCHER_TEST_ALLOCATOR_H
#include <stdlib.h>
void *nvfzf_matcher_malloc(size_t size, const char *file, int line);
void *nvfzf_matcher_calloc(size_t count, size_t size, const char *file, int line);
void *nvfzf_matcher_realloc(void *pointer, size_t size, const char *file, int line);
#define malloc(size) nvfzf_matcher_malloc((size), __FILE__, __LINE__)
#define calloc(count, size) nvfzf_matcher_calloc((count), (size), __FILE__, __LINE__)
#define realloc(pointer, size) nvfzf_matcher_realloc((pointer), (size), __FILE__, __LINE__)
#endif
