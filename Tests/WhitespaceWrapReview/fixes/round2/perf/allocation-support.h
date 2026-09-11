// Diagnostic interposition only, loaded into disposable copied apps.
static __thread NSUInteger ReviewGlyphDepth;
static NSUInteger ReviewMallocCalls,ReviewFreeCalls;
static uint64_t ReviewMallocBytes;
static void *ReviewMalloc(size_t bytes) {
    void *pointer=malloc(bytes);
    if(ReviewGlyphDepth && pointer) { ReviewMallocCalls++; ReviewMallocBytes+=bytes; }
    return pointer;
}
static void ReviewFree(void *pointer) {
    if(ReviewGlyphDepth && pointer) ReviewFreeCalls++;
    free(pointer);
}
__attribute__((used)) static struct { const void *replacement; const void *original; }
ReviewAllocationInterpose[] __attribute__((section("__DATA,__interpose"))) = {
    {(const void *)ReviewMalloc,(const void *)malloc},
    {(const void *)ReviewFree,(const void *)free}
};
