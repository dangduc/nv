#import <Foundation/Foundation.h>
#import "NVFZF.h"

/* Immutable committed model values. No NoteObject or text storage crosses the
   search boundary. Preparation is private to the service's serial worker. */
@interface NVSearchNoteSnapshot : NSObject {
    NSData *_noteUUID;
    NSString *_title;
    NSString *_tags;
    NSString *_source;
    NSUInteger _revision;
    NSString *_candidate;
    NSData *_preparedUTF8;
}
- (id)initWithNoteUUID:(NSData *)uuid title:(NSString *)title tags:(NSString *)tags source:(NSString *)source revision:(NSUInteger)revision;
@property(nonatomic, readonly) NSData *noteUUID;
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) NSString *tags;
@property(nonatomic, readonly) NSString *source;
@property(nonatomic, readonly) NSUInteger revision;
- (BOOL)hasSameContentAsSnapshot:(NVSearchNoteSnapshot *)snapshot;
/* Worker-only access. Original candidate uses original UTF-16 offsets. */
- (NSString *)candidate;
- (NSData *)preparedUTF8;
- (NSData *)preparedUTF8WithCancellation:(NVFZFCancel *)cancel status:(NVFZFStatus *)status;
- (NSRange)titleRange;
- (NSRange)tagsRange;
- (NSRange)sourceRange;
@end

@interface NVSearchCorpus : NSObject {
    NSArray *_snapshots;
    NSDictionary *_byUUID;
    NSUInteger _revision;
}
@property(nonatomic, readonly) NSArray *snapshots;
@property(nonatomic, readonly) NSUInteger revision;
/* Main-thread methods. Unchanged note versions retain their preparation. */
- (BOOL)synchronizeWithSnapshots:(NSArray *)snapshots;
- (BOOL)updateSnapshot:(NVSearchNoteSnapshot *)snapshot;
- (BOOL)removeUUID:(NSData *)uuid;
- (void)invalidate;
- (NVSearchNoteSnapshot *)snapshotForUUID:(NSData *)uuid;
@end

/* Canonical NFC from the pinned Unicode implementation, preserving NUL. */
NSData *NVSearchCanonicalUTF8(NSString *string, NVFZFCancel *cancel, NVFZFStatus *status);
