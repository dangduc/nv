// Injected only into disposable copies by run-tests.py.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NotationController.h"
#import "NotationFileManager.h"
#import "NotationPrefs.h"
#import "GlobalPrefs.h"
#import "NoteObject.h"
#import "FrozenNotation.h"
#import "NVBackupController.h"
#import "NVBackupStore.h"
#import "NSFileManager+DirectoryLocations.h"
#import "NSFileManager_NV.h"
#import "ODBEditor.h"
#import "TemporaryFileCachePreparer.h"

static NSString *Root, *Flavor, *Phase, *KeychainService;
static NSUInteger Checks, LegacyReads;
static void Check(BOOL condition, NSString *description) {
    if (!condition) { NSLog(@"FAIL: %@", description); exit(1); }
    Checks++; NSLog(@"PASS: %@", description);
}
static NSString *TestHome(void) {
    return [[NSString stringWithUTF8String:getenv("NV_ISOLATION_ROOT")] stringByAppendingPathComponent:@"Home"];
}
static NSString *HomePath(NSString *suffix) { return [TestHome() stringByAppendingPathComponent:suffix]; }
static NSString *Canonical(NSString *path) { return [[[[NSURL fileURLWithPath:path] URLByStandardizingPath] URLByResolvingSymlinksInPath] path]; }
static BOOL Development(void) { return [Flavor isEqualToString:@"development"]; }
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static void Swap(Class cls, SEL original, SEL replacement) {
    Method first = class_getInstanceMethod(cls, original), second = class_getInstanceMethod(cls, replacement);
    Check(first != NULL && second != NULL, NSStringFromSelector(original));
    method_exchangeImplementations(first, second);
}

// Redirect OS-owned base locations. Production app methods still choose every
// notes, support, cache, backup, and editing subdirectory themselves.
static NSString *TestNSHomeDirectory(void) { return TestHome(); }
static NSString *TestNSTemporaryDirectory(void) { return [[NSString stringWithUTF8String:getenv("NV_ISOLATION_ROOT")] stringByAppendingPathComponent:@"Temp/"]; }
static NSArray *TestSearchPaths(NSSearchPathDirectory directory, NSSearchPathDomainMask domain, BOOL expand) {
    if (domain & NSUserDomainMask) {
        NSString *suffix = nil;
        switch (directory) {
            case NSApplicationSupportDirectory: suffix = @"Library/Application Support"; break;
            case NSCachesDirectory: suffix = @"Library/Caches"; break;
            case NSLibraryDirectory: suffix = @"Library"; break;
            case NSDocumentDirectory: suffix = @"Documents"; break;
            case NSDesktopDirectory: suffix = @"Desktop"; break;
            default: break;
        }
        if (suffix) return @[HomePath(suffix)];
    }
    return NSSearchPathForDirectoriesInDomains(directory, domain, expand);
}
static OSErr TestFSFindFolder(FSVolumeRefNum domain, OSType type, Boolean create, FSRef *result) {
    NSString *path = nil;
    if (domain == kUserDomain) {
        if (type == kApplicationSupportFolderType) path = HomePath(@"Library/Application Support");
        else if (type == kCurrentUserFolderType) path = TestHome();
        else if (type == kCachedDataFolderType) path = HomePath(@"Library/Caches");
        else if (type == kPreferencesFolderType) path = HomePath(@"Library/Preferences");
    }
    // The app also asks for a trash folder by volume when setting up a library.
    if (type == kTrashFolderType) path = HomePath(@".Trash");
    if (path) return FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], result, NULL);
    return FSFindFolder(domain, type, create, result);
}
static OSStatus TestKeychainFind(CFTypeRef keychain, UInt32 serviceLength, const char *service,
    UInt32 accountLength, const char *account, UInt32 *length, void **data, SecKeychainItemRef *item) {
    [KeychainService release];
    KeychainService = [[NSString alloc] initWithBytes:service length:serviceLength encoding:NSUTF8StringEncoding];
    if (length) *length = 0;
    if (data) *data = NULL;
    if (item) *item = NULL;
    return errSecItemNotFound;
}
static OSStatus TestKeychainAdd(SecKeychainRef keychain, UInt32 serviceLength, const char *service,
    UInt32 accountLength, const char *account, UInt32 length, const void *data, SecKeychainItemRef *item) {
    Check(NO, @"unexpected keychain write is blocked"); return errSecAuthFailed;
}
static OSStatus TestKeychainDelete(SecKeychainItemRef item) {
    Check(NO, @"unexpected keychain delete is blocked"); return errSecAuthFailed;
}
static OSStatus TestKeychainModify(SecKeychainItemRef item, const SecKeychainAttributeList *attributes,
    UInt32 length, const void *data) {
    Check(NO, @"unexpected keychain modification is blocked"); return errSecAuthFailed;
}
#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *newFunction; const void *oldFunction; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = { (const void *)&replacement, (const void *)&original };
INTERPOSE(TestNSHomeDirectory, NSHomeDirectory)
INTERPOSE(TestNSTemporaryDirectory, NSTemporaryDirectory)
INTERPOSE(TestSearchPaths, NSSearchPathForDirectoriesInDomains)
INTERPOSE(TestFSFindFolder, FSFindFolder)
INTERPOSE(TestKeychainFind, SecKeychainFindGenericPassword)
INTERPOSE(TestKeychainAdd, SecKeychainAddGenericPassword)
INTERPOSE(TestKeychainDelete, SecKeychainItemDelete)
INTERPOSE(TestKeychainModify, SecKeychainItemModifyAttributesAndData)

