#import <Foundation/Foundation.h>

extern NSString * const NVBackupStoreErrorDomain;

// Filesystem operations run on the backup controller's serial worker. Archive
// bytes are immutable and already contain the library's existing encryption.
// Optional metadata existingRoot is an NSURL for an already selected folder.
// The destination must be its direct library-UUID child; this root is never created.
// existingRoot requires existingRootIdentity, the captured "device:inode" string.
@interface NVBackupStore : NSObject
+ (NSDictionary *)publishArchiveData:(NSData *)data metadata:(NSDictionary *)metadata
                         inDirectory:(NSURL *)directory retention:(NSDictionary *)retention
                               error:(NSError **)error;
+ (NSArray *)snapshotsInDirectory:(NSURL *)directory error:(NSError **)error;
+ (NSData *)archiveDataAtSnapshotURL:(NSURL *)snapshotURL error:(NSError **)error;
// The caller supplies an existing, empty directory. This method never replaces
// its contents or removes the selected directory, including on failure.
+ (BOOL)writeRestoreArchiveData:(NSData *)data toEmptyDirectory:(NSURL *)directory error:(NSError **)error;
+ (BOOL)pruneSnapshotsInDirectory:(NSURL *)directory retention:(NSDictionary *)retention error:(NSError **)error;
+ (BOOL)deleteUnencryptedSnapshotsInDirectory:(NSURL *)directory error:(NSError **)error;
@end

#ifdef NVBACKUPSTORE_TESTING
// Fault injection is absent from the application build.
extern NSString *NVBackupStoreFailurePoint;
extern int NVBackupStoreFailureCode;
extern NSDate *NVBackupStoreCurrentDate;
#endif
