#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "DeletedNoteObject.h"
#import "EncodingsManager.h"
#import "NotationDirectoryManager.h"
#import "NotationFileManager.h"
#import "WALController.h"
#import "NSString_NV.h"
#import <objc/runtime.h>

static void Check(BOOL result, NSString *description);
static NSString *ProtectedSourceFilename, *ExpectedExternalSource;
static BOOL ConflictJournalSynchronized;
static NSUInteger ProtectedSourceWrites;
static BOOL FailSourceConflictSync;
static NSUInteger FailedSourceConflictSyncs;

@interface WALStorageController (NVSourceDurabilityTest)
- (BOOL)nv_recordSourceSynchronization;
@end
@implementation WALStorageController (NVSourceDurabilityTest)
- (BOOL)nv_recordSourceSynchronization {
    if (FailSourceConflictSync) { FailedSourceConflictSyncs++; return NO; }
    BOOL result = [self nv_recordSourceSynchronization];
    if (ProtectedSourceFilename && result) ConflictJournalSynchronized = YES;
    return result;
}
@end

@interface NotationController (NVSourceDurabilityTest)
- (OSStatus)nv_checkSourceData:(NSData*)data withName:(NSString*)name destinationRef:(FSRef*)ref;
@end
@implementation NotationController (NVSourceDurabilityTest)
- (OSStatus)nv_checkSourceData:(NSData*)data withName:(NSString*)name destinationRef:(FSRef*)ref {
    if (ProtectedSourceFilename && [name isEqualToString:ProtectedSourceFilename]) {
        Check(ConflictJournalSynchronized, @"conflict journal synchronizes before the original source file is replaced");
        WALStorageController *writer = [self valueForKey:@"walWriter"];
        Ivar pathIvar = class_getInstanceVariable([WALController class], "journalFile");
        char *journalPath = *(char **)((char *)(void *)writer + ivar_getOffset(pathIvar));
        NSString *parentPath = [[NSString stringWithUTF8String:journalPath] stringByDeletingLastPathComponent];
        WALRecoveryController *reader = [[[WALRecoveryController alloc] initWithParentFSRep:[parentPath fileSystemRepresentation] encryptionKey:[[self notationPrefs] WALSessionKey]] autorelease];
        BOOL recoveredExternal = NO;
        for (id candidate in [[reader recoveredNotes] allValues]) {
            if ([candidate isKindOfClass:[NoteObject class]] && [[[candidate contentString] string] isEqualToString:ExpectedExternalSource]) recoveredExternal = YES;
        }
        Check(recoveredExternal, @"external source is recoverable from the real WAL before the original file is replaced");
        ProtectedSourceWrites++;
    }
    return [self nv_checkSourceData:data withName:name destinationRef:ref];
}
@end

static NSUInteger SourceConversionOffers;
@interface EncodingsManager (NVSourceConversionTest)
- (void)nv_cancelConversionForNote:(NoteObject*)note;
- (BOOL)shouldUpdateNoteFromDisk;
@end
@implementation EncodingsManager (NVSourceConversionTest)
- (void)nv_cancelConversionForNote:(NoteObject*)note { SourceConversionOffers++; }
@end

static NSWindow *SourceConversionParent;
static void (^SourceCapturedConversion)(NSModalResponse);
static NSUInteger SourceConversionSheets;
@interface NSApplication (NVSourceConversionSheetTest)
- (NSWindow *)nv_sourceConversionMainWindow;
@end
@implementation NSApplication (NVSourceConversionSheetTest)
- (NSWindow *)nv_sourceConversionMainWindow { return SourceConversionParent ?: [self nv_sourceConversionMainWindow]; }
@end
@interface NSAlert (NVSourceConversionSheetTest)
- (void)nv_captureSourceConversionSheet:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion;
@end
@implementation NSAlert (NVSourceConversionSheetTest)
- (void)nv_captureSourceConversionSheet:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion {
    SourceConversionSheets++;
    [SourceCapturedConversion release];
    SourceCapturedConversion = [completion copy];
}
@end

static NSUInteger SourceNotesWithBody(NotationController *library, NSString *body) {
    NSUInteger count = 0;
    for (NoteObject *candidate in [library allNotes]) if ([[[candidate contentString] string] isEqualToString:body]) count++;
    return count;
}

