#import <Cocoa/Cocoa.h>
#import "NVSearchService.h"
#import <stdatomic.h>
static NSUInteger checks;
static void Check(BOOL pass,const char *label){++checks;if(!pass){fprintf(stderr,"FAIL: %s\n",label);exit(1);}}
static uint64_t Tick(void){return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);}
static double MS(uint64_t start){return (double)(Tick()-start)/1e6;}
static void Wait(BOOL(^ready)(void)){
    uint64_t started=Tick();
    while(!ready()) {if(MS(started)>10000) Check(NO,"10-second fixture deadline");[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];}
    Check(YES,"bounded callback or worker gate observed");
}
@class NVSearchPositionWork;
@interface NVSearchService(ReviewObservation)
- (void)runPositionBatch:(NVSearchPositionWork *)work;
@end
@interface ObservedService:NVSearchService{
@public dispatch_semaphore_t batchDone,continueBatch;_Atomic BOOL pauseBatches;_Atomic NSUInteger batches;_Atomic BOOL batchOnMain;_Atomic uint64_t maxBatchNS,maxResumedBatchNS;
}
- (void)drain:(void(^)(void))callback;
@end
@implementation ObservedService
- (id)init{if((self=[super init])){batchDone=dispatch_semaphore_create(0);continueBatch=dispatch_semaphore_create(0);}return self;}
- (void)runPositionBatch:(NVSearchPositionWork *)work{
    if([NSThread isMainThread])atomic_store(&batchOnMain,YES);
    uint64_t start=Tick();[super runPositionBatch:work];uint64_t duration=Tick()-start;
    NSUInteger ordinal=atomic_fetch_add(&batches,1);uint64_t previous=atomic_load(&maxBatchNS);
    while(duration>previous&&!atomic_compare_exchange_weak(&maxBatchNS,&previous,duration)){}
    if(ordinal){previous=atomic_load(&maxResumedBatchNS);while(duration>previous&&!atomic_compare_exchange_weak(&maxResumedBatchNS,&previous,duration)){}}
    // Test-only gates run AFTER an unchanged production batch. They control
    // arrival order, not the mapper's cursor, ranges, limits, or work queue.
    if(atomic_load(&pauseBatches)){
        dispatch_semaphore_signal(batchDone);
        if(dispatch_semaphore_wait(continueBatch,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))) {fprintf(stderr,"FAIL: fixture worker gate timed out\n");exit(1);}
    }
}
- (void)drain:(void(^)(void))callback{dispatch_async(_worker,^{dispatch_async(dispatch_get_main_queue(),callback);});}
- (void)dealloc{dispatch_release(batchDone);dispatch_release(continueBatch);[super dealloc];}
@end
@interface Prefs:NSObject @end
@implementation Prefs
- (NSDictionary *)searchTermHighlightAttributes{return @{NSBackgroundColorAttributeName:[NSColor yellowColor]};}
@end
@interface Editor:NSObject{@public NSTextStorage *storage;NSLayoutManager *layout;Prefs *prefsController;}
- (NSString *)string;
- (NSLayoutManager *)layoutManager;
- (void)removeHighlightedTerms;
- (void)setSearchHighlightRanges:(NSArray *)ranges;
@end
@implementation Editor
- (id)init{if((self=[super init])){storage=[[NSTextStorage alloc]init];layout=[[NSLayoutManager alloc]init];[storage addLayoutManager:layout];prefsController=[[Prefs alloc]init];}return self;}
- (NSString *)string{return [storage string];}
- (NSLayoutManager *)layoutManager{return layout;}
#include "editor.inc"
- (void)dealloc{[storage removeLayoutManager:layout];[storage release];[layout release];[prefsController release];[super dealloc];}
@end
static NVSearchResult *Search(ObservedService *service,id owner,NSString *query){
    __block BOOL done=NO;__block NVSearchResult *answer=nil;
    [service requestForOwner:owner query:query completion:^(NVSearchResult *result,NSError *error){Check(!error&&result!=nil,"production search completes");answer=[result retain];done=YES;}];
    Wait(^BOOL{return done;});return [answer autorelease];
}
static NSString *MakeSource(NSArray **expectedOut,NSString **queryOut){
    NSString *unit=@"e\u0301 🧑🏽‍💻 각 🇻🇳\r\n";
    NSMutableString *body=[NSMutableString string];for(NSUInteger i=0;i<9000;i++)[body appendString:unit];
    NSString *first=@"Ωe\u0301🐙한",*second=@"Жn\u0303🦀";
    NSRange a=NSMakeRange([body length],[first length]);[body appendString:first];[body appendString:@" / gap / "];
    NSRange b=NSMakeRange([body length],[second length]);[body appendString:second];
    *expectedOut=@[[NSValue valueWithRange:a],[NSValue valueWithRange:b]];
    *queryOut=[NSString stringWithFormat:@"\"%@\" \"%@\"",[first precomposedStringWithCanonicalMapping],[second precomposedStringWithCanonicalMapping]];
    return [[body copy]autorelease];
}
static NVSearchNoteSnapshot *Snapshot(NSString *source){CFUUIDRef id=CFUUIDCreate(NULL);CFUUIDBytes bytes=CFUUIDGetUUIDBytes(id);CFRelease(id);return [[[NVSearchNoteSnapshot alloc]initWithNoteUUID:[NSData dataWithBytes:&bytes length:16] title:@"fixture" tags:@"" source:source revision:1]autorelease];}
static void CheckRanges(NVSearchPositions *positions,NSArray *expected,NSString *source){
    Check([[positions sourceRanges]isEqualToArray:expected],"complete two-range Unicode result preserves exact original UTF-16 order");
    Check(![[positions titleRanges]count]&&![[positions tagsRanges]count],"source matches do not spill into title or tags");
    for(NSValue *value in expected){NSRange range=[value rangeValue];Check(NSEqualRanges([source rangeOfComposedCharacterSequencesForRange:range],range),"returned spans preserve whole original composed sequences");}
}
static void Run(BOOL gated,NSUInteger trial){
    @autoreleasepool{
        NSArray *expected=nil;NSString *query=nil;NSString *source=MakeSource(&expected,&query);
        NVSearchNoteSnapshot *snapshot=Snapshot(source);ObservedService *service=[[[ObservedService alloc]init]autorelease];[service synchronizeWithSnapshots:@[snapshot]];
        id primary=[[[NSObject alloc]init]autorelease],peer=[[[NSObject alloc]init]autorelease];
        NVSearchResult *initial=Search(service,primary,query);Check([[initial fuzzyNoteUUIDs]isEqualToArray:@[[snapshot noteUUID]]],"late Unicode note remains complete native fuzzy result");
        Editor *editor=[[[Editor alloc]init]autorelease];[editor->storage replaceCharactersInRange:NSMakeRange(0,0)withString:source];
        NSMutableArray *events=[NSMutableArray array];__block BOOL positioned=NO;__block double delivery=0,apply=0,peerDelivery=0;__block NSUInteger peerReplies=0;
        atomic_store(&service->pauseBatches,gated);uint64_t start=Tick();
        [service requestPositionsForNoteUUID:[snapshot noteUUID]requestID:[initial requestID]owner:primary completion:^(NVSearchPositions *positions,NSError *error){
            Check([NSThread isMainThread],"position callback arrives on main");Check(!error&&positions!=nil,"Unicode positions complete without error");
            if(gated)Check(peerReplies==4,"mapping publishes after four separately queued peer completions");
            CheckRanges(positions,expected,source);
            uint64_t applyStart=Tick();[editor setSearchHighlightRanges:[positions sourceRanges]];apply=MS(applyStart);
            delivery=MS(start);[events addObject:@"positions"];positioned=YES;
        }];
        double submit=MS(start);
        if(gated){
            for(NSUInteger arrival=0;arrival<4;arrival++){
                Wait(^BOOL{return dispatch_semaphore_wait(service->batchDone,DISPATCH_TIME_NOW)==0;});
                NSString *next=[NSString stringWithFormat:@"q%lu",arrival];__block BOOL arrived=NO;
                NSUInteger before=peerReplies;
                [service requestForOwner:peer query:next completion:^(NVSearchResult *result,NSError *error){Check(!error&&result!=nil&&![[result fuzzyNoteUUIDs]count],"successive peer query completes with correct empty result");[events addObject:next];peerReplies++;arrived=YES;}];
                dispatch_semaphore_signal(service->continueBatch);
                // The already requeued mapping batch precedes this new query.
                // Releasing that one turn lets FIFO run the peer next.
                Wait(^BOOL{return dispatch_semaphore_wait(service->batchDone,DISPATCH_TIME_NOW)==0;});
                dispatch_semaphore_signal(service->continueBatch);
                Wait(^BOOL{return arrived;});Check(peerReplies==before+1&&!positioned,"one fresh peer completion precedes final positions");
            }
            atomic_store(&service->pauseBatches,NO);dispatch_semaphore_signal(service->continueBatch);
        }else{
            [service requestForOwner:peer query:@"q"completion:^(NVSearchResult *result,NSError *error){Check(!error&&result!=nil,"ungated peer search completes");[events addObject:@"q"];peerDelivery=MS(start);peerReplies++;}];
        }
        Wait(^BOOL{return positioned&&peerReplies==(gated?4:1);});
        if(gated)Check([events isEqualToArray:@[@"q0",@"q1",@"q2",@"q3",@"positions"]],"four arrivals maintain request completion order before mapping completion");
        Check(!atomic_load(&service->batchOnMain),"all production position batches ran off main");
        Check(atomic_load(&service->batches)>1,"Unicode request uses multiple production mapping batches");
        for(NSValue *value in expected)Check([editor->layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:[value rangeValue].location effectiveRange:NULL]!=nil,"both late Unicode ranges receive native temporary attributes");
        uint64_t clearStart=Tick();[editor removeHighlightedTerms];double clear=MS(clearStart);
        Check([[editor string]isEqualToString:source],"applying and clearing source highlights preserves original Unicode");
        NSArray *orderBefore=[[initial fuzzyNoteUUIDs]copy];NVSearchResult *again=Search(service,primary,query);Check([[again fuzzyNoteUUIDs]isEqualToArray:orderBefore],"position work preserves complete native result order");[orderBefore release];
        printf("%s,%lu,utf16=%lu,utf8=%lu,batches=%lu,submit_main_ms=%.3f,delivery_ms=%.3f,peer_delivery_ms=%.3f,max_batch_ms=%.3f,max_resumed_batch_ms=%.3f,apply_main_ms=%.3f,clear_main_ms=%.3f,events=%s\n",gated?"gated":"ungated",trial,[source length],[[source dataUsingEncoding:NSUTF8StringEncoding]length],atomic_load(&service->batches),submit,delivery,peerDelivery,(double)atomic_load(&service->maxBatchNS)/1e6,(double)atomic_load(&service->maxResumedBatchNS)/1e6,apply,clear,[[events componentsJoinedByString:@"|"]UTF8String]);fflush(stdout);
        [service invalidate];__block BOOL drained=NO;[service drain:^{drained=YES;}];Wait(^BOOL{return drained;});
    }
}
int main(void){@autoreleasepool{Check([NSThread isMainThread],"fixture starts on main");Run(YES,0);Run(NO,0);Run(NO,1);printf("PASS: %lu checks\n",checks);}return 0;}
