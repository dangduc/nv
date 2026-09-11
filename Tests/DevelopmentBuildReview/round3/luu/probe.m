#import <Cocoa/Cocoa.h>
#import <dispatch/dispatch.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <time.h>
@IDENTITY@

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static double Now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static NSUInteger calls[6], mainCalls, libraryCalls, completions, beats;
static BOOL recording = YES, holdNamespace = YES, nextSync;
static dispatch_semaphore_t entered, resume;
static void Count(int slot) { if (recording) { calls[slot]++; if ([NSThread isMainThread]) mainCalls++; } }
static int TraceOpen(const char *name, int flags) { Count(0); return open(name, flags); }
static int TraceOpenat(int fd, const char *name, int flags) { Count(1); return openat(fd, name, flags); }
static int TraceMkdirat(int fd, const char *name, mode_t mode) {
    Count(2);
    if (holdNamespace && !strcmp(name, "nvALT Development")) nextSync = YES;
    return mkdirat(fd, name, mode);
}
static int TraceFsync(int fd) {
    Count(3);
    if (nextSync) {
        nextSync = NO;
        dispatch_semaphore_signal(entered);
        Check(dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0, @"bounded namespace gate released");
    }
    return fsync(fd);
}
static int TraceClose(int fd) { Count(4); return close(fd); }
static int TraceFstat(int fd, struct stat *info) { Count(5); return fstat(fd, info); }
static NSDictionary *Counts(void) {
    return @{ @"open":@(calls[0]), @"openat":@(calls[1]), @"mkdirat":@(calls[2]), @"fsync":@(calls[3]), @"close":@(calls[4]), @"fstat":@(calls[5]), @"main_thread_calls":@(mainCalls) };
}
static NSString * const NVBackupStoreErrorDomain = @"ProbeStore";
@STORE_HELPERS@
#define open TraceOpen
#define openat TraceOpenat
#define mkdirat TraceMkdirat
#define fsync TraceFsync
#define close TraceClose
#define fstat TraceFstat
@OPENING@
#undef open
#undef openat
#undef mkdirat
#undef fsync
#undef close
#undef fstat

