#import <Foundation/Foundation.h>
#import "NVBackupStore.h"
#include <libproc.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <limits.h>

static NSUInteger checks;
static NSString *library = @"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static NSString *otherLibrary = @"BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF";
static NSData *payload;
static NSDictionary *unlimited, *tight;

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
static void Create(NSURL *url) {
    Check([[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:NULL], @"create disposable directory");
}
static NSString *Identity(NSURL *url) {
    struct stat info;
    Check(stat([[url path] fileSystemRepresentation], &info) == 0, @"capture root identity");
    return [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev, (unsigned long long)info.st_ino];
}
static NSDictionary *Metadata(NSString *identifier, BOOL encrypted) {
    return @{@"libraryIdentifier":identifier, @"generation":@17, @"encrypted":@(encrypted), @"appVersion":@"review-r2"};
}
static NSMutableDictionary *Selected(NSURL *root) {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:Metadata(library, NO)];
    [metadata setObject:root forKey:@"existingRoot"];
    [metadata setObject:Identity(root) forKey:@"existingRootIdentity"];
    return metadata;
}
static NSDictionary *Publish(NSURL *directory, NSDictionary *metadata) {
    NSError *error = nil;
    NSDictionary *result = [NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:directory retention:unlimited error:&error];
    Check(result && !error, [NSString stringWithFormat:@"publish disposable fixture: %@", error]);
    return result;
}
static NSArray *List(NSURL *directory) {
    NSError *error = nil;
    NSArray *result = [NVBackupStore snapshotsInDirectory:directory error:&error];
    Check(result && !error, @"list complete fixtures");
    return result;
}
static void Failure(NSURL *directory, NSDictionary *metadata, NSInteger code, int descriptors) {
    NSError *error = nil;
    Check(![NVBackupStore pruneSnapshotsInDirectory:directory metadata:metadata retention:tight error:&error], @"maintenance rejects fixture");
    Check([[error domain] isEqual:NVBackupStoreErrorDomain] && [error code] == code, @"maintenance supplies the expected error");
    Check(![NVBackupStore pruneSnapshotsInDirectory:directory metadata:metadata retention:tight error:NULL], @"error pointer is optional");
    Check(DescriptorCount() == descriptors, @"failed maintenance closes every descriptor");
}

