#import <Cocoa/Cocoa.h>
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "DeletedNoteObject.h"
#import "NSString_NV.h"
#import "NSData_transformations.h"

@interface FrozenNotation (NVBeforeRemovalProducer)
+ (NSData *)frozenDataWithExistingNotes:(NSMutableArray *)notes deletedNotes:(NSMutableSet *)deleted prefs:(NotationPrefs *)prefs;
@end

// KVC intentionally avoids compiling current NoteObject ivar offsets into the
// old-app producer. The UUID and all content access use runtime methods too.
static NSDictionary *DataSnapshot(NoteObject *note, NotationPrefs *prefs) {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"titleString", @"labelString", @"createdDate", @"modifiedDate",
          @"fileEncoding", @"sourceOriginalData", @"sourceByteOrderMark", @"sourceOriginalEncoding",
          @"sourceConversionPending", @"sourceConflictOriginUUID", @"logSequenceNumber"])
        [snapshot setObject:[note valueForKey:key] ?: [NSData data] forKey:key];
    // Legacy fileEncoding decodes a signed int32 into unsigned NSStringEncoding.
    // Its identity is the low 32 bits, as documented in architecture.md.
    [snapshot setObject:@((uint32_t)[[note valueForKey:@"fileEncoding"] unsignedLongLongValue]) forKey:@"fileEncoding"];
    [snapshot setObject:[[note contentString] string] forKey:@"characters"];
    [snapshot setObject:[NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)] forKey:@"uuid"];
    [snapshot setObject:[prefs sourceMetadataForNoteUUID:[NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]]] ?: @{} forKey:@"metadata"];
    return snapshot;
}

static BOOL ArchiveContainsKey(NSData *data, NSString *key) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    for (id object in [plist objectForKey:@"$objects"])
        if ([object isKindOfClass:[NSDictionary class]] && [object objectForKey:key]) return YES;
    return NO;
}