@CONTROLLER_HELPERS@
static NSString * const LibraryID = @"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static NSString *TestRoot;
@interface NSFileManager (ProbeSupport)
- (NSString *)applicationSupportDirectory;
@end
@implementation NSFileManager (ProbeSupport)
- (NSString *)applicationSupportDirectory { Check(NO, @"custom root required"); return nil; }
@end
@interface ProbeLibrary : NSObject
- (NSURL *)notesDirectoryURL;
- (NSDictionary *)backupSnapshotWithError:(NSError **)error;
@end
@implementation ProbeLibrary
- (NSURL *)notesDirectoryURL { Check([NSThread isMainThread], @"library URL stays on main thread"); libraryCalls++; return [NSURL fileURLWithPath:[TestRoot stringByAppendingPathComponent:@"notes"]]; }
- (NSDictionary *)backupSnapshotWithError:(NSError **)error {
    Check([NSThread isMainThread], @"capture stays on main thread"); libraryCalls++;
    return @{@"data":[@"fixture bytes" dataUsingEncoding:NSUTF8StringEncoding], @"generation":@1, @"libraryIdentifier":LibraryID};
}
@end
@interface NVBackupStore : NSObject
+ (NSData *)archiveDataAtSnapshotURL:(NSURL *)url error:(NSError **)error;
+ (NSDictionary *)publishArchiveData:(NSData *)data metadata:(NSDictionary *)metadata inDirectory:(NSURL *)directory retention:(NSDictionary *)retention error:(NSError **)error;
+ (BOOL)pruneSnapshotsInDirectory:(NSURL *)directory metadata:(NSDictionary *)metadata retention:(NSDictionary *)retention error:(NSError **)error;
+ (NSArray *)snapshotsInDirectory:(NSURL *)directory error:(NSError **)error;
@end
@implementation NVBackupStore
+ (NSData *)archiveDataAtSnapshotURL:(NSURL *)url error:(NSError **)error { Check(NO, @"manual first backup skips previous reads"); return nil; }
+ (NSDictionary *)publishArchiveData:(NSData *)data metadata:(NSDictionary *)metadata inDirectory:(NSURL *)directory retention:(NSDictionary *)retention error:(NSError **)error {
    Check(![NSThread isMainThread], @"store runs on worker");
    Check([[metadata objectForKey:@"directoryNamespace"] isEqual:@"nvALT Development"], @"captured namespace reaches worker");
    Check([data isEqual:[@"fixture bytes" dataUsingEncoding:NSUTF8StringEncoding]], @"captured bytes reach worker");
    int fd = NVOpenOperationDirectory(directory, metadata, YES, error);
    Check(fd >= 0, @"real namespace and UUID directory creation succeeds");
    TraceClose(fd);
    return @{@"date":[NSDate date], @"snapshotURL":[directory URLByAppendingPathComponent:@"BBBBBBBB-BBBB-4CCC-8DDD-EEEEEEEEEEEE.nvbackup"]};
}
+ (BOOL)pruneSnapshotsInDirectory:(NSURL *)directory metadata:(NSDictionary *)metadata retention:(NSDictionary *)retention error:(NSError **)error { Check(NO, @"first backup has no unchanged maintenance"); return NO; }
+ (NSArray *)snapshotsInDirectory:(NSURL *)directory error:(NSError **)error { Check(![NSThread isMainThread], @"listing stays on worker"); return @[]; }
@end
@interface ProbeController : NSObject {
@public
    ProbeLibrary *library;
    NSString *libraryIdentifier, *latestNotice;
    NSMutableDictionary *librarySettings;
    NSOperationQueue *worker;
    NSUInteger contextGeneration;
    long long lastRetentionDay;
    BOOL busy, stopped, retentionPending;
}
- (BOOL)hasLibrary;
- (NSDictionary *)settings;
- (void)scheduleNextAttemptAfterDelay:(NSTimeInterval)delay fromDate:(NSDate *)date;
- (void)setError:(NSError *)error;
- (void)changed;
- (void)saveSettings;
- (NSURL *)rootURLWithError:(NSError **)error;
- (NSURL *)checkedDestinationWithError:(NSError **)error;
- (void)beginBackupAtDate:(NSDate *)date manual:(BOOL)manual;
- (void)pulse:(NSTimer *)timer;
@end
@implementation ProbeController
- (BOOL)hasLibrary { return YES; }
- (NSDictionary *)settings { return [[librarySettings copy] autorelease]; }
- (void)scheduleNextAttemptAfterDelay:(NSTimeInterval)delay fromDate:(NSDate *)date { Check([NSThread isMainThread], @"schedule ownership"); }
- (void)setError:(NSError *)error { Check([NSThread isMainThread] && !error, @"successful main completion"); completions++; }
- (void)changed { Check([NSThread isMainThread], @"status ownership"); }
- (void)saveSettings { Check([NSThread isMainThread], @"settings ownership"); }
- (void)pulse:(NSTimer *)timer { beats++; }
@CONTROLLER_METHODS@
@end

