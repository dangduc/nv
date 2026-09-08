#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "EncodingsManager.h"
#import "NotationDirectoryManager.h"
#import "WALController.h"

static BOOL FailReviewSynchronization;
static NSUInteger ReviewFailedSynchronizations;
@interface WALStorageController (NVK3Review)
- (BOOL)nv_round3Synchronize;
@end
@implementation WALStorageController (NVK3Review)
- (BOOL)nv_round3Synchronize {
    if (FailReviewSynchronization) { ReviewFailedSynchronizations++; return NO; }
    return [self nv_round3Synchronize];
}
@end
@interface EncodingsManager (NVK3Review)
- (void)nv_round3IgnoreConversion:(NoteObject *)note;
@end
@implementation EncodingsManager (NVK3Review)
- (void)nv_round3IgnoreConversion:(NoteObject *)note { }
@end
