#define main ExistingCoordinatorSuiteMain
#include "../../../BackupCoordinator/coordinator.m"
#undef main
#import "NVApplicationController.h"

// Execute the complete production backup coordinator. File panels, archive decode,
// and the final application restore boundary are deterministic recording fakes.
static NSMutableArray *panels;
static NSUInteger panelsOpened, decodes, restores, assertions;
static NSInteger decodeResult;
static BOOL restoreSucceeds = YES;
static void (^decodeHook)(void);
static NSURL *restoredDirectory;
static NSDictionary *restoredPayload;

static void Assert(BOOL value, NSString *message) {
    assertions++;
    Check(value, message);
}

@interface ScriptedPanel : NSObject {
    NSInteger response;
    NSURL *selection;
    void (^modalHook)(void);
}
- (id)initWithResponse:(NSInteger)value URL:(NSURL *)url hook:(void (^)(void))hook;
- (NSInteger)runModal;
- (NSURL *)URL;
@end
@implementation ScriptedPanel
- (id)initWithResponse:(NSInteger)value URL:(NSURL *)url hook:(void (^)(void))hook {
    if ((self = [super init])) { response = value; selection = [url retain]; modalHook = [hook copy]; }
    return self;
}
- (NSInteger)runModal { if (modalHook) modalHook(); return response; }
- (NSURL *)URL { return selection; }
- (void)setCanChooseFiles:(BOOL)value {}
- (void)setCanChooseDirectories:(BOOL)value {}
- (void)setCanCreateDirectories:(BOOL)value {}
- (void)setTreatsFilePackagesAsDirectories:(BOOL)value {}
- (void)setAllowedFileTypes:(NSArray *)value {}
- (void)setPrompt:(NSString *)value {}
- (void)setDirectoryURL:(NSURL *)value {}
- (void)setMessage:(NSString *)value {}
- (void)dealloc { [selection release]; [modalHook release]; [super dealloc]; }
@end

static void EnqueuePanel(NSInteger response, NSURL *url, void (^hook)(void)) {
    [panels addObject:[[[ScriptedPanel alloc] initWithResponse:response URL:url hook:hook] autorelease]];
}
static id OpenScriptedPanel(id self, SEL command) {
    Assert([panels count] > 0, @"Only an explicitly scripted panel is opened");
    id panel = [[[panels objectAtIndex:0] retain] autorelease];
    [panels removeObjectAtIndex:0];
    panelsOpened++;
    return panel;
}
static id DecodeScriptedArchive(id self, SEL command, NSData *data, NSError **error) {
    decodes++;
    if (decodeHook) decodeHook();
    if (decodeResult) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:decodeResult userInfo:@{
            NSLocalizedDescriptionKey:@"Original library decode failure"}];
        return nil;
    }
    return @{@"data":data, @"noteCount":@2, @"captureDate":[NSDate date], @"libraryIdentifier":@"restored-library"};
}
@implementation NVApplicationController
- (BOOL)restoreBackupArchive:(NSDictionary *)archive toDirectory:(NSURL *)directory error:(NSError **)error {
    restores++;
    [restoredDirectory release]; restoredDirectory = [directory copy];
    [restoredPayload release]; restoredPayload = [archive copy];
    if (!restoreSucceeds && error) *error = [NSError errorWithDomain:@"RestoreFixture" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"Destination rejected by application"}];
    return restoreSucceeds;
}
@end

static NVBackupController *NewController(ManualQueue *worker, FixtureLibrary *library) {
    NVApplicationController *application = [[[NVApplicationController alloc] init] autorelease];
    NVBackupController *controller = [[[NVBackupController alloc] initWithApplicationController:application] autorelease];
    [[controller valueForKey:@"timer"] invalidate];
    [controller setValue:worker forKey:@"worker"];
    Attach(controller, library);
    Assert([controller setSettings:@{@"enabled":@NO} error:NULL], @"Disable automatic schedule");
    return controller;
}

