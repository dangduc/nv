#import <Cocoa/Cocoa.h>
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "DeletedNoteObject.h"
#import "LogNoteProtocol.h"

static NSUInteger ObsoleteDecodes, SourceDeallocations;

// A local observation marker. The old readers visit this object; the new
// archive boundary must skip its whole enclosing obsolete field.
@interface NVReviewObsoleteField : NSObject <NSCoding>
@end
@implementation NVReviewObsoleteField
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:@"review-marker" forKey:@"marker"]; }
- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) { ObsoleteDecodes++; }
    return self;
}
@end

@interface NVReviewArchiveEnvelope : NSObject <NSCoding> {
    id object;
    NSString *key;
}
- (id)initWithObject:(id)value obsoleteKey:(NSString *)name;
@end
@implementation NVReviewArchiveEnvelope
- (id)initWithObject:(id)value obsoleteKey:(NSString *)name {
    if ((self = [super init])) { object = [value retain]; key = [name copy]; }
    return self;
}
- (Class)classForCoder { return [object class]; }
- (Class)classForKeyedArchiver { return [object class]; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [object encodeWithCoder:coder];
    id marker = [[[NVReviewObsoleteField alloc] init] autorelease];
    // Use collection-shaped metadata so both generations receive the old shape.
    id payload = [key isEqual:@"deletedNoteSet"] ? (id)[NSMutableSet setWithObject:marker] :
        (id)[NSMutableDictionary dictionaryWithObject:
            [NSMutableDictionary dictionaryWithObject:marker forKey:@"review-marker"] forKey:@"review-only"];
    [coder encodeObject:payload forKey:key];
}
- (id)initWithCoder:(NSCoder *)coder { [self release]; return nil; }
- (void)dealloc { [object release]; [key release]; [super dealloc]; }
@end

// Implements precisely the local protocol. Only the comparison baseline needs
// the compatibility sync getter; no sync service or note/controller is involved.
@interface NVReviewLogSource : NSObject <LogNote> {
    CFUUIDBytes identity;
    unsigned int sequence;
}
@end
@implementation NVReviewLogSource
- (id)init {
    if ((self = [super init])) {
        for (NSUInteger i = 0; i < sizeof(identity); i++) ((unsigned char *)&identity)[i] = (unsigned char)(i * 13 + 7);
        sequence = 0xf1234567U;
    }
    return self;
}
- (CFUUIDBytes *)uniqueNoteIDBytes { return &identity; }
- (unsigned int)logSequenceNumber { return sequence; }
- (void)incrementLSN { sequence++; }
- (BOOL)youngerThanLogObject:(id<LogNote>)other { return sequence < [other logSequenceNumber]; }
- (NSDictionary *)syncServicesMD { return @{}; }
- (void)encodeWithCoder:(NSCoder *)coder { }
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)dealloc { SourceDeallocations++; [super dealloc]; }
@end

@interface FrozenNotation (NVReviewOldFactory)
- (id)initWithNotes:(NSMutableArray *)notes deletedNotes:(NSMutableSet *)deletions prefs:(NotationPrefs *)prefs;
@end

static BOOL ArchiveHasKey(NSData *data, NSString *key) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    for (id item in [plist objectForKey:@"$objects"]) {
        if ([item isKindOfClass:[NSDictionary class]] && [item objectForKey:key]) return YES;
    }
    return NO;
}

static id DecoratedRoundtrip(id object, NSString *key, NSData **encoded) {
    id envelope = [[[NVReviewArchiveEnvelope alloc] initWithObject:object obsoleteKey:key] autorelease];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:envelope];
    if (encoded) *encoded = data;
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}
