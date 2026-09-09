#import "NVBackupArchive.h"
#import "FrozenNotation.h"
#import "NotationPrefs.h"
#import "NotationFileManager.h"
#import <objc/runtime.h>
#include <sys/stat.h>
static BOOL NVFailBackupCheckpoint;
@interface NotationController (NVBackupFailureProbe)
- (OSStatus)nv_backupStore:(NSData*)data withName:(NSString*)name destinationRef:(FSRef*)reference verifyWithSelector:(SEL)selector verificationDelegate:(id)verifier;
@end
@implementation NotationController (NVBackupFailureProbe)
- (OSStatus)nv_backupStore:(NSData*)data withName:(NSString*)name destinationRef:(FSRef*)reference verifyWithSelector:(SEL)selector verificationDelegate:(id)verifier {
    if (NVFailBackupCheckpoint) return dskFulErr;
    return [self nv_backupStore:data withName:name destinationRef:reference verifyWithSelector:selector verificationDelegate:verifier];
}
@end
static BOOL NVFailRestoredInitialization;
@interface NotationController (NVBackupRestoreFailureProbe)
- (id)nv_restoredInit:(FSRef*)reference unlockedPrefs:(NotationPrefs*)prefs error:(OSStatus*)error;
@end
@implementation NotationController (NVBackupRestoreFailureProbe)
- (id)nv_restoredInit:(FSRef*)reference unlockedPrefs:(NotationPrefs*)prefs error:(OSStatus*)error {
    if (NVFailRestoredInitialization) { *error = permErr; [self release]; return nil; }
    return [self nv_restoredInit:reference unlockedPrefs:prefs error:error];
}
@end
static BOOL NVFailBackupJournalSync;
@interface WALStorageController (NVBackupSyncFailureProbe)
- (BOOL)nv_backupSynchronize;
@end
@implementation WALStorageController (NVBackupSyncFailureProbe)
- (BOOL)nv_backupSynchronize { return NVFailBackupJournalSync ? NO : [self nv_backupSynchronize]; }
@end
