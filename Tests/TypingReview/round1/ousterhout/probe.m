#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "NVSourceAnalysis.h"
#import "AttributedPlainText.h"

NSString * const NVNoteWordCountDidChangeNotification = @"NVNoteWordCountDidChange";
static NSUInteger checks;
static void Check(BOOL condition, NSString *label) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", [label UTF8String]); exit(1); }
    checks++; printf("PASS: %s\n", [label UTF8String]);
}
static BOOL Await(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return condition();
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];
}

@interface ReviewNote : NSObject { @public NSString *syntax; }
- (NSString *)sourceSyntaxIdentifier;
@end
@implementation ReviewNote
- (id)init { if ((self = [super init])) syntax = [@"plain" retain]; return self; }
- (NSString *)sourceSyntaxIdentifier { return syntax; }
- (void)dealloc { [syntax release]; [super dealloc]; }
@end

// This review isolates link/count analysis, so syntax colors and font refresh
// have no behavior. Storage and layout-manager membership remain real Cocoa.
@interface ReviewHighlighter : NSObject
- (id)initWithTextStorage:(NSTextStorage *)storage syntaxIdentifier:(NSString *)syntax;
- (void)layoutsChanged;
- (void)setSyntaxIdentifier:(NSString *)syntax;
- (void)close;
@end
@implementation ReviewHighlighter
- (id)initWithTextStorage:(NSTextStorage *)storage syntaxIdentifier:(NSString *)syntax { return [super init]; }
- (void)layoutsChanged {}
- (void)setSyntaxIdentifier:(NSString *)syntax {}
- (void)close {}
@end

@interface ReviewView : NSObject { @public NSTextStorage *storage; NSLayoutManager *layout; }
- (NSTextStorage *)textStorage;
- (NSLayoutManager *)layoutManager;
@end
@implementation ReviewView
- (NSTextStorage *)textStorage { return storage; }
- (NSLayoutManager *)layoutManager { return layout; }
@end

@interface ReviewSession : NSObject <NVSourceAnalysisDelegate> {
@public
    ReviewNote *note;
    NSTextStorage *textStorage;
    uint64_t sourceGeneration;
    NVSourceAnalysis *sourceAnalysis;
    NSHashTable *wordCountClients;
    NSUInteger wordCount;
    uint64_t wordCountGeneration;
    BOOL closed;
    ReviewHighlighter *sourceHighlighter;
}
- (id)initWithString:(NSString *)source;
- (void)refreshSourceFont;
- (void)sourceCharactersChanged:(NSNotification *)notification;
- (void)sourceSyntaxChanged:(NSNotification *)notification;
- (void)sourceLayoutDidAttach;
- (void)sourceLayoutDidDetach;
- (void)setWordCountRequested:(BOOL)requested forTextView:(NSTextView *)view;
- (BOOL)getWordCount:(NSUInteger *)count;
- (void)close;
@end
@implementation ReviewSession
- (id)initWithString:(NSString *)source {
    if ((self = [super init])) {
        note = [[ReviewNote alloc] init];
        textStorage = [[NSTextStorage alloc] initWithString:source];
        sourceGeneration = 1;
        sourceAnalysis = [[NVSourceAnalysis alloc] initWithDelegate:self];
        wordCountClients = [[NSHashTable weakObjectsHashTable] retain];
        NVSetSourceLinksCurrent(textStorage, NO);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sourceCharactersChanged:)
            name:NSTextStorageDidProcessEditingNotification object:textStorage];
    }
    return self;
}
- (void)refreshSourceFont {}
#include "session.inc"
- (void)close { closed = YES; [sourceAnalysis close]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)dealloc {
    [self close]; [sourceAnalysis release]; [wordCountClients release];
    [sourceHighlighter release]; [textStorage release]; [note release]; [super dealloc];
}
@end

@interface TrackedSession : ReviewSession { @public NSUInteger captures, finishes, wordNotifications; NSMutableArray *flags; }
@end
@implementation TrackedSession
- (id)initWithString:(NSString *)source {
    if ((self = [super initWithString:source])) {
        flags = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(countChanged:)
            name:NVNoteWordCountDidChangeNotification object:self];
    }
    return self;
}
- (NSDictionary *)snapshotForSourceAnalysis:(NVSourceAnalysis *)analysis {
    NSDictionary *snapshot = [super snapshotForSourceAnalysis:analysis];
    if (snapshot) { captures++; [flags addObject:@[snapshot[@"links"], snapshot[@"words"]]]; }
    return snapshot;
}
- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:(NSDictionary *)result {
    finishes++; [super sourceAnalysis:analysis didFinish:result];
}
- (void)countChanged:(NSNotification *)notification { wordNotifications++; }
- (void)dealloc { [flags release]; [super dealloc]; }
@end

static atomic_bool gateNext, entered;
static dispatch_semaphore_t gate;
static IMP decorate;
static void GatedDecoration(id receiver, SEL selector, NSRange range, NSString *syntax) {
    if (atomic_exchange(&gateNext, false)) {
        atomic_store(&entered, true);
        if (dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC))) abort();
    }
    ((void (*)(id, SEL, NSRange, NSString *))decorate)(receiver, selector, range, syntax);
}
static void Arm(void) { atomic_store(&entered, false); atomic_store(&gateNext, true); }
static ReviewView *Attach(TrackedSession *session) {
    ReviewView *view = [[ReviewView alloc] init];
    view->storage = session->textStorage;
    view->layout = [[NSLayoutManager alloc] init];
    [session->textStorage addLayoutManager:view->layout];
    [session sourceLayoutDidAttach];
    return view;
}
static void Detach(TrackedSession *session, ReviewView *view) {
    [session->textStorage removeLayoutManager:view->layout];
    [session sourceLayoutDidDetach];
    [view->layout release]; view->layout = nil; view->storage = nil;
}
static NSArray *StoredLinks(TrackedSession *session) {
    NSMutableArray *runs = [NSMutableArray array];
    [session->textStorage enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, session->textStorage.length)
        options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value) [runs addObject:@{@"range": [NSValue valueWithRange:range], @"url": value}];
        }];
    return runs;
}

