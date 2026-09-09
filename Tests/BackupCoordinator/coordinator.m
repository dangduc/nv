#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <sys/stat.h>
#import "NVBackupController.h"
#import "NVBackupStore.h"
#import "NVBackupArchive.h"
#import "NotationController.h"
#import "NotationPrefs.h"
#import "NSFileManager+DirectoryLocations.h"

// Run the production coordinator without opening windows, notes, or persistent defaults.
static NSTimeInterval clockTime = 1000000;
static NSString *testRoot;
static NSUInteger publications;
static BOOL failPublication;
static BOOL failPublicationRetention, failMaintenance;
static NSUInteger maintenanceCalls;
static NSMutableArray *maintenanceMetadata, *maintenancePolicies;
static NSMutableArray *publishedMetadata, *publishedDestinations, *publishedData;
static NSMutableArray *deletionMetadata, *deletionDestinations;
static NSMutableDictionary *expectedArchiveData;
static NSMutableArray *verificationURLs;
static id memoryDefaults, completionQueue;

@interface ManualQueue : NSOperationQueue { NSMutableArray *pending; }
- (NSUInteger)pendingCount;
- (void)runNext;
@end
@implementation ManualQueue
- (id)init { if ((self = [super init])) pending = [NSMutableArray new]; return self; }
- (void)addOperationWithBlock:(void (^)(void))block { [pending addObject:[NSBlockOperation blockOperationWithBlock:block]]; }
- (NSUInteger)pendingCount { return [pending count]; }
- (void)runNext {
    NSOperation *operation = [[pending objectAtIndex:0] retain];
    [pending removeObjectAtIndex:0];
    [operation start];
    [operation release];
}
- (void)dealloc { [pending release]; [super dealloc]; }
@end

@interface MemoryDefaults : NSObject { NSMutableDictionary *values; }
- (NSDictionary *)dictionaryForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;
@end
@implementation MemoryDefaults
- (id)init { if ((self = [super init])) values = [NSMutableDictionary new]; return self; }
- (NSDictionary *)dictionaryForKey:(NSString *)key { return [values objectForKey:key]; }
- (void)setObject:(id)object forKey:(NSString *)key { [values setObject:[[object copy] autorelease] forKey:key]; }
- (void)dealloc { [values release]; [super dealloc]; }
@end

static id ClockDate(id self, SEL command) { return [NSDate dateWithTimeIntervalSinceReferenceDate:clockTime]; }
static id ClockRelativeDate(id self, SEL command, NSTimeInterval interval) { return [NSDate dateWithTimeIntervalSinceReferenceDate:clockTime + interval]; }
static id MemoryStandardDefaults(id self, SEL command) { return memoryDefaults; }
static id ManualMainQueue(id self, SEL command) { return completionQueue; }
static void ReplaceClassMethod(Class cls, SEL selector, IMP implementation) {
    Method method = class_getClassMethod(cls, selector);
    class_replaceMethod(object_getClass(cls), selector, implementation, method_getTypeEncoding(method));
}

@implementation NSFileManager (DirectoryLocations)
- (NSString *)applicationSupportDirectory { return [testRoot stringByAppendingPathComponent:@"support"]; }
@end

@implementation NotationPrefs @end
@interface FixturePrefs : NotationPrefs { NSString *fixtureIdentifier; }
- (id)initWithIdentifier:(NSString *)identifier;
@end
@implementation FixturePrefs
- (id)initWithIdentifier:(NSString *)identifier { if ((self = [super init])) fixtureIdentifier = [identifier copy]; return self; }
- (NSString *)backupLibraryIdentifier { return fixtureIdentifier; }
- (void)renewBackupLibraryIdentifier { [fixtureIdentifier release]; fixtureIdentifier = [[[NSUUID UUID] UUIDString] copy]; }
- (void)dealloc { [fixtureIdentifier release]; [super dealloc]; }
@end