static NSDictionary *Metadata(NSURL *root, BOOL development) {
    struct stat info;
    Check(stat(root.path.fileSystemRepresentation, &info) == 0, @"fixture root exists");
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:@{@"existingRoot":root, @"libraryIdentifier":LibraryID, @"existingRootIdentity":[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev, (unsigned long long)info.st_ino]}];
    if (development) [metadata setObject:@"nvALT Development" forKey:@"directoryNamespace"];
    return metadata;
}
static NSURL *Destination(NSURL *root, BOOL development) {
    return [(development ? [root URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES] : root) URLByAppendingPathComponent:LibraryID isDirectory:YES];
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2 && NVIsDevelopmentBuild(), @"disposable Development bundle");
        TestRoot = [NSString stringWithUTF8String:argv[1]];
        NSURL *custom = [NSURL fileURLWithPath:[TestRoot stringByAppendingPathComponent:@"custom"] isDirectory:YES];
        Check([[NSFileManager defaultManager] createDirectoryAtURL:custom withIntermediateDirectories:NO attributes:nil error:NULL], @"custom root created");
        NSData *bookmark = [custom bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
        Check(bookmark != nil, @"real temporary bookmark");
        entered = dispatch_semaphore_create(0); resume = dispatch_semaphore_create(0);
        ProbeController *controller = [ProbeController new];
        controller->library = [ProbeLibrary new]; controller->libraryIdentifier = LibraryID;
        controller->librarySettings = [@{@"destinationBookmark":bookmark, @"interval":@900, @"maxBytes":@1048576} mutableCopy];
        controller->worker = [NSOperationQueue new];
        [controller->worker setMaxConcurrentOperationCount:1];
        [controller->worker setQualityOfService:NSQualityOfServiceUtility];
        double start = Now();
        [controller beginBackupAtDate:[NSDate date] manual:YES];
        double entryMs = (Now() - start) * 1000;
        Check(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, @"worker reached namespace synchronization");
        Check(controller->busy && completions == 0, @"worker remains incomplete while main runs");
        NSUInteger capturesBefore = libraryCalls;
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.002 target:controller selector:@selector(pulse:) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
        [timer invalidate];
        Check(beats >= 3 && controller->busy && completions == 0, @"main timer advances while namespace fsync is held");
        dispatch_semaphore_signal(resume);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (controller->busy && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
        Check(!controller->busy && completions == 1 && libraryCalls == capturesBefore, @"completion returns to main without worker library access");
        Check(mainCalls == 0 && calls[2] == 2 && calls[3] == 2, @"new namespace and UUID require two worker creates and syncs");
        NSMutableDictionary *report = [NSMutableDictionary dictionaryWithDictionary:@{@"controller_entry_ms":@(entryMs), @"main_timer_beats_while_worker_held":@(beats), @"library_calls_on_main":@(libraryCalls), @"completion_count":@(completions), @"first_development_open_syscalls":Counts()}];
        holdNamespace = NO;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [controller->worker addOperationWithBlock:^{ @autoreleasepool {
            NSMutableDictionary *counts = [NSMutableDictionary dictionary], *times = [NSMutableDictionary dictionary];
            for (NSNumber *development in @[@NO, @YES]) {
                BOOL dev = development.boolValue;
                NSString *label = dev ? @"development" : @"release";
                NSURL *root = dev ? custom : [NSURL fileURLWithPath:[TestRoot stringByAppendingPathComponent:@"release"] isDirectory:YES];
                if (!dev) Check([[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:NO attributes:nil error:NULL], @"release root exists");
                NSDictionary *metadata = Metadata(root, dev);
                NSURL *destination = Destination(root, dev);
                NSError *error = nil;
                if (!dev) {
                    memset(calls, 0, sizeof(calls)); mainCalls = 0;
                    int fd = NVOpenOperationDirectory(destination, metadata, YES, &error);
                    Check(fd >= 0 && !error, @"release first open succeeds"); TraceClose(fd);
                    [report setObject:Counts() forKey:@"first_release_open_syscalls"];
                }
                memset(calls, 0, sizeof(calls)); mainCalls = 0;
                int fd = NVOpenOperationDirectory(destination, metadata, NO, &error);
                Check(fd >= 0 && !error, @"warm open succeeds"); TraceClose(fd);
                Check(calls[2] == 0 && calls[3] == 0 && mainCalls == 0, @"warm worker path creates and syncs nothing");
                [counts setObject:Counts() forKey:label];
                recording = NO;
                NSMutableArray *samples = [NSMutableArray array];
                for (int rep = 0; rep < 9; rep++) {
                    double start = Now();
                    for (int iteration = 0; iteration < 100; iteration++) { @autoreleasepool {
                        int fd = NVOpenOperationDirectory(destination, metadata, NO, &error);
                        Check(fd >= 0 && !error, @"timed warm open succeeds"); TraceClose(fd);
                    }}
                    [samples addObject:@((Now() - start) * 1e6 / 100)];
                }
                recording = YES;
                [times setObject:samples forKey:label];
            }
            [report setObject:counts forKey:@"warm_open_syscalls"];
            [report setObject:times forKey:@"warm_open_microseconds"];
            dispatch_semaphore_signal(done);
        }}];
        Check(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, @"bounded worker benchmark completed");
        NSDictionary *release = [report[@"warm_open_syscalls"] objectForKey:@"release"];
        NSDictionary *development = [report[@"warm_open_syscalls"] objectForKey:@"development"];
        Check([development[@"openat"] integerValue] == [release[@"openat"] integerValue] + 1, @"namespace adds one warm openat");
        Check([development[@"close"] integerValue] == [release[@"close"] integerValue] + 1, @"namespace adds one warm close");
        Check(NSApp == nil, @"no application or GUI created");
        report[@"result"] = @"PASS";
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        printf("%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
    }
    return 0;
}