@interface NSUserDefaults (NVIsolation)
- (NSDictionary *)nv_isolationDomain:(NSString *)name;
@end
@implementation NSUserDefaults (NVIsolation)
- (NSDictionary *)nv_isolationDomain:(NSString *)name {
    if ([name isEqualToString:@"com.scrod.notationalvelocity"]) {
        LegacyReads++;
        return @{}; // Empty disposable legacy input; never read the user's domain.
    }
    return [self nv_isolationDomain:name];
}
@end
@interface NSObject (NVIsolationODB)
- (void)nv_isolationInitialize:(id)prefs;
@end
@implementation NSObject (NVIsolationODB)
- (void)nv_isolationInitialize:(id)prefs { }
@end

static NSString *ReportPath(NSString *suffix) {
    return [Root stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.%@", Flavor, Phase, suffix]];
}
static void CheckNotes(NSArray *notes) {
    Check([notes count] == 1, @"library contains exactly its own note");
    NoteObject *note = [notes lastObject];
    Check([[note valueForKey:@"titleString"] isEqualToString:[Flavor stringByAppendingString:@" note"]] &&
        [[[note contentString] string] isEqualToString:[Flavor stringByAppendingString:@" durable body"]],
        @"note title and body retain this build's content");
}
static void CheckSettings(void) {
    GlobalPrefs *prefs = [(id)NSClassFromString(@"GlobalPrefs") defaultPrefs];
    Check(fabs([prefs tableFontSize] - (Development() ? 17 : 13)) < 0.01, @"font preference retains this build's value");
    NSColor *color = [[prefs backgroundTextColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    Check(fabs([color redComponent] - (Development() ? 0.21 : 0.81)) < 0.01,
        @"editor color preference retains this build's value");
}

@interface NSObject (NVIsolationApp)
- (void)nv_isolationLaunch:(NSNotification *)notification;
- (void)nv_isolationDelayed;
- (void)nv_isolationRun;
@end
@implementation NSObject (NVIsolationApp)
+ (void)load {
    const char *root = getenv("NV_ISOLATION_ROOT");
    if (!root) return;
    Root = [[NSString stringWithUTF8String:root] copy];
    Flavor = [[NSString stringWithUTF8String:getenv("NV_ISOLATION_FLAVOR")] copy];
    Phase = [[NSString stringWithUTF8String:getenv("NV_ISOLATION_PHASE")] copy];
    Swap(NSClassFromString(@"AppController"), @selector(applicationDidFinishLaunching:), @selector(nv_isolationLaunch:));
    Swap(NSClassFromString(@"AppController"), @selector(runDelayedUIActionsAfterLaunch), @selector(nv_isolationDelayed));
    Swap([NSUserDefaults class], @selector(persistentDomainForName:), @selector(nv_isolationDomain:));
    Swap(NSClassFromString(@"ODBEditor"), @selector(initializeDatabase:), @selector(nv_isolationInitialize:));
}
- (void)nv_isolationDelayed { }
- (void)nv_isolationLaunch:(NSNotification *)notification {
    [self nv_isolationLaunch:notification]; // Original startup opens the default directory.
    [self performSelector:@selector(nv_isolationRun) withObject:nil afterDelay:0.2];
}
- (void)nv_isolationRun {
    @try {
        NVApplicationController *app = [(id)NSClassFromString(@"NVApplicationController") sharedController];
        NotationController *library = [app library];
        GlobalPrefs *prefs = [(id)NSClassFromString(@"GlobalPrefs") defaultPrefs];
        NVBackupController *backup = [app backupController];
        NSBundle *bundle = [NSBundle mainBundle];
        Check([[bundle objectForInfoDictionaryKey:@"NVBuildFlavor"] isEqualToString:Flavor], @"compiled bundle retains the expected build flavor");
        Check(Development() ? [[[NSApp dockTile] badgeLabel] isEqualToString:@"DEV"] : ![[[NSApp dockTile] badgeLabel] length],
            @"only the development app displays the DEV Dock badge");
        NSString *notesPath = [[library notesDirectoryURL] path];
        NSString *support = [[NSFileManager defaultManager] applicationSupportDirectory];
        NSString *cache = [library createCachesFolder];
        Check([notesPath isEqualToString:HomePath(Development() ? @"Library/Application Support/Notational Data Development" : @"Library/Application Support/Notational Data")],
            @"original startup selects the correct default notes folder");
        Check([support isEqualToString:HomePath(Development() ? @"Library/Application Support/nvALT Development" : @"Library/Application Support/nvALT")],
            @"application support derives the build's executable name");
        Check([cache isEqualToString:[HomePath(@"Library/Caches") stringByAppendingPathComponent:[bundle bundleIdentifier]]],
            @"journal cache derives the copied bundle's unique identifier");
        Check([[[[backup destinationURL] path] stringByDeletingLastPathComponent] isEqualToString:Canonical([support stringByAppendingPathComponent:@"Backups"])],
            @"backup destination belongs to this build's support directory");
        Check(Development() ? LegacyReads == 0 : (![Phase isEqualToString:@"first"] || LegacyReads > 0),
            @"development skips legacy BLOR preference reads; release retains first-launch import");

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
        while ([backup isBusy] && [deadline timeIntervalSinceNow] > 0) Pump();
        Check(![backup isBusy], @"initial backup worker finishes");
        if ([Phase isEqualToString:@"first"]) {
            Check([[library allNotes] count] == 0, @"fresh build starts with an empty disposable library");
            [prefs setTableFontSize:Development() ? 17 : 13 sender:nil];
            [prefs setBackgroundTextColor:[NSColor colorWithCalibratedRed:Development() ? 0.21 : 0.81 green:0.42 blue:0.63 alpha:1] sender:nil];
            NoteObject *note = [[[NSClassFromString(@"NoteObject") alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:[Flavor stringByAppendingString:@" durable body"]] autorelease]
                title:[Flavor stringByAppendingString:@" note"] delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
            [library addNewNote:note];
            [(AppController *)self revealNote:note options:0];
            Check([library flushAllNoteChanges], @"new note reaches the real library checkpoint");
            NSError *error = nil;
            Check([backup setSettings:@{@"enabled":@NO, @"interval": Development() ? @120 : @240} error:&error],
                @"independent backup settings save");
            [backup backupNow:self];
            deadline = [NSDate dateWithTimeIntervalSinceNow:20];
            while ([backup isBusy] && [deadline timeIntervalSinceNow] > 0) Pump();
            Check(![backup isBusy], @"manual backup finishes");
        }
        if ([Phase isEqualToString:@"first"]) {
            NSWindow *window = [(AppController *)self window];
            [window makeKeyAndOrderFront:self];
            Pump();
            NSView *view = [window contentView];
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
            [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bitmap];
            NSString *imagePath = [[NSString stringWithUTF8String:getenv("NV_ISOLATION_SCREENSHOTS")] stringByAppendingPathComponent:[Flavor stringByAppendingString:@".png"]];
            Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:imagePath atomically:YES], @"native window bitmap saves");
        }
        CheckSettings();
        CheckNotes([library allNotes]);
        Check([[[backup settings] objectForKey:@"interval"] integerValue] == (Development() ? 120 : 240),
            @"backup interval retains this build's value");
        NSURL *snapshotURL = [NSURL fileURLWithPath:[[backup settings] objectForKey:@"lastSnapshot"] ?: @""];
        NSError *error = nil;
        NSData *snapshot = [(id)NSClassFromString(@"NVBackupStore") archiveDataAtSnapshotURL:snapshotURL error:&error];
        Check(snapshot != nil, @"this build's backup package validates");
        FrozenNotation *archive = [NSKeyedUnarchiver unarchiveObjectWithData:snapshot];
        OSStatus archiveError = noErr;
        NSArray *backupNotes = [archive unpackedNotesReturningError:&archiveError];
        CheckNotes(backupNotes);
        Check(archiveError == noErr, @"backup payload decodes successfully");

        // Observe the actual keychain service without accessing any keychain.
        [[library notationPrefs] passwordDataFromKeychain];
        Check([KeychainService isEqualToString:Development() ? @"Notational Velocity Development" : @"Notational Velocity"],
            @"keychain lookup selects this build's service");
        TemporaryFileCachePreparer *preparer = [[[NSClassFromString(@"TemporaryFileCachePreparer") alloc] init] autorelease];
        [preparer prepEditingSpaceIfNecessaryForNotationPrefs:[library notationPrefs]];
        NSString *editing = [preparer preparedCachePath];
        Check([editing isEqualToString:[[Root stringByAppendingPathComponent:@"Temp"] stringByAppendingPathComponent:
            Development() ? @"NVPlainTextEditingSpace-Development" : @"NVPlainTextEditingSpace"]],
            @"external editing uses this build's temporary directory");
        Check([[NSUserDefaults standardUserDefaults] synchronize], @"disposable preferences synchronize");
        NSMutableDictionary *report = [NSMutableDictionary dictionaryWithDictionary:@{@"flavor":Flavor, @"phase":Phase, @"pid":@([[NSProcessInfo processInfo] processIdentifier]),
            @"notes":notesPath, @"support":support, @"cache":cache, @"backup":[[backup destinationURL] path],
            @"editing":editing, @"keychainService":KeychainService, @"bundleIdentifier":[bundle bundleIdentifier],
            @"checks":@(Checks), @"legacyReads":@(LegacyReads)}];
        Check([report writeToFile:ReportPath(@"ready.plist") atomically:YES], @"concurrent-run report is ready");
        NSString *gate = [Root stringByAppendingPathComponent:[Phase stringByAppendingString:@".continue"]];
        deadline = [NSDate dateWithTimeIntervalSinceNow:30];
        while (![[NSFileManager defaultManager] fileExistsAtPath:gate] && [deadline timeIntervalSinceNow] > 0) Pump();
        Check([[NSFileManager defaultManager] fileExistsAtPath:gate], @"runner observed both app processes alive together");
        [[NSUserDefaults standardUserDefaults] synchronize];
        CheckSettings(); CheckNotes([library allNotes]);
        Check([library flushAllNoteChanges], @"library flushes before normal application termination");
        [report setObject:@(Checks + 1) forKey:@"checks"];
        Check([report writeToFile:ReportPath(@"passed.plist") atomically:YES], @"completed probe report saves");
        NSLog(@"ISOLATION %@ %@ PASSED (%lu checks)", Flavor, Phase, (unsigned long)Checks);
        [NSApp terminate:self];
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
