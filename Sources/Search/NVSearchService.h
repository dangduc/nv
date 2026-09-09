#import <Foundation/Foundation.h>
#import "NVSearchQuery.h"
#import "NVSearchCorpus.h"
#import <dispatch/dispatch.h>

@interface NVSearchResult : NSObject {
    NSUInteger _requestID, _corpusRevision;
    NVSearchQuery *_query;
    NSArray *_titleNoteUUIDs, *_fuzzyNoteUUIDs;
    NSDictionary *_snapshotsByUUID;
}
@property(nonatomic, readonly) NSUInteger requestID;
@property(nonatomic, readonly) NSUInteger corpusRevision;
@property(nonatomic, readonly) NVSearchQuery *query;
/* Title membership is in UUID order for the browser's column comparator.
   Fuzzy membership is the complete, unchanged native order. Keep overlap. */
@property(nonatomic, readonly) NSArray *titleNoteUUIDs;
@property(nonatomic, readonly) NSArray *fuzzyNoteUUIDs;
- (NVSearchNoteSnapshot *)snapshotForUUID:(NSData *)uuid;
- (NSUInteger)distinctNoteCount;
@end

@interface NVSearchPositions : NSObject {
    NSArray *_titleRanges, *_tagsRanges, *_sourceRanges;
    NVSearchNoteSnapshot *_snapshot;
}
@property(nonatomic, readonly) NSArray *titleRanges;
@property(nonatomic, readonly) NSArray *tagsRanges;
@property(nonatomic, readonly) NSArray *sourceRanges;
@property(nonatomic, readonly) NVSearchNoteSnapshot *snapshot;
@end

typedef void (^NVSearchCompletion)(NVSearchResult *result, NSError *error);
typedef void (^NVSearchPositionsCompletion)(NVSearchPositions *positions, NSError *error);

/* Own one instance per active library. All public calls occur on main.
   Workers receive immutable values. Cancel an owner before its destruction.
   Completion is always deferred to main and only delivered while current. */
@interface NVSearchService : NSObject {
    NVSearchCorpus *_corpus;
    dispatch_queue_t _worker;
    void *_engine;
    NSMutableDictionary *_requests;
    NSMutableDictionary *_positionRequests;
    NSUInteger _nextRequestID;
}
@property(nonatomic, readonly) NSUInteger corpusRevision;
- (BOOL)synchronizeWithSnapshots:(NSArray *)snapshots;
- (BOOL)updateSnapshot:(NVSearchNoteSnapshot *)snapshot;
- (BOOL)removeUUID:(NSData *)uuid;
/* Call synchronously at model mutation boundaries, before a deferred capture.
   Invalidation cancels current work but keeps reusable immutable versions. */
- (void)invalidate;
- (NVSearchNoteSnapshot *)snapshotForUUID:(NSData *)uuid;
- (NSUInteger)requestForOwner:(id)owner query:(NSString *)query completion:(NVSearchCompletion)completion;
- (BOOL)isRequestCurrent:(NSUInteger)requestID forOwner:(id)owner;
- (void)cancelRequestsForOwner:(id)owner;
/* One position request per positionOwner. Search identity still belongs to
   owner; use a separate token for visible-row work and source highlights. */
- (void)requestPositionsForNoteUUID:(NSData *)uuid requestID:(NSUInteger)requestID owner:(id)owner completion:(NVSearchPositionsCompletion)completion;
- (void)requestPositionsForNoteUUID:(NSData *)uuid requestID:(NSUInteger)requestID owner:(id)owner positionOwner:(id)positionOwner completion:(NVSearchPositionsCompletion)completion;
- (void)cancelPositionRequestsForOwner:(id)positionOwner;
@end

/* Maps NFC Unicode-codepoint positions to original UTF-16 grapheme ranges.
   Exposed for focused Unicode tests; used only for requested notes. */
NSArray *NVSearchOriginalRanges(NSString *string, const uint32_t *offsets, NSUInteger count);
