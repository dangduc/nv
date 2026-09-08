#import <Cocoa/Cocoa.h>
#import "NotationPrefs.h"
#import "NoteObject.h"
#import "FrozenNotation.h"
@interface NSObject (NVOldServiceReadOnlyInspection)
+ (NSString *)serviceName;
+ (NSArray *)allServiceNames;
- (BOOL)syncServiceIsEnabled:(NSString *)name;
- (NSDictionary *)syncServicesMD;
- (NSSet *)deletedNotes;
@end
