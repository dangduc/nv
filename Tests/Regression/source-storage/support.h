#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "SimplenoteEntryCollector.h"
#import "SyncResponseFetcher.h"
#import "EncodingsManager.h"
#import "NotationDirectoryManager.h"

static NSUInteger SourceConversionOffers;
@interface EncodingsManager (NVSourceConversionTest)
- (void)nv_cancelConversionForNote:(NoteObject*)note;
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
