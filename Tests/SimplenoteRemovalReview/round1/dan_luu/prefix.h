#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "NotationController.h"
#import "NotationFileManager.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "WALController.h"
#import "NoteObject.h"
#import "NSString_NV.h"

@interface FrozenNotation (NVDanOldArchive)
+ (NSData *)frozenDataWithExistingNotes:(NSMutableArray *)notes deletedNotes:(NSMutableSet *)deleted prefs:(NotationPrefs *)prefs;
@end

static NSUInteger SnapshotWrites, SnapshotBytes, JournalWrites, EncodedNotes, DecodedNotes;
static CFMutableSetRef DecodedLive;
static BOOL CountOperations;
static void DanSwap(Class cls, SEL a, SEL b) {
    method_exchangeImplementations(class_getInstanceMethod(cls, a), class_getInstanceMethod(cls, b));
}
@interface NotationController (NVDanOperations)
- (NSString *)nv_dan_cacheDirectory;
- (OSStatus)nv_dan_store:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)ref
    verifyWithSelector:(SEL)selector verificationDelegate:(id)owner;
@end
@implementation NotationController (NVDanOperations)
+ (void)load {
    if (getenv("NV_WINDOW_TEST_DIRECTORY"))
        DanSwap(self, @selector(createCachesFolder), @selector(nv_dan_cacheDirectory));
}
- (NSString *)nv_dan_cacheDirectory {
    NSString *directory = [[[self notesDirectoryURL] path] stringByAppendingPathComponent:@".ReviewJournal"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    return directory;
}
- (OSStatus)nv_dan_store:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)ref
    verifyWithSelector:(SEL)selector verificationDelegate:(id)owner {
    OSStatus status = [self nv_dan_store:data withName:name destinationRef:ref verifyWithSelector:selector verificationDelegate:owner];
    if (CountOperations && [name isEqualToString:@"Notes & Settings"] && status == noErr) {
        SnapshotWrites++; SnapshotBytes += [data length];
    }
    return status;
}
@end
@interface WALStorageController (NVDanOperations)
- (BOOL)nv_dan_write:(id)note;
@end
@implementation WALStorageController (NVDanOperations)
- (BOOL)nv_dan_write:(id)note {
    BOOL result = [self nv_dan_write:note];
    if (CountOperations && result) JournalWrites++;
    return result;
}
@end
@interface NoteObject (NVDanOperations)
- (id)nv_dan_decode:(NSCoder *)coder;
- (void)nv_dan_encode:(NSCoder *)coder;
- (void)nv_dan_dealloc;
@end
@implementation NoteObject (NVDanOperations)
- (id)nv_dan_decode:(NSCoder *)coder {
    id result = [self nv_dan_decode:coder];
    if (CountOperations && result) { DecodedNotes++; CFSetAddValue(DecodedLive, result); }
    return result;
}
- (void)nv_dan_encode:(NSCoder *)coder {
    if (CountOperations) EncodedNotes++;
    [self nv_dan_encode:coder];
}
- (void)nv_dan_dealloc {
    if (DecodedLive) CFSetRemoveValue(DecodedLive, self);
    [self nv_dan_dealloc];
}
@end

static NSString *DanTitle(NSUInteger index) { return [NSString stringWithFormat:@"Synthetic %04lu", (unsigned long)index]; }
static NSString *DanBody(NSUInteger index, BOOL edited) {
    uint32_t state = (uint32_t)index + 12345;
    NSMutableString *text = [NSMutableString stringWithString:@"# Disposable source café 😀\r\n"];
    for (NSUInteger n = 0; n < 256; n++) {
        state = state * 1664525u + 1013904223u;
        [text appendFormat:@"%08x", state];
    }
    [text appendString:edited ? @"\nlocal edit" : @"\n"];
    return text;
}
static CFUUIDBytes DanUUID(NSUInteger index) {
    CFUUIDBytes bytes = {0xd0,0xa1,0,0,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc};
    bytes.byte2 = index >> 8; bytes.byte3 = index & 255; return bytes;
}
static NotationController *DanOpen(NSString *directory) {
    FSRef ref; OSStatus error = FSPathMakeRef((const UInt8 *)[directory fileSystemRepresentation], &ref, NULL);
    if (error != noErr) [NSException raise:@"Probe" format:@"directory reference %d", error];
    NotationController *library = [[NotationController alloc] initWithDirectoryRef:&ref error:&error];
    if (!library || error != noErr) [NSException raise:@"Probe" format:@"library open %d", error];
    return library;
}
