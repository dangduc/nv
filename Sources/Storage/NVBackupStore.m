#import "NVBackupStore.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <math.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

NSString * const NVBackupStoreErrorDomain = @"NVBackupStoreErrorDomain";
static NSString * const NVArchiveName = @"Notes & Settings";
static NSString * const NVManifestName = @"manifest.plist";
static NSString * const NVOwnerName = @".nvbackup-library.plist";
static NSString * const NVStageOwnerName = @".owner.plist";
static const NSUInteger NVMaximumArchiveSize = 512ULL * 1024 * 1024;

#ifdef NVBACKUPSTORE_TESTING
NSString *NVBackupStoreFailurePoint = nil;
int NVBackupStoreFailureCode = EIO;
NSDate *NVBackupStoreCurrentDate = nil;
#endif

static NSDate *NVDate(void) {
#ifdef NVBACKUPSTORE_TESTING
    if (NVBackupStoreCurrentDate) return NVBackupStoreCurrentDate;
#endif
    return [NSDate date];
}

static BOOL NVFail(NSString *point, NSError **error) {
#ifdef NVBACKUPSTORE_TESTING
    if ([NVBackupStoreFailurePoint isEqualToString:[@"crash:" stringByAppendingString:point]]) _exit(91);
    if ([NVBackupStoreFailurePoint isEqualToString:point]) {
        if (error) *error = [NSError errorWithDomain:NVBackupStoreErrorDomain code:NVBackupStoreFailureCode
            userInfo:@{NSLocalizedDescriptionKey: [@"Injected backup failure: " stringByAppendingString:point]}];
        return YES;
    }
#else
    (void)point;
    (void)error;
#endif
    return NO;
}

static BOOL NVError(NSError **error, NSInteger code, NSString *description) {
    if (error) *error = [NSError errorWithDomain:NVBackupStoreErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: description}];
    return NO;
}

static BOOL NVSystemError(NSError **error, NSString *operation) {
    int savedErrno = errno;
    return NVError(error, savedErrno, [NSString stringWithFormat:@"%@: %s", operation, strerror(savedErrno)]);
}

static BOOL NVUUID(id value) {
    if (![value isKindOfClass:[NSString class]] || [value length] != 36) return NO;
    NSUUID *uuid = [[[NSUUID alloc] initWithUUIDString:value] autorelease];
    return uuid != nil;
}

static BOOL NVUnsignedNumber(id value, unsigned long long maximum) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= 0 && floor(number) == number &&
        [value unsignedLongLongValue] <= maximum;
}

// Pin every ancestor by descriptor. A renamed or substituted symlink cannot
// redirect writes or pruning outside the selected destination.
static int NVOpenDirectory(NSURL *url, BOOL create, NSError **error) {
    if (![url isFileURL] || ![[url path] isAbsolutePath]) {
        NVError(error, EINVAL, @"The backup destination must be an absolute file URL.");
        return -1;
    }
    int descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (descriptor < 0) { NVSystemError(error, @"Cannot open the backup destination"); return -1; }
    NSArray *components = [[url path] pathComponents];
    for (NSString *component in components) {
        if ([component isEqualToString:@"/"]) continue;
        if ([component isEqualToString:@".."] || [component isEqualToString:@"."] || ![component length]) {
            close(descriptor);
            NVError(error, EINVAL, @"The backup destination contains an invalid path component.");
            return -1;
        }
        const char *name = [component fileSystemRepresentation];
        int next = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0 && errno == ENOENT && create) {
            if (mkdirat(descriptor, name, 0700) != 0 && errno != EEXIST) {
                NVSystemError(error, @"Cannot create the backup destination"); close(descriptor); return -1;
            }
            if (fsync(descriptor) != 0) {
                NVSystemError(error, @"Cannot synchronize the new backup directory"); close(descriptor); return -1;
            }
            next = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        }
        if (next < 0) { NVSystemError(error, @"Cannot open the backup destination"); close(descriptor); return -1; }
        close(descriptor);
        descriptor = next;
    }
    return descriptor;
}

