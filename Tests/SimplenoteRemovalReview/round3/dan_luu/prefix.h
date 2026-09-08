#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "NotationController.h"
#import "NotationPrefs.h"
#import "NotationFileManager.h"
#import "NotationDirectoryManager.h"
#import "NoteObject.h"
#import "DeletedNoteObject.h"
#import "WALController.h"

static NotationController *DanR3Library;
static WALStorageController *DanR3Journal;
static NSMutableSet *DanR3OriginalPointers;
static NSUInteger DanR3Created, DanR3Released;
static NSUInteger DanR3NoteWrites, DanR3RemovalWrites, DanR3Snapshots;
static NSUInteger DanR3EncodedNotes, DanR3EncodedTombstones;
static BOOL DanR3SnapshotPhase;

static void DanR3Swap(Class cls, SEL a, SEL b) {
    method_exchangeImplementations(class_getInstanceMethod(cls, a), class_getInstanceMethod(cls, b));
}
@interface NotationController (DanR3Lookup)
- (NoteObject *)noteForUUIDBytes:(CFUUIDBytes *)bytes;
@end
@interface NotationController (DanR3Probe)
- (NSString *)danR3_cacheDirectory;
- (OSStatus)danR3_store:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)ref
    verifyWithSelector:(SEL)selector verificationDelegate:(id)owner;
@end
@implementation NotationController (DanR3Probe)
+ (void)load {
    if (getenv("NV_WINDOW_TEST_DIRECTORY"))
        DanR3Swap(self, @selector(createCachesFolder), @selector(danR3_cacheDirectory));
}
- (NSString *)danR3_cacheDirectory {
    NSString *path = [[[self notesDirectoryURL] path] stringByAppendingPathComponent:@".DanR3Journal"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    return path;
}
- (OSStatus)danR3_store:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)ref
    verifyWithSelector:(SEL)selector verificationDelegate:(id)owner {
    OSStatus result = [self danR3_store:data withName:name destinationRef:ref verifyWithSelector:selector verificationDelegate:owner];
    if (self == DanR3Library && result == noErr && [name isEqualToString:@"Notes & Settings"]) DanR3Snapshots++;
    return result;
}
@end
@interface WALStorageController (DanR3Probe)
- (BOOL)danR3_write:(id)note;
@end
@implementation WALStorageController (DanR3Probe)
- (BOOL)danR3_write:(id)note {
    BOOL result = [self danR3_write:note];
    if (self == DanR3Journal && result) {
        if ([note isKindOfClass:[DeletedNoteObject class]]) DanR3RemovalWrites++;
        else DanR3NoteWrites++;
    }
    return result;
}
@end
@interface NoteObject (DanR3Probe)
- (void)danR3_dealloc;
- (void)danR3_encode:(NSCoder *)coder;
@end
@implementation NoteObject (DanR3Probe)
- (void)danR3_dealloc {
    NSValue *address = [NSValue valueWithPointer:self];
    if ([DanR3OriginalPointers containsObject:address]) {
        [DanR3OriginalPointers removeObject:address]; DanR3Released++;
    }
    [self danR3_dealloc];
}
- (void)danR3_encode:(NSCoder *)coder {
    if (DanR3SnapshotPhase) DanR3EncodedNotes++;
    [self danR3_encode:coder];
}
@end
@interface DeletedNoteObject (DanR3Probe)
- (void)danR3_encode:(NSCoder *)coder;
@end
@implementation DeletedNoteObject (DanR3Probe)
- (void)danR3_encode:(NSCoder *)coder {
    if (DanR3SnapshotPhase) DanR3EncodedTombstones++;
    [self danR3_encode:coder];
}
@end

static NotationController *DanR3Open(NSString *directory) {
    FSRef ref; OSStatus error = FSPathMakeRef((const UInt8 *)[directory fileSystemRepresentation], &ref, NULL);
    if (error != noErr) [NSException raise:@"Probe" format:@"directory error %d", error];
    NotationController *library = [[NotationController alloc] initWithDirectoryRef:&ref error:&error];
    if (!library || error != noErr) [NSException raise:@"Probe" format:@"library error %d", error];
    return library;
}
static NSString *DanR3Title(NSUInteger index) {
    return [NSString stringWithFormat:@"Removal workload %03lu", (unsigned long)index];
}
static NSString *DanR3Body(NSUInteger index) {
    NSString *line = [NSString stringWithFormat:@"%03lu Café\t日本語 😀\r\n", (unsigned long)index];
    return [line stringByPaddingToLength:4096 withString:line startingAtIndex:0];
}
