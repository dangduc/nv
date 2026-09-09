#import <Foundation/Foundation.h>
#import "NVBackupStore.h"
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <limits.h>

static NSUInteger checks = 0;
static NSURL *testRoot;
static NSString *library = @"AEEEEEEE-1111-4222-8333-123456789ABC";
static NSData *payload;
static NSDictionary *unlimited;

static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
}

static NSURL *Folder(NSString *name) {
    return [testRoot URLByAppendingPathComponent:name isDirectory:YES];
}

static NSDictionary *Metadata(NSUInteger generation, BOOL encrypted) {
    return @{ @"libraryIdentifier": library, @"generation": @(generation), @"encrypted": @(encrypted), @"appVersion": @"test" };
}

static NSDictionary *Publish(NSURL *folder, NSUInteger generation, BOOL encrypted) {
    NSError *error = nil;
    NSDictionary *result = [NVBackupStore publishArchiveData:payload metadata:Metadata(generation, encrypted) inDirectory:folder retention:unlimited error:&error];
    Check(result != nil && error == nil, [NSString stringWithFormat:@"publish %lu: %@", (unsigned long)generation, error]);
    return result;
}

static NSArray *Snapshots(NSURL *folder) {
    NSError *error = nil;
    NSArray *snapshots = [NVBackupStore snapshotsInDirectory:folder error:&error];
    Check(snapshots != nil && error == nil, [NSString stringWithFormat:@"list: %@", error]);
    return snapshots;
}

static void ChangeManifest(NSURL *snapshot, NSString *key, id value) {
    NSURL *url = [snapshot URLByAppendingPathComponent:@"manifest.plist"];
    NSMutableDictionary *manifest = [NSMutableDictionary dictionaryWithContentsOfURL:url];
    [manifest setObject:value forKey:key];
    Check([manifest writeToURL:url atomically:YES], @"write modified manifest fixture");
}

static NSSet *Generations(NSURL *folder) {
    return [NSSet setWithArray:[Snapshots(folder) valueForKey:@"generation"]];
}

static void Basic(void) {
    NSURL *folder = Folder(@"basic");
    NSDictionary *first = Publish(folder, 1, NO);
    NSURL *url = [first objectForKey:@"snapshotURL"];
    NSError *error = nil;
    Check([[NVBackupStore archiveDataAtSnapshotURL:url error:&error] isEqual:payload] && !error, @"archive bytes round trip");
    Check([[Snapshots(folder) firstObject] isEqual:first], @"published and listed metadata agree");
    struct stat attributes;
    Check(lstat([[url path] fileSystemRepresentation], &attributes) == 0 && (attributes.st_mode & 0777) == 0700, @"private snapshot directory");
    Check(lstat([[[url URLByAppendingPathComponent:@"Notes & Settings"] path] fileSystemRepresentation], &attributes) == 0 &&
        (attributes.st_mode & 0777) == 0600, @"private archive");
    NSMutableDictionary *other = [NSMutableDictionary dictionaryWithDictionary:Metadata(2, NO)];
    [other setObject:[[NSUUID UUID] UUIDString] forKey:@"libraryIdentifier"];
    Check(![NVBackupStore publishArchiveData:payload metadata:other inDirectory:folder retention:unlimited error:&error] && error, @"foreign library cannot claim destination");
    Check([Snapshots(folder) count] == 1, @"ownership failure preserves snapshot");
    Check([[NVBackupStore snapshotsInDirectory:Folder(@"missing") error:&error] count] == 0 && !error, @"missing destination lists empty");
    [other setObject:@"not-a-uuid" forKey:@"libraryIdentifier"];
    Check(![NVBackupStore publishArchiveData:payload metadata:other inDirectory:Folder(@"invalid") retention:unlimited error:&error] && error, @"reject invalid capture metadata");
}

