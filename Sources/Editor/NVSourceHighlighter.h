#import <Cocoa/Cocoa.h>

// Private display data. This attribute is never added to NSTextStorage.
extern NSString * const NVSourceCaptureAttributeName;
BOOL NVSourceCapturesAreCurrent(NSLayoutManager *layout);
// Display may use TextKit-adjusted colors while analysis of an edit is pending.
// These provisional captures must not supply syntax semantics for editing commands.
BOOL NVSourceCapturesCanDisplay(NSLayoutManager *layout);

// A parser is confined to one serial queue. Exposed separately for native tests.
@interface NVSourceParser : NSObject {
    void *parserState;
    NSString *queryDirectory;
}
- (id)initWithQueryDirectory:(NSString *)directory;
- (NSArray *)capturesForString:(NSString *)source syntaxIdentifier:(NSString *)syntax
            cancellationToken:(const uint64_t *)token generation:(uint64_t)generation;
@end

// Main-thread owner; worker requests retain immutable source snapshots only.
@interface NVSourceHighlighter : NSObject {
    NSTextStorage *storage;
    NSString *syntaxIdentifier;
    NSArray *captures;
    id captureRevision;
    dispatch_queue_t queue;
    NVSourceParser *parser;
    uint64_t generation;
    uint64_t cancellationGeneration;
    BOOL closed;
    BOOL analyzing;
}
- (id)initWithTextStorage:(NSTextStorage *)textStorage syntaxIdentifier:(NSString *)syntax;
- (id)initWithTextStorage:(NSTextStorage *)textStorage syntaxIdentifier:(NSString *)syntax queryDirectory:(NSString *)directory;
- (uint64_t)generation;
- (void)setSyntaxIdentifier:(NSString *)syntax;
- (void)layoutsChanged;
- (void)close;
@end