static void RestoreChecks(ManualQueue *worker, NSURL *snapshot, NSURL *target, BOOL expectContextIsolation) {
    FixtureLibrary *first = [[[FixtureLibrary alloc] initWithIdentifier:@"flow-A"] autorelease];
    FixtureLibrary *second = [[[FixtureLibrary alloc] initWithIdentifier:@"flow-B"] autorelease];
    NVBackupController *controller = NewController(worker, first);
    NSDictionary *initialSettings = [[[controller settings] copy] autorelease];

    EnqueuePanel(NSModalResponseCancel, snapshot, nil);
    [controller restoreBackup:nil];
    Assert(![controller isBusy] && ![worker pendingCount] && !decodes && !restores,
        @"Snapshot picker cancellation queues nothing and does not decode or replace a library");
    Assert([[controller settings] isEqual:initialSettings], @"Picker cancellation leaves all settings unchanged");

    decodeResult = NSUserCancelledError;
    EnqueuePanel(NSModalResponseOK, snapshot, nil);
    [controller restoreBackup:nil];
    Assert([controller isBusy], @"Accepted snapshot enters busy state before verification");
    [controller backupNow:nil];
    Assert([worker pendingCount] == 1 && !first->captures,
        @"A manual backup requested during restore cannot capture or queue competing work");
    Complete(worker);
    Assert(![controller isBusy] && !restores && ![[controller statusText] containsString:@"Error:"],
        @"Password cancellation clears busy without an error or application restore call");
    Assert([[controller settings] isEqual:initialSettings], @"Password cancellation leaves scheduling and retention unchanged");

    decodeResult = 0;
    EnqueuePanel(NSModalResponseOK, snapshot, nil);
    EnqueuePanel(NSModalResponseCancel, target, ^{ Assert([controller isBusy], @"Destination dialog retains busy state"); });
    [controller restoreBackup:nil]; Complete(worker);
    Assert(![controller isBusy] && !restores && [[controller settings] isEqual:initialSettings],
        @"Destination cancellation leaves the active library and settings unchanged");

    restoreSucceeds = NO;
    EnqueuePanel(NSModalResponseOK, snapshot, nil); EnqueuePanel(NSModalResponseOK, target, nil);
    [controller restoreBackup:nil]; Complete(worker);
    Assert(restores == 1 && ![controller isBusy] && [[controller statusText] containsString:@"Destination rejected by application"],
        @"Final application rejection clears busy and reports its error");
    Assert([restoredDirectory isEqual:[target URLByResolvingSymlinksInPath]] && [[restoredPayload objectForKey:@"noteCount"] integerValue] == 2,
        @"Confirmed restore forwards the decoded payload and canonical selected destination");
    Assert([[controller libraryIdentifier] isEqual:@"flow-A"], @"Application rejection does not replace the coordinator's library");
    restoreSucceeds = YES;

    NSUInteger priorDecodes = decodes, priorRestores = restores;
    EnqueuePanel(NSModalResponseOK, snapshot, ^{ Attach(controller, second); });
    [controller restoreBackup:nil];
    Assert(![worker pendingCount] && decodes == priorDecodes && restores == priorRestores,
        @"Library change during snapshot selection rejects the old selection");

    Attach(controller, first);
    EnqueuePanel(NSModalResponseOK, snapshot, nil);
    [controller restoreBackup:nil];
    Attach(controller, second);
    Complete(worker);
    Assert(![controller isBusy] && decodes == priorDecodes && restores == priorRestores,
        @"Library change while archive read is queued rejects the old completion before decode");

    Attach(controller, first);
    EnqueuePanel(NSModalResponseOK, snapshot, nil);
    EnqueuePanel(NSModalResponseOK, target, ^{ Attach(controller, second); });
    [controller restoreBackup:nil]; Complete(worker);
    Assert(![controller isBusy] && restores == priorRestores && [[controller libraryIdentifier] isEqual:@"flow-B"],
        @"Library change during destination selection rejects the old confirmation");

    // A scripted decoder hook represents a nested password modal allowing a
    // library-context callback. No full application's ability to cause that callback
    // from an ordinary menu action is asserted by this component check.
    for (NSNumber *result in @[@0, @123]) {
        Attach(controller, first);
        [memoryDefaults setObject:@{@"flow-B":@{@"destinationBookmark":[NSData data], @"enabled":@NO}}
            forKey:@"NVLibraryBackups"];
        decodeResult = [result integerValue];
        decodeHook = ^{
            Attach(controller, second);
            Assert([[controller statusText] containsString:@"selected backup folder is unavailable"],
                @"New library has its own unavailable-destination error before stale decode returns");
        };
        NSUInteger beforePanels = panelsOpened;
        EnqueuePanel(NSModalResponseOK, snapshot, nil);
        [controller restoreBackup:nil]; Complete(worker);
        decodeHook = nil;
        Assert(![controller isBusy] && restores == priorRestores && panelsOpened == beforePanels + 1,
            @"Context change during decode opens no destination panel and performs no restore");
        BOOL preservesNewError = [[controller statusText] containsString:@"selected backup folder is unavailable"];
        if (expectContextIsolation) Assert(preservesNewError, @"Stale decode cannot replace the current library's error");
        else Assert(!preservesNewError, @"REPRODUCED: stale decode replaces the current library's unavailable-destination error");
        NSLog(@"CONTEXT RESULT: decode=%@, current status=%@", result, [[controller statusText] stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);
    }
    decodeResult = 0;
    [controller stop];
}

static void DisabledManualChecks(ManualQueue *worker) {
    FixtureLibrary *library = [[[FixtureLibrary alloc] initWithIdentifier:@"manual-off"] autorelease];
    NVBackupController *controller = NewController(worker, library);
    Assert([controller setSettings:@{@"recent":@3, @"daily":@0, @"weekly":@0} error:NULL], @"Manual-only library accepts retention changes");
    Tick(controller, clockTime + 86400);
    Assert(![worker pendingCount] && !library->captures, @"Disabled schedule remains idle after retention changes and overdue interval");
    NSUInteger priorWrites = publications;
    [controller backupNow:nil]; Complete(worker);
    [controller backupNow:nil]; Complete(worker);
    Assert(publications == priorWrites + 2, @"Each explicit manual request publishes even unchanged content while scheduling is disabled");
    Assert(![[[controller settings] objectForKey:@"enabled"] boolValue] && [[controller statusText] containsString:@"Automatic backups are off."],
        @"Manual success does not reenable scheduling and status continues to show off");
    Tick(controller, clockTime + 86400);
    Assert(![worker pendingCount] && publications == priorWrites + 2, @"Manual success cannot schedule a hidden automatic follow-up");
    [controller stop];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc >= 2, @"Temporary fixture root supplied");
        BOOL expectContextIsolation = !(argc == 3 && strcmp(argv[2], "--expect-baseline-context") == 0);
        testRoot = [[NSString stringWithUTF8String:argv[1]] copy];
        memoryDefaults = [MemoryDefaults new]; completionQueue = [ManualQueue new];
        publishedMetadata = [NSMutableArray new]; publishedDestinations = [NSMutableArray new]; publishedData = [NSMutableArray new];
        expectedArchiveData = [NSMutableDictionary new]; verificationURLs = [NSMutableArray new]; panels = [NSMutableArray new];
        ReplaceClassMethod([NSUserDefaults class], @selector(standardUserDefaults), (IMP)MemoryStandardDefaults);
        ReplaceClassMethod([NSDate class], @selector(date), (IMP)ClockDate);
        ReplaceClassMethod([NSDate class], @selector(dateWithTimeIntervalSinceNow:), (IMP)ClockRelativeDate);
        ReplaceClassMethod([NSOperationQueue class], @selector(mainQueue), (IMP)ManualMainQueue);
        ReplaceClassMethod([NSOpenPanel class], @selector(openPanel), (IMP)OpenScriptedPanel);
        ReplaceClassMethod([NVBackupArchive class], @selector(restoredArchiveFromData:error:), (IMP)DecodeScriptedArchive);
        ManualQueue *worker = [ManualQueue new];
        NSURL *snapshot = [NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:@"sample.nvbackup"]];
        [[NSFileManager defaultManager] createDirectoryAtURL:snapshot withIntermediateDirectories:YES attributes:nil error:NULL];
        NSData *data = [@"verified fixture archive" dataUsingEncoding:NSUTF8StringEncoding];
        [data writeToURL:[snapshot URLByAppendingPathComponent:@"archive.bin"] atomically:YES];
        [expectedArchiveData setObject:data forKey:[snapshot path]];
        NSURL *target = [NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:@"restored-target"]];
        DisabledManualChecks(worker);
        RestoreChecks(worker, snapshot, target, expectContextIsolation);
        Assert(![panels count] && ![worker pendingCount] && ![completionQueue pendingCount], @"All scripted panels and asynchronous work are consumed");
        NSLog(@"PASS: %lu new workflow assertions", (unsigned long)assertions);
    }
    return 0;
}
