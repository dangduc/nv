#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVSourceAnalysis.h"
NSString *const NVNoteWordCountDidChangeNotification = @"ProbeWordCount";
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && end.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return condition();
}
@interface FixtureNote : NSObject { @public NSString *syntax; }
@end
@implementation FixtureNote
- (NSString *)sourceSyntaxIdentifier { return syntax; }
@end
@interface Session : NSObject <NVSourceAnalysisDelegate> {
@public
    BOOL closed;
    uint64_t sourceGeneration, wordCountGeneration;
    NSTextStorage *textStorage;
    FixtureNote *note;
    NVSourceAnalysis *sourceAnalysis;
    NSHashTable *wordCountClients;
    NSUInteger wordCount;
    id sourceHighlighter;
}
@end
@implementation Session
#include "session.inc"
@end
@interface ObservedSession : Session { @public NSUInteger captures, publications; }
@end
@implementation ObservedSession
- (NSDictionary *)snapshotForSourceAnalysis:(NVSourceAnalysis *)analysis {
    captures++; return [super snapshotForSourceAnalysis:analysis];
}
- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:(NSDictionary *)result {
    publications++; [super sourceAnalysis:analysis didFinish:result];
}
@end

// A one-shot boundary hook executes a legal main-thread event immediately
// before the actual production completion. Nothing is inserted into publication.
static IMP originalFinish;
static void (^beforeDelivery)(void);
static NSUInteger deliveries;
static void Finish(id owner, SEL selector, id ticket, NSDictionary *result) {
    Check([NSThread isMainThread],@"completion runs on main");
    deliveries++;
    if (beforeDelivery) {
        void (^action)(void) = beforeDelivery;
        beforeDelivery=nil;
        action();
        [action release];
    }
    ((void (*)(id,SEL,id,NSDictionary *))originalFinish)(owner,selector,ticket,result);
}
static ObservedSession *NewSession(NSUInteger layouts) {
    ObservedSession *s=[[ObservedSession alloc] init];
    s->note=[[FixtureNote alloc] init]; s->note->syntax=@"plain";
    s->textStorage=[[NSTextStorage alloc] initWithString:@"https://example.com/old"];
    s->sourceAnalysis=[[NVSourceAnalysis alloc] initWithDelegate:s];
    s->wordCountClients=[[NSHashTable weakObjectsHashTable] retain];
    s->sourceGeneration=1;
    NVSetSourceLinksCurrent(s->textStorage,NO);
    [[NSNotificationCenter defaultCenter] addObserver:s selector:@selector(sourceCharactersChanged:) name:NSTextStorageDidProcessEditingNotification object:s->textStorage];
    for (NSUInteger i=0;i<layouts;i++) {
        NSLayoutManager *layout=[[NSLayoutManager alloc] init];
        [s->textStorage addLayoutManager:layout]; [layout release];
    }
    return s;
}
static void RemoveLayout(ObservedSession *s) {
    [s->textStorage removeLayoutManager:[[s->textStorage layoutManagers] lastObject]];
    [s sourceLayoutDidDetach];
}
static void Destroy(ObservedSession *s) {
    [s->sourceAnalysis close];
    [[NSNotificationCenter defaultCenter] removeObserver:s];
    [s->sourceAnalysis release]; [s->wordCountClients release];
    [s->textStorage release]; [s->note release]; [s release];
}
static void TestLastDetach(void) {
    ObservedSession *s=NewSession(1);
    NSUInteger initial=deliveries;
    beforeDelivery=[^{ RemoveLayout(s); } copy];
    [s->sourceAnalysis request];
    Check(Await(^BOOL{return deliveries>initial;}),@"worker finishes before last-layout assertion");
    Check(s->publications==0 && !NVSourceLinksAreCurrent(s->textStorage),@"last detached layout cancels queued publication");
    Check(![s snapshotForSourceAnalysis:s->sourceAnalysis],@"detached source cannot produce a snapshot");
    NSLayoutManager *layout=[[NSLayoutManager alloc] init];
    [s->textStorage addLayoutManager:layout]; [layout release];
    [s->sourceAnalysis request];
    Check(Await(^BOOL{return s->publications==1;}),@"reattached source eventually publishes");
    Check(NVSourceLinksAreCurrent(s->textStorage),@"reattachment restores current links");
    Destroy(s);
}
static void TestPeerRemains(void) {
    ObservedSession *s=NewSession(2);
    beforeDelivery=[^{ RemoveLayout(s); } copy];
    [s->sourceAnalysis request];
    Check(Await(^BOOL{return s->publications==1;}),@"one remaining layout receives queued publication");
    Check(s->captures==1 && NVSourceLinksAreCurrent(s->textStorage),@"peer detach does not restart valid analysis");
    Destroy(s);
}
static void TestABA(void) {
    ObservedSession *s=NewSession(2);
    beforeDelivery=[^{
        [s->textStorage replaceCharactersInRange:NSMakeRange(20,3) withString:@"new"];
        [s->textStorage replaceCharactersInRange:NSMakeRange(20,3) withString:@"old"];
        Check(s->sourceGeneration==3,@"native edits advance generation despite identical final source");
        Check(!NVSourceLinksAreCurrent(s->textStorage),@"ABA character edits suppress stale links immediately");
    } copy];
    [s->sourceAnalysis request];
    Check(Await(^BOOL{return s->publications==1;}),@"ABA edits eventually publish replacement work");
    Check(s->captures==2,@"ABA result is canceled and latest generation recaptured");
    Check(NVSourceLinksAreCurrent(s->textStorage),@"latest ABA result restores current links");
    Destroy(s);
}
static void TestSyntaxABA(void) {
    ObservedSession *s=NewSession(1);
    beforeDelivery=[^{
        s->note->syntax=@"org"; [s sourceSyntaxChanged:nil];
        s->note->syntax=@"plain"; [s sourceSyntaxChanged:nil];
    } copy];
    [s->sourceAnalysis request];
    Check(Await(^BOOL{return s->publications==1;}),@"syntax ABA eventually publishes");
    Check(s->captures==2 && NVSourceLinksAreCurrent(s->textStorage),@"syntax ABA cancels old ticket without changing character generation");
    Destroy(s);
}
static void TestClose(void) {
    ObservedSession *s=NewSession(1);
    NSUInteger initial=deliveries;
    beforeDelivery=[^{ s->closed=YES; [s->sourceAnalysis close]; } copy];
    [s->sourceAnalysis request];
    Check(Await(^BOOL{return deliveries>initial;}),@"close occurs at queued completion boundary");
    Check(s->publications==0 && !NVSourceLinksAreCurrent(s->textStorage),@"closed analysis rejects completed work");
    Destroy(s);
}
int main(void) { @autoreleasepool {
    Method method=class_getInstanceMethod([NVSourceAnalysis class],NSSelectorFromString(@"finishTicket:result:"));
    originalFinish=method_setImplementation(method,(IMP)Finish);
    TestLastDetach(); TestPeerRemains(); TestABA(); TestSyntaxABA(); TestClose();
    method_setImplementation(method,originalFinish);
    printf("PASS: %lu checks; last-layout detach, peer detach, reattach, character ABA, syntax ABA, queued close\n",checks);
} return 0; }