static void Faults(void) {
    NSArray *points = @[@"create-stage", @"stage-owner", @"archive", @"archive-partial", @"sync-archive", @"manifest", @"manifest-partial", @"sync-manifest", @"verify", @"sync-stage", @"rename", @"sync-directory"];
    for (NSString *point in points) {
        NSURL *folder = Folder([@"fault-" stringByAppendingString:point]);
        NSDictionary *first = Publish(folder, 1, NO);
        NVBackupStoreFailurePoint = point;
        NSError *error = nil;
        NSDictionary *failed = [NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:folder retention:@{@"recent": @0, @"maxBytes": @0} error:&error];
        NVBackupStoreFailurePoint = nil;
        Check(!failed && error, [@"failure reported at " stringByAppendingString:point]);
        Check([[NVBackupStore archiveDataAtSnapshotURL:[first objectForKey:@"snapshotURL"] error:&error] isEqual:payload], @"failure preserves earlier archive");
        NSUInteger expected = [point isEqualToString:@"sync-directory"] ? 2 : 1;
        Check([Snapshots(folder) count] == expected, @"only complete publications are visible");
        Publish(folder, 3, YES);
        Check([Snapshots(folder) count] == expected + 1, @"failed job can retry");
    }
    for (NSString *point in @[@"owner", @"owner-partial", @"sync-owner", @"sync-owner-directory"]) {
        NSURL *folder = Folder([@"fault-" stringByAppendingString:point]);
        NSError *error = nil;
        NVBackupStoreFailurePoint = point;
        Check(![NVBackupStore publishArchiveData:payload metadata:Metadata(1, NO) inDirectory:folder retention:unlimited error:&error] && error, @"owner creation failure reported");
        NVBackupStoreFailurePoint = nil;
        Publish(folder, 2, NO);
        Check([Snapshots(folder) count] == 1, @"incomplete owner creation does not prevent retry");
    }
    NSURL *folder = Folder(@"failed-retention");
    Publish(folder, 1, NO);
    NVBackupStoreFailurePoint = @"prune";
    NSError *error = nil;
    NSDictionary *published = [NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:folder retention:unlimited error:&error];
    NVBackupStoreFailurePoint = nil;
    Check(published && !error && [[published objectForKey:@"retentionError"] isKindOfClass:[NSError class]], @"retention error preserves publication success");
    Check([Snapshots(folder) count] == 2, @"retention failure preserves both snapshots");

    for (NSNumber *failureCode in @[@(ENOSPC), @(EACCES)]) {
        NSURL *destination = Folder([NSString stringWithFormat:@"errno-%@", failureCode]);
        Publish(destination, 1, NO);
        NVBackupStoreFailurePoint = @"archive-partial";
        NVBackupStoreFailureCode = [failureCode intValue];
        Check(![NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:destination retention:unlimited error:&error] &&
            [error code] == [failureCode integerValue], @"report disk-full or permission error after a partial write");
        NVBackupStoreFailurePoint = nil;
        NVBackupStoreFailureCode = EIO;
        Check([Snapshots(destination) count] == 1, @"disk-full or permission error preserves earlier snapshot");
    }

    NSURL *permissions = Folder(@"permissions");
    Publish(permissions, 1, NO);
    if (getuid() != 0) {
        Check(chmod([[permissions path] fileSystemRepresentation], 0500) == 0, @"remove destination write permission");
        Check(![NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:permissions retention:unlimited error:&error] &&
            [error code] == EACCES, @"real filesystem permission failure is reported");
        Check(chmod([[permissions path] fileSystemRepresentation], 0700) == 0, @"restore destination write permission");
        Check([Snapshots(permissions) count] == 1, @"permission failure preserves complete snapshot");
    }
    int lock = open([[[permissions URLByAppendingPathComponent:@".nvbackup-lock"] path] fileSystemRepresentation], O_RDWR);
    Check(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0, @"hold destination lock");
    Check(![NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:permissions retention:unlimited error:&error] &&
        [error code] == EWOULDBLOCK, @"overlapping publisher cannot prune or write");
    close(lock);
    Check([Snapshots(permissions) count] == 1, @"lock contention preserves complete snapshot");
}

