#import <Cocoa/Cocoa.h>

@class NVSourceAnalysis;

// The delegate is borrowed and is called only on main. Snapshots contain an
// immutable source and syntax, plus generation, links, and words request flags.
@protocol NVSourceAnalysisDelegate <NSObject>
- (NSDictionary *)snapshotForSourceAnalysis:(NVSourceAnalysis *)analysis;
- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:(NSDictionary *)result;
@end

// One running job and one pending request per editing session. The pending
// request captures the latest source only when a worker slot becomes available.
@interface NVSourceAnalysis : NSObject {
    id<NVSourceAnalysisDelegate> delegate;
    id ticket;
    BOOL pending, scheduled, closed;
}
- (id)initWithDelegate:(id<NVSourceAnalysisDelegate>)aDelegate;
- (void)request;
- (void)invalidate;
- (void)close;
@end

// Run on a worker with private objects; the returned URL/range records are
// immutable. No view, layout manager, model, or preferences are accessed.
NSArray *NVSourceLinkRuns(NSString *source, NSString *syntax);
NSUInteger NVSourceWordCount(NSString *source);

// An edited source can retain old link colors until analysis finishes, but
// native link actions must not use those obsolete targets.
BOOL NVSourceLinksAreCurrent(NSTextStorage *storage);
void NVSetSourceLinksCurrent(NSTextStorage *storage, BOOL current);