static int NVOpenPublicationDirectory(NSURL *directory, NSDictionary *metadata, NSError **error) {
    NSURL *existingRoot = [metadata objectForKey:@"existingRoot"];
    if (!existingRoot) return NVOpenDirectory(directory, YES, error);
    NSString *identifier = [metadata objectForKey:@"libraryIdentifier"];
    NSString *expectedIdentity = [metadata objectForKey:@"existingRootIdentity"];
    if (![expectedIdentity isKindOfClass:[NSString class]] || ![expectedIdentity length]) {
        NVError(error, EINVAL, @"The selected backup folder has no captured filesystem identity."); return -1;
    }
    if (![existingRoot isKindOfClass:[NSURL class]] || ![existingRoot isFileURL] || ![directory isFileURL] ||
        ![[[directory URLByDeletingLastPathComponent] path] isEqual:[existingRoot path]] ||
        ![[directory lastPathComponent] isEqual:identifier]) {
        NVError(error, EINVAL, @"The backup destination must be the library folder inside the selected backup folder."); return -1;
    }
    int parent = NVOpenDirectory(existingRoot, NO, error);
    if (parent < 0) return -1;
    struct stat attributes;
    if (fstat(parent, &attributes) != 0) {
        NVSystemError(error, @"Cannot inspect the selected backup folder"); close(parent); return -1;
    }
    NSString *actualIdentity = [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)attributes.st_dev, (unsigned long long)attributes.st_ino];
    if (![actualIdentity isEqual:expectedIdentity]) {
        NVError(error, ESTALE, @"The selected backup folder changed before the backup could start. Try again after its volume is available.");
        close(parent); return -1;
    }
    const char *name = [identifier fileSystemRepresentation];
    int child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (child < 0 && errno == ENOENT) {
        if (mkdirat(parent, name, 0700) != 0 && errno != EEXIST) {
            NVSystemError(error, @"Cannot create the library backup folder"); close(parent); return -1;
        }
        if (fsync(parent) != 0) {
            NVSystemError(error, @"Cannot synchronize the library backup folder"); close(parent); return -1;
        }
        child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    }
    if (child < 0) NVSystemError(error, @"Cannot open the library backup folder");
    close(parent);
    return child;
}

static BOOL NVSync(int descriptor, NSString *point, NSError **error) {
    if (NVFail(point, error)) return NO;
    if (fsync(descriptor) != 0) return NVSystemError(error, @"Cannot synchronize the backup");
    return YES;
}

static NSData *NVReadFile(int directory, NSString *name, NSUInteger limit, NSError **error) {
    int descriptor = openat(directory, [name fileSystemRepresentation], O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (descriptor < 0) { NVSystemError(error, @"Cannot read a backup file"); return nil; }
    struct stat attributes;
    if (fstat(descriptor, &attributes) != 0) {
        NVSystemError(error, @"Cannot inspect a backup file"); close(descriptor); return nil;
    }
    if (!S_ISREG(attributes.st_mode) || attributes.st_nlink != 1 || attributes.st_size < 1 ||
        (unsigned long long)attributes.st_size > limit) {
        NVError(error, EINVAL, @"A backup file has an invalid type or size."); close(descriptor); return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)attributes.st_size];
    NSUInteger offset = 0;
    while (offset < [data length]) {
        ssize_t count = read(descriptor, (char *)[data mutableBytes] + offset, [data length] - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            if (count < 0) NVSystemError(error, @"Cannot read a backup file");
            else NVError(error, EIO, @"A backup file changed while it was read.");
            close(descriptor); return nil;
        }
        offset += (NSUInteger)count;
    }
    char extra;
    ssize_t remaining;
    do { remaining = read(descriptor, &extra, 1); } while (remaining < 0 && errno == EINTR);
    close(descriptor);
    if (remaining != 0) { NVError(error, EIO, @"A backup file changed while it was read."); return nil; }
    return data;
}

static NSDictionary *NVReadPlist(int directory, NSString *name, NSError **error) {
    NSData *data = NVReadFile(directory, name, 64 * 1024, error);
    if (!data) return nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        NVError(error, EINVAL, @"A backup manifest is not a dictionary."); return nil;
    }
    return plist;
}

static BOOL NVWriteFile(int directory, NSString *name, NSData *data, NSString *point, BOOL *created, NSError **error) {
    if (created) *created = NO;
    if (NVFail(point, error)) return NO;
    int descriptor = openat(directory, [name fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (descriptor < 0) return NVSystemError(error, @"Cannot create a backup file");
    if (created) *created = YES;
    NSUInteger offset = 0;
    while (offset < [data length]) {
        NSUInteger request = MIN([data length] - offset, (NSUInteger)1024 * 1024);
        ssize_t count = write(descriptor, (const char *)[data bytes] + offset, request);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            if (count == 0) errno = EIO;
            NVSystemError(error, @"Cannot write a backup file"); close(descriptor); return NO;
        }
        offset += (NSUInteger)count;
        if (NVFail([point stringByAppendingString:@"-partial"], error)) { close(descriptor); return NO; }
    }
    BOOL result = NVSync(descriptor, [@"sync-" stringByAppendingString:point], error);
    if (close(descriptor) != 0 && result) return NVSystemError(error, @"Cannot close a backup file");
    return result;
}

static BOOL NVWritePlist(int directory, NSString *name, NSDictionary *plist, NSString *point, NSError **error) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && NVWriteFile(directory, name, data, point, NULL, error);
}

