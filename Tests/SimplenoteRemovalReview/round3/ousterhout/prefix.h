#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NotationController.h"
#import "NotationPrefs.h"
#import "NVNoteEditingSession.h"
#import "NSString_NV.h"
#import "NoteObject.h"
#import <unistd.h>

// Sensitivity control only: the copied app can omit the real library's
// deletion Undo registration. Normal and baseline histories leave it intact.
@interface NotationController (DeletionOwnershipReview)
- (void)review_omitDeletionUndo:(NoteObject *)note;
@end
@implementation NotationController (DeletionOwnershipReview)
+ (void)load {
    if (getenv("NV_R3_OMIT_DELETION_UNDO"))
        method_exchangeImplementations(class_getInstanceMethod(self, NSSelectorFromString(@"_registerDeletionUndoForNote:")),
            class_getInstanceMethod(self, @selector(review_omitDeletionUndo:)));
}
- (void)review_omitDeletionUndo:(NoteObject *)note { }
@end
