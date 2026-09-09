/* Measure one uninterruptible native candidate separately from preparation. */
#include "NVFZF.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_ms(void) {
    struct timespec stamp; clock_gettime(CLOCK_MONOTONIC, &stamp);
    return stamp.tv_sec * 1000.0 + stamp.tv_nsec / 1000000.0;
}
typedef struct {
    NVFZFEngine *engine;
    NVFZFCancel *cancel;
    NVFZFCandidate candidate;
    NVFZFTerm term;
    _Atomic bool started, finished;
    NVFZFStatus status;
    NVFZFSearchResult result;
    double elapsed;
} Work;
static void *run(void *context) {
    Work *work = context;
    atomic_store(&work->started, true);
    double start = now_ms();
    work->status = nvfzf_search_terms(work->engine, &work->candidate, 1, &work->term, 1, work->cancel, &work->result);
    work->elapsed = now_ms() - start;
    atomic_store(&work->finished, true);
    return NULL;
}
int main(void) {
    setvbuf(stdout,NULL,_IOLBF,0);
    const size_t lengths[]={1024*1024,8*1024*1024};
    for(size_t n=0;n<2;n++) for(size_t kind=0;kind<2;kind++) {
        size_t length=lengths[n]; char *text=malloc(length); if(!text)return 1;
        if(kind) for(size_t i=0;i<length;i+=2) memcpy(text+i,"é",2);
        else {memset(text,'x',length);text[0]='a';text[length/2]='b';text[length-1]='c';}
        NVFZFEngine *engine=nvfzf_engine_create();if(!engine)return 1;
        NVFZFTerm term=kind?(NVFZFTerm){"ééé",6,NVFZF_TERM_FUZZY}:(NVFZFTerm){"abc",3,NVFZF_TERM_FUZZY};
        NVFZFCandidate candidate={text,length};
        NVFZFSearchResult result={0};double before=now_ms();
        NVFZFStatus status=nvfzf_search_terms(engine,&candidate,1,&term,1,NULL,&result);
        double full=now_ms()-before;
        if(status!=NVFZF_OK || result.count!=1)return 2;
        nvfzf_search_result_free(&result);
        printf("full,%s,bytes,%zu,ms,%.3f\n",kind?"dense_unicode":"ascii_long_gap",length,full);
        for(size_t round=0;round<3;round++) {
            NVFZFCancel *cancel=nvfzf_cancel_create();if(!cancel)return 1;
            Work work={.engine=engine,.candidate=candidate,.term=term,.cancel=cancel};
            pthread_t worker;if(pthread_create(&worker,NULL,run,&work))return 1;
            struct timespec poll={.tv_nsec=100000},delay={.tv_nsec=2000000};
            while(!atomic_load(&work.started))nanosleep(&poll,NULL);
            nanosleep(&delay,NULL);
            bool completed_before_cancel=atomic_load(&work.finished);
            double cancelled=now_ms();nvfzf_cancel_set(cancel);
            if(pthread_join(worker,NULL))return 1;
            double release=now_ms()-cancelled;
            if(!completed_before_cancel && (work.status!=NVFZF_CANCELLED || work.result.count || work.result.matches))return 3;
            printf("cancel,%s,bytes,%zu,release_ms,%.3f,operation_ms,%.3f,completed_before_cancel,%d\n",
                kind?"dense_unicode":"ascii_long_gap",length,release,work.elapsed,completed_before_cancel);
            nvfzf_search_result_free(&work.result);nvfzf_cancel_free(cancel);
        }
        nvfzf_engine_free(engine);free(text);
    }
    puts("PASS: cancellation never publishes a partial result.");return 0;
}
