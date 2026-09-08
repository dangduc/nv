#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NotationController.h"
#import "NotationFileManager.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "NSString_NV.h"

static NVNoteEditingSession *ObservedSession;
static NSUInteger ObservedCloses, ClosedSessionReloads;
static BOOL SessionHasClosed, KeepObsoleteObserver;
static void OwnershipSwap(Class cls, SEL a, SEL b) {
    method_exchangeImplementations(class_getInstanceMethod(cls, a), class_getInstanceMethod(cls, b));
}

// Each temporary library gets its own journal so that preparing the replacement
// does not recover another live library's process-wide cache journal.
@interface NotationController (OwnershipProbe)
- (NSString *)ownership_cache;
@end
@implementation NotationController (OwnershipProbe)
+ (void)load {
    if (getenv("NV_WINDOW_TEST_DIRECTORY"))
        OwnershipSwap(self, @selector(createCachesFolder), @selector(ownership_cache));
}
- (NSString *)ownership_cache {
    NSString *path = [[[self notesDirectoryURL] path] stringByAppendingPathComponent:@".OwnershipJournal"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    return path;
}
@end

@interface NVNoteEditingSession (OwnershipProbe)
- (void)ownership_close;
- (void)ownership_reload;
@end
@interface NVNoteEditingSession (OwnershipPrivateAPI)
- (void)noteContentsChanged:(NSNotification *)notification;
@end
@implementation NVNoteEditingSession (OwnershipProbe)
- (void)ownership_close {
    [self ownership_close];
    if (self == ObservedSession) {
        ObservedCloses++; SessionHasClosed = YES;
        if (KeepObsoleteObserver)
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(noteContentsChanged:)
                name:NVNoteContentsDidChangeNotification object:[self note]];
    }
}
- (void)ownership_reload {
    if (self == ObservedSession && SessionHasClosed) ClosedSessionReloads++;
    [self ownership_reload];
}
@end

// A neutral scheduler owns the delayed callback. Scheduling NoteObject itself
// lets Foundation timer cancellation compare it with unrelated objects through
// the legacy UUID-only isEqual: implementation; that is outside this scope.
@interface OwnershipDeferredChange : NSObject {
    NoteObject *oldNote;
    NSString *newBody;
}
- (id)initWithNote:(NoteObject *)note body:(NSString *)body;
- (void)deliver;
@end
@implementation OwnershipDeferredChange
- (id)initWithNote:(NoteObject *)note body:(NSString *)body {
    if ((self = [super init])) { oldNote = [note retain]; newBody = [body copy]; }
    return self;
}
- (void)deliver {
    [oldNote setContentString:[[[NSAttributedString alloc] initWithString:newBody] autorelease]];
    [[NSNotificationCenter defaultCenter] postNotificationName:NVNoteEditorDidChangeNotification object:oldNote];
}
- (void)dealloc {
    [oldNote release]; [newBody release]; [super dealloc];
}
@end
