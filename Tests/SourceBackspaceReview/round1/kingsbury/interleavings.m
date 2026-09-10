#import <Cocoa/Cocoa.h>
static NSUInteger Checks, Destroyed;
static void Check(BOOL ok, const char *name) { if(!ok){fprintf(stderr,"FAIL: %s\n",name);exit(1);} ++Checks; }
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.04]]; }
static const NSUInteger NVSearchMaximumDisplayedRanges = 1024;
@interface Editor : NSObject { @public BOOL searchHighlightsInvalidated, hasSearchHighlights; NSTextStorage *storage; NSLayoutManager *layout; }
- (void)invalidateSearchHighlights;
- (void)removeHighlightedTerms;
- (void)setSearchHighlightRanges:(NSArray *)ranges;
@end
@implementation Editor
- (id)init { if((self=[super init])){storage=[[NSTextStorage alloc]initWithString:@"alpha beta gamma"];layout=[[NSLayoutManager alloc]init];[storage addLayoutManager:layout];}return self; }
- (NSString *)string { return [storage string]; }
- (NSTextStorage *)textStorage { return storage; }
- (NSLayoutManager *)layoutManager { return layout; }
- (NSDictionary *)currentSearchHighlightAttributes { return @{NSBackgroundColorAttributeName:[NSColor yellowColor]}; }
#include "editor.inc"
- (void)dealloc { ++Destroyed; [NSObject cancelPreviousPerformRequestsWithTarget:self];[storage removeLayoutManager:layout];[storage release];[layout release];[super dealloc]; }
@end
@interface Browser : NSObject { @public Editor *textView; NSUInteger searchHighlightGeneration; }
@end
@implementation Browser
#include "observer.inc"
@end
static void Attach(Browser *b, Editor *e) { b->textView=e;[[NSNotificationCenter defaultCenter]addObserver:b selector:@selector(searchSourceStorageWillProcessEditing:) name:NSTextStorageWillProcessEditingNotification object:e->storage]; }
static BOOL HasBackground(Editor *e) { return [[e->layout temporaryAttributesAtCharacterIndex:0 effectiveRange:NULL] objectForKey:NSBackgroundColorAttributeName]!=nil; }
int main(void) { @autoreleasepool {
    Editor *a=[[Editor alloc]init], *b=[[Editor alloc]init];
    [b->storage removeLayoutManager:b->layout];[b->storage release];b->storage=[a->storage retain];[b->storage addLayoutManager:b->layout];
    Browser *ba=[Browser new], *bb=[Browser new]; Attach(ba,a);Attach(bb,b);
    NSArray *ranges=@[[NSValue valueWithRange:NSMakeRange(0,5)]];
    [a setSearchHighlightRanges:ranges];[b setSearchHighlightRanges:ranges];
    Check(HasBackground(a)&&HasBackground(b),"independent layouts initially highlight shared source");
    [a->storage deleteCharactersInRange:NSMakeRange(1,1)];
    Check(ba->searchHighlightGeneration==1&&bb->searchHighlightGeneration==1,"both owners fence callbacks synchronously");
    Check(a->searchHighlightsInvalidated&&b->searchHighlightsInvalidated,"both owners defer cleanup");
    // A switches source before zero-delay cleanup; preserve B's pending cleanup.
    [a removeHighlightedTerms];
    [[NSNotificationCenter defaultCenter]removeObserver:ba];
    NSTextStorage *old=a->storage;[old removeLayoutManager:a->layout];
    a->storage=[[NSTextStorage alloc]initWithString:@"fresh note"];
    [a->storage addLayoutManager:a->layout];[old release];Attach(ba,a);
    [a setSearchHighlightRanges:ranges];
    Check(!a->searchHighlightsInvalidated,"new note accepts current snapshot highlights");
    Pump();
    Check(HasBackground(a),"old note callback does not erase new note highlight");
    Check(!HasBackground(b)&&!b->searchHighlightsInvalidated,"peer removes old backgrounds on its own storage");
    NSUInteger generation=ba->searchHighlightGeneration;
    [b->storage deleteCharactersInRange:NSMakeRange(1,1)];
    Check(ba->searchHighlightGeneration==generation,"detached owner ignores peer mutations");
    Check(bb->searchHighlightGeneration==2,"attached owner advances for peer mutation");
    [b setSearchHighlightRanges:ranges];Pump();
    Check(HasBackground(b),"new snapshot cancels pending old cleanup");
    // Source replacement before callback is also a character notification.
    [b->storage replaceCharactersInRange:NSMakeRange(0,[b->storage length]) withString:@"x"];
    Check(bb->searchHighlightGeneration==3,"replacement fences pending source snapshot");
    Pump();Check(!HasBackground(b),"replacement cleanup uses new source length");
    [[NSNotificationCenter defaultCenter]removeObserver:ba];[[NSNotificationCenter defaultCenter]removeObserver:bb];
    [a invalidateSearchHighlights];[a removeHighlightedTerms];[a release];
    Check(Destroyed==1,"closed owner cancels callback before release");
    [b release];[ba release];[bb release];Pump();
    Check(Destroyed==2,"both editor owners release after callback cancellation");
    printf("PASS: %lu native interleaving checks\n",(unsigned long)Checks);
} return 0; }