@implementation NotationController @end
@interface FixtureLibrary : NotationController {
    FixturePrefs *fixturePrefs;
    NSURL *fixtureDirectory;
@public
    NSUInteger generation, captures;
    BOOL failCapture, sourceWarning;
}
- (id)initWithIdentifier:(NSString *)identifier;
@end
@implementation FixtureLibrary
- (id)initWithIdentifier:(NSString *)identifier {
    if ((self = [super init])) {
        fixturePrefs = [[FixturePrefs alloc] initWithIdentifier:identifier];
        fixtureDirectory = [[NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:identifier]] retain];
        [[NSFileManager defaultManager] createDirectoryAtURL:fixtureDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        generation = 1;
    }
    return self;
}
- (NotationPrefs *)notationPrefs { return fixturePrefs; }
- (NSURL *)notesDirectoryURL { return fixtureDirectory; }
- (NSDictionary *)backupSnapshotWithError:(NSError **)error {
    captures++;
    if (failCapture) {
        if (error) *error = [NSError errorWithDomain:@"FixtureCapture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Injected capture failure"}];
        return nil;
    }
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithDictionary:@{@"data":[[NSString stringWithFormat:@"generation-%lu", (unsigned long)generation] dataUsingEncoding:NSUTF8StringEncoding],
        @"generation":@(generation), @"libraryIdentifier":[fixturePrefs backupLibraryIdentifier], @"date":[NSDate date]}];
    if (sourceWarning) [snapshot setObject:[NSError errorWithDomain:@"FixtureSource" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Source file write is pending"}] forKey:@"sourceWriteError"];
    return snapshot;
}
- (void)dealloc { [fixturePrefs release]; [fixtureDirectory release]; [super dealloc]; }
@end

@implementation NVBackupStore
+ (NSDictionary *)publishArchiveData:(NSData *)data metadata:(NSDictionary *)metadata inDirectory:(NSURL *)directory retention:(NSDictionary *)retention error:(NSError **)error {
    publications++;
    [publishedData addObject:data];
    [publishedMetadata addObject:metadata];
    [publishedDestinations addObject:directory];
    if (failPublication) {
        if (error) *error = [NSError errorWithDomain:@"FixtureStore" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Injected publication failure"}];
        return nil;
    }
    NSURL *snapshot = [directory URLByAppendingPathComponent:[[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"nvbackup"]];
    [[NSFileManager defaultManager] createDirectoryAtURL:snapshot withIntermediateDirectories:YES attributes:nil error:NULL];
    [data writeToURL:[snapshot URLByAppendingPathComponent:@"archive.bin"] atomically:YES];
    [expectedArchiveData setObject:data forKey:[snapshot path]];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{@"date":[NSDate date], @"snapshotURL":snapshot}];
    if (failPublicationRetention) [result setObject:[NSError errorWithDomain:@"FixtureStore" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Injected retention failure"}] forKey:@"retentionError"];
    return result;
}
+ (BOOL)pruneSnapshotsInDirectory:(NSURL *)directory metadata:(NSDictionary *)metadata retention:(NSDictionary *)retention error:(NSError **)error {
    maintenanceCalls++;
    [maintenanceMetadata addObject:metadata]; [maintenancePolicies addObject:retention];
    if (failMaintenance && error) *error = [NSError errorWithDomain:@"FixtureStore" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Injected retention failure"}];
    return !failMaintenance;
}
+ (NSArray *)snapshotsInDirectory:(NSURL *)directory error:(NSError **)error { return @[@{@"size":@1234}]; }
+ (NSData *)archiveDataAtSnapshotURL:(NSURL *)url error:(NSError **)error {
    [verificationURLs addObject:url];
    NSData *data = [NSData dataWithContentsOfURL:[url URLByAppendingPathComponent:@"archive.bin"]];
    // The store suite checks real checksums. This fixture exposes the same verified-read contract to the coordinator.
    if (!data || ![data isEqualToData:[expectedArchiveData objectForKey:[url path]]]) return nil;
    return data;
}
+ (BOOL)deleteUnencryptedSnapshotsInDirectory:(NSURL *)url metadata:(NSDictionary *)metadata error:(NSError **)error {
    [deletionMetadata addObject:metadata]; [deletionDestinations addObject:url];
    return YES;
}
@end
@implementation NVBackupArchive
+ (NSDictionary *)restoredArchiveFromData:(NSData *)data error:(NSError **)error { return nil; }
@end

@interface NVBackupController (TestSelectors)
- (void)woke:(NSNotification *)notification;
@end

static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Attach(NVBackupController *controller, FixtureLibrary *library) {
    [controller setLibrary:library];
    [NSObject cancelPreviousPerformRequestsWithTarget:controller];
}
static void Complete(ManualQueue *worker) {
    Check([worker pendingCount] == 1, @"One worker operation is pending");
    [worker runNext];
    Check([completionQueue pendingCount] == 1, @"One main-thread completion is pending");
    [completionQueue runNext];
}
static void Tick(NVBackupController *controller, NSTimeInterval timestamp) {
    clockTime = timestamp;
    [controller checkForBackupAtDate:[NSDate date]];
}

@interface FixtureDeleteAlert : NSObject
- (void)setMessageText:(NSString *)text;
- (void)setInformativeText:(NSString *)text;
- (void)addButtonWithTitle:(NSString *)title;
- (NSInteger)runModal;
@end
@implementation FixtureDeleteAlert
- (void)setMessageText:(NSString *)text {}
- (void)setInformativeText:(NSString *)text {}
- (void)addButtonWithTitle:(NSString *)title {}
- (NSInteger)runModal { return NSAlertSecondButtonReturn; }
@end
static id AllocateDeleteAlert(id self, SEL command) { return [FixtureDeleteAlert new]; }

static void DeletionChecks(ManualQueue *worker) {
    deletionMetadata = [NSMutableArray new]; deletionDestinations = [NSMutableArray new];
    Method allocation = class_getClassMethod([NSAlert class], @selector(alloc));
    IMP originalAllocation = method_getImplementation(allocation);
    ReplaceClassMethod([NSAlert class], @selector(alloc), (IMP)AllocateDeleteAlert);
    NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
    [[controller valueForKey:@"timer"] invalidate]; [controller setValue:worker forKey:@"worker"];
    FixtureLibrary *library = [[FixtureLibrary alloc] initWithIdentifier:@"deletion-original"];
    FixtureLibrary *peer = [[FixtureLibrary alloc] initWithIdentifier:@"deletion-peer"];
    Attach(controller, library);
    [controller deleteUnencryptedBackups:nil]; Complete(worker);
    Check([[[deletionMetadata lastObject] objectForKey:@"libraryIdentifier"] isEqual:@"deletion-original"] &&
        ![[deletionMetadata lastObject] objectForKey:@"existingRoot"], @"Default deletion captures the active library identity");
    NSURL *selected = [NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:@"deletion-selected"] isDirectory:YES];
    Check([[NSFileManager defaultManager] createDirectoryAtURL:selected withIntermediateDirectories:YES attributes:nil error:NULL], @"Create selected deletion root");
    NSData *bookmark = [selected bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
    Check(bookmark != nil, @"Create selected deletion bookmark");
    NSMutableDictionary *settings = [controller valueForKey:@"librarySettings"];
    [settings setObject:bookmark forKey:@"destinationBookmark"];
    struct stat identity;
    Check(stat([[selected path] fileSystemRepresentation], &identity) == 0, @"Read selected root identity");
    NSString *capturedIdentity = [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)identity.st_dev, (unsigned long long)identity.st_ino];
    [controller deleteUnencryptedBackups:nil];
    Check([worker pendingCount] == 1 && [controller isBusy], @"Deletion runs on the worker");
    Attach(controller, peer); Complete(worker);
    NSDictionary *captured = [deletionMetadata lastObject];
    Check([[captured objectForKey:@"libraryIdentifier"] isEqual:@"deletion-original"] &&
        [[captured objectForKey:@"existingRootIdentity"] isEqual:capturedIdentity], @"Queued deletion retains the original library and selected-root identity");
    Check([[[[captured objectForKey:@"existingRoot"] URLByResolvingSymlinksInPath] path] isEqual:[[selected URLByResolvingSymlinksInPath] path]] &&
        [[[deletionDestinations lastObject] lastPathComponent] isEqual:@"deletion-original"], @"Queued deletion retains its selected root and original destination");
    Check([[controller libraryIdentifier] isEqual:@"deletion-peer"] && ![[controller settings] objectForKey:@"lastGeneration"],
        @"Old deletion completion does not update the new library");
    [controller stop]; [controller release]; [library release]; [peer release];
    ReplaceClassMethod([NSAlert class], @selector(alloc), originalAllocation);
}

static void ShortIntervalRetryChecks(ManualQueue *worker) {
    for (NSString *failure in @[@"capture", @"publication", @"destination"]) {
        NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
        [[controller valueForKey:@"timer"] invalidate]; [controller setValue:worker forKey:@"worker"];
        FixtureLibrary *library = [[FixtureLibrary alloc] initWithIdentifier:[@"retry-" stringByAppendingString:failure]];
        Attach(controller, library);
        Check([controller setSettings:@{@"interval":@60} error:NULL], @"Accept the supported 60-second interval");
        library->failCapture = [failure isEqual:@"capture"];
        failPublication = [failure isEqual:@"publication"];
        NSMutableDictionary *settings = [controller valueForKey:@"librarySettings"];
        if ([failure isEqual:@"destination"]) [settings setObject:[NSData data] forKey:@"destinationBookmark"];
        NSTimeInterval failedAt = clockTime;
        Tick(controller, failedAt);
        if ([worker pendingCount]) Complete(worker);
        Check([[controller statusText] containsString:@"Error:"], @"Failure produces a status error");
        for (NSNumber *elapsed in @[@30, @60, @90, @299]) {
            Tick(controller, failedAt + [elapsed doubleValue]);
            Check([worker pendingCount] == 0 && [[controller valueForKey:@"nextAttempt"] timeIntervalSinceReferenceDate] == failedAt + 300,
                @"Short interval preserves the full five-minute failure deadline");
        }
        NSTimeInterval movedBack = failedAt - 86400;
        Tick(controller, movedBack);
        Check([[controller valueForKey:@"nextAttempt"] timeIntervalSinceReferenceDate] == movedBack + 300,
            @"An actual backward clock change bounds the failure retry to five minutes");
        Tick(controller, movedBack + 299); Check([worker pendingCount] == 0, @"Backward clock correction preserves the retry delay");
        library->failCapture = NO; failPublication = NO; [settings removeObjectForKey:@"destinationBookmark"];
        Tick(controller, movedBack + 300); Complete(worker);
        Check(![[controller statusText] containsString:@"Error:"], @"Success clears the failure at its retry deadline");
        Tick(controller, movedBack - 3600);
        Check([[controller valueForKey:@"nextAttempt"] timeIntervalSinceReferenceDate] == movedBack - 3540,
            @"A later ordinary check still corrects backward movement to the 60-second interval");
        [controller stop]; [controller release]; [library release];
    }
}

static void RetentionChecks(ManualQueue *worker) {
    maintenanceMetadata = [NSMutableArray new]; maintenancePolicies = [NSMutableArray new];
    NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
    [[controller valueForKey:@"timer"] invalidate]; [controller setValue:worker forKey:@"worker"];
    FixtureLibrary *library = [[FixtureLibrary alloc] initWithIdentifier:@"retention-policy"];
    Attach(controller, library);
    NSUInteger before = publications, beforeMaintenance = maintenanceCalls;
    failPublicationRetention = YES;
    Tick(controller, 40000000); Complete(worker);
    Check([[controller statusText] containsString:@"Injected retention failure"], @"Publication reports its failed retention");
    failPublicationRetention = NO; failMaintenance = YES;
    Tick(controller, 40000300);
    Check([[controller statusText] containsString:@"Injected retention failure"], @"Unresolved retention error remains visible during retry");
    Complete(worker);
    Check(maintenanceCalls == beforeMaintenance + 1 && publications == before + 1 && [[controller statusText] containsString:@"Injected retention failure"],
        @"Unchanged checkpoint retries pruning without another snapshot and retains its error on failure");
    Tick(controller, 40000599); Check([worker pendingCount] == 0, @"Retention failure respects the five-minute retry bound");
    failMaintenance = NO;
    Tick(controller, 40000600); Complete(worker);
    Check(maintenanceCalls == beforeMaintenance + 2 && publications == before + 1 && ![[controller statusText] containsString:@"Injected retention failure"],
        @"Successful cleanup clears the retention error without a duplicate snapshot");
    NSDate *lastDate = [[[controller settings] objectForKey:@"lastDate"] retain];
    NSString *lastSnapshot = [[[controller settings] objectForKey:@"lastSnapshot"] copy];
    NSError *error = nil;
    Check([controller setSettings:@{@"recent":@3, @"daily":@0, @"weekly":@0} error:&error], @"Accept stricter retention");
    Tick(controller, clockTime); Complete(worker);
    Check(maintenanceCalls == beforeMaintenance + 3 && [[[maintenancePolicies lastObject] objectForKey:@"recent"] integerValue] == 3,
        @"Policy changes prune unchanged content using the selected policy");
    Check([[[controller settings] objectForKey:@"lastDate"] isEqual:lastDate] && [[[controller settings] objectForKey:@"lastSnapshot"] isEqual:lastSnapshot],
        @"Maintenance preserves the last successful backup identity and capture date");
    Check([[[maintenanceMetadata lastObject] objectForKey:@"protectedSnapshotIdentifier"] isEqual:[[lastSnapshot lastPathComponent] stringByDeletingPathExtension]],
        @"Maintenance protects the already verified current snapshot");
    Check([controller setSettings:@{@"recent":@3, @"daily":@0, @"weekly":@0} error:&error], @"Accept unchanged retention settings");
    Tick(controller, clockTime); Complete(worker);
    Check(maintenanceCalls == beforeMaintenance + 3, @"Unchanged settings do not repeat a full retention scan");
    Tick(controller, clockTime + 86400); Complete(worker);
    Check(maintenanceCalls == beforeMaintenance + 4 && publications == before + 1, @"A new UTC day applies time-based retention to unchanged content");
    Tick(controller, clockTime + 900); Complete(worker);
    Check(maintenanceCalls == beforeMaintenance + 4, @"Routine unchanged checks do not rescan history within the same day");
    [controller setSettings:@{@"recent":@4} error:&error];
    Tick(controller, clockTime); [worker runNext];
    FixtureLibrary *peer = [[FixtureLibrary alloc] initWithIdentifier:@"retention-peer"];
    Attach(controller, peer); [completionQueue runNext];
    Check(![[controller settings] objectForKey:@"storageBytes"] && [[controller valueForKey:@"retentionPending"] boolValue],
        @"Old maintenance completion cannot clear the replacement library's pending maintenance or write status");
    Check([[[maintenanceMetadata lastObject] objectForKey:@"libraryIdentifier"] isEqual:@"retention-policy"],
        @"Queued maintenance preserves its original library identity");
    Tick(controller, clockTime); Complete(worker);
    Check(![[controller valueForKey:@"retentionPending"] boolValue], @"New library clears pending maintenance only after its own successful publication");
    [controller stop]; [controller release]; [library release]; [peer release]; [lastDate release]; [lastSnapshot release];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc == 2, @"Temporary test root argument supplied");
        testRoot = [[NSString stringWithUTF8String:argv[1]] copy];
        memoryDefaults = [MemoryDefaults new];
        completionQueue = [ManualQueue new];
        publishedMetadata = [NSMutableArray new]; publishedDestinations = [NSMutableArray new]; publishedData = [NSMutableArray new];
        expectedArchiveData = [NSMutableDictionary new]; verificationURLs = [NSMutableArray new];
        ReplaceClassMethod([NSUserDefaults class], @selector(standardUserDefaults), (IMP)MemoryStandardDefaults);
        ReplaceClassMethod([NSDate class], @selector(date), (IMP)ClockDate);
        ReplaceClassMethod([NSDate class], @selector(dateWithTimeIntervalSinceNow:), (IMP)ClockRelativeDate);
        ReplaceClassMethod([NSOperationQueue class], @selector(mainQueue), (IMP)ManualMainQueue);
        NVBackupController *controller = [[NVBackupController alloc] initWithApplicationController:nil];
        [[controller valueForKey:@"timer"] invalidate];
        ManualQueue *worker = [ManualQueue new];
        [controller setValue:worker forKey:@"worker"];
        FixtureLibrary *first = [[FixtureLibrary alloc] initWithIdentifier:@"library-A"];
        FixtureLibrary *second = [[FixtureLibrary alloc] initWithIdentifier:@"library-B"];
        Attach(controller, first);

        Tick(controller, 1000000);
        Check([controller isBusy] && first->captures == 1, @"First successful library opening starts one backup");
        Tick(controller, 1000001);
        Check(first->captures == 1 && [worker pendingCount] == 1, @"Busy timer ticks do not duplicate capture");
        first->generation = 2;
        Complete(worker);
        Check([[[controller settings] objectForKey:@"lastGeneration"] integerValue] == 1, @"Publication records the captured generation");
        Check([[[[NSString alloc] initWithData:[publishedData lastObject] encoding:NSUTF8StringEncoding] autorelease] isEqualToString:@"generation-1"], @"Worker receives original checkpoint bytes");
        Tick(controller, 1000899);
        Check([worker pendingCount] == 0, @"Edit during work remains pending until interval");
        Tick(controller, 1000900); Complete(worker);
        Check([[[controller settings] objectForKey:@"lastGeneration"] integerValue] == 2, @"Later backup captures the pending edit");
        NSDate *priorBackupDate = [[[controller settings] objectForKey:@"lastDate"] retain];
        first->sourceWarning = YES;
        Tick(controller, 1001800);
        Check([controller isBusy] && [verificationURLs count] == 0, @"Unchanged snapshot verification is queued on the worker");
        Complete(worker);
        Check(publications == 2 && [worker pendingCount] == 0, @"Unchanged existing snapshot does not publish another copy");
        Check([[[controller settings] objectForKey:@"lastDate"] isEqual:priorBackupDate], @"Verified unchanged backup does not advance its capture date");
        Check([[controller statusText] rangeOfString:@"Source file write is pending"].location != NSNotFound, @"Verified unchanged backup preserves the primary write warning");
        [priorBackupDate release]; first->sourceWarning = NO;
        NSUInteger manualWrites = publications, manualReads = [verificationURLs count];
        [controller backupNow:nil]; Complete(worker);
        Check(publications == manualWrites + 1 && [verificationURLs count] == manualReads, @"Manual backup publishes unchanged content without a verification-only shortcut");

        for (NSUInteger damage = 0; damage < 3; damage++) {
            NSString *lastPath = [[controller settings] objectForKey:@"lastSnapshot"];
            NSURL *archive = [[NSURL fileURLWithPath:lastPath isDirectory:YES] URLByAppendingPathComponent:@"archive.bin"];
            if (damage == 0) [@"corrupt archive" writeToURL:archive atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            else if (damage == 1) [[NSFileManager defaultManager] removeItemAtURL:archive error:NULL];
            else {
                NSData *foreignData = [@"different valid archive" dataUsingEncoding:NSUTF8StringEncoding];
                [foreignData writeToURL:archive atomically:YES];
                [expectedArchiveData setObject:foreignData forKey:lastPath];
            }
            NSUInteger before = publications;
            Tick(controller, 1002700 + damage * 900); Complete(worker);
            Check(publications == before + 1 && [[[controller settings] objectForKey:@"lastGeneration"] integerValue] == 2,
                @"Corrupt, missing, or different verified archive is replaced even without a generation change");
            Check([[NSFileManager defaultManager] fileExistsAtPath:lastPath], @"The damaged snapshot directory remained present during repair");
        }
        NSString *foreignPath = [[[[testRoot stringByAppendingPathComponent:@"foreign"] stringByAppendingPathComponent:@"library-A"]
            stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingPathExtension:@"nvbackup"];
        [[NSFileManager defaultManager] createDirectoryAtPath:foreignPath withIntermediateDirectories:YES attributes:nil error:NULL];
        [[controller valueForKey:@"librarySettings"] setObject:foreignPath forKey:@"lastSnapshot"];
        NSUInteger readsBeforeForeignPath = [verificationURLs count], writesBeforeForeignPath = publications;
        Tick(controller, 1005400); Complete(worker);
        Check([verificationURLs count] == readsBeforeForeignPath && publications == writesBeforeForeignPath + 1,
            @"A snapshot outside the selected destination is never opened for verification");
        Check([[publishedMetadata objectAtIndex:0] objectForKey:@"existingRoot"] == nil, @"Default destination does not claim an externally selected root");

        NSUInteger writesBeforeStaleVerification = publications;
        Tick(controller, 1006300);
        [worker runNext];
        Check([completionQueue pendingCount] == 1 && [controller isBusy], @"Verified result waits for its main-thread completion");
        FixtureLibrary *verificationPeer = [[FixtureLibrary alloc] initWithIdentifier:@"verification-peer"];
        Attach(controller, verificationPeer);
        [completionQueue runNext];
        Check(![[controller settings] objectForKey:@"lastGeneration"] && publications == writesBeforeStaleVerification,
            @"A verified result from the previous library cannot advance the replacement library");
        Attach(controller, first);

        Tick(controller, 900000);
        NSDate *next = [controller valueForKey:@"nextAttempt"];
        Check([next timeIntervalSinceReferenceDate] == 900900, @"Backward clock movement bounds the next wait to one interval");
        first->generation = 3;
        Tick(controller, 900900); Complete(worker);
        clockTime = 2000000;
        first->generation = 4;
        [controller woke:nil]; [controller woke:nil];
        Check([worker pendingCount] == 1, @"Forward clock or wake catches up with one backup");
        Complete(worker);
        Tick(controller, 2000001);
        Check([worker pendingCount] == 0, @"Missed intervals do not create repeated snapshots");

        first->generation = 5;
        failPublication = YES;
        Tick(controller, 2000900); Complete(worker);
        Check([[[controller settings] objectForKey:@"lastGeneration"] integerValue] == 4, @"Failed publication preserves last successful generation");
        Check([[controller statusText] rangeOfString:@"Injected publication failure"].location != NSNotFound, @"Failure status remains visible");
        Tick(controller, 2001199);
        Check([worker pendingCount] == 0, @"Failed publication does not retry before bounded delay");
        failPublication = NO;
        Tick(controller, 2001200); Complete(worker);
        Check([[[controller settings] objectForKey:@"lastGeneration"] integerValue] == 5, @"Bounded retry advances success only after publication");

        first->generation = 6;
        Tick(controller, 2002100);
        Attach(controller, second);
        Tick(controller, 2002100);
        Check([worker pendingCount] == 1 && second->captures == 0, @"Library switch waits for existing worker");
        Complete(worker);
        Check([[controller libraryIdentifier] isEqualToString:@"library-B"] && ![[controller settings] objectForKey:@"lastGeneration"], @"Old completion cannot advance new library status");
        Check([[[publishedMetadata lastObject] objectForKey:@"libraryIdentifier"] isEqualToString:@"library-A"], @"Old job retains original library identity");
        Check([[[publishedDestinations lastObject] lastPathComponent] isEqualToString:@"library-A"], @"Old job retains original destination");
        Tick(controller, 2002100); Complete(worker);
        Check([[[controller settings] objectForKey:@"lastGeneration"] integerValue] == 1, @"New library has an independent first backup");

        second->generation = 2;
        Tick(controller, 2003000);
        [controller stop];
        Complete(worker);
        Check([[[controller settings] objectForKey:@"lastGeneration"] integerValue] == 1, @"Stopped coordinator rejects worker completion");
        Tick(controller, 9000000);
        Check([worker pendingCount] == 0, @"Stopped coordinator schedules no work");
        [controller release];

        NVBackupController *restarted = [[NVBackupController alloc] initWithApplicationController:nil];
        [[restarted valueForKey:@"timer"] invalidate];
        [restarted setValue:worker forKey:@"worker"];
        Attach(restarted, second);
        Check([[[restarted settings] objectForKey:@"lastGeneration"] integerValue] == 1, @"Restart retains only the last accepted publication");
        Tick(restarted, 9000000); Complete(worker);
        Check([[[restarted settings] objectForKey:@"lastGeneration"] integerValue] == 2, @"Restart retries the interrupted generation");
        NSError *settingsError = nil;
        Check(![restarted setSettings:@{@"recent":@2} error:&settingsError] && settingsError != nil, @"Coordinator enforces retention minimum");
        Check([restarted setSettings:@{@"enabled":@NO} error:&settingsError], @"Automatic backups can be disabled");
        second->generation = 3;
        Tick(restarted, 9010000);
        Check([worker pendingCount] == 0, @"Disabled scheduling ignores overdue changes");
        [restarted backupNow:nil]; Complete(worker);
        Check([[[restarted settings] objectForKey:@"lastGeneration"] integerValue] == 3, @"Manual backup remains available while automatic backups are off");
        Check([restarted setSettings:@{@"enabled":@YES} error:&settingsError], @"Automatic backups can be reenabled");
        second->generation = 4; second->failCapture = YES;
        Tick(restarted, 9010000);
        Check(![restarted isBusy] && [worker pendingCount] == 0, @"Capture failure starts no worker");
        Check([[[restarted settings] objectForKey:@"lastGeneration"] integerValue] == 3 && [[restarted statusText] rangeOfString:@"Injected capture failure"].location != NSNotFound, @"Capture failure preserves success and reports its error");
        second->failCapture = NO;
        Tick(restarted, 9010299);
        Check([worker pendingCount] == 0, @"Capture failure uses a bounded retry delay");
        Tick(restarted, 9010300); Complete(worker);
        Check([[[restarted settings] objectForKey:@"lastGeneration"] integerValue] == 4, @"Capture retries after five minutes");

        NSURL *moved = [NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:@"library-B-moved"]];
        Check([[NSFileManager defaultManager] moveItemAtURL:[second notesDirectoryURL] toURL:moved error:NULL], @"Move fixture library");
        [second setValue:moved forKey:@"fixtureDirectory"];
        Attach(restarted, second);
        Check([[restarted libraryIdentifier] isEqualToString:@"library-B"], @"Moved library retains backup identity");
        FixtureLibrary *copied = [[FixtureLibrary alloc] initWithIdentifier:@"library-B"];
        Attach(restarted, copied);
        Check(![[restarted libraryIdentifier] isEqualToString:@"library-B"] && ![[restarted settings] objectForKey:@"lastGeneration"], @"Independent copied library receives a separate backup identity");
        [restarted stop]; [restarted release];

        NVBackupController *validation = [[NVBackupController alloc] initWithApplicationController:nil];
        [[validation valueForKey:@"timer"] invalidate];
        [validation setValue:worker forKey:@"worker"];
        FixtureLibrary *corrupt = [[FixtureLibrary alloc] initWithIdentifier:@"library-corrupt"];
        NSDictionary *invalidSettings = @{@"enabled":@"no", @"interval":@0, @"recent":@-1, @"daily":@3651,
            @"weekly":@0.5, @"maxBytes":@(NAN), @"lastDate":@"bad date", @"lastGeneration":@"1",
            @"lastSnapshot":@42, @"storageBytes":@-1, @"destinationBookmark":@"not bookmark data", @"unknown":@"ignored"};
        [memoryDefaults setObject:@{@"library-corrupt":invalidSettings} forKey:@"NVLibraryBackups"];
        [memoryDefaults setObject:@{@"library-corrupt":@[@"invalid claim"]} forKey:@"NVBackupLibraryLocations"];
        Attach(validation, corrupt);
        NSDictionary *sanitized = [validation settings];
        Check([[sanitized objectForKey:@"enabled"] boolValue] && [[sanitized objectForKey:@"interval"] integerValue] == 900 &&
            [[sanitized objectForKey:@"recent"] integerValue] == 96 && [[sanitized objectForKey:@"daily"] integerValue] == 30 &&
            [[sanitized objectForKey:@"weekly"] integerValue] == 12 && [[sanitized objectForKey:@"maxBytes"] unsignedLongLongValue] == 2147483648ULL,
            @"Malformed public settings use valid defaults");
        for (NSString *key in @[@"lastDate", @"lastGeneration", @"lastSnapshot", @"storageBytes", @"unknown"])
            Check([sanitized objectForKey:key] == nil, @"Malformed or unknown saved status is discarded");
        Check([[sanitized objectForKey:@"destinationBookmark"] isKindOfClass:[NSData class]], @"Invalid selected bookmark remains an explicit invalid selection");
        Check([validation destinationURL] == nil && [[validation statusText] rangeOfString:@"Error:"].location != NSNotFound,
            @"Invalid selected bookmark reports an error instead of falling back");
        NSUInteger beforeInvalidDestination = publications;
        Tick(validation, clockTime);
        Check(corrupt->captures == 0 && [worker pendingCount] == 0 && publications == beforeInvalidDestination,
            @"Invalid destination cannot write into the default backup folder");

        NSArray *badClaims = @[@[@"not a dictionary"], @{@"library-corrupt":@42},
            @{@"library-corrupt":@{@"identity":@42, @"path":@42}},
            @{@"library-corrupt":@{@"identity":@"1:2", @"path":@[@"wrong type"]}}];
        for (id claims in badClaims) {
            [memoryDefaults setObject:claims forKey:@"NVBackupLibraryLocations"];
            [memoryDefaults setObject:@{@"library-corrupt":@[@"not settings"]} forKey:@"NVLibraryBackups"];
            Attach(validation, corrupt);
            Check([[validation libraryIdentifier] isEqualToString:@"library-corrupt"] && [[[validation settings] objectForKey:@"interval"] integerValue] == 900,
                @"Malformed library claims and settings entries do not crash or rename the live library");
        }
        NSArray *invalidIntervals = @[@(NAN), @(INFINITY), @(-INFINITY), @59, @86401, @60.5, @"900", @[]];
        for (id interval in invalidIntervals) {
            [memoryDefaults setObject:@{@"library-corrupt":@{@"interval":interval}} forKey:@"NVLibraryBackups"];
            Attach(validation, corrupt);
            Check([[[validation settings] objectForKey:@"interval"] integerValue] == 900, @"Invalid persisted intervals cannot stop the schedule");
        }
        for (id date in @[@42, [NSDate dateWithTimeIntervalSinceReferenceDate:NAN], [NSDate dateWithTimeIntervalSinceReferenceDate:1e300]]) {
            [memoryDefaults setObject:@{@"library-corrupt":@{@"lastDate":date}} forKey:@"NVLibraryBackups"];
            Attach(validation, corrupt);
            Check([[validation settings] objectForKey:@"lastDate"] == nil && isfinite([[validation valueForKey:@"nextAttempt"] timeIntervalSinceReferenceDate]),
                @"Malformed dates cannot poison date formatting or scheduling");
        }
        for (id bookmark in @[[NSData data], [@"broken bookmark" dataUsingEncoding:NSUTF8StringEncoding]]) {
            [memoryDefaults setObject:@{@"library-corrupt":@{@"destinationBookmark":bookmark}} forKey:@"NVLibraryBackups"];
            Attach(validation, corrupt);
            Check([validation destinationURL] == nil && [[validation statusText] rangeOfString:@"Error:"].location != NSNotFound,
                @"Malformed bookmark bytes preserve the selected-destination failure");
        }
        NSString *snapshotName = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"nvbackup"];
        NSArray *invalidSnapshotPaths = @[@"", @"/", @"relative.nvbackup", [testRoot stringByAppendingPathComponent:@"not-a-uuid.nvbackup"],
            [[testRoot stringByAppendingPathComponent:@"library-other"] stringByAppendingPathComponent:snapshotName],
            [[testRoot stringByAppendingPathComponent:@"library-corrupt"] stringByAppendingPathComponent:[snapshotName stringByAppendingString:@".txt"]]];
        for (NSString *path in invalidSnapshotPaths) {
            [memoryDefaults setObject:@{@"library-corrupt":@{@"lastGeneration":@(corrupt->generation), @"lastSnapshot":path}} forKey:@"NVLibraryBackups"];
            Attach(validation, corrupt);
            Check([[validation settings] objectForKey:@"lastSnapshot"] == nil, @"Malformed or foreign-library snapshot paths are discarded");
            NSUInteger before = publications;
            Tick(validation, clockTime); Complete(worker);
            Check(publications == before + 1, @"An invalid saved path with the current generation cannot suppress a needed backup");
        }
        NSURL *customRoot = [NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:@"custom-backups"]];
        Check([[NSFileManager defaultManager] createDirectoryAtURL:customRoot withIntermediateDirectories:YES attributes:nil error:NULL], @"Create selected destination fixture");
        NSData *bookmark = [customRoot bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
        Check(bookmark != nil, @"Create a valid persisted bookmark");
        NSDictionary *validSettings = @{@"enabled":@NO, @"interval":@86400, @"recent":@10000, @"daily":@3650,
            @"weekly":@520, @"maxBytes":@1099511627776ULL, @"lastDate":[NSDate date], @"lastGeneration":@18446744073709551615ULL,
            @"lastSnapshot":[[[customRoot path] stringByAppendingPathComponent:@"library-corrupt"] stringByAppendingPathComponent:snapshotName], @"storageBytes":@9223372036854775807ULL,
            @"destinationBookmark":bookmark};
        [memoryDefaults setObject:@{@"library-corrupt":validSettings} forKey:@"NVLibraryBackups"];
        Attach(validation, corrupt);
        Check([[validation settings] isEqualToDictionary:validSettings], @"Valid persisted bounds, 64-bit generations, status, and bookmark survive sanitization");
        Check([[[[validation destinationURL] URLByDeletingLastPathComponent] URLByResolvingSymlinksInPath] isEqual:[customRoot URLByResolvingSymlinksInPath]],
            @"Valid custom destination remains selected");
        [validation backupNow:nil]; Complete(worker);
        Check([[[[publishedMetadata lastObject] objectForKey:@"existingRoot"] URLByResolvingSymlinksInPath] isEqual:[customRoot URLByResolvingSymlinksInPath]],
            @"Publication pins the already selected external root in worker metadata");
        struct stat customRootInfo;
        Check(stat([[customRoot path] fileSystemRepresentation], &customRootInfo) == 0, @"Read fixture custom-root identity");
        NSString *rootIdentity = [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)customRootInfo.st_dev, (unsigned long long)customRootInfo.st_ino];
        Check([[[publishedMetadata lastObject] objectForKey:@"existingRootIdentity"] isEqual:rootIdentity],
            @"Publication captures custom-root device and inode before queueing");
        [validation setSettings:@{@"enabled":@YES, @"recent":@9999} error:NULL];
        NSUInteger beforeCustomMaintenance = maintenanceCalls;
        maintenanceMetadata = [NSMutableArray new]; maintenancePolicies = [NSMutableArray new];
        Tick(validation, clockTime); Complete(worker);
        Check(maintenanceCalls == beforeCustomMaintenance + 1 && [[[maintenanceMetadata lastObject] objectForKey:@"existingRootIdentity"] isEqual:rootIdentity],
            @"Unchanged maintenance carries the captured custom-root device and inode");
        [validation stop]; [validation release];
        RetentionChecks(worker);
        DeletionChecks(worker);
        ShortIntervalRetryChecks(worker);
        NSLog(@"PASS: production scheduling, integrity verification, changes, pending edits, clocks, wake, retry, switch, stop, restart, disablement, manual backup, capture failure, moved/copied libraries, corrupt persisted settings, deletion identity, and short-interval failure deadlines");
    }
    return 0;
}
