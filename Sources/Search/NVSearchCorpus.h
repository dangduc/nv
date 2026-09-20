#import <Foundation/Foundation.h>
#import "NVFZF.h"

/* One nonempty logical line, with offsets in its original field. Immutable
   after worker preparation; bytes use NFC, ranges use original UTF-16. */
@interface NVSearchLine : NSObject {
    NSString *_text, *_field;
    NSData *_preparedUTF8;
    NSRange _range;
    NSUInteger _lineNumber;
}
- (id)initWithText:(NSString *)text field:(NSString *)field range:(NSRange)range lineNumber:(NSUInteger)lineNumber bytes:(NSData *)bytes;
@property(nonatomic, readonly) NSString *text;
@property(nonatomic, readonly) NSString *field;
@property(nonatomic, readonly) NSData *preparedUTF8;
@property(nonatomic, readonly) NSRange range;
@property(nonatomic, readonly) NSUInteger lineNumber;
@end

/* Immutable committed model values. No NoteObject or text storage crosses the
   search boundary. Preparation is private to the service's serial worker. */
@interface NVSearchNoteSnapshot : NSObject {
    NSData *_noteUUID;
    NSString *_title;
    NSString *_tags;
    NSString *_source;
    NSUInteger _revision;
    NSMutableArray *_lines;
    NSUInteger _lineField, _lineOffset, _lineNumber;
}
- (id)initWithNoteUUID:(NSData *)uuid title:(NSString *)title tags:(NSString *)tags source:(NSString *)source revision:(NSUInteger)revision;
@property(nonatomic, readonly) NSData *noteUUID;
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) NSString *tags;
@property(nonatomic, readonly) NSString *source;
@property(nonatomic, readonly) NSUInteger revision;
- (BOOL)hasSameContentAsSnapshot:(NVSearchNoteSnapshot *)snapshot;
/* Worker-only, resumable preparation. YES means complete or failed; inspect
   status. Completed lines and their normalized bytes survive repeated queries. */
- (BOOL)prepareLinesWithCancellation:(NVFZFCancel *)cancel status:(NVFZFStatus *)status;
- (NSArray *)lines;
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
