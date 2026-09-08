#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "EncodingsManager.h"
#import "NotationDirectoryManager.h"

static NSUInteger ConversionOffers;
@interface EncodingsManager (NVKingsburyReview)
- (void)nv_reviewDeclineConversion:(NoteObject *)note;
@end
@interface EncodingsManager (NVKingsburyExistingAPI)
- (BOOL)shouldUpdateNoteFromDisk;
@end
@implementation EncodingsManager (NVKingsburyReview)
- (void)nv_reviewDeclineConversion:(NoteObject *)note { ConversionOffers++; }
@end
