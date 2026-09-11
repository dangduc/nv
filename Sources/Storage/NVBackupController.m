#import "NVAppIdentity.h"
#import "NVBackupController.h"
#import "NVBackupStore.h"
#import "NVBackupArchive.h"
#import "NVApplicationController.h"
#import "NotationController.h"
#import "NotationPrefs.h"
#import "NSFileManager+DirectoryLocations.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>

NSString * const NVBackupStatusDidChangeNotification = @"NVBackupStatusDidChangeNotification";
static NSString * const SettingsKey = @"NVLibraryBackups";
static NSString * const ClaimsKey = @"NVBackupLibraryLocations";

static NSError *BackupError(NSString *message) {
    return [NSError errorWithDomain:@"NVBackupController" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL ContainsPath(NSString *parent, NSString *child) {
    return parent && child && ([parent isEqual:@"/"] || [parent isEqual:child] || [child hasPrefix:[parent stringByAppendingString:@"/"]]);
}
static NSURL *CanonicalURL(NSURL *url) {
    return [[url URLByStandardizingPath] URLByResolvingSymlinksInPath];
}
static NSString *DateLabel(NSDate *date) {
    return date ? [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : NSLocalizedString(@"Never", nil);
}
static BOOL ValidBackupInteger(id value, unsigned long long minimum, unsigned long long maximum) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    double number = [value doubleValue];
    return isfinite(number) && floor(number) == number &&
        [value compare:@(minimum)] != NSOrderedAscending && [value compare:@(maximum)] != NSOrderedDescending;
}
static BOOL ValidBackupPath(id value) {
    return [value isKindOfClass:[NSString class]] && [value hasPrefix:@"/"] &&
        [value rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location == NSNotFound;
}
static NSDictionary *ValidatedSavedBackupSettings(id saved, NSString *identifier) {
    if (![saved isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *valid = [NSMutableDictionary dictionary];
    NSDictionary *bounds = @{@"enabled":@[@0,@1], @"interval":@[@60,@86400], @"recent":@[@3,@10000],
        @"daily":@[@0,@3650], @"weekly":@[@0,@520], @"maxBytes":@[@1048576,@1099511627776ULL],
        @"lastGeneration":@[@0,@18446744073709551615ULL], @"storageBytes":@[@0,@9223372036854775807ULL]};
    for (NSString *key in bounds) {
        id value = [saved objectForKey:key];
        NSArray *range = [bounds objectForKey:key];
        if (ValidBackupInteger(value, [[range objectAtIndex:0] unsignedLongLongValue], [[range objectAtIndex:1] unsignedLongLongValue]))
            [valid setObject:@([value unsignedLongLongValue]) forKey:key];
    }
    id date = [saved objectForKey:@"lastDate"];
    if ([date isKindOfClass:[NSDate class]]) {
        NSTimeInterval time = [date timeIntervalSinceReferenceDate];
        if (isfinite(time) && time >= [[NSDate distantPast] timeIntervalSinceReferenceDate] && time <= [[NSDate distantFuture] timeIntervalSinceReferenceDate])
            [valid setObject:[[date copy] autorelease] forKey:@"lastDate"];
    }
    id path = [saved objectForKey:@"lastSnapshot"];
    if (ValidBackupPath(path) && [[path pathExtension] isEqualToString:@"nvbackup"] &&
        [[[path stringByDeletingLastPathComponent] lastPathComponent] isEqualToString:identifier]) {
        NSUUID *snapshotIdentifier = [[[NSUUID alloc] initWithUUIDString:[[path lastPathComponent] stringByDeletingPathExtension]] autorelease];
        if (snapshotIdentifier) [valid setObject:[[path copy] autorelease] forKey:@"lastSnapshot"];
    }
    id bookmark = [saved objectForKey:@"destinationBookmark"];
    if (bookmark) {
        // Keep an invalid selection explicit. Dropping it would silently redirect backups to the default folder.
        [valid setObject:([bookmark isKindOfClass:[NSData class]] ? [[bookmark copy] autorelease] : [NSData data]) forKey:@"destinationBookmark"];
    }
    return valid;
}

@implementation NVBackupController
- (id)initWithApplicationController:(NVApplicationController *)controller {
    if ((self = [super init])) {
        applicationController = controller;
        worker = [[NSOperationQueue alloc] init];
        [worker setMaxConcurrentOperationCount:1];
        [worker setQualityOfService:NSQualityOfServiceUtility];
        timer = [[NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(tick:) userInfo:nil repeats:YES] retain];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
    }
    return self;
}
- (void)changed { [[NSNotificationCenter defaultCenter] postNotificationName:NVBackupStatusDidChangeNotification object:self]; }
- (void)scheduleNextAttemptAfterDelay:(NSTimeInterval)delay fromDate:(NSDate *)date {
    nextAttemptDelay = delay;
    [nextAttempt release]; nextAttempt = [[date dateByAddingTimeInterval:delay] retain];
}
- (void)saveSettings {
    if (!libraryIdentifier) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all = [[[defaults dictionaryForKey:SettingsKey] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
    [all setObject:librarySettings forKey:libraryIdentifier];
    [defaults setObject:all forKey:SettingsKey];
}
- (void)setError:(NSError *)error {
    [latestError release]; latestError = [[error localizedDescription] copy];
    [self changed];
}
- (void)setLibrary:(NotationController *)newLibrary {
    contextGeneration++;
    retentionPending = YES;
    [library release]; library = [newLibrary retain];
    [libraryIdentifier release]; libraryIdentifier = nil;
    [librarySettings release]; librarySettings = nil;
    [nextAttempt release]; nextAttempt = nil;
    [latestError release]; latestError = nil;
    [latestNotice release]; latestNotice = nil;
    // A running worker retains its original bytes and destination. Its result is ignored after this boundary.
    if (!library) { [self changed]; return; }
    NotationPrefs *prefs = [library notationPrefs];
    NSString *identifier = [prefs backupLibraryIdentifier];
    struct stat info;
    NSURL *location = CanonicalURL([library notesDirectoryURL]);
    NSString *fileIdentity = stat([[location path] fileSystemRepresentation], &info) == 0 ?
        [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev, (unsigned long long)info.st_ino] : nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *savedClaims = [defaults dictionaryForKey:ClaimsKey];
    NSMutableDictionary *claims = [NSMutableDictionary dictionary];
    if ([savedClaims isKindOfClass:[NSDictionary class]]) {
        for (id key in savedClaims) {
            id savedClaim = [savedClaims objectForKey:key];
            if (![key isKindOfClass:[NSString class]] || ![savedClaim isKindOfClass:[NSDictionary class]]) continue;
            id identity = [savedClaim objectForKey:@"identity"], path = [savedClaim objectForKey:@"path"];
            if ([identity isKindOfClass:[NSString class]] && [identity length] && ValidBackupPath(path))
                [claims setObject:@{@"identity":[[identity copy] autorelease], @"path":[[path copy] autorelease]} forKey:key];
        }
    }
    NSDictionary *claim = [claims objectForKey:identifier];
    if (fileIdentity && claim && ![[claim objectForKey:@"identity"] isEqual:fileIdentity] &&
        [[NSFileManager defaultManager] fileExistsAtPath:[claim objectForKey:@"path"]]) {
        [prefs renewBackupLibraryIdentifier];
        identifier = [prefs backupLibraryIdentifier];
    }
    if (fileIdentity) {
        [claims setObject:@{@"identity":fileIdentity, @"path":[location path]} forKey:identifier];
        [defaults setObject:claims forKey:ClaimsKey];
    }
    libraryIdentifier = [identifier copy];
    NSDictionary *savedSettings = [defaults dictionaryForKey:SettingsKey];
    id saved = [savedSettings isKindOfClass:[NSDictionary class]] ? [savedSettings objectForKey:identifier] : nil;
    librarySettings = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"enabled":@YES, @"interval":@900, @"recent":@96, @"daily":@30, @"weekly":@12, @"maxBytes":@(2ULL*1024*1024*1024)}];
    [librarySettings addEntriesFromDictionary:ValidatedSavedBackupSettings(saved, libraryIdentifier)];
    if ([librarySettings objectForKey:@"destinationBookmark"]) {
        NSError *destinationError = nil;
        if (![self rootURLWithError:&destinationError]) latestError = [[destinationError localizedDescription] copy];
    }
    NSDate *last = [librarySettings objectForKey:@"lastDate"];
    NSTimeInterval interval = [[librarySettings objectForKey:@"interval"] doubleValue];
    [self scheduleNextAttemptAfterDelay:(last ? interval : 0) fromDate:last ?: [NSDate date]];
    [self changed];
    [self performSelector:@selector(tick:) withObject:nil afterDelay:0.0];
}
- (NSString *)libraryIdentifier { return libraryIdentifier; }
- (NSDictionary *)settings { return [[librarySettings copy] autorelease] ?: @{}; }
- (BOOL)hasLibrary { return library != nil && !stopped; }
- (BOOL)isBusy { return busy; }
- (BOOL)setSettings:(NSDictionary *)values error:(NSError **)error {
    if (error) *error = nil;
    if (![self hasLibrary] || busy) { if (error) *error = BackupError(@"Wait for the current backup operation to finish."); return NO; }
    if (![values isKindOfClass:[NSDictionary class]] || ([values objectForKey:@"enabled"] && ![[values objectForKey:@"enabled"] isKindOfClass:[NSNumber class]])) {
        if (error) *error = BackupError(@"The backup settings are invalid."); return NO;
    }
    NSDictionary *bounds = @{@"interval":@[@60,@86400], @"recent":@[@3,@10000], @"daily":@[@0,@3650],
        @"weekly":@[@0,@520], @"maxBytes":@[@1048576,@1099511627776ULL]};
    for (NSString *key in bounds) {
        id value = [values objectForKey:key];
        if (!value) continue;
        double number = [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : NAN;
        NSArray *range = [bounds objectForKey:key];
        if (!isfinite(number) || number < [[range objectAtIndex:0] doubleValue] || number > [[range objectAtIndex:1] doubleValue] || floor(number) != number) {
            if (error) *error = BackupError(@"The backup interval, retention counts, or storage target is outside the allowed range.");
            return NO;
        }
    }
    for (NSString *key in bounds) if ([values objectForKey:key]) {
        if (![key isEqualToString:@"interval"] && ![[values objectForKey:key] isEqual:[librarySettings objectForKey:key]])
            retentionPending = YES;
        [librarySettings setObject:[values objectForKey:key] forKey:key];
    }
    if ([values objectForKey:@"enabled"]) [librarySettings setObject:@([[values objectForKey:@"enabled"] boolValue]) forKey:@"enabled"];
    [self saveSettings];
    [self scheduleNextAttemptAfterDelay:0 fromDate:[NSDate date]];
    [self changed];
    return YES;
}
- (NSURL *)rootURLWithError:(NSError **)error {
    NSData *bookmark = [librarySettings objectForKey:@"destinationBookmark"];
    if (bookmark) {
        BOOL stale = NO;
        NSURL *root = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
            relativeToURL:nil bookmarkDataIsStale:&stale error:error];
        BOOL isDirectory = NO;
        if (!root || ![[NSFileManager defaultManager] fileExistsAtPath:[root path] isDirectory:&isDirectory] || !isDirectory) {
            if (error) *error = BackupError(@"The selected backup folder is unavailable. Connect its volume or choose another folder.");
            return nil;
        }
        // A copied library can retain its UUID in both apps. Keep their backup
        // histories separate even when the same custom parent folder is chosen.
        if (NVIsDevelopmentBuild()) root = [root URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES];
        return CanonicalURL(root);
    }
    NSString *support = [[NSFileManager defaultManager] applicationSupportDirectory];
    if (!support) { if (error) *error = BackupError(@"The application support folder is unavailable."); return nil; }
    return CanonicalURL([NSURL fileURLWithPath:[support stringByAppendingPathComponent:@"Backups"] isDirectory:YES]);
}
- (NSURL *)destinationURL { return [[self rootURLWithError:NULL] URLByAppendingPathComponent:libraryIdentifier ?: @"" isDirectory:YES]; }
- (NSURL *)checkedDestinationWithError:(NSError **)error {
    NSURL *root = [self rootURLWithError:error];
    NSURL *destination = [root URLByAppendingPathComponent:libraryIdentifier isDirectory:YES];
    NSString *notes = [CanonicalURL([library notesDirectoryURL]) path];
    if (destination && ContainsPath(notes, [CanonicalURL(destination) path])) {
        if (error) *error = BackupError(@"Choose a backup folder outside the active notes folder.");
        return nil;
    }
    return destination;
}
- (NSString *)statusText {
    if (![self hasLibrary]) return NSLocalizedString(@"Open a library to configure backups.", nil);
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"Last backup: %@", nil), DateLabel([librarySettings objectForKey:@"lastDate"])]];
    [lines addObject:busy ? NSLocalizedString(@"Backup operation in progress…", nil) :
        ([[librarySettings objectForKey:@"enabled"] boolValue] ? [NSString stringWithFormat:NSLocalizedString(@"Next check: %@", nil), DateLabel(nextAttempt)] : NSLocalizedString(@"Automatic backups are off.", nil))];
    if ([librarySettings objectForKey:@"storageBytes"]) {
        [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"Backup storage: %@", nil),
            [NSByteCountFormatter stringFromByteCount:[[librarySettings objectForKey:@"storageBytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]]];
    }
    if (latestNotice) [lines addObject:latestNotice];
    if (latestError) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"Error: %@", nil), latestError]];
    return [lines componentsJoinedByString:@"\n"];
}
- (void)tick:(id)sender { [self checkForBackupAtDate:[NSDate date]]; }
- (void)woke:(NSNotification *)notification { [self tick:nil]; }
- (void)checkForBackupAtDate:(NSDate *)date {
    if (![self hasLibrary] || busy || ![[librarySettings objectForKey:@"enabled"] boolValue]) return;
    NSTimeInterval interval = [[librarySettings objectForKey:@"interval"] doubleValue];
    // Preserve deliberate failure delays. A backward clock change must not
    // postpone either a regular check or its retry by days or years.
    NSTimeInterval delay = nextAttemptDelay > 0 ? nextAttemptDelay : interval;
    if ([nextAttempt timeIntervalSinceDate:date] > delay) {
        [self scheduleNextAttemptAfterDelay:delay fromDate:date];
    }
    if (!nextAttempt || [nextAttempt compare:date] != NSOrderedDescending) [self beginBackupAtDate:date manual:NO];
    else [self changed];
}
- (void)beginBackupAtDate:(NSDate *)date manual:(BOOL)manual {
    if (![self hasLibrary] || busy) return;
    [self scheduleNextAttemptAfterDelay:[[librarySettings objectForKey:@"interval"] doubleValue] fromDate:date];
    NSError *error = nil;
    NSURL *destination = [self checkedDestinationWithError:&error];
    if (!destination) { [self scheduleNextAttemptAfterDelay:300 fromDate:date]; [self setError:error]; return; }
    NSURL *existingRoot = nil;
    NSString *existingRootIdentity = nil;
    if ([librarySettings objectForKey:@"destinationBookmark"]) {
        existingRoot = [destination URLByDeletingLastPathComponent];
        struct stat rootInfo;
        if (stat([[existingRoot path] fileSystemRepresentation], &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode)) {
            [self scheduleNextAttemptAfterDelay:300 fromDate:date];
            [self setError:BackupError(@"The selected backup folder is unavailable. Connect its volume or choose another folder.")];
            return;
        }
        existingRootIdentity = [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)rootInfo.st_dev, (unsigned long long)rootInfo.st_ino];
    }
    NSDictionary *snapshot = [library backupSnapshotWithError:&error];
    if (!snapshot) { [self scheduleNextAttemptAfterDelay:300 fromDate:date]; [self setError:error]; return; }
    NSError *primaryWarning = [snapshot objectForKey:@"sourceWriteError"] ?: [snapshot objectForKey:@"journalWriteError"];
    [latestNotice release];
    latestNotice = [(primaryWarning ? [primaryWarning localizedDescription] : NSLocalizedString(@"Includes committed notes. Unfinished text composition and metadata edits are excluded.", nil)) copy];
    NSString *lastPath = [librarySettings objectForKey:@"lastSnapshot"];
    NSURL *previousSnapshot = nil;
    if (!manual && [[snapshot objectForKey:@"generation"] isEqual:[librarySettings objectForKey:@"lastGeneration"]] && ValidBackupPath(lastPath)) {
        NSURL *candidate = [NSURL fileURLWithPath:lastPath isDirectory:YES];
        NSString *parent = [[[candidate URLByDeletingLastPathComponent] URLByStandardizingPath] path];
        if ([parent isEqual:[[destination URLByStandardizingPath] path]]) {
            // Rebuild from the checked destination so saved settings cannot redirect verification to another folder.
            previousSnapshot = [destination URLByAppendingPathComponent:[candidate lastPathComponent] isDirectory:YES];
        }
    }
    NSMutableDictionary *metadata = [[snapshot mutableCopy] autorelease];
    [metadata removeObjectForKey:@"data"];
    [metadata removeObjectForKey:@"sourceWriteError"]; [metadata removeObjectForKey:@"journalWriteError"];
    [metadata setObject:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] ?: @"unknown" forKey:@"appVersion"];
    if (existingRoot) {
        [metadata setObject:existingRoot forKey:@"existingRoot"];
        [metadata setObject:existingRootIdentity forKey:@"existingRootIdentity"];
    }
    if (previousSnapshot) [metadata setObject:[[previousSnapshot lastPathComponent] stringByDeletingPathExtension] forKey:@"protectedSnapshotIdentifier"];
    NSDictionary *retention = [self settings];
    NSUInteger context = contextGeneration;
    long long retentionDay = (long long)floor([date timeIntervalSince1970] / 86400.0);
    BOOL maintainUnchanged = retentionPending || lastRetentionDay != retentionDay;
    busy = YES;
    [self changed];
    [worker addOperationWithBlock:^{ @autoreleasepool {
        // A directory alone cannot establish that unchanged content remains recoverable.
        NSData *previousData = previousSnapshot ? [NVBackupStore archiveDataAtSnapshotURL:previousSnapshot error:NULL] : nil;
        BOOL verified = previousData && [previousData isEqualToData:[snapshot objectForKey:@"data"]];
        NSError *writeError = nil;
        NSDictionary *result = verified ? nil : [NVBackupStore publishArchiveData:[snapshot objectForKey:@"data"] metadata:metadata inDirectory:destination retention:retention error:&writeError];
        NSError *retentionError = [result objectForKey:@"retentionError"];
        if (verified && maintainUnchanged)
            [NVBackupStore pruneSnapshotsInDirectory:destination metadata:metadata retention:retention error:&retentionError];
        unsigned long long bytes = 0;
        NSError *listingError = nil;
        NSArray *entries = (result || (verified && maintainUnchanged)) ? [NVBackupStore snapshotsInDirectory:destination error:&listingError] : nil;
        for (NSDictionary *entry in entries) bytes += [[entry objectForKey:@"size"] unsignedLongLongValue];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            busy = NO;
            if (stopped || context != contextGeneration) { [self changed]; return; }
            if (result || verified) {
                if (result) {
                    [librarySettings setObject:[result objectForKey:@"date"] forKey:@"lastDate"];
                    [librarySettings setObject:[snapshot objectForKey:@"generation"] forKey:@"lastGeneration"];
                    [librarySettings setObject:[[result objectForKey:@"snapshotURL"] path] forKey:@"lastSnapshot"];
                }
                if (entries) [librarySettings setObject:@(bytes) forKey:@"storageBytes"];
                NSError *maintenanceError = retentionError ?: listingError;
                if (result || maintainUnchanged) {
                    retentionPending = maintenanceError != nil;
                    if (!retentionPending) lastRetentionDay = retentionDay;
                }
                [self saveSettings];
                NSMutableArray *notices = [NSMutableArray arrayWithObject:NSLocalizedString(@"Includes committed notes. Unfinished text composition and metadata edits are excluded.", nil)];
                NSError *primaryError = [snapshot objectForKey:@"sourceWriteError"] ?: [snapshot objectForKey:@"journalWriteError"];
                if (primaryError) [notices addObject:[primaryError localizedDescription]];
                if ([[librarySettings objectForKey:@"storageBytes"] unsignedLongLongValue] > [[retention objectForKey:@"maxBytes"] unsignedLongLongValue]) [notices addObject:NSLocalizedString(@"The three retained snapshots exceed the storage target.", nil)];
                [latestNotice release]; latestNotice = [[notices componentsJoinedByString:@"\n"] copy];
                if (maintenanceError) {
                    [self scheduleNextAttemptAfterDelay:300 fromDate:[NSDate date]];
                }
                [self setError:maintenanceError];
            } else {
                [self scheduleNextAttemptAfterDelay:300 fromDate:[NSDate date]];
                [self setError:writeError];
            }
        }];
    }}];
}
- (IBAction)backupNow:(id)sender { [self beginBackupAtDate:[NSDate date] manual:YES]; }
- (IBAction)chooseDestination:(id)sender {
    if (![self hasLibrary] || busy) return;
    NSString *identity = [[libraryIdentifier copy] autorelease];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO]; [panel setCanChooseDirectories:YES]; [panel setCanCreateDirectories:YES];
    [panel setPrompt:NSLocalizedString(@"Choose Backup Folder", nil)];
    if ([panel runModal] != NSModalResponseOK || ![identity isEqual:libraryIdentifier] || busy) return;
    NSURL *root = CanonicalURL([panel URL]);
    if (ContainsPath([CanonicalURL([library notesDirectoryURL]) path], [root path])) { [self setError:BackupError(@"Choose a backup folder outside the active notes folder.")]; return; }
    NSError *error = nil;
    NSData *bookmark = [root bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    if (!bookmark) { [self setError:error]; return; }
    [librarySettings setObject:bookmark forKey:@"destinationBookmark"];
    retentionPending = YES;
    for (NSString *key in @[@"lastDate",@"lastGeneration",@"lastSnapshot",@"storageBytes"]) [librarySettings removeObjectForKey:key];
    [self saveSettings];
    [self scheduleNextAttemptAfterDelay:0 fromDate:[NSDate date]];
    [self setError:nil];
}
- (IBAction)showBackupsInFinder:(id)sender {
    NSURL *directory = [self destinationURL];
    if (directory && [[NSFileManager defaultManager] fileExistsAtPath:[directory path]]) [[NSWorkspace sharedWorkspace] openURL:directory];
    else [self setError:BackupError(@"No backup folder exists yet. Create a backup first.")];
}
- (IBAction)deleteUnencryptedBackups:(id)sender {
    if (![self hasLibrary] || busy) return;
    NSUInteger context = contextGeneration;
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:NSLocalizedString(@"Delete older unencrypted backups?", nil)];
    [alert setInformativeText:NSLocalizedString(@"This deletes recognized, complete unencrypted snapshots in this library’s current backup folder. Damaged or unrecognized files remain for manual review. Your notes and encrypted snapshots remain available.", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)]; [alert addButtonWithTitle:NSLocalizedString(@"Delete Backups", nil)];
    if ([alert runModal] != NSAlertSecondButtonReturn || context != contextGeneration || busy) return;
    NSError *error = nil;
    NSURL *destination = [self checkedDestinationWithError:&error];
    if (!destination) { [self setError:error]; return; }
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithObject:libraryIdentifier forKey:@"libraryIdentifier"];
    if ([librarySettings objectForKey:@"destinationBookmark"]) {
        NSURL *existingRoot = [destination URLByDeletingLastPathComponent];
        struct stat rootInfo;
        if (stat([[existingRoot path] fileSystemRepresentation], &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode)) {
            [self setError:BackupError(@"The selected backup folder is unavailable. Connect its volume or choose another folder.")];
            return;
        }
        [metadata setObject:existingRoot forKey:@"existingRoot"];
        [metadata setObject:[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)rootInfo.st_dev, (unsigned long long)rootInfo.st_ino]
                     forKey:@"existingRootIdentity"];
    }
    busy = YES; [self changed];
    [worker addOperationWithBlock:^{ @autoreleasepool {
        NSError *deleteError = nil;
        BOOL success = [NVBackupStore deleteUnencryptedSnapshotsInDirectory:destination metadata:metadata error:&deleteError];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            busy = NO;
            if (stopped || context != contextGeneration) { [self changed]; return; }
            if (success) {
                for (NSString *key in @[@"lastGeneration",@"lastSnapshot",@"storageBytes"]) [librarySettings removeObjectForKey:key];
                [self saveSettings];
            }
            [self setError:deleteError];
        }];
    }}];
}
- (IBAction)restoreBackup:(id)sender {
    if (![self hasLibrary] || busy) return;
    NSUInteger context = contextGeneration;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES]; [panel setCanChooseDirectories:YES];
    [panel setTreatsFilePackagesAsDirectories:NO]; [panel setAllowedFileTypes:@[@"nvbackup"]];
    [panel setPrompt:NSLocalizedString(@"Restore Backup", nil)];
    [panel setDirectoryURL:[self destinationURL]];
    if ([panel runModal] != NSModalResponseOK || context != contextGeneration || busy) return;
    NSURL *selected = [panel URL];
    NSURL *snapshotURL = [CanonicalURL([selected URLByDeletingLastPathComponent]) URLByAppendingPathComponent:[selected lastPathComponent]];
    busy = YES; [self changed];
    [worker addOperationWithBlock:^{ @autoreleasepool {
        NSError *readError = nil;
        NSData *data = [NVBackupStore archiveDataAtSnapshotURL:snapshotURL error:&readError];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (stopped || context != contextGeneration) { busy = NO; [self changed]; return; }
            if (!data) { busy = NO; [self setError:readError]; return; }
            NSError *decodeError = nil;
            NSDictionary *restored = [NVBackupArchive restoredArchiveFromData:data error:&decodeError];
            if (stopped || context != contextGeneration) { busy = NO; [self changed]; return; }
            if (!restored) {
                busy = NO;
                if ([decodeError code] != NSUserCancelledError) [self setError:decodeError];
                else [self changed];
                return;
            }
            NSOpenPanel *folder = [NSOpenPanel openPanel];
            [folder setCanChooseFiles:NO]; [folder setCanChooseDirectories:YES]; [folder setCanCreateDirectories:YES];
            [folder setMessage:[NSString stringWithFormat:NSLocalizedString(@"Restore %lu notes from %@ into a new, empty folder. The current library remains in its original folder.", nil), (unsigned long)[[restored objectForKey:@"noteCount"] unsignedIntegerValue], DateLabel([restored objectForKey:@"captureDate"])]];
            [folder setPrompt:NSLocalizedString(@"Restore Here", nil)];
            if ([folder runModal] != NSModalResponseOK || context != contextGeneration) { busy = NO; [self changed]; return; }
            NSError *restoreError = nil;
            BOOL success = [applicationController restoreBackupArchive:restored toDirectory:CanonicalURL([folder URL]) error:&restoreError];
            busy = NO;
            if (!success) [self setError:restoreError];
            else [self changed];
        }];
    }}];
}
- (void)stop {
    stopped = YES; contextGeneration++;
    [timer invalidate]; [timer release]; timer = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [self changed];
}
- (void)dealloc {
    [self stop];
    [library release]; [libraryIdentifier release]; [worker release]; [librarySettings release];
    [nextAttempt release]; [latestError release]; [latestNotice release];
    [super dealloc];
}
@end
