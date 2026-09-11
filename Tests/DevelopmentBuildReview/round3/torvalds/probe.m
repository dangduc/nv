#import <Foundation/Foundation.h>
#include <unistd.h>
#include <errno.h>
#include <libproc.h>

static NSUInteger SyncCalls, FailSyncAt;
static int ReviewSync(int fd) {
    SyncCalls++;
    if(FailSyncAt && SyncCalls==FailSyncAt) { errno=EIO; return -1; }
    return fsync(fd);
}
// Compile the actual implementation in this translation unit, exposing its
// static helpers. Only fsync has an observation/failure wrapper.
#define fsync ReviewSync
#import "NVBackupStore.m"
#undef fsync

static NSUInteger Checks, Successes, Rejections, DescriptorSamples;
static NSURL *Root;
static NSString *Library=@"F1000000-1111-4222-8333-123456789ABC";
static void Check(BOOL ok,NSString *message) {
    Checks++; if(!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
static NSUInteger DescriptorCount(void) {
    struct proc_fdinfo descriptors[1024];
    int bytes=proc_pidinfo(getpid(),PROC_PIDLISTFDS,0,descriptors,sizeof(descriptors));
    Check(bytes>0 && bytes<(int)sizeof(descriptors) && bytes%sizeof(struct proc_fdinfo)==0,@"native descriptor inventory fits its fixed buffer");
    DescriptorSamples++; return bytes/sizeof(struct proc_fdinfo);
}
static NSURL *Folder(NSString *name) { return [Root URLByAppendingPathComponent:name isDirectory:YES]; }
static void Make(NSURL *url) {
    NSError *error=nil;
    Check([[NSFileManager defaultManager]createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&error],@"create disposable fixture directory");
}
static NSString *Identity(NSURL *root) {
    struct stat info; Check(stat(root.path.fileSystemRepresentation,&info)==0,@"inspect disposable selected root");
    return [NSString stringWithFormat:@"%llu:%llu",(unsigned long long)info.st_dev,(unsigned long long)info.st_ino];
}
static NSMutableDictionary *Metadata(NSURL *root,BOOL development) {
    NSMutableDictionary *m=[NSMutableDictionary dictionaryWithDictionary:@{@"libraryIdentifier":Library,@"existingRoot":root,@"existingRootIdentity":Identity(root),@"generation":@1,@"encrypted":@0,@"appVersion":@"review"}];
    if(development)m[@"directoryNamespace"]=@"nvALT Development";
    return m;
}
static NSURL *Destination(NSURL *root,BOOL development) {
    if(development)root=[root URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES];
    return [root URLByAppendingPathComponent:Library isDirectory:YES];
}
static void Operation(NSURL *destination,NSDictionary *metadata,BOOL create,NSInteger expectedError) {
    NSUInteger before=DescriptorCount(); NSError *error=nil;
    int descriptor=NVOpenOperationDirectory(destination,metadata,create,&error);
    if(expectedError) {
        Check(descriptor<0 && [error.domain isEqual:NVBackupStoreErrorDomain] && error.code==expectedError,@"rejected operation returns its expected native error");
        Rejections++;
    } else {
        Check(descriptor>=0 && error==nil,@"successful operation returns one owned descriptor");
        Check(DescriptorCount()==before+1,@"successful operation retains only its returned descriptor");
        Check((fcntl(descriptor,F_GETFD)&FD_CLOEXEC)!=0,@"returned descriptor closes on exec");
        struct stat opened,path;
        Check(fstat(descriptor,&opened)==0&&stat(destination.path.fileSystemRepresentation,&path)==0&&S_ISDIR(opened.st_mode)&&opened.st_dev==path.st_dev&&opened.st_ino==path.st_ino,@"returned descriptor names the requested disposable directory");
        Check(close(descriptor)==0,@"caller releases its owned descriptor"); Successes++;
    }
    Check(DescriptorCount()==before,@"operation leaves no extra descriptors after completion");
}
static void Lifecycle(void) {
    for(NSUInteger i=0;i<8;i++)@autoreleasepool {
        NSURL *selected=Folder([NSString stringWithFormat:@"success-%lu",(unsigned long)i]);Make(selected);
        for(NSNumber *dev in @[@NO,@YES]) {
            NSDictionary *m=Metadata(selected,dev.boolValue);NSURL *d=Destination(selected,dev.boolValue);
            Operation(d,m,YES,0); Operation(d,m,NO,0); Operation(d,m,YES,0);
            struct stat info;Check(stat(d.path.fileSystemRepresentation,&info)==0&&(info.st_mode&0777)==0700,@"new library directory is private");
        }
        Check(![[Destination(selected,NO)path]isEqual:Destination(selected,YES).path],@"release and development paths remain distinct");
        Check([Destination(selected,NO).URLByDeletingLastPathComponent.path isEqual:selected.path],@"release retains its direct library child");
    }
    for(NSUInteger phase=1;phase<=2;phase++) {
        NSURL *selected=Folder([NSString stringWithFormat:@"sync-failure-%lu",(unsigned long)phase]);Make(selected);
        NSDictionary *m=Metadata(selected,YES);NSURL *d=Destination(selected,YES);
        SyncCalls=0;FailSyncAt=phase; Operation(d,m,YES,EIO); FailSyncAt=0;
        Operation(d,m,YES,0);Operation(d,m,NO,0);
    }
    NSURL *parentURL=Folder(@"borrowed-parent");Make(parentURL);
    int parent=NVOpenDirectory(parentURL,NO,NULL);Check(parent>=0,@"open borrowed parent fixture");
    NSUInteger held=DescriptorCount();
    for(NSUInteger i=0;i<8;i++) {
        NSError *error=nil;int child=NVOpenBackupChild(parent,@"child",YES,&error);
        Check(child>=0&&!error,@"child helper returns its child descriptor");Check(close(child)==0,@"close child descriptor");
        child=NVOpenBackupChild(parent,@"absent",NO,&error);Check(child<0&&error.code==ENOENT,@"child helper reports missing child");
        Check(fcntl(parent,F_GETFD)>=0&&DescriptorCount()==held,@"child helper preserves the caller's borrowed parent");
    }
    Check(close(parent)==0,@"caller closes borrowed parent after helper use");
}
static void RejectionBranches(void) {
    NSURL *selected=Folder(@"reject-selected");Make(selected);
    NSMutableDictionary *good=Metadata(selected,YES);NSURL *destination=Destination(selected,YES);
    NSArray *changes=@[@{@"directoryNamespace":@"unexpected"},@{@"directoryNamespace":@1},@{@"existingRootIdentity":@""},@{@"existingRootIdentity":@1},@{@"existingRootIdentity":@"0:0"},@{@"existingRoot":@"not a URL"}];
    for(NSUInteger iteration=0;iteration<16;iteration++)@autoreleasepool {
        for(NSDictionary *change in changes) {
            NSMutableDictionary *m=[[good mutableCopy]autorelease];[m addEntriesFromDictionary:change];
            Operation(destination,m,YES,[change[@"existingRootIdentity"]isEqual:@"0:0"]?ESTALE:EINVAL);
        }
        NSMutableDictionary *missingRoot=[[good mutableCopy]autorelease];[missingRoot removeObjectForKey:@"existingRoot"];
        Operation(destination,missingRoot,YES,EINVAL);
        Operation([selected URLByAppendingPathComponent:Library isDirectory:YES],good,YES,EINVAL);
        Operation(destination,good,NO,ENOENT);
    }
    Check([[[NSFileManager defaultManager]contentsOfDirectoryAtPath:selected.path error:NULL]count]==0,@"invalid metadata and noncreating operations leave selected root empty");
    NSURL *namespaceFile=Folder(@"namespace-file");Make(namespaceFile);
    Check([[@"file"dataUsingEncoding:NSUTF8StringEncoding]writeToURL:[namespaceFile URLByAppendingPathComponent:@"nvALT Development"]atomically:YES],@"create regular file namespace fixture");
    NSURL *libraryFile=Folder(@"library-file");Make([libraryFile URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES]);
    Check([[@"file"dataUsingEncoding:NSUTF8StringEncoding]writeToURL:Destination(libraryFile,YES)atomically:YES],@"create regular file library fixture");
    for(NSUInteger i=0;i<16;i++)for(NSURL *root in @[namespaceFile,libraryFile]) {
        Operation(Destination(root,YES),Metadata(root,YES),YES,ENOTDIR);
        Operation(Destination(root,YES),Metadata(root,YES),NO,ENOTDIR);
    }
    NSURL *disappeared=Folder(@"removed-root");Make(disappeared);NSDictionary *saved=Metadata(disappeared,YES);
    Check([[NSFileManager defaultManager]removeItemAtURL:disappeared error:NULL],@"remove disposable selected root");
    for(NSUInteger i=0;i<16;i++)Operation(Destination(disappeared,YES),saved,YES,ENOENT);
    Check(![[NSFileManager defaultManager]fileExistsAtPath:disappeared.path],@"operation never recreates a missing selected root");
}
static void PublicOperations(void) {
    NSURL *selected=Folder(@"public-operations");Make(selected);
    NSData *payload=[@"disposable archive bytes"dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *retention=@{@"recent":@100,@"daily":@0,@"weekly":@0,@"maxBytes":@1048576};
    NSUInteger before=DescriptorCount();
    for(NSNumber *dev in @[@NO,@YES]) {
        NSDictionary *m=Metadata(selected,dev.boolValue);NSURL *d=Destination(selected,dev.boolValue);
        for(NSUInteger iteration=0;iteration<3;iteration++) {
            NSError *error=nil;
            Check([NVBackupStore publishArchiveData:payload metadata:m inDirectory:d retention:retention error:&error]!=nil&&!error,@"public publication succeeds under the intended flavor path");
            Check(DescriptorCount()==before,@"public publication closes directory and file descriptors");
            Check([NVBackupStore pruneSnapshotsInDirectory:d metadata:m retention:retention error:&error]&&!error,@"public maintenance succeeds with captured root metadata");
            Check(DescriptorCount()==before,@"public maintenance closes descriptors");
        }
    }
    Check([[NVBackupStore snapshotsInDirectory:Destination(selected,NO)error:NULL]count]==3,@"release snapshots remain at their original direct-child path");
    Check([[NVBackupStore snapshotsInDirectory:Destination(selected,YES)error:NULL]count]==3,@"development snapshots use their namespace path");
    Check(DescriptorCount()==before,@"public snapshot enumeration closes descriptors");
}
int main(int argc,const char **argv) { @autoreleasepool {
    Check(argc==3,@"disposable root and result path supplied");Root=[NSURL fileURLWithPath:@(argv[1])isDirectory:YES];
    // Warm native Foundation and descriptor enumeration before the global comparison.
    Make(Folder(@"warm"));(void)Identity(Folder(@"warm"));(void)DescriptorCount();
    NSUInteger before=DescriptorCount();Lifecycle();RejectionBranches();PublicOperations();NSUInteger after=DescriptorCount();
    Check(before==after,@"complete bounded review leaves descriptor count unchanged");
    NSDictionary *result=@{@"checks":@(Checks+1),@"successfulDirectoryOperations":@(Successes),@"rejectedDirectoryOperations":@(Rejections),@"descriptorSamples":@(DescriptorSamples),@"initialDescriptors":@(before),@"finalDescriptors":@(after),@"injectedSyncFailures":@2,@"publicPublications":@6,@"publicMaintenanceRuns":@6,@"passed":@YES};
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    Check([json writeToFile:@(argv[2])atomically:YES],@"write review evidence");
    printf("PASS %lu checks; descriptors %lu -> %lu; %lu successful and %lu rejected directory operations\n",(unsigned long)Checks,(unsigned long)before,(unsigned long)after,(unsigned long)Successes,(unsigned long)Rejections);
}return 0; }
