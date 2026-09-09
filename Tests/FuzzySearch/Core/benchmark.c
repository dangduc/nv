/* Test-only inspection includes the bridge so two engines can vary only their
   I32 scratch capacity. The I16 limit, native scorer, and sorter stay fixed. */
#include "NVFZF.c"
#include <stdio.h>
#include <inttypes.h>
#include <time.h>

static double now_ms(void) {
    struct timespec stamp; clock_gettime(CLOCK_MONOTONIC, &stamp);
    return stamp.tv_sec * 1000.0 + stamp.tv_nsec / 1000000.0;
}
static uint64_t checksum(const NVFZFSearchResult *result) {
    uint64_t value = UINT64_C(1469598103934665603);
    for (size_t i = 0; i < result->count; i++) {
        const NVFZFMatch *m = &result->matches[i];
        value ^= m->candidate_index; value *= UINT64_C(1099511628211);
        value ^= m->public_score; value *= UINT64_C(1099511628211);
        value ^= m->rank_score; value *= UINT64_C(1099511628211);
        value ^= m->trimmed_length; value *= UINT64_C(1099511628211);
    }
    return value;
}
static void measure(NVFZFEngine *engine, const char *label, NVFZFCandidate *items, size_t count, const char *query,
                    NVFZFSearchResult *result) {
    NVFZFTerm term = {query, strlen(query), NVFZF_TERM_FUZZY};
    NVFZFJob *job = NULL; bool done = false;
    double start = now_ms();
    NVFZFStatus status = nvfzf_job_create_terms(items, count, &term, 1, NULL, &job);
    double ready = now_ms();
    if (status == NVFZF_OK) status = nvfzf_job_step(engine, job, SIZE_MAX, &done);
    double scored = now_ms();
    if (status == NVFZF_OK) status = nvfzf_job_finish(job, result);
    double finished = now_ms();
    if (status != NVFZF_OK || !done) { fprintf(stderr,"benchmark failed: %d\n",status); exit(1); }
    printf("query,%s,%s,prepare_ms,%.3f,score_ms,%.3f,sort_ms,%.3f,total_ms,%.3f,count,%zu,checksum,%" PRIu64 "\n",
           label,query,ready-start,scored-ready,finished-scored,finished-start,result->count,checksum(result));
    nvfzf_job_free(job);
}
int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    const size_t count = 10000, source_length = 5243;
    NVFZFCandidate *items = calloc(count, sizeof *items); if (!items) return 1;
    size_t corpus_bytes = 0;
    for (size_t i = 0; i < count; i++) {
        char header[256], seed[256];
        int header_length = snprintf(header,sizeof header,"Project %05zu %s\n%s\n",i,
            i%5==0 ? "Road map" : "Research", i%3==0 ? "planning meetings" : "archive finance");
        int seed_length = snprintf(seed,sizeof seed,"Record %zu: meeting notes, budget review, deployment status, source editing and weekly road map. %s ",
            i, i%7==0 ? "copper lantern" : "ordinary material");
        size_t length = (size_t)header_length + source_length;
        char *text = malloc(length); if (!text) return 1;
        memcpy(text,header,(size_t)header_length);
        for (size_t offset = (size_t)header_length; offset < length; offset++)
            text[offset] = seed[(offset-(size_t)header_length) % (size_t)seed_length];
        items[i] = (NVFZFCandidate){text,length}; corpus_bytes+=length;
    }
    NVFZFEngine *baseline = nvfzf_engine_create(), *expanded = nvfzf_engine_create();
    if (!baseline || !expanded) return 1;
    fzf_free_slab(expanded->slab);
    expanded->slab = fzf_make_slab((fzf_slab_config_t){100 * 1024,64 * 1024});
    if (!expanded->slab) return 1;
    printf("corpus,notes,%zu,bytes,%zu\n",count,corpus_bytes);
    double start=now_ms(); size_t ascii=0;
    for(size_t i=0;i<count;i++) ascii+=is_ascii_utf8proc(items[i].bytes,items[i].length);
    printf("classify,ascii,%zu,ms,%.3f\n",ascii,now_ms()-start);
    const char *queries[]={"road","copper","budget","deploy","finance","planning","source","weekly","archive","lantern","mtg","review"};
    for(size_t round=0;round<3;round++) {
        for(size_t q=0;q<sizeof queries/sizeof queries[0];q++) {
            NVFZFSearchResult a={0},b={0};
            if (round & 1) {
                measure(expanded,"expanded_i32",items,count,queries[q],&b);
                measure(baseline,"upstream_i32",items,count,queries[q],&a);
            } else {
                measure(baseline,"upstream_i32",items,count,queries[q],&a);
                measure(expanded,"expanded_i32",items,count,queries[q],&b);
            }
            if(a.count!=b.count) return 2;
            for(size_t i=0;i<a.count;i++) if(a.matches[i].candidate_index!=b.matches[i].candidate_index ||
                a.matches[i].public_score!=b.matches[i].public_score || a.matches[i].rank_score!=b.matches[i].rank_score ||
                a.matches[i].trimmed_length!=b.matches[i].trimmed_length) return 3;
            nvfzf_search_result_free(&a);nvfzf_search_result_free(&b);
        }
    }
    for(size_t i=0;i<count;i++)free((void *)items[i].bytes);
    free(items);nvfzf_engine_free(baseline);nvfzf_engine_free(expanded);
    puts("PASS: full result parity for every paired benchmark query.");
    return 0;
}
