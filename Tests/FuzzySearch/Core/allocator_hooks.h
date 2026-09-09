/* This allocation domain is included only for the bridge. The scorer uses
   matcher_allocator_hooks.h and its separate failure counter. */
#ifndef NVFZF_TEST_ALLOCATOR_H
#define NVFZF_TEST_ALLOCATOR_H
#include <stdlib.h>
void *nvfzf_test_malloc(size_t size);
void *nvfzf_test_calloc(size_t count, size_t size);
void *nvfzf_test_realloc(void *pointer, size_t size);
#define malloc nvfzf_test_malloc
#define calloc nvfzf_test_calloc
#define realloc nvfzf_test_realloc
#endif