static void SubscribersWhileRunning(void) {
    TrackedSession *session = [[TrackedSession alloc] initWithString:@"one two https://example.com"];
    Arm(); ReviewView *first = Attach(session), *second = Attach(session);
    Check(Await(^BOOL { return atomic_load(&entered); }), @"link-only job reaches worker gate");
    [session setWordCountRequested:YES forTextView:(id)first];
    [session setWordCountRequested:YES forTextView:(id)second];
    [session setWordCountRequested:NO forTextView:(id)first];
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL { return session->wordNotifications == 1; }), @"second subscriber receives count after first unsubscribes");
    Check(session->captures == 2 && [session->flags isEqual:@[@[@YES, @NO], @[@NO, @YES]]],
          @"late interest schedules one word-only follow-up after link acceptance");
    NSUInteger count = 0;
    Check([session getWordCount:&count] && count == NVSourceWordCount([session->textStorage string]),
          @"shared count equals Cocoa word rules");
    Check([StoredLinks(session) isEqual:NVSourceLinkRuns(session->textStorage.string, @"plain")],
          @"accepted links equal the complete immutable snapshot");
    Detach(session, second);
    Check([session->wordCountClients count] == 0, @"detaching interested view removes its weak subscriber");
    NSUInteger before = session->wordNotifications;
    [session->textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"extra "];
    Check(Await(^BOOL { return NVSourceLinksAreCurrent(session->textStorage); }), @"remaining layout refreshes links without word subscribers");
    Check(session->wordNotifications == before && [[session->flags lastObject] isEqual:@[@YES, @NO]],
          @"hidden count does no new word computation");
    Detach(session, first); [first release]; [second release]; [session close]; [session release];
}

static void GenerationsAndReattachment(void) {
    TrackedSession *session = [[TrackedSession alloc] initWithString:@"https://old.example one"];
    ReviewView *view = Attach(session);
    [session setWordCountRequested:YES forTextView:(id)view];
    Check(Await(^BOOL { return session->wordNotifications == 1; }), @"initial count and links publish");
    Arm();
    [session->textStorage replaceCharactersInRange:NSMakeRange(0, session->textStorage.length)
        withString:@"https://cancelled.example two three"];
    Check(Await(^BOOL { return atomic_load(&entered); }), @"replacement reaches controlled worker gate");
    Check(!NVSourceLinksAreCurrent(session->textStorage), @"character edits invalidate old link actions immediately");
    NSUInteger finishes = session->finishes;
    Detach(session, view);
    [session->textStorage replaceCharactersInRange:NSMakeRange(0, session->textStorage.length)
        withString:@"[[https://final.example][final label]] four five six"];
    [session->note->syntax release]; session->note->syntax = [@"org" retain];
    [session sourceSyntaxChanged:nil];
    ReviewView *returned = Attach(session);
    [session setWordCountRequested:YES forTextView:(id)returned];
    dispatch_semaphore_signal(gate);
    Check(Await(^BOOL { return session->wordNotifications == 2; }), @"reattached subscriber receives newest source and syntax result");
    Check(session->finishes == finishes + 1, @"cancelled detached generation never reaches the delegate");
    Check([StoredLinks(session) isEqual:NVSourceLinkRuns(session->textStorage.string, @"org")],
          @"reattachment applies current Org targets only");
    NSUInteger count;
    Check([session getWordCount:&count] && count == NVSourceWordCount(session->textStorage.string),
          @"word count follows final source generation");
    uint64_t generation = session->sourceGeneration;
    NSDictionary *obsolete = @{@"generation": @(generation - 1), @"syntax": @"org", @"wordCount": @9999,
        @"linkRuns": @[@{@"range": [NSValue valueWithRange:NSMakeRange(0, 1)], @"url": [NSURL URLWithString:@"https://obsolete.example"]}]};
    [session sourceAnalysis:session->sourceAnalysis didFinish:obsolete];
    Check(session->wordCount == count && [StoredLinks(session) isEqual:NVSourceLinkRuns(session->textStorage.string, @"org")],
          @"session independently rejects obsolete result generations");
    Pump();
    Check(session->wordNotifications == 2 && session->sourceGeneration == generation,
          @"attribute publication neither advances source generation nor loops");
    Detach(session, returned); [returned release]; [view release]; [session close]; [session release];
}

int main(void) { @autoreleasepool {
    Method method = class_getInstanceMethod([NSMutableAttributedString class], @selector(addLinkAttributesForRange:syntaxIdentifier:));
    decorate = method_setImplementation(method, (IMP)GatedDecoration);
    gate = dispatch_semaphore_create(0);
    SubscribersWhileRunning(); GenerationsAndReattachment();
    method_setImplementation(method, decorate); dispatch_release(gate);
    printf("PASS: %lu headless review checks across two interleaving probes\n", (unsigned long)checks);
} return 0; }