int main(int argc, const char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Check(argc == 2, @"fixture root argument");
    NSURL *root = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    Create(root);
    payload = [@"Disposable backup review content" dataUsingEncoding:NSUTF8StringEncoding];
    unlimited = @{@"recent":@1000, @"daily":@0, @"weekly":@0, @"maxBytes":@(ULLONG_MAX)};
    tight = @{@"recent":@3, @"daily":@0, @"weekly":@0, @"maxBytes":@0};
    NVBackupStoreCurrentDate = [NSDate dateWithTimeIntervalSince1970:1788782400];
    NSURL *selected = [root URLByAppendingPathComponent:@"selected" isDirectory:YES];
    Create(selected);
    NSMutableDictionary *metadata = Selected(selected);
    NSURL *history = [selected URLByAppendingPathComponent:library isDirectory:YES];
    for (NSUInteger index = 0; index < 9; index++) Publish(history, metadata);
    NSArray *entries = List(history);
    NSString *protectedIdentifier = [[entries lastObject] objectForKey:@"snapshotIdentifier"];
    NSURL *protectedURL = [[entries lastObject] objectForKey:@"snapshotURL"];
    [metadata setObject:protectedIdentifier forKey:@"protectedSnapshotIdentifier"];
    int baseline = DescriptorCount();

    for (NSUInteger iteration = 0; iteration < 10; iteration++) {
        NSAutoreleasePool *iterationPool = [[NSAutoreleasePool alloc] init];
        NSMutableDictionary *bad = [[metadata mutableCopy] autorelease];
        [bad setObject:@"invalid" forKey:@"libraryIdentifier"];
        Failure(history, bad, EINVAL, baseline);
        bad = [[metadata mutableCopy] autorelease];
        [bad setObject:@"invalid" forKey:@"protectedSnapshotIdentifier"];
        Failure(history, bad, EINVAL, baseline);
        bad = [[metadata mutableCopy] autorelease];
        [bad removeObjectForKey:@"existingRootIdentity"];
        Failure(history, bad, EINVAL, baseline);
        bad = [[metadata mutableCopy] autorelease];
        [bad setObject:@"0:0" forKey:@"existingRootIdentity"];
        Failure(history, bad, ESTALE, baseline);
        Failure([selected URLByAppendingPathComponent:@"wrong-child"], metadata, EINVAL, baseline);
        Failure([root URLByAppendingPathComponent:@"missing/default"], Metadata(library, NO), ENOENT, baseline);
        Check(![[NSFileManager defaultManager] fileExistsAtPath:[[root URLByAppendingPathComponent:@"missing"] path]], @"default maintenance creates no ancestor");
        int lock = open([[[history URLByAppendingPathComponent:@".nvbackup-lock"] path] fileSystemRepresentation], O_RDWR | O_CLOEXEC);
        Check(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0, @"hold real destination lock");
        Failure(history, metadata, EWOULDBLOCK, baseline + 1);
        close(lock);
        NVBackupStoreFailurePoint = @"prune";
        Failure(history, metadata, EIO, baseline);
        NVBackupStoreFailurePoint = nil;
        Check([List(history) count] == 9, @"failed maintenance preserves all complete snapshots");
        [iterationPool drain];
        Check(DescriptorCount() == baseline, @"maintenance failure objects release without open descriptors");
    }
    NVBackupStoreFailurePoint = @"sync-prune";
    NSError *error = nil;
    Check(![NVBackupStore pruneSnapshotsInDirectory:history metadata:metadata retention:tight error:&error] && [error code] == EIO, @"retention reports the final sync failure");
    NVBackupStoreFailurePoint = nil;
    Check([List(history) count] == 3, @"completed deletions retain three complete snapshots");
    Check([[NVBackupStore archiveDataAtSnapshotURL:protectedURL error:NULL] isEqual:payload], @"equal-date maintenance preserves its designated current snapshot");
    Check([NVBackupStore pruneSnapshotsInDirectory:history metadata:metadata retention:tight error:&error] && !error, @"retry succeeds and clears the previous error");
    Check(DescriptorCount() == baseline, @"successful maintenance and retry close descriptors");

    NSURL *emptyRoot = [root URLByAppendingPathComponent:@"empty-selected" isDirectory:YES];
    Create(emptyRoot);
    NSMutableDictionary *emptyMetadata = Selected(emptyRoot);
    NSURL *absentChild = [emptyRoot URLByAppendingPathComponent:library isDirectory:YES];
    Failure(absentChild, emptyMetadata, ENOENT, baseline);
    Check([[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[emptyRoot path] error:NULL] count] == 0, @"maintenance creates neither absent child nor lock");
    Check([[NSFileManager defaultManager] removeItemAtURL:emptyRoot error:NULL], @"delete empty selected fixture");
    Failure(absentChild, emptyMetadata, ENOENT, baseline);
    Check(![[NSFileManager defaultManager] fileExistsAtPath:[emptyRoot path]], @"maintenance does not recreate the selected root");

    // Ordinary misplaced-library fixture: copy library B's complete folder into
    // library A's expected child. No concurrent mutation or linked paths occur.
    NSURL *source = [root URLByAppendingPathComponent:@"foreign-source" isDirectory:YES];
    Publish(source, Metadata(otherLibrary, NO));
    Publish(source, Metadata(otherLibrary, YES));
    NSURL *misfiledRoot = [root URLByAppendingPathComponent:@"misfiled" isDirectory:YES];
    Create(misfiledRoot);
    NSURL *misfiled = [misfiledRoot URLByAppendingPathComponent:library isDirectory:YES];
    Check([[NSFileManager defaultManager] copyItemAtURL:source toURL:misfiled error:NULL], @"copy foreign library folder to the wrong child");
    Failure(misfiled, Selected(misfiledRoot), EINVAL, baseline);
    Check([List(misfiled) count] == 2, @"maintenance rejects the owner mismatch before deletion");
    Check([NVBackupStore deleteUnencryptedSnapshotsInDirectory:misfiled error:&error] && !error, @"path-only plaintext deletion accepts the destination owner");
    NSArray *remaining = List(misfiled);
    Check([remaining count] == 1 && [[[remaining firstObject] objectForKey:@"encrypted"] boolValue], @"path-only deletion deletes the foreign plaintext fixture");
    Check([List(source) count] == 2, @"source fixtures remain intact");
    Check(DescriptorCount() == baseline, @"owner rejection and plaintext deletion close descriptors");
    printf("OBSERVED: misplaced library B folder under library A's child: maintenance rejects ownership; path-only plaintext deletion deletes B's plaintext snapshot.\n");
    printf("PASS: %lu checks; 160 rejected maintenance calls; equal-date protection and sync retry; descriptor count %d -> %d\n", (unsigned long)checks, baseline, DescriptorCount());
    NVBackupStoreCurrentDate = nil;
    [pool drain];
    return 0;
}
