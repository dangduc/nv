#import <Foundation/Foundation.h>
#import <libxml/HTMLparser.h>
#import <pthread.h>

static htmlDocPtr ObservedReadMemory(htmlParserCtxtPtr parser, const char *buffer, int size,
                                    const char *URL, const char *encoding, int options);
// Instrument only the parser call. Compile the production implementation unchanged.
#define htmlCtxtReadMemory ObservedReadMemory
#import "NVMarkupRenderer.m"
#undef htmlCtxtReadMemory

typedef struct {
    NSUInteger diagnostics;
    NSUInteger laterDiagnostics;
    BOOL sawLimit;
    BOOL lostLimit;
} ParseObservation;
static __thread ParseObservation *currentObservation;
static pthread_mutex_t liveLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableSet *liveParsers, *liveSAX, *liveStatuses;
static NSUInteger ownershipFailures, livePeak;

static void ObserveError(void *context, xmlErrorPtr error) {
    ParseObservation *observation = currentObservation;
    if (observation && error) {
        observation->diagnostics++;
        if (observation->sawLimit) observation->laterDiagnostics++;
        if (error->code == XML_ERR_NO_MEMORY || error->code == XML_ERR_INTERNAL_ERROR || error->code == XML_ERR_NAME_TOO_LONG)
            observation->sawLimit = YES;
    }
#ifdef NV_PROBE_LAST_ERROR_ONLY
    // Negative control: retain only the final diagnostic's classification.
    NVHTMLParseStatus *status = ((htmlParserCtxtPtr)context)->_private;
    status->limitExceeded = status->fatalError = NO;
#endif
    NVHTMLParseError(context, error);
    if (observation && observation->sawLimit && !((NVHTMLParseStatus *)((htmlParserCtxtPtr)context)->_private)->limitExceeded)
        observation->lostLimit = YES;
}

static htmlDocPtr ObservedReadMemory(htmlParserCtxtPtr parser, const char *buffer, int size,
                                    const char *URL, const char *encoding, int options) {
    NSValue *parserID = [NSValue valueWithPointer:parser];
    NSValue *SAXID = [NSValue valueWithPointer:parser->sax];
    NSValue *statusID = [NSValue valueWithPointer:parser->_private];
    pthread_mutex_lock(&liveLock);
    if ([liveParsers containsObject:parserID] || [liveSAX containsObject:SAXID] || [liveStatuses containsObject:statusID]) ownershipFailures++;
    [liveParsers addObject:parserID]; [liveSAX addObject:SAXID]; [liveStatuses addObject:statusID];
    livePeak = MAX(livePeak, [liveParsers count]);
    pthread_mutex_unlock(&liveLock);
    parser->sax->serror = ObserveError;
    // Keep small parses overlapping large ones to test independent status storage.
    usleep(1500);
    htmlDocPtr document = htmlCtxtReadMemory(parser, buffer, size, URL, encoding, options);
    pthread_mutex_lock(&liveLock);
    [liveParsers removeObject:parserID]; [liveSAX removeObject:SAXID]; [liveStatuses removeObject:statusID];
    pthread_mutex_unlock(&liveLock);
    return document;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    liveParsers = [NSMutableSet new]; liveSAX = [NSMutableSet new]; liveStatuses = [NSMutableSet new];
    NSString *largeBody = [@"x" stringByPaddingToLength:11 * 1024 * 1024 withString:@"x" startingAtIndex:0];
    NSString *limited = [NSString stringWithFormat:@"<p>START%@END</p><section>TAIL</section>", largeBody];
    NSString *boundedBody = [@"x" stringByPaddingToLength:9 * 1024 * 1024 withString:@"x" startingAtIndex:0];
    NSString *bounded = [NSString stringWithFormat:@"<p>START%@END</p><section>TAIL</section>", boundedBody];
    NSOperationQueue *queue = [NSOperationQueue new]; [queue setMaxConcurrentOperationCount:8];
    NSLock *resultLock = [NSLock new];
    __block NSUInteger failures = 0, validPass = 0, limitPass = 0, laterDiagnostics = 0;
    for (NSUInteger index = 0; index < 64; index++) {
        [queue addOperationWithBlock:^{
            NSAutoreleasePool *workerPool = [[NSAutoreleasePool alloc] init];
            ParseObservation observation = {0}; currentObservation = &observation;
            BOOL expectLimit = index % 8 == 0;
            NSString *source = expectLimit ? limited : (index % 8 == 1 ? bounded : @"<section><p>START &amp; café 😀<p>END</section><article>TAIL</article>");
            NSError *error = nil;
            NSString *rendered = NVInertDocument(source, @"Concurrent parse", &error);
            BOOL passed = expectLimit ? (!rendered && [error code] == NVMarkupLimitExceeded && observation.sawLimit && !observation.lostLimit) :
                (rendered && !error && [rendered containsString:@"START"] && [rendered containsString:@"END"] && [rendered containsString:@"TAIL"]);
            [resultLock lock];
            if (!passed) { failures++; fprintf(stderr, "FAIL request=%lu result=%d error=%ld lost=%d\n", (unsigned long)index, rendered != nil, (long)[error code], observation.lostLimit); }
            else if (expectLimit) limitPass++; else validPass++;
            laterDiagnostics += observation.laterDiagnostics;
            [resultLock unlock];
            currentObservation = NULL;
            [workerPool drain];
        }];
    }
    [queue waitUntilAllOperationsAreFinished];
    // This host stops parsing after its resource error. Test the callback's
    // documented accumulation contract with explicit diagnostic sequences too.
    NSUInteger accumulatorFailures = 0;
    const int codes[] = { XML_ERR_NO_MEMORY, XML_ERR_INTERNAL_ERROR, XML_ERR_NAME_TOO_LONG, XML_ERR_DOCUMENT_END };
    for (NSUInteger index = 0; index < sizeof(codes) / sizeof(codes[0]); index++) {
        htmlParserCtxt parser = {0};
        NVHTMLParseStatus status = { NO, NO }; parser._private = &status;
        ParseObservation observation = {0}; currentObservation = &observation;
        xmlError diagnostic = {0}; diagnostic.code = codes[index]; diagnostic.level = XML_ERR_FATAL;
        ObserveError(&parser, &diagnostic);
        diagnostic.code = XML_HTML_UNKNOWN_TAG; diagnostic.level = XML_ERR_ERROR;
        ObserveError(&parser, &diagnostic);
        if (!status.fatalError || (index < 3 && !status.limitExceeded)) accumulatorFailures++;
        currentObservation = NULL;
    }
    BOOL pass = !failures && !ownershipFailures && !accumulatorFailures && livePeak > 1;
    printf("%s: valid=%lu limit=%lu actual-later-diagnostics=%lu peak-independent-contexts=%lu ownership-failures=%lu result-failures=%lu accumulator-sequence-failures=%lu/4\n",
           pass ? "PASS" : "FAIL", (unsigned long)validPass, (unsigned long)limitPass, (unsigned long)laterDiagnostics,
           (unsigned long)livePeak, (unsigned long)ownershipFailures, (unsigned long)failures, (unsigned long)accumulatorFailures);
    [queue release]; [resultLock release]; [liveParsers release]; [liveSAX release]; [liveStatuses release];
    [pool drain];
    return pass ? 0 : 1;
}
