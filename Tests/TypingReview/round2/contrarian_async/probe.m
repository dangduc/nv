#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "AttributedPlainText.h"
#import "NVSourceAnalysis.h"
NSString * const NVNoteWordCountDidChangeNotification = @"ProbeWordCount";
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) {
    checks++; if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
    printf("PASS: %s\n",message.UTF8String);
}
static void Pump(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.18]]; }
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return condition();
}
static atomic_bool gateNext, entered;
static dispatch_semaphore_t gate;
static IMP decoration;
static void Gated(id self, SEL cmd, NSRange range, NSString *syntax) {
    if (atomic_exchange(&gateNext,false)) {
        atomic_store(&entered,true);
        if (dispatch_semaphore_wait(gate,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))) abort();
    }
    ((void(*)(id,SEL,NSRange,NSString*))decoration)(self,cmd,range,syntax);
}
static void Arm(void) { atomic_store(&entered,false); atomic_store(&gateNext,true); }
@interface Note : NSObject
@end
@implementation Note
- (NSString *)sourceSyntaxIdentifier { return @"plain"; }
@end
@interface Session : NSObject <NVSourceAnalysisDelegate> {
@public BOOL closed; uint64_t sourceGeneration,wordCountGeneration;
    NSTextStorage *textStorage; Note *note; NVSourceAnalysis *sourceAnalysis;
    NSHashTable *wordCountClients; NSUInteger wordCount;
}
- (id)initWithString:(NSString *)string;
- (void)setWordCountRequested:(BOOL)requested forTextView:(NSTextView *)view;
- (BOOL)getWordCount:(NSUInteger *)count;
@end
@implementation Session
- (id)initWithString:(NSString *)string {
    if ((self=[super init])) {
        sourceGeneration=1; note=[Note new]; textStorage=[[NSTextStorage alloc] initWithString:string];
        [textStorage addLayoutManager:[[[NSLayoutManager alloc] init] autorelease]];
        sourceAnalysis=[[NVSourceAnalysis alloc] initWithDelegate:self];
        wordCountClients=[[NSHashTable weakObjectsHashTable] retain];
        NVSetSourceLinksCurrent(textStorage,NO);
    } return self;
}
#include "session.inc"
- (void)dealloc { [sourceAnalysis close]; [sourceAnalysis release]; [wordCountClients release]; [textStorage release]; [note release]; [super dealloc]; }
@end
@interface Label : NSObject { @public BOOL hidden; NSString *value; }
@end
@implementation Label
- (BOOL)isHidden { return hidden; }
- (NSString *)stringValue { return value ?: @""; }
- (void)setStringValue:(NSString *)s { [value release];value=[s copy]; }
- (void)dealloc { [value release];[super dealloc]; }
@end
// These are the exact production AppController observer methods. A label and
// an identity-only view replace UI objects; NSTextStorage and analysis are real.
@interface Controller : NSObject { @public Session *editingSession; id textView; Label *wordCounter; }
- (void)updateWordCount:(BOOL)doIt;
- (void)sourceWordCountDidChange:(NSNotification *)notification;
@end
@implementation Controller
- (id)init { if ((self=[super init])) { textView=[NSObject new];wordCounter=[Label new]; } return self; }
#include "controller.inc"
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self];[textView release];[wordCounter release];[super dealloc]; }
@end
static NSUInteger captures;
static IMP snapshot;
static NSDictionary *Capture(id self,SEL cmd,NVSourceAnalysis *analysis) {
    captures++; return ((id(*)(id,SEL,id))snapshot)(self,cmd,analysis);
}
static Controller *Attach(Session *session) { Controller *c=[Controller new];c->editingSession=session;return c; }
static void StartGate(Session *s) { Arm();[s->sourceAnalysis request];Check(Await(^BOOL{return atomic_load(&entered);}),@"real link worker reaches capture boundary"); }
static void CheckInterestAdded(void) {
    Session *s=[[Session alloc] initWithString:@"one two three"];
    Controller *c=Attach(s);StartGate(s);[c updateWordCount:YES];
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL{return s->wordCountGeneration==1;}),@"interest added after links-only capture eventually receives words");
    Check([c->wordCounter.stringValue isEqual:@"3 words"],@"late interest renders the computed count");
    [c updateWordCount:NO];[c release];[s release];Pump();
}
static void CheckInterestRemoved(void) {
    Session *s=[[Session alloc] initWithString:@"one two three four"];
    Controller *c=Attach(s);__block NSUInteger notices=0;
    id token=[[NSNotificationCenter defaultCenter] addObserverForName:NVNoteWordCountDidChangeNotification object:s queue:nil usingBlock:^(id n){notices++;}];
    Arm();[c updateWordCount:YES];Check(Await(^BOOL{return atomic_load(&entered);}),@"word-interested capture reaches barrier");
    [c updateWordCount:NO];c->wordCounter->hidden=YES;dispatch_semaphore_signal(gate);Pump();
    Check(notices==0 && s->wordCountGeneration==0,@"removing last interest suppresses late word publication");
    c->wordCounter->hidden=NO;[c updateWordCount:YES];
    Check(Await(^BOOL{return s->wordCountGeneration==1;}),@"reenabling after discarded completion recovers count");
    Check(notices==1 && [c->wordCounter.stringValue isEqual:@"4 words"],@"reenabled observer receives one current notification");
    [c updateWordCount:NO];[[NSNotificationCenter defaultCenter] removeObserver:token];[c release];[s release];Pump();
}
static void CheckSharedAndReentrant(void) {
    Session *s=[[Session alloc] initWithString:@"one two"];
    Controller *a=Attach(s),*b=Attach(s);Arm();[a updateWordCount:YES];[b updateWordCount:YES];
    Check(Await(^BOOL{return atomic_load(&entered);}),@"shared client capture reaches barrier");
    [a updateWordCount:NO];a->wordCounter->hidden=YES;dispatch_semaphore_signal(gate);
    Check(Await(^BOOL{return s->wordCountGeneration==1;}),@"remaining client preserves shared count demand");
    Check([a->wordCounter.stringValue isEqual:@""] && [b->wordCounter.stringValue isEqual:@"2 words"],@"unsubscribed hidden client receives no late count label");
    NSUInteger before=captures;for(NSUInteger i=0;i<100;i++){[b updateWordCount:NO];[b updateWordCount:YES];}Pump();
    Check(captures==before,@"100 off/on transitions reuse an already-current count");
    Session *other=[[Session alloc] initWithString:@"other"];
    [b sourceWordCountDidChange:[NSNotification notificationWithName:NVNoteWordCountDidChangeNotification object:other]];
    Check([b->wordCounter.stringValue isEqual:@"2 words"],@"notification for another session does not alter active label");
    [a release];[b updateWordCount:NO];[b release];[s release];[other release];Pump();
}
static void CheckToggleInFlight(void) {
    Session *s=[[Session alloc] initWithString:@"one two three"];
    Controller *c=Attach(s);Arm();[c updateWordCount:YES];Check(Await(^BOOL{return atomic_load(&entered);}),@"toggle test reaches barrier");
    NSUInteger before=captures;
    for(NSUInteger i=0;i<100;i++){[c updateWordCount:NO];[c updateWordCount:YES];}
    dispatch_semaphore_signal(gate);Check(Await(^BOOL{return s->wordCountGeneration==1;}),@"in-flight off/on churn publishes the still-current source");Pump();
    Check(captures==before+1,@"coalesced redundant follow-up makes one nil snapshot and stops");
    [c updateWordCount:NO];[c release];[s release];Pump();
}
static void CheckEmptyAndUnavailable(void) {
    Session *s=[[Session alloc] initWithString:@""];Controller *c=Attach(s);[c updateWordCount:YES];
    Check(Await(^BOOL{return s->wordCountGeneration==1;}),@"empty source accepts zero word count");
    NSUInteger count=99;Check([s getWordCount:&count] && count==0 && [c->wordCounter.stringValue isEqual:@""],@"zero is a valid cached count with an empty label");
    NSUInteger before=captures;for(NSUInteger i=0;i<100;i++)[c updateWordCount:YES];Pump();Check(captures==before,@"empty-source repeated demand does not reschedule work");
    [c updateWordCount:NO];[c release];[s release];
    s=[[Session alloc] initWithString:@"one two"];c=Attach(s);
    NSLayoutManager *layout=[[s->textStorage.layoutManagers firstObject] retain];[s->textStorage removeLayoutManager:layout];
    before=captures;[c updateWordCount:YES];Pump();
    Check(captures==before+1 && s->wordCountGeneration==0,@"detached source returns nil once and remains idle");
    Pump();Check(captures==before+1,@"nil-snapshot demand does not spin");
    [s->textStorage addLayoutManager:layout];[layout release];[s->sourceAnalysis request];
    Check(Await(^BOOL{return s->wordCountGeneration==1;}),@"reattachment demand recovers from unavailable snapshot");
    [c updateWordCount:NO];[c release];[s release];Pump();
}
int main(void) { @autoreleasepool {
    gate=dispatch_semaphore_create(0);
    Method m=class_getInstanceMethod([NSMutableAttributedString class],@selector(addLinkAttributesForRange:syntaxIdentifier:));
    decoration=method_setImplementation(m,(IMP)Gated);
    Method sm=class_getInstanceMethod([Session class],@selector(snapshotForSourceAnalysis:));snapshot=method_setImplementation(sm,(IMP)Capture);
    CheckInterestAdded();CheckInterestRemoved();CheckSharedAndReentrant();CheckToggleInFlight();CheckEmptyAndUnavailable();
    method_setImplementation(sm,snapshot);method_setImplementation(m,decoration);dispatch_release(gate);
    printf("PASS: %lu assertions across 6 demand/observer transition cases\n",(unsigned long)checks);
} return 0; }
