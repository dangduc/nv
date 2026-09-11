// Only the separate allocation sample includes these process interpositions.
static void*CountMalloc(size_t bytes){void*p=malloc(bytes);if(GlyphDepth&&p){Mallocs++;MallocBytes+=bytes;}return p;}
static void CountFree(void*p){if(GlyphDepth&&p)Frees++;free(p);}
__attribute__((used,section("__DATA,__interpose")))static struct{const void*replacement;const void*original;}AllocationInterpose[]={
 {(const void*)CountMalloc,(const void*)malloc},{(const void*)CountFree,(const void*)free}};
