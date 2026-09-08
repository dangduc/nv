#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "DeletedNoteObject.h"
#import "NSString_NV.h"
@interface SimplenoteSession : NSObject
+ (NSString *)serviceName;
@end
@interface SyncSessionController : NSObject
+ (NSArray *)allServiceNames;
@end
@interface NotationPrefs (NVLegacyFixtureAccount)
- (BOOL)syncServiceIsEnabled:(NSString *)serviceName;
@end
@interface NSObject (NVLegacyFixtureRemoteMetadata)
- (NSDictionary *)syncServicesMD;
@end
@interface FrozenNotation (NVLegacyFixtureGenerator)
+ (NSData *)frozenDataWithExistingNotes:(NSMutableArray *)notes deletedNotes:(NSMutableSet *)deleted prefs:(NotationPrefs *)prefs;
- (NSSet *)deletedNotes;
@end
