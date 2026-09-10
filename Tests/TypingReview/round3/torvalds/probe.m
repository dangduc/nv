#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include "flags.inc"
static NSUInteger checks, cases, nativeClicks, menuBuilds, menuLinks, internalClicks;
static void Check(BOOL ok, NSString *what) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL case=%lu: %s\n", cases, what.UTF8String); exit(1); }
}
@interface Prefs : NSObject
- (BOOL)URLsAreClickable;
@end
@implementation Prefs
- (BOOL)URLsAreClickable { return YES; }
@end
@interface AppController : NSObject
- (void)interpretNVURL:(id)url;
@end
@implementation AppController
- (void)interpretNVURL:(id)url { internalClicks++; }
@end
static AppController *controller;
static id NVControllerForView(id view) { return controller; }
// Terminal Cocoa action hooks are recorded. No menu or external URL is opened.
@interface ActionBoundary : NSTextView
@end
@implementation ActionBoundary
- (void)clickedOnLink:(id)link atIndex:(NSUInteger)index { nativeClicks++; }
- (NSMenu *)menuForEvent:(NSEvent *)event {
    menuBuilds++; menuLinks=0;
    [[self textStorage] enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,[[self textStorage] length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) { if(value) menuLinks++; }];
    return nil;
}
@end
@interface Editor : ActionBoundary { Prefs *prefsController; }
- (id)highlightLinkAtIndex:(NSUInteger)index;
- (void)setAutomaticallySelectedRange:(NSRange)range;
@end
@implementation Editor
- (id)initWithFrame:(NSRect)frame textContainer:(NSTextContainer *)container {
    if ((self=[super initWithFrame:frame textContainer:container])) prefsController=[Prefs new];
    return self;
}
- (void)setAutomaticallySelectedRange:(NSRange)range { [self setSelectedRange:range]; }
#include "methods.inc"
- (void)dealloc { [prefsController release]; [super dealloc]; }
@end
@interface AnalysisRecorder : NSObject { @public NSUInteger invalidations, requests; }
- (void)invalidate;
- (void)request;
@end
@implementation AnalysisRecorder
- (void)invalidate { invalidations++; }
- (void)request { requests++; }
@end
@interface Session : NSObject {
@public
    NSTextStorage *textStorage;
    AnalysisRecorder *sourceAnalysis;
    uint64_t sourceGeneration;
}
- (id)initWithStorage:(NSTextStorage *)storage;
@end
@implementation Session
- (id)initWithStorage:(NSTextStorage *)storage {
    if ((self=[super init])) {
        textStorage=[storage retain]; sourceAnalysis=[AnalysisRecorder new]; sourceGeneration=1;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sourceCharactersChanged:) name:NSTextStorageDidProcessEditingNotification object:storage];
    }
    return self;
}
#include "invalidate.inc"
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [textStorage release]; [sourceAnalysis release]; [super dealloc]; }
@end
static Editor *NewEditor(NSTextStorage *storage) {
    NSLayoutManager *layout=[NSLayoutManager new];
    NSTextContainer *container=[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(500,500)];
    [layout addTextContainer:container]; [storage addLayoutManager:layout];
    Editor *editor=[[Editor alloc] initWithFrame:NSMakeRect(0,0,500,500) textContainer:container];
    [container release]; [layout release]; return editor;
}
static NSUInteger LinkCount(NSTextStorage *storage) {
    __block NSUInteger count=0;
    [storage enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,storage.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) count++; }];
    return count;
}
static void Exercise(NSString *source) {
    cases++;
    NSTextStorage *old=[[NSTextStorage alloc] initWithString:source];
    Session *session=[[Session alloc] initWithStorage:old];
    Editor *a=NewEditor(old), *b=NewEditor(old);
    NSURL *url=[NSURL URLWithString:@"https://example.invalid/stale"];
    if (old.length) [old addAttribute:NSLinkAttributeName value:url range:NSMakeRange(0,old.length)];
    [old addAttribute:@"ProbeKeep" value:@"kept" range:NSMakeRange(0,old.length)];
    NVSetSourceLinksCurrent(old, YES);
    // The real session notification method invalidates every attached editor.
    [old replaceCharactersInRange:NSMakeRange(old.length,0) withString:@"x"];
    Check(session->sourceGeneration==2 && session->sourceAnalysis->invalidations==1 && session->sourceAnalysis->requests==1,@"native edit invokes exact production invalidation once");
    Check(!NVSourceLinksAreCurrent(old),@"native edit makes shared links stale");
    NSUInteger length=old.length;
    NSUInteger indexes[]={0,length-1,length,NSNotFound,NSUIntegerMax};
    for (Editor *editor in @[a,b]) {
        for (NSUInteger k=0;k<5;k++) {
            NSUInteger index=indexes[k]; [editor setSelectedRange:NSMakeRange(0,0)];
            Check([editor highlightLinkAtIndex:index]==nil,@"stale highlight must reject target");
            Check(NSEqualRanges(editor.selectedRange,NSMakeRange(0,0)),@"stale highlight preserves selection");
            NSUInteger before=nativeClicks+internalClicks;
            [editor clickedOnLink:url atIndex:index];
            [editor clickedOnLink:[NSURL URLWithString:@"nvalt://find/stale"] atIndex:index];
            Check(nativeClicks+internalClicks==before,@"stale clicks cannot reach external or internal action boundary");
            Check(NSEqualRanges(editor.selectedRange,NSMakeRange(MIN(index,length),0)),@"stale caret clamps to source length");
        }
    }
    NSString *saved=[[old string] copy];
    NSUInteger menuBefore=menuBuilds;
    [a menuForEvent:nil];
    Check(menuBuilds==menuBefore+1 && menuLinks==0,@"superclass menu boundary sees zero obsolete targets");
    Check(LinkCount(old)==0 && [[old string] isEqual:saved],@"menu cleanup preserves shared source");
    if(source.length) Check([[old attribute:@"ProbeKeep" atIndex:0 effectiveRange:NULL] isEqual:@"kept"],@"menu cleanup preserves unrelated attribute");
    [saved release];
    // Move one native layout, as note switching does; the peer retains old storage.
    NSTextStorage *fresh=[[NSTextStorage alloc] initWithString:@"new link"];
    [fresh addAttribute:NSLinkAttributeName value:url range:NSMakeRange(0,fresh.length)];
    NVSetSourceLinksCurrent(fresh,YES);
    NSLayoutManager *layout=[[a layoutManager] retain];
    [old removeLayoutManager:layout]; [fresh addLayoutManager:layout]; [layout release];
    Check(a.textStorage==fresh && b.textStorage==old,@"layout attachment remains local to one editor");
    Check([a highlightLinkAtIndex:NSUIntegerMax]==url,@"current new storage clamps highlight index and returns new link");
    Check([b highlightLinkAtIndex:0]==nil,@"peer remains blocked on old stale storage");
    NSUInteger before=nativeClicks; [a clickedOnLink:url atIndex:0];
    Check(nativeClicks==before+1,@"current external target reaches action boundary");
    before=internalClicks; [a clickedOnLink:[NSURL URLWithString:@"nvalt://find/current"] atIndex:0];
    Check(internalClicks==before+1,@"current internal target reaches controller boundary");
    [a menuForEvent:nil]; Check(menuLinks==1 && LinkCount(fresh)==1,@"current menu preserves current links");
    [fresh replaceCharactersInRange:NSMakeRange(0,fresh.length) withString:@""];
    for(NSUInteger k=0;k<5;k++) Check([a highlightLinkAtIndex:indexes[k]]==nil,@"current empty storage has no index underflow");
    NVSetSourceLinksCurrent(fresh,NO);
    for(NSUInteger k=0;k<5;k++) {
        [a clickedOnLink:url atIndex:indexes[k]];
        Check(NSEqualRanges(a.selectedRange,NSMakeRange(0,0)),@"empty stale click remains in bounds");
    }
    [a menuForEvent:nil]; Check(menuLinks==0,@"empty stale menu remains safe");
    [a release]; [b release]; [session release]; [old release]; [fresh release];
}
int main(void) { @autoreleasepool {
    controller=[AppController new];
    for(NSUInteger i=0;i<80;i++) { @autoreleasepool {
        Exercise(@[@"abcdef",@"🪻é中👩‍💻\r\n",@"",@"x"][i%4]);
    }}
    [controller release];
    printf("PASS: %lu native shared-storage cases; %lu checks; %lu current external and %lu current internal actions; %lu menu boundaries\n",cases,checks,nativeClicks,internalClicks,menuBuilds);
} return 0; }