static void Interrupted(void) {
    for (NSString *point in @[@"archive-partial", @"sync-stage", @"rename", @"sync-directory"]) {
        NSURL *folder = Folder([@"crash-" stringByAppendingString:point]);
        NSDictionary *first = Publish(folder, 1, NO);
        pid_t child = fork();
        Check(child >= 0, @"fork interrupted publication fixture");
        if (child == 0) {
            NVBackupStoreFailurePoint = [@"crash:" stringByAppendingString:point];
            [NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:folder retention:unlimited error:NULL];
            _exit(92);
        }
        int status = 0;
        Check(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 91, @"publication interrupted at expected stage");
        Check([[NVBackupStore archiveDataAtSnapshotURL:[first objectForKey:@"snapshotURL"] error:NULL] isEqual:payload], @"interruption preserves previous archive");
        Check([Snapshots(folder) count] == ([point isEqualToString:@"sync-directory"] ? 2 : 1), @"incomplete interrupted stage is hidden");
        Publish(folder, 3, NO);
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[folder path] error:NULL];
        for (NSString *name in names) Check(![name hasPrefix:@".nvbackup-stage-"], @"restart removes only owned abandoned stage");
    }
}

static void Corruption(void) {
    NSURL *folder = Folder(@"corruption");
    NSError *error = nil;
    NSURL *archiveURL = [[Publish(folder, 1, NO) objectForKey:@"snapshotURL"] URLByAppendingPathComponent:@"Notes & Settings"];
    Check([@"changed bytes" writeToURL:archiveURL atomically:YES encoding:NSUTF8StringEncoding error:&error], @"corrupt archive fixture");
    Check(![NVBackupStore archiveDataAtSnapshotURL:[archiveURL URLByDeletingLastPathComponent] error:&error] && error, @"reject checksum corruption");
    NSArray *fields = @[@"formatVersion", @"libraryIdentifier", @"snapshotIdentifier", @"size", @"generation", @"encrypted", @"date", @"archiveName", @"sha256"];
    NSArray *values = @[@2, @"wrong-library", @"wrong-snapshot", @((unsigned long long)512 * 1024 * 1024 + 1), @(-1), @2, @"yesterday", @"../escape", @"bad-checksum"];
    for (NSUInteger index = 0; index < [fields count]; index++) {
        NSURL *url = [Publish(folder, index + 2, NO) objectForKey:@"snapshotURL"];
        ChangeManifest(url, [fields objectAtIndex:index], [values objectAtIndex:index]);
        Check(![NVBackupStore archiveDataAtSnapshotURL:url error:&error] && error, [@"reject corrupt " stringByAppendingString:[fields objectAtIndex:index]]);
    }
    Check([Snapshots(folder) count] == 0, @"corrupt packages excluded from complete snapshots");
    Check([NVBackupStore pruneSnapshotsInDirectory:folder retention:@{@"recent":@0, @"daily":@0, @"weekly":@0, @"maxBytes":@0} error:&error], @"prune skips corrupt packages");
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[folder path] error:&error];
    Check([[files filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.nvbackup'"]] count] == 10, @"retention preserves all corrupt packages for inspection");
}

static void UnsafePaths(void) {
    NSURL *folder = Folder(@"unsafe");
    NSURL *first = [Publish(folder, 1, NO) objectForKey:@"snapshotURL"];
    NSURL *outside = Folder(@"unrelated.txt");
    Check([@"keep me" writeToURL:outside atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"unrelated file fixture");
    NSURL *archive = [first URLByAppendingPathComponent:@"Notes & Settings"];
    Check(unlink([[archive path] fileSystemRepresentation]) == 0 &&
        symlink([[outside path] fileSystemRepresentation], [[archive path] fileSystemRepresentation]) == 0, @"archive symlink fixture");
    NSError *error = nil;
    Check(![NVBackupStore archiveDataAtSnapshotURL:first error:&error] && error, @"reject linked archive");
    Check([NVBackupStore pruneSnapshotsInDirectory:folder retention:@{@"maxBytes":@0} error:&error], @"prune ignores linked archive");
    Check([[NSString stringWithContentsOfURL:outside encoding:NSUTF8StringEncoding error:NULL] isEqual:@"keep me"], @"preserve symlink target");
    NSURL *link = Folder(@"destination-link");
    Check(symlink([[folder path] fileSystemRepresentation], [[link path] fileSystemRepresentation]) == 0, @"destination symlink fixture");
    Check(![NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:link retention:unlimited error:&error] && error, @"reject linked destination");
    Check(![NVBackupStore publishArchiveData:payload metadata:Metadata(2, NO) inDirectory:[link URLByAppendingPathComponent:@"nested"] retention:unlimited error:&error] && error, @"reject linked ancestor");
    NSURL *newURL = [Publish(folder, 3, NO) objectForKey:@"snapshotURL"];
    NSURL *unexpected = [newURL URLByAppendingPathComponent:@"unrelated"];
    Check([@"keep me" writeToURL:unexpected atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"unexpected package entry fixture");
    Check(![NVBackupStore archiveDataAtSnapshotURL:newURL error:&error] && error, @"reject unexpected package entries");
    Check([NVBackupStore deleteUnencryptedSnapshotsInDirectory:folder metadata:Metadata(1, NO) error:&error], @"plaintext delete skips malformed packages");
    Check([[NSFileManager defaultManager] fileExistsAtPath:[unexpected path]], @"plaintext deletion preserves unrelated package content");
    NSString *stageName = [@".nvbackup-stage-" stringByAppendingString:[[NSUUID UUID] UUIDString]];
    NSURL *foreignStage = [folder URLByAppendingPathComponent:stageName];
    Check([[NSFileManager defaultManager] createDirectoryAtURL:foreignStage withIntermediateDirectories:NO attributes:nil error:NULL], @"foreign stage fixture");
    Check([@{@"formatVersion": @1, @"libraryIdentifier": [[NSUUID UUID] UUIDString]} writeToURL:[foreignStage URLByAppendingPathComponent:@".owner.plist"] atomically:YES], @"foreign stage ownership");
    Publish(folder, 4, YES);
    Check([[NSFileManager defaultManager] fileExistsAtPath:[foreignStage path]], @"preserve other library's staging directory");
    NSURL *foreign = Folder(@"foreign-library");
    NSMutableDictionary *foreignMetadata = [NSMutableDictionary dictionaryWithDictionary:Metadata(10, NO)];
    [foreignMetadata setObject:[[NSUUID UUID] UUIDString] forKey:@"libraryIdentifier"];
    NSDictionary *foreignSnapshot = [NVBackupStore publishArchiveData:payload metadata:foreignMetadata inDirectory:foreign retention:unlimited error:&error];
    Check(foreignSnapshot != nil, @"foreign complete snapshot fixture");
    NSURL *copiedForeign = [folder URLByAppendingPathComponent:[[foreignSnapshot objectForKey:@"snapshotURL"] lastPathComponent]];
    Check([[NSFileManager defaultManager] copyItemAtURL:[foreignSnapshot objectForKey:@"snapshotURL"] toURL:copiedForeign error:&error], @"copy unrelated library snapshot");
    Check([NVBackupStore deleteUnencryptedSnapshotsInDirectory:folder metadata:Metadata(1, NO) error:&error], @"delete only owned plaintext snapshots");
    Check([[NSFileManager defaultManager] fileExistsAtPath:[copiedForeign path]], @"preserve complete foreign snapshot");
    NSURL *ownerURL = [folder URLByAppendingPathComponent:@".nvbackup-library.plist"];
    Check([@{@"formatVersion": @99, @"libraryIdentifier": library} writeToURL:ownerURL atomically:YES], @"malformed ownership fixture");
    Check(![NVBackupStore snapshotsInDirectory:folder error:&error] && error, @"reject malformed directory ownership");
}

static void Retention(void) {
    NSURL *folder = Folder(@"retention");
    // Monday 2026-09-07 12:00 UTC. Test daily and Monday-based weekly boundaries.
    NVBackupStoreCurrentDate = [NSDate dateWithTimeIntervalSince1970:1788782400];
    NSDate *now = NVBackupStoreCurrentDate;
    NSArray *ages = @[@0, @60, @120, @86400, @(2 * 86400), @(3 * 86400), @(7 * 86400), @(8 * 86400), @(14 * 86400), @(15 * 86400), @(30 * 86400)];
    for (NSUInteger index = 0; index < [ages count]; index++) {
        NSDictionary *snapshot = Publish(folder, [ages count] - index, NO);
        ChangeManifest([snapshot objectForKey:@"snapshotURL"], @"date", [now dateByAddingTimeInterval:-[[ages objectAtIndex:index] doubleValue]]);
    }
    NSError *error = nil;
    Check([NVBackupStore pruneSnapshotsInDirectory:folder retention:@{@"recent":@3, @"daily":@3, @"weekly":@3, @"maxBytes":@(ULLONG_MAX)} error:&error], @"apply union retention");
    Check([Generations(folder) isEqual:[NSSet setWithArray:@[@11,@10,@9,@8,@7,@4]]], @"keep recent plus latest UTC day and week representatives");
    Check([NVBackupStore pruneSnapshotsInDirectory:folder retention:@{@"recent":@96, @"daily":@30, @"weekly":@12, @"minimum":@0, @"maxBytes":@0} error:&error], @"apply storage target");
    Check([Generations(folder) isEqual:[NSSet setWithArray:@[@11,@10,@9]]], @"size target overrides old buckets and retains at least three");

    NSURL *clockChange = Folder(@"backward-clock");
    Publish(clockChange, 1, NO); Publish(clockChange, 2, NO); Publish(clockChange, 3, NO);
    NVBackupStoreCurrentDate = [now dateByAddingTimeInterval:-86400];
    NSDictionary *tight = @{@"recent":@3, @"daily":@0, @"weekly":@0, @"maxBytes":@0};
    NSDictionary *latest = [NVBackupStore publishArchiveData:payload metadata:Metadata(4, NO) inDirectory:clockChange retention:tight error:&error];
    Check(latest && !error && [[NVBackupStore archiveDataAtSnapshotURL:[latest objectForKey:@"snapshotURL"] error:&error] isEqual:payload], @"publication survives retention after a backward clock change");
    Check([NVBackupStore pruneSnapshotsInDirectory:clockChange retention:tight error:&error], @"standalone pruning handles backward clock change");
    Check([Generations(clockChange) containsObject:@4] && [Snapshots(clockChange) count] == 3, @"retention keeps newest generation and three complete snapshots after clock change");
    NVBackupStoreCurrentDate = nil;
    NSURL *mixed = Folder(@"plaintext");
    Publish(mixed, 1, NO); Publish(mixed, 2, YES); Publish(mixed, 3, NO); Publish(mixed, 4, YES);
    Check([NVBackupStore deleteUnencryptedSnapshotsInDirectory:mixed metadata:Metadata(1, NO) error:&error], @"explicit plaintext deletion succeeds");
    Check([Generations(mixed) isEqual:[NSSet setWithArray:@[@2,@4]]], @"plaintext deletion keeps encrypted history");
}

static void RestoreWriter(void) {
    NSURL *folder = Folder(@"restore-writer");
    Check([[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:nil error:NULL], @"empty restore folder fixture");
    NSError *error = nil;
    Check([NVBackupStore writeRestoreArchiveData:payload toEmptyDirectory:folder error:&error] && !error, @"write restored archive into empty folder");
    NSURL *archive = [folder URLByAppendingPathComponent:@"Notes & Settings"];
    Check([[NSData dataWithContentsOfURL:archive] isEqual:payload], @"restored archive bytes are exact");
    struct stat attributes;
    Check(lstat([[folder path] fileSystemRepresentation], &attributes) == 0 && (attributes.st_mode & 0777) == 0700, @"restored folder is private");
    Check(lstat([[archive path] fileSystemRepresentation], &attributes) == 0 && (attributes.st_mode & 0777) == 0600, @"restored archive is private");
    Check(![NVBackupStore writeRestoreArchiveData:payload toEmptyDirectory:folder error:&error] && [error code] == EEXIST, @"refuse to overwrite existing restored library");
    Check([[NSData dataWithContentsOfURL:archive] isEqual:payload], @"existing restored library remains intact");
    Check(![NVBackupStore writeRestoreArchiveData:payload toEmptyDirectory:Folder(@"missing-restore") error:&error] && error, @"restore requires an existing selected folder");
    Check(![[NSFileManager defaultManager] fileExistsAtPath:[Folder(@"missing-restore") path]], @"restore does not create an unavailable selected folder");
    for (NSString *point in @[@"restore-archive", @"restore-archive-partial", @"sync-restore-archive", @"restore-rename", @"sync-restore-directory"]) {
        NSURL *destination = Folder(point);
        Check([[NSFileManager defaultManager] createDirectoryAtURL:destination withIntermediateDirectories:NO attributes:nil error:NULL], @"restore failure folder fixture");
        NVBackupStoreFailurePoint = point;
        Check(![NVBackupStore writeRestoreArchiveData:payload toEmptyDirectory:destination error:&error] && error, @"restore write failure reported");
        NVBackupStoreFailurePoint = nil;
        NSArray *remaining = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[destination path] error:&error];
        Check(remaining != nil && [remaining count] == 0, @"failed restore removes its own file but preserves the selected folder");
        Check([NVBackupStore writeRestoreArchiveData:payload toEmptyDirectory:destination error:&error] && !error, @"failed restore can retry in the same empty folder");
    }
    NSURL *occupied = Folder(@"restore-unrelated");
    Check([[NSFileManager defaultManager] createDirectoryAtURL:occupied withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0755} error:NULL], @"occupied restore fixture");
    NSURL *unrelated = [occupied URLByAppendingPathComponent:@"unrelated"];
    Check([@"keep" writeToURL:unrelated atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"unrelated restore file fixture");
    Check(![NVBackupStore writeRestoreArchiveData:payload toEmptyDirectory:occupied error:&error] && [error code] == EEXIST, @"refuse nonempty restore folder");
    Check([[NSString stringWithContentsOfURL:unrelated encoding:NSUTF8StringEncoding error:NULL] isEqual:@"keep"], @"restore preserves unrelated files");
    Check(lstat([[occupied path] fileSystemRepresentation], &attributes) == 0 && (attributes.st_mode & 0777) == 0755, @"restore preserves nonempty folder permissions");
}

static void ExistingRoot(void) {
    NSURL *selected = Folder(@"selected-volume-root");
    Check([[NSFileManager defaultManager] createDirectoryAtURL:selected withIntermediateDirectories:NO attributes:nil error:NULL], @"selected backup root exists at main-thread check");
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:Metadata(1, NO)];
    [metadata setObject:selected forKey:@"existingRoot"];
    struct stat identity;
    Check(stat([[selected path] fileSystemRepresentation], &identity) == 0, @"capture the selected root identity before queueing");
    [metadata setObject:[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)identity.st_dev, (unsigned long long)identity.st_ino] forKey:@"existingRootIdentity"];
    NSURL *destination = [selected URLByAppendingPathComponent:library isDirectory:YES];
    Check([[NSFileManager defaultManager] fileExistsAtPath:[selected path]], @"main-thread destination check passes before disappearance");
    Check([[NSFileManager defaultManager] removeItemAtURL:selected error:NULL], @"selected root disappears before the worker opens it");
    NSError *error = nil;
    Check(![NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:destination retention:unlimited error:&error] && [error code] == ENOENT,
        @"worker reports unavailable selected root instead of creating it");
    Check(![[NSFileManager defaultManager] fileExistsAtPath:[selected path]], @"missing volume path is not recreated on local storage");
    Check([[NSFileManager defaultManager] createDirectoryAtURL:selected withIntermediateDirectories:NO attributes:nil error:NULL], @"selected root becomes available again");
    Check(stat([[selected path] fileSystemRepresentation], &identity) == 0, @"a new main-thread check captures the available root identity");
    [metadata setObject:[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)identity.st_dev, (unsigned long long)identity.st_ino] forKey:@"existingRootIdentity"];
    NSDictionary *published = [NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:destination retention:unlimited error:&error];
    Check(published && !error && [[NVBackupStore archiveDataAtSnapshotURL:[published objectForKey:@"snapshotURL"] error:&error] isEqual:payload],
        @"worker creates only the direct library child under an existing selected root");
    Check(![NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:Folder(@"outside-selected-root") retention:unlimited error:&error] && [error code] == EINVAL,
        @"selected root cannot authorize publication outside itself");
    Check(![NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:[selected URLByAppendingPathComponent:@"wrong-library"] retention:unlimited error:&error] && [error code] == EINVAL,
        @"selected root requires the exact library UUID child");
    NSURL *unmounted = Folder(@"unmounted-selected-root");
    Check([[NSFileManager defaultManager] moveItemAtURL:selected toURL:unmounted error:NULL], @"original selected root moves out of the mountpoint path");
    Check([[NSFileManager defaultManager] createDirectoryAtURL:selected withIntermediateDirectories:NO attributes:nil error:NULL], @"a different local directory occupies the old mountpoint path");
    Check(![NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:destination retention:unlimited error:&error] && [error code] == ESTALE,
        @"worker rejects a different existing directory at the selected mountpoint");
    Check([[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[selected path] error:NULL] count] == 0,
        @"identity mismatch creates no library folder or lock on local storage");
    NSURL *previousSnapshot = [[unmounted URLByAppendingPathComponent:library isDirectory:YES] URLByAppendingPathComponent:[[published objectForKey:@"snapshotURL"] lastPathComponent] isDirectory:YES];
    Check([[NVBackupStore archiveDataAtSnapshotURL:previousSnapshot error:&error] isEqual:payload], @"identity mismatch preserves the original root's earlier snapshot");
    [metadata removeObjectForKey:@"existingRootIdentity"];
    Check(![NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:destination retention:unlimited error:&error] && [error code] == EINVAL,
        @"custom root publication requires captured filesystem identity");
    [metadata setObject:@1 forKey:@"existingRootIdentity"];
    Check(![NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:destination retention:unlimited error:&error] && [error code] == EINVAL,
        @"reject malformed root filesystem identity");
    [metadata setObject:@"1:2" forKey:@"existingRootIdentity"];
    [metadata setObject:@"not a URL" forKey:@"existingRoot"];
    Check(![NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:destination retention:unlimited error:&error] && [error code] == EINVAL,
        @"reject malformed selected-root metadata");
}

static void Maintenance(void) {
    NSURL *selected = Folder(@"maintenance-root");
    Check([[NSFileManager defaultManager] createDirectoryAtURL:selected withIntermediateDirectories:NO attributes:nil error:NULL], @"create maintenance root");
    struct stat identity;
    Check(stat([[selected path] fileSystemRepresentation], &identity) == 0, @"capture maintenance root identity");
    NSURL *destination = [selected URLByAppendingPathComponent:library isDirectory:YES];
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:Metadata(5, NO)];
    [metadata setObject:selected forKey:@"existingRoot"];
    [metadata setObject:[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)identity.st_dev, (unsigned long long)identity.st_ino] forKey:@"existingRootIdentity"];
    NSDictionary *policy = @{@"recent":@3, @"daily":@0, @"weekly":@0, @"maxBytes":@(ULLONG_MAX)};
    NSError *error = nil;
    Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:policy error:&error] && error, @"maintenance rejects a missing library folder");
    Check(![NVBackupStore deleteUnencryptedSnapshotsInDirectory:destination metadata:metadata error:&error] && [error code] == ENOENT, @"deletion rejects a missing library folder");
    Check(![[NSFileManager defaultManager] fileExistsAtPath:[destination path]], @"maintenance does not recreate the library folder");
    NSMutableDictionary *first = nil;
    for (NSUInteger generation=1; generation<=5; generation++) {
        NVBackupStoreCurrentDate = [NSDate dateWithTimeIntervalSince1970:1000000+generation*100];
        NSDictionary *published = Publish(destination, generation, NO);
        if (!first) first = [NSMutableDictionary dictionaryWithDictionary:published];
    }
    [metadata setObject:[first objectForKey:@"snapshotIdentifier"] forKey:@"protectedSnapshotIdentifier"];
    NVBackupStoreFailurePoint = @"prune";
    Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:policy error:&error] && error, @"maintenance reports pruning failure");
    NVBackupStoreFailurePoint = nil;
    Check([Snapshots(destination) count] == 5, @"failed maintenance preserves prior snapshots");
    Check([NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:policy error:&error] && !error, @"maintenance retries with captured identity");
    // The retained recent three, highest generation, and explicitly protected old snapshot form a union.
    Check([Snapshots(destination) count] == 4 && [[NVBackupStore archiveDataAtSnapshotURL:[first objectForKey:@"snapshotURL"] error:&error] isEqual:payload],
        @"maintenance protects the verified current snapshot even when its date or generation is old");
    NSMutableDictionary *foreign = [[metadata mutableCopy] autorelease];
    [foreign removeObjectForKey:@"existingRoot"]; [foreign removeObjectForKey:@"existingRootIdentity"];
    [foreign setObject:[[NSUUID UUID] UUIDString] forKey:@"libraryIdentifier"];
    Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:foreign retention:policy error:&error] && [error code] == EINVAL, @"maintenance rejects a different library owner");
    Check(![NVBackupStore deleteUnencryptedSnapshotsInDirectory:destination metadata:foreign error:&error] && [error code] == EINVAL, @"deletion rejects a different library owner");
    Check([Snapshots(destination) count] == 4, @"foreign maintenance preserves all snapshots");
    [metadata setObject:@"invalid" forKey:@"protectedSnapshotIdentifier"];
    Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:policy error:&error] && [error code] == EINVAL, @"maintenance validates protected snapshot identity");
    [metadata removeObjectForKey:@"protectedSnapshotIdentifier"];
    NSURL *moved = Folder(@"maintenance-root-moved");
    Check([[NSFileManager defaultManager] moveItemAtURL:selected toURL:moved error:NULL], @"move original maintenance root");
    Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:policy error:&error] && error, @"maintenance rejects an unavailable custom root");
    Check(![NVBackupStore deleteUnencryptedSnapshotsInDirectory:destination metadata:metadata error:&error] && [error code] == ENOENT, @"deletion rejects an unavailable custom root");
    Check(![[NSFileManager defaultManager] fileExistsAtPath:[selected path]], @"maintenance never recreates the custom root");
    Check([[NSFileManager defaultManager] createDirectoryAtURL:selected withIntermediateDirectories:NO attributes:nil error:NULL], @"replace custom root with a different directory");
    Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:policy error:&error] && [error code] == ESTALE, @"maintenance rejects replaced custom-root identity");
    Check(![NVBackupStore deleteUnencryptedSnapshotsInDirectory:destination metadata:metadata error:&error] && [error code] == ESTALE, @"deletion rejects replaced custom-root identity");
    Check([[[NSFileManager defaultManager] contentsOfDirectoryAtURL:selected includingPropertiesForKeys:nil options:0 error:NULL] count] == 0, @"rejected maintenance leaves replacement root empty");
    Check([Snapshots([moved URLByAppendingPathComponent:library isDirectory:YES]) count] == 4, @"rejected maintenance preserves snapshots in original root");
    NVBackupStoreCurrentDate = nil;
}

int main(int argc, const char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Check(argc == 2, @"test destination supplied");
    testRoot = [[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES] URLByResolvingSymlinksInPath];
    NSMutableData *bytes = [NSMutableData dataWithLength:2 * 1024 * 1024 + 17];
    for (NSUInteger index = 0; index < [bytes length]; index++) ((unsigned char *)[bytes mutableBytes])[index] = (unsigned char)(index * 17);
    payload = bytes;
    unlimited = @{ @"recent":@100000, @"daily":@0, @"weekly":@0, @"maxBytes":@(ULLONG_MAX) };
    Basic(); Faults(); Interrupted(); Corruption(); UnsafePaths(); Retention(); RestoreWriter(); ExistingRoot(); Maintenance();
    printf("PASS: %lu backup store assertions\n", (unsigned long)checks);
    [pool drain];
    return 0;
}
