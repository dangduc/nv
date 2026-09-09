#import <Foundation/Foundation.h>
#import "NVBackupStore.h"
#include <libproc.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

static NSUInteger checks;
static void Check(BOOL result, NSString *description) {
    checks++;
    if (!result) { fprintf(stderr, "FAIL: %s\n", [description UTF8String]); exit(1); }
}
static int DescriptorCount(void) {
    struct proc_fdinfo descriptors[1024];
    int bytes = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, descriptors, sizeof(descriptors));
    Check(bytes >= 0 && bytes < (int)sizeof(descriptors), @"read descriptor inventory without truncation");
    return bytes / (int)sizeof(descriptors[0]);
}

int main(int argc, const char **argv) {
    NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
    Check(argc == 2, @"fixture root argument");
    NSURL *root = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    NSURL *history = [root URLByAppendingPathComponent:@"history" isDirectory:YES];
    NSURL *restore = [root URLByAppendingPathComponent:@"restore" isDirectory:YES];
    Check([[NSFileManager defaultManager] createDirectoryAtURL:restore withIntermediateDirectories:YES attributes:nil error:NULL], @"create empty restore fixture");
    NSData *data = [NSMutableData dataWithLength:65536];
    NSDictionary *metadata = @{@"libraryIdentifier":@"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", @"generation":@1, @"encrypted":@0, @"appVersion":@"review"};
    NSDictionary *retention = @{@"recent":@3, @"daily":@0, @"weekly":@0, @"maxBytes":@1};
    NSError *error = nil;
    NSDictionary *first = [NVBackupStore publishArchiveData:data metadata:metadata inDirectory:history retention:retention error:&error];
    Check(first != nil && error == nil, @"warm successful publication");
    NSURL *firstURL = [first objectForKey:@"snapshotURL"];
    Check([[NVBackupStore archiveDataAtSnapshotURL:firstURL error:&error] isEqual:data], @"warm successful snapshot read");
    Check([NVBackupStore writeRestoreArchiveData:data toEmptyDirectory:restore error:&error], @"warm successful restore write");
    Check([[NSFileManager defaultManager] removeItemAtURL:[restore URLByAppendingPathComponent:@"Notes & Settings"] error:&error], @"clear own restore fixture");
    NSArray *failurePoints = @[@"stage-owner", @"archive-partial", @"sync-archive", @"manifest-partial", @"verify", @"sync-stage", @"rename"];
    int baseline = DescriptorCount();
    for (NSUInteger iteration = 0; iteration < 20; iteration++) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        for (NSString *point in failurePoints) {
            NVBackupStoreFailurePoint = point;
            Check(![NVBackupStore publishArchiveData:data metadata:metadata inDirectory:history retention:retention error:&error] && error != nil,
                [NSString stringWithFormat:@"publication failure at %@", point]);
            NVBackupStoreFailurePoint = nil;
            Check(DescriptorCount() == baseline, @"publication failure closes root, lock, and stage descriptors");
        }
        NSString *lockPath = [[history URLByAppendingPathComponent:@".nvbackup-lock"] path];
        int lock = open([lockPath fileSystemRepresentation], O_RDWR | O_CLOEXEC);
        Check(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0, @"hold real publication lock");
        Check(![NVBackupStore publishArchiveData:data metadata:metadata inDirectory:history retention:retention error:&error] && error != nil,
            @"real lock contention returns an error");
        close(lock);
        Check(DescriptorCount() == baseline, @"lock contention closes its descriptors");
        NVBackupStoreFailurePoint = @"restore-archive-partial";
        Check(![NVBackupStore writeRestoreArchiveData:data toEmptyDirectory:restore error:&error] && error != nil, @"failed partial restore reports error");
        NVBackupStoreFailurePoint = nil;
        Check(DescriptorCount() == baseline, @"failed partial restore closes its descriptors");
        Check([[[NSFileManager defaultManager] contentsOfDirectoryAtURL:restore includingPropertiesForKeys:nil options:0 error:&error] count] == 0,
            @"failed restore removes only its temporary file");
        Check([[NVBackupStore archiveDataAtSnapshotURL:firstURL error:&error] isEqual:data], @"all failures preserve complete existing backup");
        Check([[NVBackupStore snapshotsInDirectory:history error:&error] count] == 1, @"all failures leave one complete backup");
        Check([NVBackupStore pruneSnapshotsInDirectory:history retention:retention error:&error], @"small retention target preserves minimum");
        [pool drain];
        Check(DescriptorCount() == baseline, @"enumeration and retention close descriptors after draining autoreleases");
    }
    Check([NVBackupStore deleteUnencryptedSnapshotsInDirectory:history error:&error], @"explicit plaintext deletion succeeds");
    Check([[NVBackupStore snapshotsInDirectory:history error:&error] count] == 0, @"plaintext deletion leaves no complete package");
    Check(DescriptorCount() == baseline, @"explicit deletion closes all descriptors");
    printf("PASS: %lu checks; 140 injected publication failures, 20 real lock-contention failures, 20 partial-restore failures; descriptor count %d -> %d\n",
        (unsigned long)checks, baseline, DescriptorCount());
    [outerPool drain];
    return 0;
}
