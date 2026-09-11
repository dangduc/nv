#import <Cocoa/Cocoa.h>
#import "NVBackupStore.h"
#import "NVAppIdentity.h"
#include <sys/stat.h>

static NSUInteger Checks;
static NSString * const LibraryID=@"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static NSURL *SelectedParent;
static NSString *RootIdentity;
static void Check(BOOL result, NSString *message) {
    Checks++;
    if (!result) { NSLog(@"FAIL: %@",message); exit(1); }
}

static NSURL *Destination(BOOL development) {
    NSURL *parent=development ? [SelectedParent URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES] : SelectedParent;
    return [parent URLByAppendingPathComponent:LibraryID isDirectory:YES];
}

static NSDictionary *Metadata(NSUInteger generation) {
    NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithDictionary:@{
        @"libraryIdentifier":LibraryID,@"generation":@(generation),@"encrypted":@NO,@"appVersion":@"review",
        @"existingRoot":SelectedParent,@"existingRootIdentity":RootIdentity}];
    if (NVIsDevelopmentBuild()) metadata[@"directoryNamespace"]=@"nvALT Development";
    return metadata;
}

static NSData *Payload(NSString *flavor,NSUInteger generation) {
    return [[NSString stringWithFormat:@"Disposable %@ generation %lu: Việt 中文 👩🏽‍💻\n",flavor,(unsigned long)generation]
        dataUsingEncoding:NSUTF8StringEncoding];
}

static NSDictionary *ReadArchives(BOOL development) {
    NSError *error=nil;
    NSArray *snapshots=[NVBackupStore snapshotsInDirectory:Destination(development) error:&error];
    Check(snapshots!=nil && error==nil,@"the actual store reopens the flavor destination");
    NSMutableDictionary *records=[NSMutableDictionary dictionary];
    for (NSDictionary *snapshot in snapshots) {
        NSData *data=[NVBackupStore archiveDataAtSnapshotURL:snapshot[@"snapshotURL"] error:&error];
        Check(error==nil && [data isEqual:Payload(development?@"development":@"release",[snapshot[@"generation"] unsignedIntegerValue])],
            @"the reopened snapshot has exact flavor-specific archive bytes");
        records[snapshot[@"snapshotIdentifier"]]=data;
    }
    return records;
}

static void Publish(NSString *flavor,NSUInteger generation) {
    NSError *error=nil;
    NSDictionary *result=[NVBackupStore publishArchiveData:Payload(flavor,generation) metadata:Metadata(generation)
        inDirectory:Destination(NVIsDevelopmentBuild())
        retention:@{@"recent":@10,@"daily":@0,@"weekly":@0,@"maxBytes":@10000000} error:&error];
    Check(result!=nil && error==nil && result[@"retentionError"]==nil,@"production publication succeeds with captured selected-root metadata");
}

int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==5,@"selected parent, checkpoint, flavor, and command are required");
        SelectedParent=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
        NSString *checkpoint=[NSString stringWithUTF8String:argv[2]];
        NSString *flavor=[NSString stringWithUTF8String:argv[3]], *command=[NSString stringWithUTF8String:argv[4]];
        BOOL development=NVIsDevelopmentBuild();
        Check(development==[flavor isEqual:@"development"],@"the frozen identity helper reads the expected fixture bundle flavor");
        NSString *peer=development?@"release":@"development";
        struct stat parentInfo;
        Check(stat([[SelectedParent path] fileSystemRepresentation],&parentInfo)==0 && S_ISDIR(parentInfo.st_mode),
            @"only the selected parent must exist before first publication");
        NSString *identity=[NSString stringWithFormat:@"%llu:%llu",(unsigned long long)parentInfo.st_dev,(unsigned long long)parentInfo.st_ino];
        NSMutableDictionary *state=[NSMutableDictionary dictionaryWithContentsOfFile:checkpoint];
        if (!state) state=[NSMutableDictionary dictionaryWithDictionary:@{@"release":@{},@"development":@{},@"rootIdentity":identity}];
        RootIdentity=state[@"rootIdentity"];
        Check([RootIdentity isEqual:identity],@"every reopened process uses the original selected-root identity");
        Check([ReadArchives(NO) isEqual:state[@"release"]] && [ReadArchives(YES) isEqual:state[@"development"]],
            @"reopen preserves all prior snapshot identifiers and archive bytes in both histories");
        NSDictionary *peerBefore=state[peer];
        if ([command isEqual:@"seed"]) {
            Check([state[flavor] count]==0,@"the flavor history is empty before first publication");
            if (development) Check(![[NSFileManager defaultManager] fileExistsAtPath:[[SelectedParent
                URLByAppendingPathComponent:@"nvALT Development"] path]],@"the development namespace does not exist before first publication");
            Publish(flavor,1);
            struct stat directoryInfo;
            Check(stat([[Destination(development) path] fileSystemRepresentation],&directoryInfo)==0 && S_ISDIR(directoryInfo.st_mode),
                @"the production store creates the library UUID directory on first publication");
            if (development) Check(stat([[[SelectedParent URLByAppendingPathComponent:@"nvALT Development"] path] fileSystemRepresentation],&directoryInfo)==0 &&
                S_ISDIR(directoryInfo.st_mode),@"the production store creates the development namespace without fixture precreation");
            for (NSUInteger generation=2;generation<=5;generation++) Publish(flavor,generation);
            Check(ReadArchives(development).count==5,@"five complete snapshots exist after the first publication history");
        } else if ([command isEqual:@"prune"]) {
            NSError *error=nil;
            Check([NVBackupStore pruneSnapshotsInDirectory:Destination(development) metadata:Metadata(5)
                retention:@{@"recent":@3,@"daily":@0,@"weekly":@0,@"maxBytes":@10000000} error:&error] && !error,
                @"reopened retention accepts the namespace metadata");
            Check(ReadArchives(development).count==3,@"retention reduces only this flavor to three snapshots");
        } else if ([command isEqual:@"delete-republish"] || [command isEqual:@"delete"]) {
            NSError *error=nil;
            Check([NVBackupStore deleteUnencryptedSnapshotsInDirectory:Destination(development) metadata:Metadata(5) error:&error] && !error,
                @"reopened plaintext deletion accepts the selected-root and namespace metadata");
            Check(ReadArchives(development).count==0,@"plaintext deletion removes this flavor's complete plaintext snapshots");
            Check([ReadArchives(!development) isEqual:peerBefore],@"plaintext deletion preserves every peer snapshot identifier and archive byte");
            if ([command isEqual:@"delete-republish"]) {
                Publish(flavor,6);
                Check(ReadArchives(development).count==1,@"publication after deletion creates a new readable snapshot in the same flavor history");
            }
        } else Check(NO,@"unknown history command");
        NSDictionary *current=ReadArchives(development);
        Check([ReadArchives(!development) isEqual:peerBefore],@"the complete flavor operation preserves every peer snapshot identifier and archive byte");
        state[flavor]=current;
        Check([state writeToFile:checkpoint atomically:YES],@"write independent expected snapshot IDs and bytes for the next process");
        Check(NSApp==nil,@"the fixture never starts NSApplication or a GUI");
        printf("PASS: %s %s checks=%lu own=%lu peer=%lu\n",flavor.UTF8String,command.UTF8String,(unsigned long)Checks,
            (unsigned long)current.count,(unsigned long)[peerBefore count]);
    }
    return 0;
}