static BOOL NVCreateOwner(int directory, NSDictionary *owner, NSError **error) {
    NSString *temporary = [NSString stringWithFormat:@".nvbackup-owner-%@.tmp", [[NSUUID UUID] UUIDString]];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:owner format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    BOOL created = NO;
    BOOL result = data && NVWriteFile(directory, temporary, data, @"owner", &created, error);
    if (result && renameatx_np(directory, [temporary fileSystemRepresentation], directory, [NVOwnerName fileSystemRepresentation], RENAME_EXCL) != 0)
        result = NVSystemError(error, @"Cannot publish backup directory ownership");
    if (result) result = NVSync(directory, @"sync-owner-directory", error);
    if (!result && created) unlinkat(directory, [temporary fileSystemRepresentation], 0);
    return result;
}

static NSString *NVSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    char text[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) sprintf(text + index * 2, "%02x", digest[index]);
    text[CC_SHA256_DIGEST_LENGTH * 2] = 0;
    return [NSString stringWithUTF8String:text];
}

static BOOL NVOwnerValid(NSDictionary *owner) {
    return NVUnsignedNumber([owner objectForKey:@"formatVersion"], 1) &&
        [[owner objectForKey:@"formatVersion"] integerValue] == 1 && NVUUID([owner objectForKey:@"libraryIdentifier"]);
}

static NSDictionary *NVReadOwner(int directory, BOOL allowMissing, NSError **error) {
    struct stat attributes;
    if (fstatat(directory, [NVOwnerName fileSystemRepresentation], &attributes, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno == ENOENT && allowMissing) return nil;
        NVSystemError(error, @"Cannot read backup directory ownership"); return nil;
    }
    NSDictionary *owner = NVReadPlist(directory, NVOwnerName, error);
    if (!owner) return nil;
    if (!NVOwnerValid(owner)) { NVError(error, EINVAL, @"The backup directory has an invalid ownership record."); return nil; }
    return owner;
}

static NSArray *NVNames(int directory, NSError **error) {
    // dup() shares the enumeration offset; reopen "." for a fresh offset.
    int copy = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (copy < 0) { NVSystemError(error, @"Cannot list backups"); return nil; }
    DIR *stream = fdopendir(copy);
    if (!stream) { NVSystemError(error, @"Cannot list backups"); close(copy); return nil; }
    NSMutableArray *names = [NSMutableArray array];
    struct dirent *entry;
    errno = 0;
    while ((entry = readdir(stream))) {
        NSString *name = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
        if (name && ![name isEqualToString:@"."] && ![name isEqualToString:@".."]) [names addObject:name];
        errno = 0;
    }
    int savedErrno = errno;
    closedir(stream);
    if (savedErrno) { errno = savedErrno; NVSystemError(error, @"Cannot list backups"); return nil; }
    return names;
}

