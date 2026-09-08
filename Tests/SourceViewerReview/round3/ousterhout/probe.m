#import <Cocoa/Cocoa.h>
#import "PreviewController.h"
#import "NVMarkupRenderer.h"
static NSUInteger Checks;
static void Check(BOOL value, NSString *label) { Checks++; if (!value) { fprintf(stderr, "FAIL: %s\n", [label UTF8String]); exit(1); } }
static NVNoteContentSnapshot *Snap(NSString *library, NSString *note, NSUInteger generation) {
    return [[[NVNoteContentSnapshot alloc] initWithLibraryIdentifier:library noteIdentifier:note generation:generation title:note source:@"source" contentType:@"html" assetRootURL:nil] autorelease];
}
// Substitute the asynchronous I/O and native field boundaries, keeping the
// complete production capture, display, restoration, Find, and close methods.
@interface Field : NSObject { NSString *text; }
@end
@implementation Field
- (void)setStringValue:(NSString *)value { [text release]; text = [value copy]; }
- (NSString *)stringValue { return text ?: @""; }
- (void)setHidden:(BOOL)hidden {}
- (void)dealloc { [text release]; [super dealloc]; }
@end
@interface Web : NSObject { @public NSMutableArray *replies; }
@end
@implementation Web
- (id)init { if ((self = [super init])) replies = [NSMutableArray new]; return self; }
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id,NSError *))completion { if (completion) [replies addObject:[[completion copy] autorelease]]; }
- (void)findString:(NSString *)query withConfiguration:(id)configuration completionHandler:(id)completion {}
- (void)stopLoading {}
- (void)setHidden:(BOOL)value {}
- (void)setNavigationDelegate:(id)value {}
- (void)setUIDelegate:(id)value {}
- (id)configuration { return nil; }
- (void)removeFromSuperview {}
- (void)dealloc { [replies release]; [super dealloc]; }
@end
@interface Renderer : NSObject
@end
@implementation Renderer
- (NSOperation *)renderSnapshot:(id)snapshot viewerIdentifier:(id)identifier completion:(id)completion { return nil; }
- (void)cancelAllRendering {}
@end
@interface Fixture : PreviewController
- (void)prepare;
- (void)find:(NSString *)query;
@end
@implementation Fixture
- (NSView *)view { return nil; }
- (void)prepare {
    _webView = (id)[Web new]; _findField = (id)[Field new]; _statusField = (id)[Field new];
    [_renderer release]; _renderer = (id)[Renderer new];
    _snapshot = [Snap(@"library", @"A", 1) retain];
    [_viewerIdentifier release]; _viewerIdentifier = [@"html" copy];
    _documentBaseURL = [[NSURL URLWithString:@"nvalt-asset://controlled/"] retain];
    _renderResult = [[NVMarkupRenderResult alloc] initWithSnapshot:_snapshot viewerIdentifier:@"html" HTML:@"<p>source</p>"];
}
- (void)find:(NSString *)query { [(id)_findField setStringValue:query]; [self performSelector:NSSelectorFromString(@"findNext:") withObject:_findField]; }
@end
static Fixture *New(void) { Fixture *v = [Fixture new]; [v prepare]; [v restoreViewerState:@{@"scrollY":@100,@"find":@"original"}]; return v; }
static void Reply(Fixture *v, NSUInteger index, NSNumber *y) { Web *w = (id)[v webView]; void (^reply)(id,NSError *) = [w->replies objectAtIndex:index]; reply(@[@"nvalt-asset://controlled/",@0,y],nil); }
static void Returns(Fixture *v, NSUInteger generation) {
    [v displaySnapshot:Snap(@"library", @"B", generation-1) viewerIdentifier:@"html"];
    [v displaySnapshot:Snap(@"library", @"A", generation) viewerIdentifier:@"html"];
}
int main(void) { @autoreleasepool {
    for (NSUInteger scenario = 0; scenario < 3; scenario++) {
        Fixture *v = New(); __block NSUInteger callbacks=0; __block NSUInteger nested=0;
        for (NSUInteger i=0;i<4;i++) {
            if (i) Returns(v, i*2+1);
            NSUInteger expectedGeneration=i*2+1;
            [v captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
                callbacks++;
                Check([snapshot generation] == expectedGeneration && [[snapshot noteIdentifier] isEqual:@"A"] && [identifier isEqual:@"html"], @"each joined caller receives its own call-time generation and identity");
                Check([[state objectForKey:@"scrollY"] doubleValue] == 420, @"joined exact result remains immutable across callback side effects");
                if (i == 0) {
                    if (scenario == 0) [v restoreViewerState:@{@"scrollY":@777,@"find":@"restored inside callback"}];
                    else if (scenario == 1) [v close];
                    else [v captureViewerStateWithCompletion:^(NVNoteContentSnapshot *s,NSString *viewer,NSDictionary *st) { nested++; Check([s generation] == 7 && [[st objectForKey:@"scrollY"] doubleValue] == 420, @"reentrant capture sees current canonical state and current snapshot"); }];
                }
            }];
        }
        Check(((Web *)[v webView])->replies.count == 1, @"four caller generations share a single controlled WebKit read");
        Reply(v,0,@420); Reply(v,0,@999);
        Check(callbacks == 4, @"close, restore, or nested capture inside callback cannot repeat or suppress joined delivery");
        if (scenario == 0) Check([[[v viewerState] objectForKey:@"scrollY"] doubleValue] == 777 && [[[v viewerState] objectForKey:@"find"] isEqual:@"restored inside callback"], @"explicit restore in first callback survives remaining joined completions");
        if (scenario == 1) Check([v snapshot] == nil && ![v loading], @"close from callback remains terminal");
        if (scenario == 2) Check(nested==1, @"nested loading capture completes once without extending old group");
        [v close]; [v release];
    }
    Fixture *v=New(); __block NSUInteger first=0,other=0;
    [v captureViewerStateWithCompletion:^(id snapshot,id viewer,id state){ first++; }];
    [v displaySnapshot:Snap(@"other-library",@"A",2) viewerIdentifier:@"html"];
    [v restoreViewerState:@{@"scrollY":@234,@"find":@"other library"}];
    [v captureViewerStateWithCompletion:^(NVNoteContentSnapshot *s,NSString *viewer,NSDictionary *state){ other++; Check([[s libraryIdentifier] isEqual:@"other-library"] && [[state objectForKey:@"scrollY"] doubleValue]==234, @"same note name in another library uses independent cached state"); }];
    Reply(v,0,@420); Check(first==1 && other==1 && [[[v viewerState] objectForKey:@"scrollY"] doubleValue]==234,@"old library reply cannot enter current canonical state");
    [v close]; [v release];
    v=New(); __block NSDictionary *joinedState=nil;
    [v captureViewerStateWithCompletion:^(id s,id viewer,NSDictionary *state){ Check([[state objectForKey:@"find"] isEqual:@"original"], @"initial caller retains its original query"); }];
    [v find:@"newer query"];
    Check([[[v viewerState] objectForKey:@"find"] isEqual:@"newer query"], @"production Find action updates canonical state after the first capture starts");
    // This is the production same-note refresh operation, as used after an edit
    // in another browser. The queued renderer boundary keeps it loading.
    [v displaySnapshot:Snap(@"library",@"A",2) viewerIdentifier:@"html"];
    [v captureViewerStateWithCompletion:^(NVNoteContentSnapshot *s,id viewer,NSDictionary *state){ joinedState=[state copy]; Check([s generation]==2,@"loading refresh joined caller has its own current generation"); }];
    Reply(v,0,@420);
    Check([[[v viewerState] objectForKey:@"find"] isEqual:@"newer query"],@"provider canonical query survives the old exact read");
    printf("Joined capture: query at call = newer query; callback query = %s; provider query = %s\n", [[joinedState objectForKey:@"find"] UTF8String], [[[v viewerState] objectForKey:@"find"] UTF8String]);
    BOOL losesNewQuery=![[joinedState objectForKey:@"find"] isEqual:@"newer query"];
    printf("%s: joined caller %s its own current Find state. %lu checks passed.\n", losesNewQuery?"OBSERVED":"REJECTED", losesNewQuery?"loses":"retains", (unsigned long)Checks);
    [joinedState release]; [v close]; [v release];
    return losesNewQuery ? 2 : 0;
} }
