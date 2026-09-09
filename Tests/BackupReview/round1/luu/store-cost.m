#import <Foundation/Foundation.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/resource.h>

// Count bytes returned by the production store's read calls. The descriptor
// size distinguishes the 1 MiB archive fixture from its small plist files.
static unsigned long long ArchiveReadBytes;
static ssize_t MeasuredRead(int descriptor, void *buffer, size_t size) {
    ssize_t count = read(descriptor, buffer, size);
    struct stat info;
    if (count > 0 && fstat(descriptor, &info) == 0 && info.st_size >= 1024 * 1024)
        ArchiveReadBytes += (unsigned long long)count;
    return count;
}
#define read MeasuredRead
#include "Sources/Storage/NVBackupStore.m"
#undef read

static void Check(BOOL success, NSString *description) {
    if (!success) { NSLog(@"FAIL: %@", description); exit(1); }
}
int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc == 2, @"disposable root supplied");
    NSURL *root = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    NSString *library = [[NSUUID UUID] UUIDString];
    NSURL *destination = [root URLByAppendingPathComponent:library isDirectory:YES];
    NSMutableData *data = [NSMutableData dataWithLength:1024 * 1024];
    memset([data mutableBytes], 0x51, [data length]);
    NSDictionary *metadata = @{@"libraryIdentifier":library, @"generation":@1, @"encrypted":@NO, @"appVersion":@"review"};
    NSDictionary *retention = @{@"recent":@100, @"daily":@0, @"weekly":@0, @"maxBytes":@(2ULL*1024*1024*1024)};
    NSError *error = nil;
    NSDictionary *first = [NVBackupStore publishArchiveData:data metadata:metadata inDirectory:destination retention:retention error:&error];
    Check(first && !error, @"production publisher creates first snapshot");
    NSURL *firstURL = [first objectForKey:@"snapshotURL"];
    for (NSUInteger index = 1; index < 96; index++) { @autoreleasepool {
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSURL *copy = [destination URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"nvbackup"] isDirectory:YES];
        Check([[NSFileManager defaultManager] copyItemAtURL:firstURL toURL:copy error:&error], @"copy bounded fixture");
        NSMutableDictionary *manifest = [NSMutableDictionary dictionaryWithContentsOfURL:[copy URLByAppendingPathComponent:@"manifest.plist"]];
        [manifest setObject:identifier forKey:@"snapshotIdentifier"];
        Check([manifest writeToURL:[copy URLByAppendingPathComponent:@"manifest.plist"] atomically:YES], @"match copied manifest identity");
    }}
    Check([[NVBackupStore snapshotsInDirectory:destination error:&error] count] == 96, @"all 96 packages pass production verification");
    ArchiveReadBytes = 0;
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    NSDictionary *result = [NVBackupStore publishArchiveData:data metadata:metadata inDirectory:destination retention:retention error:&error];
    NSTimeInterval published = [NSDate timeIntervalSinceReferenceDate];
    unsigned long long publishReads = ArchiveReadBytes;
    Check(result && !error, @"publish measurement succeeds");
    NSArray *entries = [NVBackupStore snapshotsInDirectory:destination error:&error];
    NSTimeInterval listed = [NSDate timeIntervalSinceReferenceDate];
    Check([entries count] == 97 && !error, @"post-publication status listing succeeds");
    Check(publishReads == 98ULL * [data length], @"publisher reads new archive once and scans 97 snapshots");
    Check(ArchiveReadBytes == 195ULL * [data length], @"post-publication listing repeats all 97 reads");
    struct rusage usage; getrusage(RUSAGE_SELF, &usage);
    printf("STORE_COST retained_before=96 archive_mib=1 publish_archive_read_mib=%.0f status_archive_read_mib=%.0f total_archive_read_mib=%.0f publish_ms=%.2f status_ms=%.2f peak_rss_mib=%.2f\n",
        publishReads/1048576.0, (ArchiveReadBytes-publishReads)/1048576.0, ArchiveReadBytes/1048576.0,
        (published-start)*1000, (listed-published)*1000, usage.ru_maxrss/1048576.0);
    puts("PASS: measured actual production filesystem operations; no GUI or archive decoder");
}}