static BOOL NVManifestValid(NSDictionary *manifest, NSString *name, NSError **error) {
    NSString *checksum = [manifest objectForKey:@"sha256"];
    BOOL validChecksum = [checksum isKindOfClass:[NSString class]] && [checksum length] == 64 &&
        [checksum rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location == NSNotFound;
    NSDate *date = [manifest objectForKey:@"date"];
    BOOL valid = NVOwnerValid(manifest) && NVUUID([manifest objectForKey:@"snapshotIdentifier"]) &&
        [name isEqualToString:[[manifest objectForKey:@"snapshotIdentifier"] stringByAppendingPathExtension:@"nvbackup"]] &&
        [[manifest objectForKey:@"archiveName"] isEqual:NVArchiveName] &&
        NVUnsignedNumber([manifest objectForKey:@"size"], NVMaximumArchiveSize) && [[manifest objectForKey:@"size"] unsignedLongLongValue] > 0 &&
        NVUnsignedNumber([manifest objectForKey:@"generation"], ULLONG_MAX) && NVUnsignedNumber([manifest objectForKey:@"encrypted"], 1) &&
        [date isKindOfClass:[NSDate class]] && isfinite([date timeIntervalSinceReferenceDate]) && fabs([date timeIntervalSince1970]) < 1.0e12 &&
        [[manifest objectForKey:@"appVersion"] isKindOfClass:[NSString class]] && [[manifest objectForKey:@"appVersion"] length] <= 256 && validChecksum;
    return valid || NVError(error, EINVAL, @"The backup manifest is invalid or uses an unsupported format.");
}

static NSDictionary *NVSnapshot(int directory, NSString *name, NSURL *rootURL, NSString *libraryIdentifier, NSData **archive, NSError **error) {
    if (![[name pathExtension] isEqualToString:@"nvbackup"] || !NVUUID([name stringByDeletingPathExtension])) {
        NVError(error, EINVAL, @"Select a complete nvALT backup package."); return nil;
    }
    int package = openat(directory, [name fileSystemRepresentation], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (package < 0) { NVSystemError(error, @"Cannot open the backup package"); return nil; }
    NSDictionary *manifest = NVReadPlist(package, NVManifestName, error);
    if (!manifest || !NVManifestValid(manifest, name, error)) { close(package); return nil; }
    if (libraryIdentifier && ![[manifest objectForKey:@"libraryIdentifier"] isEqual:libraryIdentifier]) {
        NVError(error, EINVAL, @"The backup belongs to another library."); close(package); return nil;
    }
    NSArray *names = NVNames(package, error);
    NSSet *allowed = [NSSet setWithObjects:NVArchiveName, NVManifestName, nil];
    if (!names || ![[NSSet setWithArray:names] isEqual:allowed]) {
        NVError(error, EINVAL, @"The backup package contains unexpected files."); close(package); return nil;
    }
    NSData *data = NVReadFile(package, NVArchiveName, NVMaximumArchiveSize, error);
    close(package);
    if (!data) return nil;
    if ([data length] != [[manifest objectForKey:@"size"] unsignedLongLongValue] || ![NVSHA256(data) isEqual:[manifest objectForKey:@"sha256"]]) {
        NVError(error, EINVAL, @"The backup archive failed its size or checksum check."); return nil;
    }
    if (archive) *archive = data;
    NSMutableDictionary *result = [[manifest mutableCopy] autorelease];
    [result setObject:[rootURL URLByAppendingPathComponent:name isDirectory:YES] forKey:@"snapshotURL"];
    return result;
}

static NSArray *NVSnapshots(int directory, NSURL *url, NSString *libraryIdentifier, NSError **error) {
    NSArray *names = NVNames(directory, error);
    if (!names) return nil;
    NSMutableArray *snapshots = [NSMutableArray array];
    for (NSString *name in names) {
        if (![[name pathExtension] isEqualToString:@"nvbackup"]) continue;
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSDictionary *snapshot = NVSnapshot(directory, name, url, libraryIdentifier, NULL, NULL);
        if (snapshot) [snapshots addObject:snapshot];
        [pool drain];
    }
    [snapshots sortUsingComparator:^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
        NSComparisonResult result = [[second objectForKey:@"date"] compare:[first objectForKey:@"date"]];
        if (result == NSOrderedSame) result = [[second objectForKey:@"snapshotIdentifier"] compare:[first objectForKey:@"snapshotIdentifier"]];
        return result;
    }];
    return snapshots;
}

// A deletion checks both identity and the complete entry set. It never follows
// links or recursively removes directories supplied by another application.
static BOOL NVRemovePackage(int directory, NSString *name, NSSet *allowed, NSError **error) {
    int package = openat(directory, [name fileSystemRepresentation], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (package < 0) return NVSystemError(error, @"Cannot open a backup for deletion");
    struct stat opened, current;
    BOOL result = fstat(package, &opened) == 0;
    NSArray *names = result ? NVNames(package, error) : nil;
    if (!names || ![[NSSet setWithArray:names] isSubsetOfSet:allowed]) {
        close(package); return NVError(error, EINVAL, @"A backup contains unexpected files and was preserved.");
    }
    for (NSString *entry in names) {
        if (fstatat(package, [entry fileSystemRepresentation], &current, AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(current.st_mode) || current.st_nlink != 1) {
            close(package); return NVError(error, EINVAL, @"A backup contains an unexpected file type and was preserved.");
        }
    }
    if (fstatat(directory, [name fileSystemRepresentation], &current, AT_SYMLINK_NOFOLLOW) != 0 ||
        current.st_dev != opened.st_dev || current.st_ino != opened.st_ino) {
        close(package); return NVError(error, EIO, @"A backup changed during deletion and was preserved.");
    }
    for (NSString *entry in names) {
        if (unlinkat(package, [entry fileSystemRepresentation], 0) != 0) {
            NVSystemError(error, @"Cannot remove an expired backup file"); close(package); return NO;
        }
    }
    close(package);
    if (unlinkat(directory, [name fileSystemRepresentation], AT_REMOVEDIR) != 0) return NVSystemError(error, @"Cannot remove an expired backup package");
    return YES;
}

static void NVCleanStages(int directory, NSString *libraryIdentifier) {
    for (NSString *name in NVNames(directory, NULL)) {
        if (![name hasPrefix:@".nvbackup-stage-"] || !NVUUID([name substringFromIndex:[@".nvbackup-stage-" length]])) continue;
        int stage = openat(directory, [name fileSystemRepresentation], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (stage < 0) continue;
        NSDictionary *owner = NVReadPlist(stage, NVStageOwnerName, NULL);
        BOOL owned = NVOwnerValid(owner) && [[owner objectForKey:@"libraryIdentifier"] isEqual:libraryIdentifier];
        if (!owned && !NVOwnerValid(owner)) {
            NSDictionary *manifest = NVReadPlist(stage, NVManifestName, NULL);
            NSString *finalName = [[name substringFromIndex:[@".nvbackup-stage-" length]] stringByAppendingPathExtension:@"nvbackup"];
            owned = NVManifestValid(manifest, finalName, NULL) && [[manifest objectForKey:@"libraryIdentifier"] isEqual:libraryIdentifier];
        }
        close(stage);
        if (owned) NVRemovePackage(directory, name, [NSSet setWithObjects:NVStageOwnerName, NVArchiveName, NVManifestName, nil], NULL);
    }
}

static NSUInteger NVRetentionCount(NSDictionary *retention, NSString *key, NSUInteger fallback, NSUInteger limit) {
    id value = [retention objectForKey:key];
    return NVUnsignedNumber(value, limit) ? [value unsignedIntegerValue] : fallback;
}

static BOOL NVPrune(int directory, NSURL *url, NSString *libraryIdentifier, NSDictionary *retention, NSString *publishedIdentifier, NSError **error) {
    if (NVFail(@"prune", error)) return NO;
    NSArray *snapshots = NVSnapshots(directory, url, libraryIdentifier, error);
    if (!snapshots) return NO;
    NSUInteger recent = NVRetentionCount(retention, @"recent", 96, 100000);
    NSUInteger daily = NVRetentionCount(retention, @"daily", 30, 36600);
    NSUInteger weekly = NVRetentionCount(retention, @"weekly", 12, 5200);
    NSUInteger minimum = MAX((NSUInteger)3, NVRetentionCount(retention, @"minimum", 3, 100000));
    unsigned long long maxBytes = NVUnsignedNumber([retention objectForKey:@"maxBytes"], ULLONG_MAX) ?
        [[retention objectForKey:@"maxBytes"] unsignedLongLongValue] : 2ULL * 1024 * 1024 * 1024;
    NSMutableIndexSet *keep = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *protected = [NSMutableIndexSet indexSet];
    NSMutableSet *days = [NSMutableSet set], *weeks = [NSMutableSet set];
    NSTimeInterval now = [NVDate() timeIntervalSince1970];
    long long today = (long long)floor(now / 86400.0);
    // 1970-01-01 was Thursday. Weeks start Monday, in UTC.
    long long thisWeek = (long long)floor((double)(today + 3) / 7.0);
    // A backward clock change cannot expire the newest committed state or the
    // snapshot that this publication returns to its caller.
    unsigned long long newestGeneration = 0;
    NSUInteger newestGenerationIndex = NSNotFound;
    for (NSUInteger index = 0; index < [snapshots count]; index++) {
        unsigned long long generation = [[[snapshots objectAtIndex:index] objectForKey:@"generation"] unsignedLongLongValue];
        if (newestGenerationIndex == NSNotFound || generation > newestGeneration) {
            newestGeneration = generation;
            newestGenerationIndex = index;
        }
    }
    if (newestGenerationIndex != NSNotFound) [protected addIndex:newestGenerationIndex];
    for (NSUInteger index = 0; index < [snapshots count]; index++) {
        NSDictionary *snapshot = [snapshots objectAtIndex:index];
        if ([[snapshot objectForKey:@"snapshotIdentifier"] isEqual:publishedIdentifier]) [protected addIndex:index];
        NSTimeInterval time = [[snapshot objectForKey:@"date"] timeIntervalSince1970];
        long long day = (long long)floor(time / 86400.0), week = (long long)floor((double)(day + 3) / 7.0);
        NSNumber *dayKey = [NSNumber numberWithLongLong:day], *weekKey = [NSNumber numberWithLongLong:week];
        BOOL retain = index < MAX(recent, minimum) || [protected containsIndex:index];
        if (day <= today && today - day < (long long)daily && ![days containsObject:dayKey]) { retain = YES; [days addObject:dayKey]; }
        if (week <= thisWeek && thisWeek - week < (long long)weekly && ![weeks containsObject:weekKey]) { retain = YES; [weeks addObject:weekKey]; }
        if (retain) [keep addIndex:index];
    }
    unsigned long long total = 0;
    for (NSUInteger index = [keep firstIndex]; index != NSNotFound; index = [keep indexGreaterThanIndex:index]) {
        unsigned long long size = [[[snapshots objectAtIndex:index] objectForKey:@"size"] unsignedLongLongValue];
        total = ULLONG_MAX - total < size ? ULLONG_MAX : total + size;
    }
    while (total > maxBytes && [keep count] > minimum) {
        NSUInteger index = [keep lastIndex];
        while (index != NSNotFound && [protected containsIndex:index]) index = [keep indexLessThanIndex:index];
        if (index == NSNotFound) break;
        total -= [[[snapshots objectAtIndex:index] objectForKey:@"size"] unsignedLongLongValue];
        [keep removeIndex:index];
    }
    BOOL changed = NO;
    // Delete oldest first. No error path can delete any of the newest minimum.
    for (NSUInteger remaining = [snapshots count]; remaining > 0; remaining--) {
        NSUInteger index = remaining - 1;
        if ([keep containsIndex:index]) continue;
        NSString *name = [[[snapshots objectAtIndex:index] objectForKey:@"snapshotURL"] lastPathComponent];
        if (!NVRemovePackage(directory, name, [NSSet setWithObjects:NVArchiveName, NVManifestName, nil], error)) return NO;
        changed = YES;
    }
    return !changed || NVSync(directory, @"sync-prune", error);
}

static int NVLock(int directory, NSError **error) {
    int lock = openat(directory, ".nvbackup-lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0600);
    if (lock < 0) { NVSystemError(error, @"Cannot lock the backup destination"); return -1; }
    struct stat attributes;
    if (fstat(lock, &attributes) != 0 || !S_ISREG(attributes.st_mode) || attributes.st_nlink != 1) {
        NVError(error, EINVAL, @"The backup destination has an invalid lock file."); close(lock); return -1;
    }
    if (flock(lock, LOCK_EX | LOCK_NB) != 0) { NVSystemError(error, @"The backup destination is in use"); close(lock); return -1; }
    return lock;
}

@implementation NVBackupStore

+ (NSDictionary *)publishArchiveData:(NSData *)data metadata:(NSDictionary *)metadata
                         inDirectory:(NSURL *)directory retention:(NSDictionary *)retention error:(NSError **)error {
    if (error) *error = nil;
    if (![data isKindOfClass:[NSData class]] || ![data length] || [data length] > NVMaximumArchiveSize ||
        !NVUUID([metadata objectForKey:@"libraryIdentifier"]) || !NVUnsignedNumber([metadata objectForKey:@"generation"], ULLONG_MAX) ||
        !NVUnsignedNumber([metadata objectForKey:@"encrypted"], 1) || ![[metadata objectForKey:@"appVersion"] isKindOfClass:[NSString class]] ||
        [[metadata objectForKey:@"appVersion"] length] > 256) {
        NVError(error, EINVAL, @"The captured backup data or metadata is invalid, or exceeds 512 MiB."); return nil;
    }
    int root = NVOpenPublicationDirectory(directory, metadata, error);
    if (root < 0) return nil;
    int lock = NVLock(root, error);
    if (lock < 0) { close(root); return nil; }
    NSError *ownerError = nil;
    NSDictionary *owner = NVReadOwner(root, YES, &ownerError);
    NSString *libraryIdentifier = [metadata objectForKey:@"libraryIdentifier"];
    if (ownerError || (owner && ![[owner objectForKey:@"libraryIdentifier"] isEqual:libraryIdentifier])) {
        if (error) *error = ownerError ?: [NSError errorWithDomain:NVBackupStoreErrorDomain code:EINVAL
            userInfo:@{NSLocalizedDescriptionKey: @"The backup destination belongs to another library."}];
        close(lock); close(root); return nil;
    }
    if (!owner) {
        owner = @{ @"formatVersion": @1, @"libraryIdentifier": libraryIdentifier };
        if (!NVCreateOwner(root, owner, error)) {
            close(lock); close(root); return nil;
        }
    }
    NVCleanStages(root, libraryIdentifier);
    NSString *identifier = [[NSUUID UUID] UUIDString];
    NSString *stageName = [@".nvbackup-stage-" stringByAppendingString:identifier];
    NSString *finalName = [identifier stringByAppendingPathExtension:@"nvbackup"];
    if (NVFail(@"create-stage", error) || mkdirat(root, [stageName fileSystemRepresentation], 0700) != 0) {
        if (!error || !*error) NVSystemError(error, @"Cannot create a backup staging directory");
        close(lock); close(root); return nil;
    }
    int stage = openat(root, [stageName fileSystemRepresentation], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (stage < 0) { NVSystemError(error, @"Cannot open the backup staging directory"); close(lock); close(root); return nil; }
    NSDictionary *manifest = @{ @"formatVersion": @1, @"libraryIdentifier": libraryIdentifier,
        @"snapshotIdentifier": identifier, @"date": NVDate(), @"appVersion": [metadata objectForKey:@"appVersion"],
        @"generation": [metadata objectForKey:@"generation"], @"encrypted": [metadata objectForKey:@"encrypted"],
        @"archiveName": NVArchiveName, @"size": @([data length]), @"sha256": NVSHA256(data) };
    BOOL complete = NVWritePlist(stage, NVStageOwnerName, owner, @"stage-owner", error) &&
        NVWriteFile(stage, NVArchiveName, data, @"archive", NULL, error) && NVWritePlist(stage, NVManifestName, manifest, @"manifest", error);
    if (complete) {
        NSData *readback = NVReadFile(stage, NVArchiveName, NVMaximumArchiveSize, error);
        NSDictionary *readManifest = NVReadPlist(stage, NVManifestName, error);
        complete = !NVFail(@"verify", error) && readback && [readManifest isEqual:manifest] &&
            [readback length] == [data length] && [NVSHA256(readback) isEqual:[manifest objectForKey:@"sha256"]];
        if (!complete && (!error || !*error)) NVError(error, EIO, @"The backup failed its readback check.");
    }
    if (complete && unlinkat(stage, [NVStageOwnerName fileSystemRepresentation], 0) != 0) complete = NVSystemError(error, @"Cannot finalize backup metadata");
    if (complete) complete = NVSync(stage, @"sync-stage", error);
    close(stage);
    if (complete) {
        if (NVFail(@"rename", error)) complete = NO;
        else if (renameatx_np(root, [stageName fileSystemRepresentation], root, [finalName fileSystemRepresentation], RENAME_EXCL) != 0)
            complete = NVSystemError(error, @"Cannot publish the backup");
    }
    if (complete) complete = NVSync(root, @"sync-directory", error);
    if (!complete) {
        NVRemovePackage(root, stageName, [NSSet setWithObjects:NVStageOwnerName, NVArchiveName, NVManifestName, nil], NULL);
        close(lock); close(root); return nil;
    }
    NSMutableDictionary *result = [[manifest mutableCopy] autorelease];
    [result setObject:[directory URLByAppendingPathComponent:finalName isDirectory:YES] forKey:@"snapshotURL"];
    NSError *retentionError = nil;
    if (!NVPrune(root, directory, libraryIdentifier, retention, identifier, &retentionError) && retentionError)
        [result setObject:retentionError forKey:@"retentionError"];
    close(lock); close(root);
    return result;
}

+ (NSArray *)snapshotsInDirectory:(NSURL *)directory error:(NSError **)error {
    if (error) *error = nil;
    NSError *openError = nil;
    int root = NVOpenDirectory(directory, NO, &openError);
    if (root < 0) {
        if ([openError code] == ENOENT) return @[];
        if (error) *error = openError;
        return nil;
    }
    NSError *ownerError = nil;
    NSDictionary *owner = NVReadOwner(root, YES, &ownerError);
    NSArray *result = nil;
    if (!owner && !ownerError) result = @[];
    else if (owner) result = NVSnapshots(root, directory, [owner objectForKey:@"libraryIdentifier"], error);
    else if (error) *error = ownerError;
    close(root);
    return result;
}

+ (NSData *)archiveDataAtSnapshotURL:(NSURL *)snapshotURL error:(NSError **)error {
    if (error) *error = nil;
    NSURL *parent = [snapshotURL URLByDeletingLastPathComponent];
    int root = NVOpenDirectory(parent, NO, error);
    if (root < 0) return nil;
    NSData *archive = nil;
    NVSnapshot(root, [snapshotURL lastPathComponent], parent, nil, &archive, error);
    close(root);
    return archive;
}

+ (BOOL)writeRestoreArchiveData:(NSData *)data toEmptyDirectory:(NSURL *)directory error:(NSError **)error {
    if (error) *error = nil;
    if (![data isKindOfClass:[NSData class]] || ![data length] || [data length] > NVMaximumArchiveSize)
        return NVError(error, EINVAL, @"The restored archive is empty or exceeds 512 MiB.");
    int root = NVOpenDirectory(directory, NO, error);
    if (root < 0) return NO;
    if (flock(root, LOCK_EX | LOCK_NB) != 0) {
        NVSystemError(error, @"The restore destination is in use"); close(root); return NO;
    }
    NSArray *names = NVNames(root, error);
    if (!names || [names count]) {
        if (names) NVError(error, EEXIST, @"Choose an empty folder for the restored library.");
        close(root); return NO;
    }
    if (fchmod(root, 0700) != 0) {
        NVSystemError(error, @"Cannot make the restored library folder private"); close(root); return NO;
    }
    NSString *temporary = [NSString stringWithFormat:@".nvbackup-restore-%@.tmp", [[NSUUID UUID] UUIDString]];
    BOOL created = NO;
    BOOL result = NVWriteFile(root, temporary, data, @"restore-archive", &created, error);
    struct stat written;
    BOOL identityKnown = created && fstatat(root, [temporary fileSystemRepresentation], &written, AT_SYMLINK_NOFOLLOW) == 0;
    if (result) {
        NSData *readback = NVReadFile(root, temporary, NVMaximumArchiveSize, error);
        result = readback && [readback isEqual:data];
        if (!result && (!error || !*error)) NVError(error, EIO, @"The restored archive failed its readback check.");
    }
    BOOL renamed = NO;
    if (result) {
        if (NVFail(@"restore-rename", error)) result = NO;
        else if (renameatx_np(root, [temporary fileSystemRepresentation], root, [NVArchiveName fileSystemRepresentation], RENAME_EXCL) != 0)
            result = NVSystemError(error, @"Cannot publish the restored archive");
        else renamed = YES;
    }
    if (result) result = NVSync(root, @"sync-restore-directory", error);
    if (!result && created) {
        NSString *name = renamed ? NVArchiveName : temporary;
        struct stat current;
        if (identityKnown && fstatat(root, [name fileSystemRepresentation], &current, AT_SYMLINK_NOFOLLOW) == 0 &&
            current.st_dev == written.st_dev && current.st_ino == written.st_ino) {
            unlinkat(root, [name fileSystemRepresentation], 0);
            fsync(root);
        }
    }
    close(root);
    return result;
}

+ (BOOL)pruneSnapshotsInDirectory:(NSURL *)directory retention:(NSDictionary *)retention error:(NSError **)error {
    if (error) *error = nil;
    int root = NVOpenDirectory(directory, NO, error);
    if (root < 0) return NO;
    int lock = NVLock(root, error);
    if (lock < 0) { close(root); return NO; }
    NSDictionary *owner = NVReadOwner(root, NO, error);
    BOOL result = owner && NVPrune(root, directory, [owner objectForKey:@"libraryIdentifier"], retention, nil, error);
    close(lock); close(root);
    return result;
}

+ (BOOL)deleteUnencryptedSnapshotsInDirectory:(NSURL *)directory error:(NSError **)error {
    if (error) *error = nil;
    int root = NVOpenDirectory(directory, NO, error);
    if (root < 0) return NO;
    int lock = NVLock(root, error);
    if (lock < 0) { close(root); return NO; }
    NSDictionary *owner = NVReadOwner(root, NO, error);
    NSArray *snapshots = owner ? NVSnapshots(root, directory, [owner objectForKey:@"libraryIdentifier"], error) : nil;
    BOOL result = snapshots != nil;
    for (NSDictionary *snapshot in snapshots) {
        if ([[snapshot objectForKey:@"encrypted"] boolValue]) continue;
        if (!NVRemovePackage(root, [[snapshot objectForKey:@"snapshotURL"] lastPathComponent], [NSSet setWithObjects:NVArchiveName, NVManifestName, nil], error)) { result = NO; break; }
    }
    if (result) result = NVSync(root, @"sync-delete-plaintext", error);
    close(lock); close(root);
    return result;
}
@end
