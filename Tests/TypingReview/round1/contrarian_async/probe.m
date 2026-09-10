#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "NVSourceAnalysis.h"
#import "AttributedPlainText.h"

static NSUInteger assertions;
static void Check(BOOL value, NSString *description) {
    assertions++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", description.UTF8String); exit(1); }
}
static BOOL Await(BOOL (^ready)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!ready() && limit.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return ready();
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];
}

static atomic_bool gateNext, gateEntered;
static atomic_uint decorations;
static dispatch_semaphore_t gate;
static IMP realDecoration;
static void GateDecoration(id receiver, SEL selector, NSRange range, NSString *syntax) {
    atomic_fetch_add(&decorations, 1);
    if (atomic_exchange(&gateNext, false)) {
        atomic_store(&gateEntered, true);
        if (dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC))) abort();
    }
    ((void (*)(id, SEL, NSRange, NSString *))realDecoration)(receiver, selector, range, syntax);
}

@interface Client : NSObject <NVSourceAnalysisDelegate> {
@public
    NSUInteger generation, captures, publications, publishedGeneration;
    BOOL available, requestInsidePublication;
    BOOL *destroyed;
}
@end
@implementation Client
- (id)init {
    if ((self = [super init])) { generation = 1; available = YES; }
    return self;
}
- (NSDictionary *)snapshotForSourceAnalysis:(NVSourceAnalysis *)analysis {
    Check([NSThread isMainThread], @"capture uses main thread");
    captures++;
    if (!available) return nil;
    return @{@"source": [NSString stringWithFormat:@"generation %lu https://example.com", (unsigned long)generation],
             @"syntax": @"plain", @"generation": @(generation), @"links": @YES, @"words": @YES};
}
- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:(NSDictionary *)result {
    Check([NSThread isMainThread], @"publication uses main thread");
    publications++;
    publishedGeneration = [result[@"generation"] unsignedIntegerValue];
    Check(publishedGeneration == generation, @"only the latest requested generation publishes");
    Check([result[@"linkRuns"] count] == 1 && [result[@"wordCount"] unsignedIntegerValue] > 0,
          @"surviving work performs real link and word analysis");
    if (requestInsidePublication) {
        requestInsidePublication = NO;
        generation++;
        [analysis invalidate];
        [analysis request];
    }
}
- (void)dealloc { if (destroyed) *destroyed = [NSThread isMainThread]; [super dealloc]; }
@end

static void CheckSeveralSessions(void) {
    Client *clientSlots[6]; Client **clients = clientSlots; NVSourceAnalysis *analyses[6];
    for (NSUInteger i = 0; i < 6; i++) {
        clients[i] = [[Client alloc] init];
        analyses[i] = [[NVSourceAnalysis alloc] initWithDelegate:clients[i]];
    }
    atomic_store(&gateNext, true);
    [analyses[0] request];
    Check(Await(^BOOL { return atomic_load(&gateEntered); }), @"first session enters controlled worker barrier");
    for (NSUInteger i = 1; i < 6; i++) [analyses[i] request];
    Check(Await(^BOOL { return clients[5]->captures == 1; }), @"other sessions capture while their jobs wait in the shared queue");
    for (NSUInteger edit = 0; edit < 10000; edit++) {
        for (NSUInteger i = 0; i < 4; i++) {
            clients[i]->generation++;
            [analyses[i] invalidate];
            [analyses[i] request];
        }
    }
    for (NSUInteger i = 0; i < 6; i++)
        Check(clients[i]->captures == 1 && clients[i]->publications == 0,
              @"40,000 edit requests do not create additional snapshots behind the barrier");
    BOOL destroyedOnMain = NO;
    clients[5]->destroyed = &destroyedOnMain;
    [analyses[5] close]; [analyses[5] release]; [clients[5] release];
    Check(destroyedOnMain, @"queued work does not prolong the closed session's delegate lifetime");
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL {
        for (NSUInteger i = 0; i < 5; i++) if (clients[i]->publications != 1) return NO;
        return YES;
    }), @"all five surviving sessions eventually publish");
    for (NSUInteger i = 0; i < 4; i++) {
        Check(clients[i]->captures == 2 && clients[i]->publishedGeneration == 10001,
              @"each edited session captures only its original and latest source");
    }
    Check(clients[4]->captures == 1 && clients[4]->publishedGeneration == 1,
          @"unmodified session is not canceled by another session's requests");
    Pump();
    Check(atomic_load(&decorations) == 6,
          @"canceled queued snapshots skip link analysis; one in-flight job remains indivisible");
    for (NSUInteger i = 0; i < 5; i++) {
        Check(clients[i]->publications == 1, @"no duplicate publications remain after the burst");
        [analyses[i] close]; [analyses[i] release]; [clients[i] release];
    }
}

static void CheckDemandTransitions(void) {
    Client *client = [[Client alloc] init];
    NVSourceAnalysis *analysis = [[NVSourceAnalysis alloc] initWithDelegate:client];
    client->available = NO;
    [analysis request];
    Check(Await(^BOOL { return client->captures == 1; }), @"unavailable demand reaches snapshot delegate");
    Pump();
    Check(client->publications == 0 && client->captures == 1, @"nil snapshots do not spin or publish");
    client->available = YES;
    client->requestInsidePublication = YES;
    [analysis request];
    Check(Await(^BOOL { return client->publications == 2; }), @"demand added during publication completes");
    Check(client->captures == 3 && client->publishedGeneration == 2,
          @"reentrant request receives exactly one new capture");
    [analysis close];
    [analysis invalidate]; [analysis request];
    Pump();
    Check(client->captures == 3 && client->publications == 2, @"closed analyzer ignores further demand");
    [analysis release]; [client release];
}

int main(void) { @autoreleasepool {
    gate = dispatch_semaphore_create(0);
    Method method = class_getInstanceMethod([NSMutableAttributedString class], @selector(addLinkAttributesForRange:syntaxIdentifier:));
    realDecoration = method_setImplementation(method, (IMP)GateDecoration);
    CheckSeveralSessions(); CheckDemandTransitions();
    method_setImplementation(method, realDecoration);
    dispatch_release(gate);
    printf("PASS: %lu assertions; 6 sessions; 40,000 coalesced edit requests; 1 queued teardown; reentrant demand\n", (unsigned long)assertions);
    printf("LIMIT: this probe does not bound the runtime of an already-running link detector or word counter.\n");
} return 0; }
