#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "EncodingsManager.h"
#import "NotationDirectoryManager.h"
#import "WALController.h"

static void (^CapturedConversion)(NSModalResponse);
static NSUInteger ConversionSheets;
static NSUInteger FailedSyncs;
static BOOL FailConflictSync;
static NSWindow *ReviewParentWindow;

@interface NSApplication (NVK2Review)
- (NSWindow *)nv_reviewMainWindow;
@end
@implementation NSApplication (NVK2Review)
- (NSWindow *)nv_reviewMainWindow { return ReviewParentWindow ?: [self nv_reviewMainWindow]; }
@end

@interface NSAlert (NVK2Review)
- (void)nv_captureSheet:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion;
@end
@implementation NSAlert (NVK2Review)
- (void)nv_captureSheet:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion {
    ConversionSheets++;
    [CapturedConversion release];
    CapturedConversion = [completion copy];
}
@end

@interface WALStorageController (NVK2Review)
- (BOOL)nv_failSelectedSync;
@end
@implementation WALStorageController (NVK2Review)
- (BOOL)nv_failSelectedSync {
    if (FailConflictSync) { FailedSyncs++; return NO; }
    return [self nv_failSelectedSync];
}
@end

@interface EncodingsManager (NVK2Review)
- (void)nv_ignoreConversion:(NoteObject *)note;
@end
@implementation EncodingsManager (NVK2Review)
- (void)nv_ignoreConversion:(NoteObject *)note { }
@end
