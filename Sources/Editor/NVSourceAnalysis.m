#import "NVSourceAnalysis.h"
#import "AttributedPlainText.h"
#import <objc/runtime.h>
#import <stdatomic.h>

static char NVSourceLinksCurrentKey;
BOOL NVSourceLinksAreCurrent(NSTextStorage *storage) {
    NSNumber *current = objc_getAssociatedObject(storage, &NVSourceLinksCurrentKey);
    return !current || [current boolValue];
}
void NVSetSourceLinksCurrent(NSTextStorage *storage, BOOL current) {
    objc_setAssociatedObject(storage, &NVSourceLinksCurrentKey, current ? @YES : @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

NSArray *NVSourceLinkRuns(NSString *source, NSString *syntax) {
    // Reuse the existing URL/wiki/Org rules on a private attributed string. It
    // has no layout managers, attachments, or other application state.
    NSMutableAttributedString *decorated = [[NSMutableAttributedString alloc] initWithString:source];
    [decorated addLinkAttributesForRange:NSMakeRange(0, [decorated length]) syntaxIdentifier:syntax];
    NSMutableArray *runs = [NSMutableArray array];
    [decorated enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [decorated length]) options:0
        usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value) [runs addObject:@{@"range": [NSValue valueWithRange:range], @"url": value}];
        }];
    [decorated release];
    return [[runs copy] autorelease];
}

NSUInteger NVSourceWordCount(NSString *source) {
    // Cocoa's scripting word ranges differ from NSString word enumeration.
    // Their substring observers must die on the thread that owns this storage.
    NSUInteger count;
    @autoreleasepool {
        NSTextStorage *privateStorage = [[NSTextStorage alloc] initWithString:source];
        count = [[privateStorage words] count];
        [privateStorage release];
    }
    return count;
}

@interface NVSourceAnalysisTicket : NSObject {
@public
    NVSourceAnalysis *owner; // Read and cleared only on main; never retained.
    atomic_bool cancelled;
}
@end
@implementation NVSourceAnalysisTicket
- (id)init { if ((self = [super init])) atomic_init(&cancelled, false); return self; }
@end

@interface NVSourceAnalysis ()
- (void)start;
- (void)finishTicket:(NVSourceAnalysisTicket *)completed result:(NSDictionary *)result;
@end

@implementation NVSourceAnalysis
- (id)initWithDelegate:(id<NVSourceAnalysisDelegate>)aDelegate {
    if ((self = [super init])) delegate = aDelegate;
    return self;
}
- (void)request {
    NSAssert([NSThread isMainThread], @"Source analysis requests belong to main");
    if (closed) return;
    pending = YES;
    if (!ticket && !scheduled) {
        scheduled = YES;
        // A fixed delay coalesces captures without postponing them on each key.
        [self performSelector:@selector(start) withObject:nil afterDelay:0.06];
    }
}
- (void)invalidate {
    NSAssert([NSThread isMainThread], @"Source analysis invalidation belongs to main");
    if (ticket) atomic_store(&((NVSourceAnalysisTicket *)ticket)->cancelled, true);
}
- (void)start {
    scheduled = NO;
    if (closed || ticket || !pending) return;
    pending = NO;
    NSDictionary *snapshot = [[delegate snapshotForSourceAnalysis:self] copy];
    if (!snapshot) return;
    NVSourceAnalysisTicket *job = [[NVSourceAnalysisTicket alloc] init];
    job->owner = self;
    ticket = job;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("org.nvalt.source-analysis", DISPATCH_QUEUE_SERIAL); });
    // Only the snapshot and ticket cross the queue. In particular, the worker
    // cannot become the last owner of an editing session or its delegate.
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:snapshot];
            if (!atomic_load(&job->cancelled) && [snapshot[@"links"] boolValue])
                result[@"linkRuns"] = NVSourceLinkRuns(snapshot[@"source"], snapshot[@"syntax"]);
            if (!atomic_load(&job->cancelled) && [snapshot[@"words"] boolValue])
                result[@"wordCount"] = @(NVSourceWordCount(snapshot[@"source"]));
            NSDictionary *immutableResult = [result copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                NVSourceAnalysis *owner = job->owner;
                if (owner) [owner finishTicket:job result:immutableResult];
            });
            [immutableResult release];
        }
    });
    [snapshot release];
}
- (void)finishTicket:(NVSourceAnalysisTicket *)completed result:(NSDictionary *)result {
    NSAssert([NSThread isMainThread], @"Source analysis publication belongs to main");
    if (closed || ticket != completed) return;
    BOOL accepted = !atomic_load(&completed->cancelled);
    completed->owner = nil;
    [ticket release]; ticket = nil;
    if (accepted) [delegate sourceAnalysis:self didFinish:result];
    if (pending) [self request];
}
- (void)close {
    NSAssert([NSThread isMainThread], @"Source analysis closure belongs to main");
    closed = YES; pending = NO; scheduled = NO; delegate = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (ticket) {
        ((NVSourceAnalysisTicket *)ticket)->owner = nil;
        atomic_store(&((NVSourceAnalysisTicket *)ticket)->cancelled, true);
        [ticket release]; ticket = nil;
    }
}
- (void)dealloc { [self close]; [super dealloc]; }
@end
