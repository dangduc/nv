#import <Foundation/Foundation.h>
#import "NVBackupStore.h"
#include <sys/stat.h>

static NSUInteger Checks;
static NSString * const LibraryID = @"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static void Check(BOOL result, NSString *message) {
    Checks++;
    if (!result) { NSLog(@"FAIL: %@",message); exit(1); }
}

static NSDictionary *Metadata(NSURL *destination, NSUInteger generation) {
    NSURL *parent = [destination URLByDeletingLastPathComponent];
    struct stat attributes;
    Check(stat([[parent path] fileSystemRepresentation],&attributes)==0 && S_ISDIR(attributes.st_mode),
        @"the selected disposable parent already exists");
    NSString *identity = [NSString stringWithFormat:@"%llu:%llu",(unsigned long long)attributes.st_dev,(unsigned long long)attributes.st_ino];
    return @{@"libraryIdentifier":LibraryID,@"generation":@(generation),@"encrypted":@NO,@"appVersion":@"review",
        @"existingRoot":parent,@"existingRootIdentity":identity};
}

static NSData *Payload(NSString *flavor, NSUInteger generation) {
    return [[NSString stringWithFormat:@"Disposable %@ archive %lu: Việt 中文 👩🏽‍💻\n",flavor,(unsigned long)generation]
        dataUsingEncoding:NSUTF8StringEncoding];
}

static NSDictionary *ReadArchives(NSURL *destination, NSString *flavor) {
    NSError *error=nil;
    NSArray *snapshots = [NVBackupStore snapshotsInDirectory:destination error:&error];
    Check(snapshots!=nil && error==nil,@"actual store lists the selected flavor destination");
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    for (NSDictionary *snapshot in snapshots) {
        NSUInteger generation=[snapshot[@"generation"] unsignedIntegerValue];
        NSData *bytes=[NVBackupStore archiveDataAtSnapshotURL:snapshot[@"snapshotURL"] error:&error];
        Check(error==nil && [bytes isEqual:Payload(flavor,generation)],@"every listed archive retains exact flavor-specific bytes");
        result[snapshot[@"snapshotIdentifier"]]=bytes;
    }
    return result;
}

int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==3,@"two disposable destinations are required");
        NSURL *release=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
        NSURL *development=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]] isDirectory:YES];
        Check(![release.path isEqual:development.path] && [release.lastPathComponent isEqual:LibraryID] &&
            [development.lastPathComponent isEqual:LibraryID],@"both flavor destinations retain the copied library UUID but differ by path");
        NSDictionary *keep=@{@"recent":@10,@"daily":@0,@"weekly":@0,@"maxBytes":@(10000000)};
        NSDictionary *prune=@{@"recent":@3,@"daily":@0,@"weekly":@0,@"maxBytes":@(10000000)};
        NSArray *destinations=@[release,development], *flavors=@[@"release",@"development"];
        for (NSUInteger index=0;index<2;index++) {
            for (NSUInteger generation=1;generation<=5;generation++) {
                NSError *error=nil;
                NSDictionary *published=[NVBackupStore publishArchiveData:Payload(flavors[index],generation)
                    metadata:Metadata(destinations[index],generation) inDirectory:destinations[index] retention:keep error:&error];
                Check(published!=nil && error==nil && published[@"retentionError"]==nil,@"the actual store publishes a complete flavor-specific snapshot");
            }
        }
        NSDictionary *releaseBefore=ReadArchives(release,@"release");
        NSDictionary *developmentBefore=ReadArchives(development,@"development");
        Check(releaseBefore.count==5 && developmentBefore.count==5,@"each flavor initially owns five readable snapshots");
        NSError *error=nil;
        Check([NVBackupStore pruneSnapshotsInDirectory:development metadata:Metadata(development,5) retention:prune error:&error] && !error,
            @"development retention completes through the actual store");
        NSDictionary *developmentAfter=ReadArchives(development,@"development");
        Check(developmentAfter.count==3,@"development retention prunes its own history to three snapshots");
        Check([releaseBefore isEqual:ReadArchives(release,@"release")],@"development retention preserves every release snapshot ID and archive byte");
        Check([NVBackupStore pruneSnapshotsInDirectory:release metadata:Metadata(release,5) retention:prune error:&error] && !error,
            @"release retention completes through the actual store");
        Check(ReadArchives(release,@"release").count==3,@"release retention prunes its own history to three snapshots");
        Check([developmentAfter isEqual:ReadArchives(development,@"development")],@"release retention preserves every remaining development snapshot ID and archive byte");
        printf("PASS: retention separation (%lu checks): release 5 -> 3, development 5 -> 3, sibling snapshots and bytes unchanged\n",(unsigned long)Checks);
    }
    return 0;
}
