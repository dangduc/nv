#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVSearchService.h"
#include <mach/mach_time.h>
static NSUInteger Checks, ScansOnMain, ApplyCalls;
static double LastApplyMS;
static double Now(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW)/1e6; }
static void Check(BOOL value, const char *message) { if (!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } ++Checks; }
static BOOL Await(BOOL (^condition)(void)) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:15]; while(!condition() && [end timeIntervalSinceNow]>0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.001]]; return condition(); }
static BOOL LeaseReleasedOnMain;
@interface Lease : NSObject @end
@implementation Lease
- (void)dealloc { LeaseReleasedOnMain=[NSThread isMainThread];[super dealloc]; }
@end
@interface Prefs : NSObject @end
@implementation Prefs
- (BOOL)highlightSearchTerms { return YES; }
- (NSDictionary *)searchTermHighlightAttributes { return @{NSBackgroundColorAttributeName:[NSColor yellowColor]}; }
@end
@interface Editor : NSObject { @public NSTextStorage *storage; NSLayoutManager *layout; Prefs *prefsController; }
- (NSString *)string;
- (NSLayoutManager *)layoutManager;
- (NSTextStorage *)textStorage;
- (void)removeHighlightedTerms;
- (void)setSearchHighlightRanges:(NSArray *)ranges;
- (NSRange)highlightTermsTemporarilyReturningFirstRange:(NSString *)query avoidHighlight:(BOOL)avoid;
@end
@implementation Editor
- (id)init { if((self=[super init])){storage=[[NSTextStorage alloc]init];layout=[[NSLayoutManager alloc]init];[storage addLayoutManager:layout];prefsController=[[Prefs alloc]init];} return self; }
- (NSString *)string { return [storage string]; }
- (NSLayoutManager *)layoutManager { return layout; }
- (NSTextStorage *)textStorage { return storage; }
#include "editor.inc"
- (void)dealloc { [storage removeLayoutManager:layout];[storage release];[layout release];[prefsController release];[super dealloc]; }
@end
@interface Note : NSObject { @public NSAttributedString *content; } @end
@implementation Note
- (NSAttributedString *)contentString { return content; }
- (void)dealloc { [content release];[super dealloc]; }
@end
@interface NVBrowserSession : NSObject { @public NSString *query,*key,*kind; BOOL current; }
- (BOOL)searchResultsAreCurrent;
- (NSString *)searchString;
- (NSString *)matchKindAtIndex:(NSInteger)row;
- (NSString *)rowKeyAtIndex:(NSInteger)row;
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(void (^)(NSArray *,NSString *))completion;
@end
@implementation NVBrowserSession
- (id)init { if((self=[super init])){query=@"a";key=@"title:fixture";kind=@"title";current=YES;}return self; }
- (BOOL)searchResultsAreCurrent { return current; }
- (NSString *)searchString { return query; }
- (NSString *)matchKindAtIndex:(NSInteger)row { return kind; }
- (NSString *)rowKeyAtIndex:(NSInteger)row { return key; }
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(void (^)(NSArray *,NSString *))completion { abort(); }
@end
@interface Table : NSObject @end
@implementation Table
- (NSInteger)primarySelectedRow { return 0; }
@end
@interface NVApplicationController : NSObject { @public NVSearchService *service; }
+ (id)sharedController;
- (NVSearchService *)searchService;
@end
@implementation NVApplicationController
+ (id)sharedController { static id app; if(!app)app=[[self alloc]init];return app; }
- (NVSearchService *)searchService { return service; }
@end
@interface Controller : NSObject { @public NSUInteger searchHighlightGeneration; Editor *textView;Note *currentNote;Prefs *prefsController; BOOL searchHasPendingComposition;Table *notesTableView;NVBrowserSession *browser; }
- (NVBrowserSession *)browserSession;
- (void)refreshSearchHighlights;
- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification;
@end
@implementation Controller
- (NVBrowserSession *)browserSession { return browser; }
#include "refresh.inc"
#include "storage.inc"
@end
static NSString *Source(NSUInteger length) { NSString *line=@"meeting notes: a clear goal and a small task to finish today.\n";return [line stringByPaddingToLength:length withString:line startingAtIndex:0]; }
static NSUInteger BackgroundRuns(Editor *editor) { NSUInteger count=0,index=0,length=[[editor string]length];while(index<length){NSRange range;id value=[editor->layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:index effectiveRange:&range];if(value)++count;if(NSMaxRange(range)<=index)abort();index=NSMaxRange(range);}return count; }
static NSRange OldCaret(NSString *source, NSString *query, BOOL avoid) {
    NSString *separator=[query rangeOfString:@"\""].location==NSNotFound?@" ":@"\"";NSRange first=NSMakeRange(NSNotFound,0);
    for(NSString *term in [query componentsSeparatedByString:separator]){if(![term length])continue;CFArrayRef ranges=CFStringCreateArrayWithFindResults(NULL,(CFStringRef)source,(CFStringRef)term,CFRangeMake(0,[source length]),kCFCompareCaseInsensitive);if(!ranges)continue;for(CFIndex i=0;i<CFArrayGetCount(ranges);++i){CFRange range=*(CFRange*)CFArrayGetValueAtIndex(ranges,i);if((NSUInteger)range.location<first.location){first=NSMakeRange(range.location,range.length);if(avoid){CFRelease(ranges);return first;}}}CFRelease(ranges);}return first;
}
int main(void) { setvbuf(stdout,NULL,_IOLBF,0); @autoreleasepool {
    NVSearchService *service=[[[NVSearchService alloc]init]autorelease];[(NVApplicationController*)[NVApplicationController sharedController] setValue:service forKey:@"service"];
    Controller *controller=[[[Controller alloc]init]autorelease];controller->textView=[[[Editor alloc]init]autorelease];controller->prefsController=[[[Prefs alloc]init]autorelease];controller->notesTableView=[[[Table alloc]init]autorelease];controller->currentNote=[[[Note alloc]init]autorelease];controller->browser=[[[NVBrowserSession alloc]init]autorelease];
    Editor *editor=controller->textView; NVBrowserSession *browser=controller->browser;
    // Observe actual worker placement without replacing the discovery algorithm.
    SEL scanSelector=@selector(literalRangesInString:maximumCount:cancellation:);Method scan=class_getInstanceMethod([NVSearchQuery class],scanSelector);IMP originalScan=method_getImplementation(scan);
    method_setImplementation(scan,imp_implementationWithBlock(^id(id object,NSString *source,NSUInteger limit,BOOL(^cancelled)(void)){if([NSThread isMainThread])++ScansOnMain;return ((id(*)(id,SEL,id,NSUInteger,id))originalScan)(object,scanSelector,source,limit,cancelled);}));
    Method apply=class_getInstanceMethod([Editor class],@selector(setSearchHighlightRanges:));IMP originalApply=method_getImplementation(apply);
    method_setImplementation(apply,imp_implementationWithBlock(^(id object,NSArray *ranges){Check([NSThread isMainThread],"attribute application stays on main");double start=Now();((void(*)(id,SEL,id))originalApply)(object,@selector(setSearchHighlightRanges:),ranges);LastApplyMS=Now()-start;++ApplyCalls;}));
    for(NSString *small in @[@"beta ALPHA alpha beta",@"alpha:beta gamma",@"café cafe\u0301 🧑🏽‍💻",@"quoted blue sky and red"]){[editor->storage replaceCharactersInRange:NSMakeRange(0,[editor->storage length]) withString:small];for(NSString *query in @[@"alpha beta",@"beta alpha",@"\"blue sky\" red",@"CAFÉ",@"alpha:beta",@"\"unfinished"]){for(NSUInteger avoid=0;avoid<2;++avoid){Check(NSEqualRanges([editor highlightTermsTemporarilyReturningFirstRange:query avoidHighlight:avoid],OldCaret(small,query,avoid)),"legacy first-match caret selection unchanged");}}Check(BackgroundRuns(editor)==0,"legacy caret lookup installs no unbounded attributes");}
    NVSearchQuery *literal=[[[NVSearchQuery alloc]initWithString:@"a"]autorelease];__block NSUInteger cancellations=0;
    Check([literal literalRangesInString:Source(8388608) maximumCount:NVSearchMaximumDisplayedRanges cancellation:^BOOL{return ++cancellations>10;}] == nil,"literal discovery obeys cancellation before full scan");
    Check([[literal literalRangesInString:Source(8388608) maximumCount:NVSearchMaximumDisplayedRanges cancellation:nil]count]<=NVSearchMaximumDisplayedRanges,"literal discovery stops at occurrence cap before allocation grows");
    NSString *source=Source(8388608); controller->currentNote->content=[[NSAttributedString alloc]initWithString:source];[editor->storage setAttributedString:controller->currentNote->content];
    [[NSNotificationCenter defaultCenter] addObserver:controller selector:@selector(searchSourceStorageWillProcessEditing:) name:NSTextStorageWillProcessEditingNotification object:editor->storage];
    [editor->layout addTemporaryAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] forCharacterRange:NSMakeRange(0,10)];
    double startComponent=Now();NSString *copied=[[[controller->currentNote contentString] string] copy];double copyMS=Now()-startComponent;
    startComponent=Now();Check([[editor string]isEqual:[[controller->currentNote contentString] string]],"component source equality");double equalityMS=Now()-startComponent;[copied release];
    startComponent=Now();NSString *editorCopy=[[editor string]copy];double editorCopyMS=Now()-startComponent;startComponent=Now();Check([editorCopy isEqual:[[controller->currentNote contentString]string]],"copied source equality");double copiedEqualityMS=Now()-startComponent;[editorCopy release];
    printf("components,source_copy_ms,%.3f,source_equality_ms,%.3f,editor_copy_ms,%.3f,copied_equality_ms,%.3f\n",copyMS,equalityMS,editorCopyMS,copiedEqualityMS);
    printf("source_bytes,query,submission_ms,application_ms,clear_ms,displayed_ranges\n");
    for(NSString *query in @[@"a",@"meeting",@"absent"]){browser->query=query;NSUInteger before=ApplyCalls;ScansOnMain=0;double start=Now();[controller refreshSearchHighlights];double submission=Now()-start;Check(ApplyCalls==before,"refresh returns before async range publication");Check(Await(^BOOL{return ApplyCalls>before;}),"literal request completes");Check(ScansOnMain==0,"dense and absent source discovery stays off main");NSUInteger displayed=BackgroundRuns(editor);Check(displayed<=NVSearchMaximumDisplayedRanges,"display installation stays within documented range cap");if(![query isEqual:@"absent"])Check(displayed>0,"literal matched ranges receive native attributes");Check([[editor string]isEqual:source],"source characters remain unchanged");Check([editor->layout temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL]!=nil,"syntax foreground survives search replacement");start=Now();[editor removeHighlightedTerms];double clear=Now()-start;Check(BackgroundRuns(editor)==0,"invalidation clears installed attributes");printf("%lu,%s,%.3f,%.3f,%.3f,%lu\n",[source length],[query UTF8String],submission,LastApplyMS,clear,displayed);}
    NSMutableArray *tooMany=[NSMutableArray array];for(NSUInteger i=0;i<NVSearchMaximumDisplayedRanges+100;++i)[tooMany addObject:[NSValue valueWithRange:NSMakeRange(i*3,1)]];
    [editor setSearchHighlightRanges:tooMany];Check(BackgroundRuns(editor)==NVSearchMaximumDisplayedRanges,"editor independently caps oversized native range input");[editor removeHighlightedTerms];
    __block BOOL nativeValidated=NO;[service validateSourceRanges:tooMany source:source matchingSource:source owner:browser completion:^(NSArray*r,NSString*s,NSError*e){Check([r count]==NVSearchMaximumDisplayedRanges,"native source validation bounds copied presentation ranges");nativeValidated=YES;}];Check(Await(^BOOL{return nativeValidated;}),"native range validation completes");
    for(NSArray *forms in @[@[@"é",@"e\u0301"],@[@"e\u0301",@"é"],@[@"a\u0301\u0327",@"a\u0327\u0301"]]) {
        __block BOOL checked=NO;
        [service validateSourceRanges:@[[NSValue valueWithRange:NSMakeRange(0,[forms[0]length])]] source:forms[0] matchingSource:forms[1] owner:browser completion:^(NSArray*r,NSString*s,NSError*e){Check([r count]==0,"canonical equivalents with different UTF16 reject snapshot offsets");checked=YES;}];
        Check(Await(^BOOL{return checked;}),"canonical source compatibility check completes");
    }
    NVSearchQuery *accent=[[[NVSearchQuery alloc]initWithString:@"é"]autorelease];
    Check(NSEqualRanges([[[accent literalRangesInString:@"e\u0301" maximumCount:1 cancellation:nil]firstObject]rangeValue],NSMakeRange(0,2)),"literal matching still expands canonical match to original grapheme");
    // Delay only callback delivery after the real service has completed work.
    NSMutableArray *deliveries=[NSMutableArray array];Method request=class_getInstanceMethod([NVSearchService class],@selector(requestLiteralRangesInSource:matchingSource:query:owner:completion:));IMP originalRequest=method_getImplementation(request);
    method_setImplementation(request,imp_implementationWithBlock(^(id object,NSString *text,NSString *displayed,NSString *query,id owner,NVSearchLiteralRangesCompletion completion){((void(*)(id,SEL,id,id,id,id,id))originalRequest)(object,@selector(requestLiteralRangesInSource:matchingSource:query:owner:completion:),text,displayed,query,owner,^(NSArray *ranges,NSString *snapshot,NSError *error){[deliveries addObject:[[^{completion(ranges,snapshot,error);}copy]autorelease]];});}));
    void(^deliverFirst)(void)=^{void(^delivery)(void)=[[[deliveries objectAtIndex:0]copy]autorelease];[deliveries removeObjectAtIndex:0];delivery();};
    browser->query=@"a";[controller refreshSearchHighlights];Check(Await(^BOOL{return [deliveries count]==1;}),"old query completion held");browser->query=@"absent";[controller refreshSearchHighlights];Check(Await(^BOOL{return [deliveries count]==2;}),"replacement completion held");NSUInteger applied=ApplyCalls;deliverFirst();Check(ApplyCalls==applied&&BackgroundRuns(editor)==0,"stale query generation cannot install highlights");deliverFirst();
    browser->query=@"a";[controller refreshSearchHighlights];Check(Await(^BOOL{return [deliveries count]==1;}),"row-context completion held");browser->key=@"fuzzy:fixture";applied=ApplyCalls;deliverFirst();Check(ApplyCalls==applied,"changed duplicate occurrence rejects old row highlights");browser->key=@"title:fixture";
    [controller refreshSearchHighlights];Check(Await(^BOOL{return [deliveries count]==1;}),"source-revision completion held");[editor->storage replaceCharactersInRange:NSMakeRange(0,1) withString:@"X"];applied=ApplyCalls;deliverFirst();Check(ApplyCalls==applied,"incompatible uncommitted source rejects snapshot highlights");
    [controller refreshSearchHighlights];Check(Await(^BOOL{return [deliveries count]==1;}),"incompatible initial source comparison completed");deliverFirst();Check(BackgroundRuns(editor)==0,"background compatibility check suppresses existing uncommitted source");
    method_setImplementation(request,originalRequest);
    Lease *lease=[[Lease alloc]init];
    [service requestLiteralRangesInSource:source query:@"a" owner:browser completion:^(NSArray*r,NSString*s,NSError*e){(void)[lease description];}];[lease release];[service cancelLiteralRangesForOwner:browser];
    Check(LeaseReleasedOnMain,"cancellation releases captured browser lifetime on main without waiting for worker");
    __block BOOL cancelledPublished=NO;[service requestLiteralRangesInSource:source query:@"a" owner:browser completion:^(NSArray*r,NSString*s,NSError*e){cancelledPublished=YES;}];[service cancelRequestsForOwner:browser];
    __block BOOL marker=NO;[service requestLiteralRangesInSource:source query:@"absent" owner:controller completion:^(NSArray*r,NSString*s,NSError*e){marker=YES;}];Check(Await(^BOOL{return marker;})&&!cancelledPublished,"owner closure cancels pending literal publication");
    [[NSNotificationCenter defaultCenter] removeObserver:controller];
    [service invalidate];printf("HIGHLIGHT BOUNDS PASSED: %lu checks\n",Checks);
}return 0;}
