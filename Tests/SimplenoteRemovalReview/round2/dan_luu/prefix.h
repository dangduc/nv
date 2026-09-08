#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "NotationController.h"
#import "NotationPrefs.h"
#import "NotationFileManager.h"
#import "NotationDirectoryManager.h"
#import "WALController.h"
#import "NoteObject.h"
#import "NVNoteEditingSession.h"

static NotationController *MeasuredLibrary;
static WALStorageController *MeasuredJournal;
static NSUInteger FileWrites, SnapshotWrites, JournalWrites;
static void DanR2Swap(Class cls, SEL a, SEL b) {
    method_exchangeImplementations(class_getInstanceMethod(cls, a), class_getInstanceMethod(cls, b));
}
@interface NotationController (DanR2Operations)
- (NSString *)danR2_cacheDirectory;
- (OSStatus)danR2_store:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)ref
    verifyWithSelector:(SEL)selector verificationDelegate:(id)owner;
- (void)danR2_schedule:(NoteObject *)note;
@end
@implementation NotationController (DanR2Operations)
+ (void)load {
    if (getenv("NV_WINDOW_TEST_DIRECTORY"))
        DanR2Swap(self, @selector(createCachesFolder), @selector(danR2_cacheDirectory));
}
- (NSString *)danR2_cacheDirectory {
    NSString *path = [[[self notesDirectoryURL] path] stringByAppendingPathComponent:@".DanR2Journal"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    return path;
}
- (OSStatus)danR2_store:(NSData *)data withName:(NSString *)name destinationRef:(FSRef *)ref
    verifyWithSelector:(SEL)selector verificationDelegate:(id)owner {
    OSStatus result = [self danR2_store:data withName:name destinationRef:ref verifyWithSelector:selector verificationDelegate:owner];
    if (self == MeasuredLibrary && result == noErr) {
        if ([name isEqualToString:@"Notes & Settings"]) SnapshotWrites++;
        else FileWrites++;
    }
    return result;
}
- (void)danR2_schedule:(NoteObject *)note {
    [self danR2_schedule:note];
    // Sensitivity control: intentionally defeat batching through the real writer.
    if (self == MeasuredLibrary && getenv("NV_DAN_R2_FORCE_UNBATCHED"))
        [self synchronizeNoteChanges:nil];
}
@end
@interface WALStorageController (DanR2Operations)
- (BOOL)danR2_write:(id)note;
@end
@implementation WALStorageController (DanR2Operations)
- (BOOL)danR2_write:(id)note {
    BOOL result = [self danR2_write:note];
    if (self == MeasuredJournal && result) JournalWrites++;
    return result;
}
@end
static void DanR2Pump(NSTimeInterval interval) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:interval];
    do { [[NSRunLoop currentRunLoop] runUntilDate:end]; } while ([end timeIntervalSinceNow] > 0);
}
static NSString *DanR2Body(NSUInteger index) {
    return [NSString stringWithFormat:@"# Plain source %lu\r\nCafé and 😀 remain exact.\n{\"n\":%lu}\n", (unsigned long)index, (unsigned long)index];
}
static NotationController *DanR2Open(NSString *directory) {
    FSRef ref; OSStatus error = FSPathMakeRef((const UInt8 *)[directory fileSystemRepresentation], &ref, NULL);
    if (error != noErr) [NSException raise:@"Probe" format:@"directory error %d", error];
    NotationController *library = [[NotationController alloc] initWithDirectoryRef:&ref error:&error];
    if (!library || error != noErr) [NSException raise:@"Probe" format:@"library error %d", error];
    return library;
}
static NSUInteger DanR2PhysicalRecords(NSString *directory) {
    NSString *path = [directory stringByAppendingPathComponent:@".DanR2Journal/Interim Note-Changes"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) [NSException raise:@"Probe" format:@"missing disposable journal"];
    NSUInteger offset = 0, records = 0;
    while (offset < [data length]) {
        if ([data length] - offset < sizeof(WALRecordHeader))
            [NSException raise:@"Probe" format:@"partial journal header"];
        WALRecordHeader header;
        memcpy(&header, (const char *)[data bytes] + offset, sizeof(header));
        NSUInteger length = CFSwapInt32BigToHost(header.dataLength);
        offset += sizeof(header);
        if (!length || length > [data length] - offset)
            [NSException raise:@"Probe" format:@"partial journal payload"];
        offset += length; records++;
    }
    return records;
}
