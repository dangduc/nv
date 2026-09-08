#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "DeletedNoteObject.h"
#import "NSString_NV.h"
@interface FrozenNotation (NVLegacyFixtureGenerator)
+ (NSData *)frozenDataWithExistingNotes:(NSMutableArray *)notes deletedNotes:(NSMutableSet *)deleted prefs:(NotationPrefs *)prefs;
@end
