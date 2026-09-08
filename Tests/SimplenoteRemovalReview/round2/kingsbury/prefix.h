#import "NotationController.h"
#import "NotationFileManager.h"
#import "NotationPrefs.h"
#import "BookmarksController.h"
#import "NoteObject.h"
#import "WALController.h"
#import <objc/runtime.h>
#import <unistd.h>
#import <sys/stat.h>

static NotationController *NVFailureLibrary;
static BOOL NVFailSnapshot;
static NSUInteger NVFailedStores, NVSuccessfulStores, NVJournalCloses;
static NSUInteger NVLastRejectedBytes;

@interface NotationController (NVKingsburySnapshotFault)
- (OSStatus)nv_reviewStore:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)destination
    verifyWithSelector:(SEL)selector verificationDelegate:(id)verificationTarget;
- (void)nv_reviewCloseJournal;
- (void)nv_reviewCloseResources;
@end
@implementation NotationController (NVKingsburySnapshotFault)
+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(storeDataAtomicallyInNotesDirectory:withName:destinationRef:verifyWithSelector:verificationDelegate:)),
        class_getInstanceMethod(self, @selector(nv_reviewStore:withName:destinationRef:verifyWithSelector:verificationDelegate:)));
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(closeJournal)), class_getInstanceMethod(self, @selector(nv_reviewCloseJournal)));
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(closeAllResources)), class_getInstanceMethod(self, @selector(nv_reviewCloseResources)));
}
- (OSStatus)nv_reviewStore:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)destination
    verifyWithSelector:(SEL)selector verificationDelegate:(id)verificationTarget {
    BOOL target = self == NVFailureLibrary && [name isEqual:@"Notes & Settings"];
    if (target && NVFailSnapshot) {
        NVFailedStores++; NVLastRejectedBytes = [data length];
        NSLog(@"INJECT: reject serialized database store, status=%d, bytes=%lu, attempt=%lu", (int)dskFulErr,
            (unsigned long)[data length], (unsigned long)NVFailedStores);
        return dskFulErr;
    }
    OSStatus status = [self nv_reviewStore:data withName:name destinationRef:destination verifyWithSelector:selector verificationDelegate:verificationTarget];
    if (target && status == noErr) NVSuccessfulStores++;
    return status;
}
- (void)nv_reviewCloseJournal {
    if (self == NVFailureLibrary) NVJournalCloses++;
    [self nv_reviewCloseJournal];
}
- (void)nv_reviewCloseResources {
    [self nv_reviewCloseResources];
    // Sensitivity control: simulate deletion of the success guard at close.
    if (self == NVFailureLibrary && NVFailSnapshot && getenv("NV_KINGSBURY_DROP_FAILED_WAL")) [self closeJournal];
}
@end
