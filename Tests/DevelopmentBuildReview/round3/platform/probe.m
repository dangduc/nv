// Two selected-parent lifecycle checks. All paths belong to a disposable fixture.
#import <Foundation/Foundation.h>
#import "NVBackupStore.h"
#include <sys/stat.h>
#include <errno.h>

static NSUInteger Checks;
static NSString * const LibraryID = @"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static void Check(BOOL result, NSString *message) {
    Checks++;
    if (!result) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSString *Identity(NSURL *root) {
    struct stat value;
    Check(stat([[root path] fileSystemRepresentation], &value) == 0 && S_ISDIR(value.st_mode),
          @"capture the selected disposable parent identity");
    return [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)value.st_dev, (unsigned long long)value.st_ino];
}
static NSDictionary *Metadata(NSURL *root, BOOL development) {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
        @"libraryIdentifier":LibraryID, @"generation":@1, @"encrypted":@NO,
        @"appVersion":@"platform-round3", @"existingRoot":root, @"existingRootIdentity":Identity(root)}];
    if (development) [result setObject:@"nvALT Development" forKey:@"directoryNamespace"];
    return result;
}
static NSDictionary *TreeBytes(NSURL *root) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *relative in [manager enumeratorAtPath:[root path]]) {
        NSString *path = [[root path] stringByAppendingPathComponent:relative];
        BOOL directory = NO;
        Check([manager fileExistsAtPath:path isDirectory:&directory], @"every recorded fixture path exists");
        id bytes = directory ? (id)[NSNull null] : (id)[NSData dataWithContentsOfFile:path];
        Check(bytes != nil, @"read every regular fixture file");
        [result setObject:bytes forKey:relative];
    }
    return result;
}
static void RejectedOperations(NSURL *destination, NSDictionary *metadata, NSData *payload,
                               NSDictionary *retention, NSInteger expectedCode) {
    NSError *error = nil;
    Check([NVBackupStore publishArchiveData:payload metadata:metadata inDirectory:destination retention:retention error:&error] == nil,
          @"publication rejects the unavailable or replaced selected parent");
    Check([[error domain] isEqual:NVBackupStoreErrorDomain] && [error code] == expectedCode,
          @"publication reports the expected selected-parent error");
    Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:retention error:&error],
          @"retention rejects the unavailable or replaced selected parent");
    Check([[error domain] isEqual:NVBackupStoreErrorDomain] && [error code] == expectedCode,
          @"retention reports the expected selected-parent error");
    Check(![NVBackupStore deleteUnencryptedSnapshotsInDirectory:destination metadata:metadata error:&error],
          @"plaintext deletion rejects the unavailable or replaced selected parent");
    Check([[error domain] isEqual:NVBackupStoreErrorDomain] && [error code] == expectedCode,
          @"plaintext deletion reports the expected selected-parent error");
}
static void Publish(NSURL *destination, NSDictionary *metadata, NSData *payload, NSDictionary *retention) {
    NSError *error = nil;
    NSDictionary *snapshot = [NVBackupStore publishArchiveData:payload metadata:metadata
        inDirectory:destination retention:retention error:&error];
    Check(snapshot != nil && error == nil, @"correct captured metadata publishes into an absent namespace/library path");
    Check([[NVBackupStore archiveDataAtSnapshotURL:[snapshot objectForKey:@"snapshotURL"] error:&error] isEqual:payload]
        && error == nil, @"the valid control retains exact archive bytes");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 3, @"expected a disposable path and flavor");
        NSString *flavor = [NSString stringWithUTF8String:argv[2]];
        BOOL development = [flavor isEqual:@"development"];
        Check(development || [flavor isEqual:@"release"], @"only the two production metadata layouts participate");
        NSURL *base = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
        NSFileManager *manager = [NSFileManager defaultManager];
        NSData *payload = [@"Disposable Round 3 archive: Việt 中文" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *retention = @{@"recent":@3, @"daily":@0, @"weekly":@0, @"maxBytes":@10000000};
        for (NSString *phase in @[@"before-first-publication", @"after-publication"]) {
            NSURL *phaseRoot = [base URLByAppendingPathComponent:phase isDirectory:YES];
            NSURL *root = [phaseRoot URLByAppendingPathComponent:@"selected-parent" isDirectory:YES];
            NSURL *held = [phaseRoot URLByAppendingPathComponent:@"held-parent" isDirectory:YES];
            Check([manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL],
                  @"create only the selected parent for the initial control");
            NSURL *namespace = development ? [root URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES] : root;
            NSURL *destination = [namespace URLByAppendingPathComponent:LibraryID isDirectory:YES];
            Check(![manager fileExistsAtPath:[destination path]], @"the library destination starts absent");
            if (development) Check(![manager fileExistsAtPath:[namespace path]], @"the Development namespace starts absent");
            NSDictionary *metadata = Metadata(root, development);
            if ([phase isEqual:@"after-publication"]) Publish(destination, metadata, payload, retention);
            NSDictionary *before = TreeBytes(root);
            Check([manager moveItemAtURL:root toURL:held error:NULL], @"make the captured selected parent unavailable");

            RejectedOperations(destination, metadata, payload, retention, ENOENT);
            Check(![manager fileExistsAtPath:[root path]], @"no operation recreates the absent selected parent");
            Check([before isEqual:TreeBytes(held)], @"absent-parent rejection preserves all original paths and file bytes");

            Check([manager createDirectoryAtURL:root withIntermediateDirectories:NO attributes:nil error:NULL],
                  @"create an empty replacement selected parent");
            Check(![Identity(root) isEqual:[metadata objectForKey:@"existingRootIdentity"]],
                  @"the replacement parent differs from the captured filesystem identity");
            RejectedOperations(destination, metadata, payload, retention, ESTALE);
            Check([[manager contentsOfDirectoryAtPath:[root path] error:NULL] count] == 0,
                  @"stale metadata creates no namespace or library child in the replacement parent");
            Check([before isEqual:TreeBytes(held)], @"stale-parent rejection preserves all original paths and file bytes");

            // A fresh identity is the positive control after both rejected states.
            Publish(destination, Metadata(root, development), payload, retention);
            Check([before isEqual:TreeBytes(held)], @"a valid retry leaves the old parent's snapshots unchanged");
            printf("PASS: %s %s absent parent ENOENT; replacement parent ESTALE; fresh identity succeeds\n",
                   [flavor UTF8String], [phase UTF8String]);
        }
        printf("ASSERTIONS:%lu\n", (unsigned long)Checks);
    }
    return 0;
}
