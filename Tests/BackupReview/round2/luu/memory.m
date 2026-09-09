#import <Foundation/Foundation.h>
#include <sys/resource.h>
#include <string.h>
#import "Sources/Storage/NVBackupStore.h"
extern unsigned long long ReviewArchiveReadBytes;
static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    Check(argc == 3, @"temporary directory and package count supplied");
    NSUInteger packageCount = (NSUInteger)strtoul(argv[2], NULL, 10);
    Check(packageCount == 8 || packageCount == 48, @"fixture size is bounded");
    const NSUInteger archiveSize = 2 * 1024 * 1024;
    NSString *library = [[NSUUID UUID] UUIDString];
    NSURL *root = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    NSURL *directory = [root URLByAppendingPathComponent:library isDirectory:YES];
    NSMutableData *data = [NSMutableData dataWithLength:archiveSize];
    memset([data mutableBytes], 0x52, [data length]);
    NSError *error = nil;
    NSDictionary *metadata = @{@"libraryIdentifier":library, @"generation":@1, @"encrypted":@NO, @"appVersion":@"review"};
    NSDictionary *retention = @{@"recent":@64, @"daily":@0, @"weekly":@0};
    NSDictionary *first = [NVBackupStore publishArchiveData:data metadata:metadata inDirectory:directory retention:retention error:&error];
    Check(first && !error, @"first production package created");
    for (NSUInteger index=1; index<packageCount; index++) { @autoreleasepool {
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSURL *copy = [directory URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"nvbackup"] isDirectory:YES];
        Check([[NSFileManager defaultManager] copyItemAtURL:[first objectForKey:@"snapshotURL"] toURL:copy error:&error], @"copy bounded fixture");
        NSMutableDictionary *manifest = [NSMutableDictionary dictionaryWithContentsOfURL:[copy URLByAppendingPathComponent:@"manifest.plist"]];
        [manifest setObject:identifier forKey:@"snapshotIdentifier"];
        Check([manifest writeToURL:[copy URLByAppendingPathComponent:@"manifest.plist"] atomically:YES], @"copied manifest matches package identity");
    }}
    ReviewArchiveReadBytes = 0;
    NSArray *entries = [NVBackupStore snapshotsInDirectory:directory error:&error];
    Check([entries count] == packageCount && !error, @"every package passes production checksum checks");
    Check(ReviewArchiveReadBytes == packageCount * archiveSize, @"every archive was read in full");
    for (NSDictionary *entry in entries) Check(![entry objectForKey:@"data"], @"listing does not retain archive payloads in its result");
    struct rusage usage;
    Check(getrusage(RUSAGE_SELF, &usage) == 0, @"peak RSS available");
    printf("LIST_MEMORY packages=%lu archive_mib=2 retained_archive_mib=%lu peak_rss_bytes=%ld peak_rss_mib=%.2f\n", (unsigned long)packageCount, (unsigned long)packageCount*2, usage.ru_maxrss, usage.ru_maxrss/1048576.0);
}}
