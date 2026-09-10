#import <Cocoa/Cocoa.h>
#import <Block.h>
static NSUInteger Checks, UnsafeWrites;
static void Check(BOOL ok, const char *name) { if (!ok) { fprintf(stderr,"FAIL: %s\n",name); exit(1); } Checks++; }
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.035]]; }
static const NSUInteger NVSearchMaximumDisplayedRanges = 1024;
typedef void (^NVSearchLiteralRangesCompletion)(NSArray *, NSString *, NSError *);
typedef void (^SourceCompletion)(NSArray *, NSString *);
@interface TrackedLayout : NSLayoutManager { @public NSUInteger adds, removes; }
@end
@implementation TrackedLayout
- (void)addTemporaryAttribute:(NSAttributedStringKey)name value:(id)value forCharacterRange:(NSRange)range {
    if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeWrites++;
    adds++; [super addTemporaryAttribute:name value:value forCharacterRange:range];
}
- (void)removeTemporaryAttribute:(NSAttributedStringKey)name forCharacterRange:(NSRange)range {
    if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) UnsafeWrites++;
    removes++; [super removeTemporaryAttribute:name forCharacterRange:range];
}
@end
@interface Editor : NSObject { @public BOOL searchHighlightsInvalidated, hasSearchHighlights; NSTextStorage *storage; TrackedLayout *layout; }
- (id)initWithStorage:(NSTextStorage *)s;
- (void)invalidateSearchHighlights;
- (void)removeHighlightedTerms;
- (void)setSearchHighlightRanges:(NSArray *)ranges;
@end
@implementation Editor
- (id)initWithStorage:(NSTextStorage *)s { if ((self=[super init])) { storage=[s retain]; layout=[TrackedLayout new]; [storage addLayoutManager:layout]; } return self; }
- (NSString *)string { return [storage string]; }
- (NSTextStorage *)textStorage { return storage; }
- (NSLayoutManager *)layoutManager { return layout; }
- (NSDictionary *)currentSearchHighlightAttributes { return @{NSBackgroundColorAttributeName:[NSColor yellowColor]}; }
#include "editor.inc"
- (void)dealloc { [NSObject cancelPreviousPerformRequestsWithTarget:self]; [storage removeLayoutManager:layout]; [storage release]; [layout release]; [super dealloc]; }
@end
@interface Pending : NSObject { @public NVSearchLiteralRangesCompletion completion; NSString *source; }
@end
@implementation Pending
- (void)dealloc { if (completion) Block_release(completion); [source release]; [super dealloc]; }
@end
@interface NVSearchService : NSObject { @public NSMutableArray *pending; NSUInteger cancellations; }
- (void)cancelLiteralRangesForOwner:(id)owner;
- (void)validateSourceRanges:(NSArray *)ranges source:(NSString *)source matchingSource:(NSString *)display owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion;
- (void)requestLiteralRangesInSource:(NSString *)source matchingSource:(NSString *)display query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)completion;
- (void)complete:(NSUInteger)index error:(NSError *)error;
@end
@implementation NVSearchService
- (id)init { if((self=[super init])) pending=[NSMutableArray new]; return self; }
// Keep canceled work deliverable. The application closure must reject a late delivery.
- (void)cancelLiteralRangesForOwner:(id)owner { cancellations++; }
- (void)validateSourceRanges:(NSArray *)ranges source:(NSString *)src matchingSource:(NSString *)display owner:(id)owner completion:(NVSearchLiteralRangesCompletion)block {
    Pending *p=[Pending new]; p->completion=Block_copy(block); p->source=[src copy]; [pending addObject:p]; [p release];
}
- (void)requestLiteralRangesInSource:(NSString *)src matchingSource:(NSString *)display query:(NSString *)query owner:(id)owner completion:(NVSearchLiteralRangesCompletion)block { [self validateSourceRanges:nil source:src matchingSource:display owner:owner completion:block]; }
- (void)complete:(NSUInteger)index error:(NSError *)error { Pending *p=[pending objectAtIndex:index]; p->completion(@[[NSValue valueWithRange:NSMakeRange(0,1)]],p->source,error); }
- (void)dealloc { [pending release]; [super dealloc]; }
@end
static NVSearchService *Service;
@interface NVApplicationController : NSObject
+ (id)sharedController;
- (NVSearchService *)searchService;
@end
@implementation NVApplicationController
+ (id)sharedController { static id shared; if(!shared)shared=[self new]; return shared; }
- (NVSearchService *)searchService { return Service; }
@end
@interface NVBrowserSession : NSObject { @public BOOL current; NSString *key, *kind; SourceCompletion fuzzyCompletion; }
- (BOOL)searchResultsAreCurrent;
- (NSString *)rowKeyAtIndex:(NSInteger)index;
- (NSString *)matchKindAtIndex:(NSInteger)index;
- (NSString *)searchString;
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(SourceCompletion)completion;
@end
@implementation NVBrowserSession
- (id)init { if((self=[super init])) { current=YES; key=[@"note-A" copy]; kind=[@"title" copy]; } return self; }
- (BOOL)searchResultsAreCurrent { return current; }
- (NSString *)rowKeyAtIndex:(NSInteger)index { return index < 0 ? nil : key; }
- (NSString *)matchKindAtIndex:(NSInteger)index { return kind; }
- (NSString *)searchString { return @"a"; }
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(SourceCompletion)block { if(fuzzyCompletion)Block_release(fuzzyCompletion); fuzzyCompletion=Block_copy(block); }
- (void)dealloc { if(fuzzyCompletion)Block_release(fuzzyCompletion); [key release]; [kind release]; [super dealloc]; }
@end
@interface Table : NSObject { @public NSInteger row; }
- (NSInteger)primarySelectedRow;
@end
@implementation Table
- (NSInteger)primarySelectedRow { return row; }
@end
@interface Prefs : NSObject
- (BOOL)highlightSearchTerms;
@end
@implementation Prefs
- (BOOL)highlightSearchTerms { return YES; }
@end
@interface Note : NSObject { @public NSTextStorage *source; }
- (NSTextStorage *)contentString;
@end
@implementation Note
- (NSTextStorage *)contentString { return source; }
@end
@interface Browser : NSObject { @public Editor *textView; NSUInteger searchHighlightGeneration; BOOL searchHasPendingComposition; NVBrowserSession *browserState; Table *notesTableView; Prefs *prefsController; Note *currentNote; }
- (id)initWithStorage:(NSTextStorage *)storage;
- (NVBrowserSession *)browserSession;
- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification;
- (void)refreshSearchHighlights;
@end
@implementation Browser
- (id)initWithStorage:(NSTextStorage *)s {
    if((self=[super init])) { textView=[[Editor alloc]initWithStorage:s]; browserState=[NVBrowserSession new]; notesTableView=[Table new]; prefsController=[Prefs new]; currentNote=[Note new]; currentNote->source=s;
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(searchSourceStorageWillProcessEditing:) name:NSTextStorageWillProcessEditingNotification object:s]; }
    return self;
}
- (NVBrowserSession *)browserSession { return browserState; }
#include "observer.inc"
#include "refresh.inc"
- (void)dealloc { [[NSNotificationCenter defaultCenter]removeObserver:self]; [textView release]; [browserState release]; [notesTableView release]; [prefsController release]; [currentNote release]; [super dealloc]; }
@end
static BOOL Highlighted(Browser *b) { return [[b->textView->layout temporaryAttributesAtCharacterIndex:0 effectiveRange:NULL] objectForKey:NSBackgroundColorAttributeName]!=nil; }
static void SetKey(Browser *b, NSString *key) { [b->browserState->key release]; b->browserState->key=[key copy]; }
static void ResetService(void) { [Service release]; Service=[NVSearchService new]; }
static void Delete(Browser *b) { [b->textView->storage deleteCharactersInRange:NSMakeRange(1,1)]; }
// The oracle tracks application events, not implementation counters or pending flags.
typedef struct { NSUInteger revision, request; } Model;
typedef struct { NSUInteger revision, request; } Snapshot;
static BOOL Current(Model m, Snapshot s) { return m.revision==s.revision && m.request==s.request; }
static NSUInteger Schedules;
static void RunSchedule(const int *events) {
    @autoreleasepool {
        ResetService(); NSTextStorage *storage=[[NSTextStorage alloc]initWithString:@"alpha beta gamma"];
        Browser *b=[[Browser alloc]initWithStorage:storage]; Model oracle={0,1}; Snapshot old={0,1}, fresh={0,0};
        [b refreshSearchHighlights];
        for (int i=0;i<4;i++) {
            switch(events[i]) {
            case 0: oracle.revision++; Delete(b); break;
            case 1: oracle.request++; fresh=(Snapshot){oracle.revision,oracle.request}; [b refreshSearchHighlights]; break;
            case 2: { NSUInteger before=b->textView->layout->adds; [Service complete:0 error:nil]; Check(b->textView->layout->adds==before+Current(oracle,old),"old completion agrees with revision/request oracle"); break; }
            case 3: { NSUInteger before=b->textView->layout->adds; [Service complete:1 error:nil]; Check(b->textView->layout->adds==before+Current(oracle,fresh),"new completion agrees with revision/request oracle"); break; }
            }
        }
        Pump(); Check(UnsafeWrites==0,"permutation performs no writes during character processing");
        [Service->pending removeAllObjects]; [b release]; [storage release]; Schedules++;
    }
}
static void Permute(int *events, int at) {
    if(at==4) { int refresh=-1,newCompletion=-1; for(int i=0;i<4;i++){if(events[i]==1)refresh=i;if(events[i]==3)newCompletion=i;} if(refresh<newCompletion)RunSchedule(events); return; }
    for(int i=at;i<4;i++) { int t=events[at];events[at]=events[i];events[i]=t;Permute(events,at+1);t=events[at];events[at]=events[i];events[i]=t; }
}
static void NestedEdits(void) {
    ResetService(); NSTextStorage *storage=[[NSTextStorage alloc]initWithString:@"alpha beta gamma"];
    Browser *a=[[Browser alloc]initWithStorage:storage],*b=[[Browser alloc]initWithStorage:storage];
    [a refreshSearchHighlights]; [b refreshSearchHighlights]; [Service complete:0 error:nil]; [Service complete:1 error:nil];
    Check(Highlighted(a)&&Highlighted(b),"both owners publish initial source");
    Delete(a); [storage beginEditing]; Delete(a);
    NSUInteger ar=a->textView->layout->removes,br=b->textView->layout->removes;
    Pump();
    Check(a->textView->searchHighlightsInvalidated&&b->textView->searchHighlightsInvalidated,"both pending clears survive an open nested edit");
    Check(a->textView->layout->removes==ar&&b->textView->layout->removes==br,"nested run loop does not touch either dirty layout");
    NSUInteger aa=a->textView->layout->adds,ba=b->textView->layout->adds;
    [Service complete:0 error:nil];[Service complete:1 error:nil];
    Check(a->textView->layout->adds==aa&&b->textView->layout->adds==ba,"pre-edit completions cannot publish during the open edit");
    [a refreshSearchHighlights]; NSUInteger during=[Service->pending count]-1; [Service complete:during error:nil];
    Check(a->textView->layout->adds==aa,"even a current callback cannot install ranges during an open edit");
    [storage endEditing];
    [Service complete:during error:nil];
    Check(a->textView->layout->adds==aa,"endEditing fences a callback captured inside that edit");
    Browser *c=[[Browser alloc]initWithStorage:storage];
    [a refreshSearchHighlights]; [Service complete:[Service->pending count]-1 error:nil];
    [c refreshSearchHighlights]; [Service complete:[Service->pending count]-1 error:nil]; Pump();
    Check(Highlighted(a)&&Highlighted(c)&&!Highlighted(b),"fresh owner and refreshed peer survive the other peer cleanup");
    Check(!a->textView->searchHighlightsInvalidated&&!b->textView->searchHighlightsInvalidated&&!c->textView->searchHighlightsInvalidated,"all pending states settle after the edit closes");
    Check(UnsafeWrites==0,"nested edit schedule performs no unsafe layout writes");
    [Service->pending removeAllObjects];[a release];[b release];[c release];[storage release];
}
static void CompletionGates(void) {
    ResetService(); NSTextStorage *storage=[[NSTextStorage alloc]initWithString:@"alpha beta gamma"];
    Browser *b=[[Browser alloc]initWithStorage:storage];
    [b refreshSearchHighlights]; SetKey(b,@"note-B"); [Service complete:0 error:nil]; Check(!Highlighted(b),"row-key change rejects a late callback before refresh");
    SetKey(b,@"note-A"); [b refreshSearchHighlights]; [Service complete:0 error:nil]; Check(!Highlighted(b),"ABA note selection rejects old same-key callback after refresh");
    b->browserState->current=NO; [Service complete:1 error:nil]; Check(!Highlighted(b),"pending result snapshot rejects callback");
    b->browserState->current=YES; b->notesTableView->row=-1; [Service complete:1 error:nil]; Check(!Highlighted(b),"no selected row rejects callback");
    b->notesTableView->row=0; [Service complete:1 error:[NSError errorWithDomain:@"fixture" code:1 userInfo:nil]]; Check(!Highlighted(b),"error completion does not publish");
    [Service complete:1 error:nil]; Check(Highlighted(b),"current successful completion still publishes");
    [b->browserState->kind release];b->browserState->kind=[@"fuzzy" copy];[b refreshSearchHighlights];
    SourceCompletion stage1=Block_copy(b->browserState->fuzzyCompletion); NSUInteger pending=[Service->pending count]; Delete(b);
    stage1(@[[NSValue valueWithRange:NSMakeRange(0,1)]],@"alpha beta gamma"); Check([Service->pending count]==pending,"obsolete fuzzy first stage never enters source validation"); Block_release(stage1);
    [b refreshSearchHighlights];b->browserState->fuzzyCompletion(@[[NSValue valueWithRange:NSMakeRange(0,1)]],[storage string]);
    Check([Service->pending count]==pending+1,"current fuzzy first stage reaches source validation");
    Delete(b); NSUInteger before=b->textView->layout->adds;[Service complete:pending error:nil];Check(b->textView->layout->adds==before,"edit between fuzzy stages rejects old validated ranges");
    Pump();Check(!Highlighted(b),"rejected staged results leave no stale background after cleanup");
    // Break the fake browserState's stored completion cycle before releasing the browser.
    Block_release(b->browserState->fuzzyCompletion);b->browserState->fuzzyCompletion=nil;
    [Service->pending removeAllObjects];[b release];[storage release];
}
int main(void) { @autoreleasepool { int events[]={0,1,2,3};Permute(events,0); Check(Schedules==12,"all twelve legal completion schedules executed"); NestedEdits();CompletionGates(); [Service release]; Service=nil; Check(UnsafeWrites==0,"all schedules avoid dirty TextKit writes"); printf("PASS: %lu checks; %lu exhaustive schedules; nested shared editing; async stage and selection gates\n",(unsigned long)Checks,(unsigned long)Schedules); } return 0; }
