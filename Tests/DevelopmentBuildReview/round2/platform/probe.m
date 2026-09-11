// Foundation-only checks using the complete frozen backup store.
#import <Foundation/Foundation.h>
#import "NVAppIdentity.h"
#import "NVBackupStore.h"
#include <sys/stat.h>
#include <errno.h>

static NSUInteger Checks;
static NSString * const LibraryID = @"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static void Check(BOOL result, NSString *message) {
    Checks++;
    if (!result) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void MissingRootError(NSError *error) {
    Check([[error domain] isEqual:NVBackupStoreErrorDomain] && [error code] == ENOENT,
          @"an unavailable root returns the store's missing-path error");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 3, @"expected a disposable path and build flavor");
        NSString *flavor = [NSString stringWithUTF8String:argv[2]];
        BOOL development = [flavor isEqual:@"development"];
        NSBundle *bundle = [NSBundle mainBundle];
        Check(NVIsDevelopmentBuild() == development, @"the current helper consumes actual built flavor metadata");
        Check([[bundle bundleIdentifier] isEqual:development ? @"net.elasticthreads.nv.development" : @"net.elasticthreads.nv"],
              @"runtime flavor agrees with the built bundle identifier");
        Check([[bundle objectForInfoDictionaryKey:@"CFBundleName"] isEqual:development ? @"nvALT Development" : @"nvALT"],
              @"runtime flavor agrees with the built product name");
        NSString *scheme = NVNoteURLScheme();
        Check([scheme isEqual:development ? @"nvalt-dev" : @"nvalt"], @"the runtime note scheme follows the built flavor");
        NSArray *registrations = [bundle objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        Check([[[registrations objectAtIndex:0] objectForKey:@"CFBundleURLSchemes"] containsObject:scheme],
              @"the runtime scheme is present in built URL metadata");

        NSFileManager *manager = [NSFileManager defaultManager];
        NSURL *base = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
        NSURL *parent = [base URLByAppendingPathComponent:@"selected-parent" isDirectory:YES];
        NSURL *root = development ? [parent URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES] : parent;
        Check([manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL],
              @"the valid control starts with an existing custom destination root");
        struct stat identity;
        Check(stat([[root path] fileSystemRepresentation], &identity) == 0, @"capture the disposable root identity");
        NSDictionary *metadata = @{@"libraryIdentifier":LibraryID, @"generation":@1, @"encrypted":@NO,
            @"appVersion":@"platform-review", @"existingRoot":root,
            @"existingRootIdentity":[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)identity.st_dev,
                (unsigned long long)identity.st_ino]};
        NSDictionary *retention = @{@"recent":@3, @"daily":@0, @"weekly":@0, @"maxBytes":@10000000};
        NSURL *destination = [root URLByAppendingPathComponent:LibraryID isDirectory:YES];
        NSData *payload = [@"Disposable native platform archive: Việt 中文" dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *snapshot = [NVBackupStore publishArchiveData:payload metadata:metadata
            inDirectory:destination retention:retention error:&error];
        Check(snapshot != nil && error == nil, @"the complete native store publishes the valid control");
        Check([[NVBackupStore archiveDataAtSnapshotURL:[snapshot objectForKey:@"snapshotURL"] error:&error] isEqual:payload]
            && error == nil, @"the valid control has an exact archive readback");

        // A normal external volume loss also leaves the captured root path absent.
        NSURL *heldRoot = [base URLByAppendingPathComponent:@"held-root" isDirectory:YES];
        Check([manager moveItemAtURL:root toURL:heldRoot error:&error] && error == nil,
              @"make only the disposable captured root unavailable");
        snapshot = [NVBackupStore publishArchiveData:payload metadata:metadata
            inDirectory:destination retention:retention error:&error];
        Check(snapshot == nil, @"publication refuses the unavailable root");
        MissingRootError(error);
        Check(![NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:retention error:&error],
              @"retention refuses the unavailable root");
        MissingRootError(error);
        Check(![NVBackupStore deleteUnencryptedSnapshotsInDirectory:destination metadata:metadata error:&error],
              @"deletion refuses the unavailable root");
        MissingRootError(error);
        Check(![manager fileExistsAtPath:[root path]], @"failed operations do not recreate the captured root");
        error = nil;
        NSURL *heldDestination = [heldRoot URLByAppendingPathComponent:LibraryID isDirectory:YES];
        NSArray *saved = [NVBackupStore snapshotsInDirectory:heldDestination error:&error];
        Check([saved count] == 1 && error == nil, @"failed operations preserve the existing snapshot");
        Check([[NVBackupStore archiveDataAtSnapshotURL:[[saved objectAtIndex:0] objectForKey:@"snapshotURL"] error:&error]
            isEqual:payload] && error == nil, @"failed operations preserve the exact archive bytes");
        printf("PASS: %s metadata/runtime alignment and unavailable-root store contract (%lu assertions)\n",
            [flavor UTF8String], (unsigned long)Checks);
    }
    return 0;
}