@interface NVSourcePrefsDelegate : NSObject {
@public
    NotationPrefs *prefs;
}
@end
@implementation NVSourcePrefsDelegate
- (NotationPrefs*)notationPrefs { return prefs; }
@end

#import "NSData_transformations.h"

static BOOL SourceArchiveHasKey(NSData *data, NSString *key) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    Check([plist isKindOfClass:[NSDictionary class]], @"archive inspection reads a keyed property list");
    for (id object in [plist objectForKey:@"$objects"])
        if ([object isKindOfClass:[NSDictionary class]] && [object objectForKey:key] != nil) return YES;
    return NO;
}

// Decode only the obsolete fixture fields into test records. The production
// decoder deliberately ignores these keys and exposes no remote-service API.
@interface NVLegacyFixtureArchiveFields : NSObject <NSCoding> {
    NSDictionary *fields;
}
- (id)fieldForKey:(NSString *)key;
@end
@implementation NVLegacyFixtureArchiveFields
- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        NSMutableDictionary *decoded = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"prefs", @"notesData", @"deletedNoteSet", @"syncServiceAccounts", @"syncServicesMD"]) {
            if (![coder containsValueForKey:key]) continue;
            id value = [coder decodeObjectForKey:key];
            if (value) [decoded setObject:value forKey:key];
        }
        fields = [decoded copy];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [NSException raise:NSInternalInconsistencyException format:@"Legacy fixture inspection is decode-only"];
}
- (id)fieldForKey:(NSString *)key { return [fields objectForKey:key]; }
- (void)dealloc { [fields release]; [super dealloc]; }
@end

static id SourceInspectLegacyFixtureArchive(NSData *data, NSString *key) {
    NSKeyedUnarchiver *decoder = [[[NSKeyedUnarchiver alloc] initForReadingWithData:data] autorelease];
    for (NSString *className in @[@"FrozenNotation", @"NotationPrefs", @"NoteObject", @"DeletedNoteObject"])
        [decoder setClass:[NVLegacyFixtureArchiveFields class] forClassName:className];
    return [decoder decodeObjectForKey:key];
}

static void SourceCheckLegacyFixtureMetadata(NSData *data) {
    NVLegacyFixtureArchiveFields *root = SourceInspectLegacyFixtureArchive(data, @"root");
    NSDictionary *accounts = [[root fieldForKey:@"prefs"] fieldForKey:@"syncServiceAccounts"];
    Check([[accounts objectForKey:@"SN"] isEqual:@{@"enabled": @YES, @"username": @"fixture@example.invalid", @"frequency": @1}],
          @"legacy fixture contains the exact enabled account under the recognized SN identifier");
    NSArray *notes = SourceInspectLegacyFixtureArchive([[root fieldForKey:@"notesData"] uncompressedData], @"notes");
    Check([notes count] == 1 && [[[[notes firstObject] fieldForKey:@"syncServicesMD"] objectForKey:@"SN"] isEqual:
          @{@"key": @"legacy-remote-note", @"version": @7, @"dirty": @YES, @"modify": @700000123.5, @"SepStr": @"e\n\n#"}],
          @"legacy fixture contains recognized pending upload metadata on its local note");
    NSSet *deleted = [root fieldForKey:@"deletedNoteSet"];
    Check([deleted count] == 1 && [[[[[deleted allObjects] firstObject] fieldForKey:@"syncServicesMD"] objectForKey:@"SN"] isEqual:
          @{@"key": @"legacy-remote-deletion", @"version": @11, @"dirty": @YES, @"modify": @700000124.5}],
          @"legacy fixture contains recognized pending deletion metadata on its tombstone");
}

// Sequential archives require consuming the old metadata object between UUID
// and sequence. Skipping it changes the type of the next decoded value.
@interface NVLegacySequentialTombstone : NSObject <NSCoding>
@end
@implementation NVLegacySequentialTombstone
- (void)encodeWithCoder:(NSCoder *)coder {
    CFUUIDBytes identifier = { 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef };
    unsigned int sequence = 0xf1234567U;
    [coder encodeValueOfObjCType:@encode(CFUUIDBytes) at:&identifier];
    [coder encodeObject:@{@"Simplenote": @{@"key": @"old-remote-deletion"}}];
    [coder encodeValueOfObjCType:@encode(unsigned int) at:&sequence];
}
- (id)initWithCoder:(NSCoder *)coder { [self release]; return nil; }
@end
