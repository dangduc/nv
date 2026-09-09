#import <Cocoa/Cocoa.h>

extern NSString * const NVBackupArchiveErrorDomain;

// This decoder never opens a library, starts a journal, or writes note data to disk.
@interface NVBackupArchive : NSObject
// Main thread only; encrypted archives can request their original password.
+ (NSDictionary*)restoredArchiveFromData:(NSData*)data error:(NSError**)error;
// Noninteractive variant for recovery checks. A wrong password returns an error.
+ (NSDictionary*)restoredArchiveFromData:(NSData*)data passphraseData:(NSData*)passphrase error:(NSError**)error;
@end
