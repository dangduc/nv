#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "SimplenoteEntryCollector.h"
#import "SyncResponseFetcher.h"
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

@interface WALStorageController (NVSourceDurabilityTest)
- (BOOL)nv_recordSourceSynchronization;
@end
@implementation WALStorageController (NVSourceDurabilityTest)
- (BOOL)nv_recordSourceSynchronization {
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

@interface NVSourcePrefsDelegate : NSObject {
@public
    NotationPrefs *prefs;
}
@end
@implementation NVSourcePrefsDelegate
- (NotationPrefs*)notationPrefs { return prefs; }
@end
