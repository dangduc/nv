#import <Cocoa/Cocoa.h>
#import "NVSearchService.h"
#import <stdatomic.h>
static NSUInteger checks;
static _Atomic uint64_t nativeNS, mappingNS;
void NVReviewPositionPhase(int phase,double milliseconds) {
    if(phase==0) atomic_store(&nativeNS,(uint64_t)(milliseconds*1e6));
    else atomic_store(&mappingNS,(uint64_t)(milliseconds*1e6));
}
static void Check(BOOL condition,const char *message) { checks++; if(!condition){fprintf(stderr,"FAIL %s\n",message);exit(1);} }
static double Now(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW)/1e6; }
static void Wait(BOOL(^finished)(void)) { double deadline=Now()+20000; while(!finished()&&Now()<deadline) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]]; Check(finished(),"bounded async completion"); }
static NSString *LongSource(NSUInteger bytes,BOOL unicode,BOOL dense) {
    if(dense) { NSMutableString *s=[NSMutableString string]; while([s length]<bytes) [s appendString:@"meeting notes: a clear goal and a small task to finish today.\n"]; return [s substringToIndex:bytes]; }
    NSString *unit=unicode?@"e\u0301":@"x";
    NSMutableString *s=[NSMutableString stringWithCapacity:bytes];
    NSUInteger size=unicode?bytes/3:bytes;
    NSString *chunk=[@"" stringByPaddingToLength:4096 withString:unit startingAtIndex:0];
    while([s length]<size) [s appendString:chunk];
    if([s length]>size) [s deleteCharactersInRange:NSMakeRange(size,[s length]-size)];
    [s appendString:@"needle"]; return [[s copy] autorelease];
}
static NVSearchResult *Search(NVSearchService *service,id owner,NSString *query,double *elapsed) {
    __block BOOL done=NO; __block NVSearchResult *output=nil; double start=Now();
    [service requestForOwner:owner query:query completion:^(NVSearchResult *result,NSError *error){Check(!error&&result!=nil,"native search succeeds");output=[result retain];done=YES;}];
    Wait(^BOOL{return done;}); if(elapsed)*elapsed=Now()-start; return [output autorelease];
}
static NVSearchNoteSnapshot *Snapshot(NSString *source) {
    CFUUIDRef uuid=CFUUIDCreate(NULL);CFUUIDBytes bytes=CFUUIDGetUUIDBytes(uuid);CFRelease(uuid);
    return [[[NVSearchNoteSnapshot alloc] initWithNoteUUID:[NSData dataWithBytes:&bytes length:16] title:@"fixture" tags:@"" source:source revision:1] autorelease];
}
@interface Prefs:NSObject @end
@implementation Prefs
- (BOOL)highlightSearchTerms{return YES;}
- (NSDictionary *)searchTermHighlightAttributes{return @{NSBackgroundColorAttributeName:[NSColor yellowColor]};}
@end
@interface Editor:NSObject { @public NSTextStorage *storage;NSLayoutManager *layout;Prefs *prefsController; }
- (NSString *)string;
- (NSLayoutManager *)layoutManager;
- (void)setSearchHighlightRanges:(NSArray *)ranges;
- (void)removeHighlightedTerms;
@end
@implementation Editor
- (id)init{if((self=[super init])){storage=[[NSTextStorage alloc]init];layout=[[NSLayoutManager alloc]init];[storage addLayoutManager:layout];prefsController=[[Prefs alloc]init];}return self;}
- (NSString *)string{return [storage string];}
- (NSLayoutManager *)layoutManager{return layout;}
#include "editor.inc"
- (void)dealloc{[storage removeLayoutManager:layout];[storage release];[layout release];[prefsController release];[super dealloc];}
@end
@interface TimedEditor:Editor { @public NSUInteger applications,rangeCount;double applyMS; }
@end
@implementation TimedEditor
- (void)setSearchHighlightRanges:(NSArray *)ranges {Check([NSThread isMainThread],"native attributes applied on main");double start=Now();[super setSearchHighlightRanges:ranges];applyMS=Now()-start;rangeCount=[ranges count];applications++;}
@end
@interface Note:NSObject{@public NSAttributedString *body;} @end
@implementation Note
- (NSAttributedString *)contentString{return body;}
- (void)dealloc{[body release];[super dealloc];}
@end
@interface NVBrowserSession:NSObject{@public NSString *query;}
- (BOOL)searchResultsAreCurrent;
- (NSString *)matchKindAtIndex:(NSInteger)row;
- (NSString *)rowKeyAtIndex:(NSInteger)row;
- (NSString *)searchString;
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(void(^)(NSArray *,NSString *))callback;
@end
@implementation NVBrowserSession
- (BOOL)searchResultsAreCurrent{return YES;}
- (NSString *)matchKindAtIndex:(NSInteger)row{return @"title";}
- (NSString *)rowKeyAtIndex:(NSInteger)row{return @"title:fixture";}
- (NSString *)searchString{return query;}
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(void(^)(NSArray *,NSString *))callback{abort();}
@end
@interface Table:NSObject @end
@implementation Table
- (NSInteger)primarySelectedRow{return 0;}
@end
static NVSearchService *activeService;
@interface NVApplicationController:NSObject
+ (id)sharedController;
- (NVSearchService *)searchService;
@end
@implementation NVApplicationController
+ (id)sharedController{static id object; if(!object)object=[[self alloc]init];return object;}
- (NVSearchService *)searchService{return activeService;}
@end
@interface Controller:NSObject{@public NSUInteger searchHighlightGeneration;TimedEditor *textView;Note *currentNote;Prefs *prefsController;BOOL searchHasPendingComposition;Table *notesTableView;NVBrowserSession *browser;}
- (NVBrowserSession *)browserSession;
- (void)refreshSearchHighlights;
@end
@implementation Controller
- (NVBrowserSession *)browserSession{return browser;}
#include "refresh.inc"
@end
static void Dense(void) {
    activeService=[[[NVSearchService alloc]init]autorelease];
    Controller *controller=[[[Controller alloc]init]autorelease];
    controller->prefsController=[[[Prefs alloc]init]autorelease];controller->textView=[[[TimedEditor alloc]init]autorelease];controller->currentNote=[[[Note alloc]init]autorelease];controller->notesTableView=[[[Table alloc]init]autorelease];controller->browser=[[[NVBrowserSession alloc]init]autorelease];controller->browser->query=@"a";
    NSString *source=LongSource(8*1024*1024,NO,YES);controller->currentNote->body=[[NSAttributedString alloc]initWithString:source];[controller->textView->storage setAttributedString:controller->currentNote->body];
    printf("case,trial,source_utf16,ranges,submit_main_ms,worker_to_apply_ms,apply_main_ms,clear_main_ms\n");
    for(NSUInteger trial=0;trial<3;trial++){
        NSUInteger before=controller->textView->applications;double start=Now();[controller refreshSearchHighlights];double submit=Now()-start;
        Wait(^BOOL{return controller->textView->applications>before;});double total=Now()-start;
        Check(controller->textView->rangeCount==2048,"dense source returns capped 2048 ranges");
        Check([controller->textView->layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:15 effectiveRange:NULL]!=nil,"real literal a highlight exists");
        start=Now();[controller->textView removeHighlightedTerms];double clear=Now()-start;
        Check([[controller->textView string]isEqualToString:source],"source remains unchanged");
        printf("dense,%lu,%lu,%lu,%.3f,%.3f,%.3f,%.3f\n",trial,[source length],controller->textView->rangeCount,submit,total,controller->textView->applyMS,clear);
    }
    [activeService cancelRequestsForOwner:controller->browser];[activeService invalidate];activeService=nil;
}
static void Lane(BOOL positions) {
    printf("case,source_utf16,trial,baseline_peer_ms,presentation_ms,peer_queued_ms,delivered_ranges,native_positions_ms,unicode_map_ms\n");
    for(NSUInteger sizeIndex=0;sizeIndex<(positions?2:1);sizeIndex++) {
    for(NSUInteger trial=0;trial<2;trial++){@autoreleasepool{
        NSString *source=LongSource(positions?(sizeIndex?4*1024*1024:1024*1024):8*1024*1024,NO,NO);
        NVSearchService *service=[[[NVSearchService alloc]init]autorelease];NVSearchNoteSnapshot *snapshot=Snapshot(source);[service synchronizeWithSnapshots:@[snapshot]];
        id owner=[[[NSObject alloc]init]autorelease],peer=[[[NSObject alloc]init]autorelease];
        NVSearchResult *search=Search(service,owner,@"needle",NULL);Check([[search fuzzyNoteUUIDs]count]==1,"late fuzzy candidate present");
        double baseline=0;Search(service,peer,@"q",&baseline);[service cancelRequestsForOwner:peer];
        __block BOOL presented=NO,peerDone=NO;__block double presentation=0,peerMS=0;__block NSUInteger count=0;double start=Now();
        if(positions) [service requestPositionsForNoteUUID:[snapshot noteUUID] requestID:[search requestID] owner:owner completion:^(NVSearchPositions *value,NSError *error){Check(!error&&value!=nil,"late native positions succeed");count=[[value sourceRanges]count];Check(count==1&&[[[value sourceRanges]firstObject]rangeValue].location==[source length]-6,"late position maps to original source");presentation=Now()-start;presented=YES;}];
        else [service requestLiteralRangesInSource:source matchingSource:source query:@"needle" owner:owner completion:^(NSArray *ranges,NSString *returned,NSError *error){Check(!error&&[ranges count]==1,"late literal range succeeds");Check([[ranges firstObject]rangeValue].location==[source length]-6,"late literal range has exact original offset");count=[ranges count];presentation=Now()-start;presented=YES;}];
        [service requestForOwner:peer query:@"q" completion:^(NVSearchResult *value,NSError *error){Check(!error&&value!=nil,"peer query succeeds after presentation");peerMS=Now()-start;peerDone=YES;}];
        Wait(^BOOL{return presented&&peerDone;});
        printf("%s,%lu,%lu,%.3f,%.3f,%.3f,%lu,%.3f,%.3f\n",positions?"late_positions":"late_literal",[source length],trial,baseline,presentation,peerMS,count,(double)atomic_load(&nativeNS)/1e6,(double)atomic_load(&mappingNS)/1e6);fflush(stdout);
        if(positions&&sizeIndex==1&&trial==1) {
            [service cancelRequestsForOwner:peer];
            __block BOOL cancelled=NO,completed=NO,positionCallback=NO;__block double cancelledAt=0,completedAt=0;
            double controlStart=Now();
            [service requestPositionsForNoteUUID:[snapshot noteUUID] requestID:[search requestID] owner:owner completion:^(NVSearchPositions *value,NSError *error){positionCallback=YES;}];
            [service requestForOwner:peer query:@"q" completion:^(NVSearchResult *value,NSError *error){Check(!error&&value!=nil,"peer query after position cancellation succeeds");completedAt=Now();completed=YES;}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{cancelledAt=Now();[service cancelPositionRequestsForOwner:owner];cancelled=YES;});
            Wait(^BOOL{return cancelled&&completed;});
            Check(!positionCallback,"cancelled position request does not publish");
            printf("cancel_control,source_utf16=%lu,total_peer_ms=%.3f,cancel_to_peer_ms=%.3f,native_positions_ms=%.3f,unicode_map_ms=%.3f\n",[source length],completedAt-controlStart,completedAt-cancelledAt,(double)atomic_load(&nativeNS)/1e6,(double)atomic_load(&mappingNS)/1e6);fflush(stdout);
        }
        [service cancelRequestsForOwner:owner];[service cancelRequestsForOwner:peer];[service invalidate];
    }}}
}
int main(int argc,const char **argv){@autoreleasepool{Check([NSThread isMainThread],"fixture begins on main");Check(argc==2,"one bounded fixture selected");if(!strcmp(argv[1],"dense"))Dense();else if(!strcmp(argv[1],"literal"))Lane(NO);else if(!strcmp(argv[1],"positions"))Lane(YES);else Check(NO,"known fixture");fprintf(stderr,"PASS %lu checks\n",checks);}return 0;}
