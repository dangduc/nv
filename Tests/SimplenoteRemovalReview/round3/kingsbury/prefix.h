#import "NotationController.h"
#import "NotationFileManager.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "NoteObject.h"
#import "BookmarksController.h"
#import "WALController.h"
#import "NSData_transformations.h"
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import <unistd.h>

static NSData *NVMigrationFixture;
static NSUInteger NVRejectedMigrationStores;
static NSUInteger NVMigrationPhase;
static const CFUUIDBytes NVLegacyUUID = {0x10,0x32,0x54,0x76,0x98,0xba,0xdc,0xfe,0x01,0x23,0x45,0x67,0x89,0xab,0xcd,0xef};
static const CFUUIDBytes NVRemoteDeletedUUID = {0xff,0xee,0xdd,0xcc,0xbb,0xaa,0x99,0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11,0x00};
static const CFUUIDBytes NVFreshUUID = {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
static const CFUUIDBytes NVBornDeletedUUID = {3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3};

static NSString *NVMigrationHash(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}
static BOOL NVMigrationArchiveHasKey(NSData *data, NSString *key) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"$objects"] isKindOfClass:[NSArray class]]) {
        NSLog(@"FAIL: migration archive-key inspection did not receive a keyed archive"); _exit(1);
    }
    for (id object in plist[@"$objects"])
        if ([object isKindOfClass:[NSDictionary class]] && object[key] != nil) return YES;
    return NO;
}

@interface NotationController (NVMigrationCrashCut)
- (OSStatus)nv_migrationStore:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)destination
    verifyWithSelector:(SEL)selector verificationDelegate:(id)verificationTarget;
@end
@implementation NotationController (NVMigrationCrashCut)
+ (void)load {
    if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
    @autoreleasepool {
        NVMigrationPhase = atoi(getenv("NV_REVIEW_PHASE"));
        const char *fixturePath = getenv("NV_MIGRATION_FIXTURE");
        if (!fixturePath) { NSLog(@"FAIL: NV_MIGRATION_FIXTURE is required"); _exit(1); }
        NVMigrationFixture = [[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:fixturePath]] retain];
        if (![[NVMigrationHash(NVMigrationFixture) lowercaseString] isEqual:@"07bc028440a8dfba96f53023f3035141a94c5b1ecd8b6cd23d99eaeb9bf52f4d"]) {
            NSLog(@"FAIL: fixture differs from corrected pre-removal artifact"); _exit(1);
        }
        NSString *database = [[NSString stringWithUTF8String:getenv("NV_WINDOW_TEST_DIRECTORY")]
            stringByAppendingPathComponent:@"Notes/Notes & Settings"];
        if (NVMigrationPhase == 1 && ![NVMigrationFixture writeToFile:database atomically:YES]) {
            NSLog(@"FAIL: cannot install old fixture before library initialization"); _exit(1);
        }
        NSData *startupBytes = [NSData dataWithContentsOfFile:database];
        if (NVMigrationPhase <= 2 && ![startupBytes isEqual:NVMigrationFixture]) {
            NSLog(@"FAIL: startup checkpoint must still be the exact old archive"); _exit(1);
        }
        NSLog(@"MIGRATION PRE-OPEN phase%lu: checkpoint bytes=%lu sha256=%@", (unsigned long)NVMigrationPhase,
            (unsigned long)[startupBytes length], NVMigrationHash(startupBytes));
        method_exchangeImplementations(class_getInstanceMethod(self,
            @selector(storeDataAtomicallyInNotesDirectory:withName:destinationRef:verifyWithSelector:verificationDelegate:)),
            class_getInstanceMethod(self, @selector(nv_migrationStore:withName:destinationRef:verifyWithSelector:verificationDelegate:)));
    }
}
- (OSStatus)nv_migrationStore:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)destination
    verifyWithSelector:(SEL)selector verificationDelegate:(id)verificationTarget {
    // This is a controlled scheduling/failure cut, not a simulated physical disk.
    // Serialize normally but preserve the old checkpoint during process one.
    if (NVMigrationPhase == 1 && [name isEqual:@"Notes & Settings"]) {
        NVRejectedMigrationStores++;
        NSLog(@"INJECT: reject migration snapshot replacement bytes=%lu", (unsigned long)[data length]);
        return dskFulErr;
    }
    return [self nv_migrationStore:data withName:name destinationRef:destination
        verifyWithSelector:selector verificationDelegate:verificationTarget];
}
@end
