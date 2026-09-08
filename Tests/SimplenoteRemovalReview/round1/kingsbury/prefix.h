#import "NotationController.h"
#import "NoteObject.h"
#import "BookmarksController.h"
#import "NotationPrefs.h"
#import "DeletedNoteObject.h"
#import "WALController.h"
#import <objc/runtime.h>
#import <unistd.h>

// The only mutation is optional and confined to the disposable test process.
// It makes the first WAL record win by refusing every later LSN.
@interface NoteObject (NVKingsburyOrderingMutation)
- (BOOL)nv_kingsburyNeverNewer:(id)object;
@end
@implementation NoteObject (NVKingsburyOrderingMutation)
+ (void)load {
    if (!getenv("NV_KINGSBURY_BROKEN_ORDER")) return;
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(youngerThanLogObject:)),
        class_getInstanceMethod(self, @selector(nv_kingsburyNeverNewer:)));
}
- (BOOL)nv_kingsburyNeverNewer:(id)object { return NO; }
@end
@interface DeletedNoteObject (NVKingsburyOrderingMutation)
- (BOOL)nv_kingsburyNeverNewer:(id)object;
@end
@implementation DeletedNoteObject (NVKingsburyOrderingMutation)
+ (void)load {
    if (!getenv("NV_KINGSBURY_BROKEN_ORDER")) return;
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(youngerThanLogObject:)),
        class_getInstanceMethod(self, @selector(nv_kingsburyNeverNewer:)));
}
- (BOOL)nv_kingsburyNeverNewer:(id)object { return NO; }
@end
