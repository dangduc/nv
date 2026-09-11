// No GUI startup. The runner inserts the selected production backup methods.
#import <Cocoa/Cocoa.h>
#include <sys/stat.h>
#include <math.h>

static NSString *TestRoot;
static NSString * const SharedLibraryID = @"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@HELPERS@

@interface ProbePrefs : NSObject { NSString *identifier; }
- (NSString *)backupLibraryIdentifier;
- (void)renewBackupLibraryIdentifier;
@end
@implementation ProbePrefs
- (id)init { if ((self = [super init])) identifier = [SharedLibraryID copy]; return self; }
- (NSString *)backupLibraryIdentifier { return identifier; }
- (void)renewBackupLibraryIdentifier { [identifier release]; identifier = [[[NSUUID UUID] UUIDString] copy]; }
@end

@interface ProbeLibrary : NSObject { ProbePrefs *prefs; NSURL *location; }
- (id)initWithLocation:(NSURL *)url;
- (ProbePrefs *)notationPrefs;
- (NSURL *)notesDirectoryURL;
@end
@implementation ProbeLibrary
- (id)initWithLocation:(NSURL *)url {
    if ((self = [super init])) { prefs = [[ProbePrefs alloc] init]; location = [url retain]; } return self;
}
- (ProbePrefs *)notationPrefs { return prefs; }
- (NSURL *)notesDirectoryURL { return location; }
@end

@interface NSFileManager (ProbeSupport)
- (NSString *)applicationSupportDirectory;
@end
@implementation NSFileManager (ProbeSupport)
- (NSString *)applicationSupportDirectory { return [TestRoot stringByAppendingPathComponent:@"unused-default-support"]; }
@end

@interface ProbeBackup : NSObject {
    ProbeLibrary *library;
    NSString *libraryIdentifier, *latestError, *latestNotice;
    NSMutableDictionary *librarySettings;
    NSDate *nextAttempt;
    NSTimeInterval nextAttemptDelay;
    NSUInteger contextGeneration;
    BOOL retentionPending;
}
- (void)setLibrary:(ProbeLibrary *)newLibrary;
- (void)saveSettings;
- (NSURL *)rootURLWithError:(NSError **)error;
- (NSURL *)destinationURL;
- (void)scheduleNextAttemptAfterDelay:(NSTimeInterval)delay fromDate:(NSDate *)date;
- (void)changed;
- (void)tick:(id)sender;
@end
@implementation ProbeBackup
@METHODS@
- (void)tick:(id)sender { Check(NO, @"The headless probe must not run a backup timer"); }
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 4, @"expected root, flavor, and command");
        TestRoot = [NSString stringWithUTF8String:argv[1]];
        NSString *flavor = [NSString stringWithUTF8String:argv[2]];
        NSString *command = [NSString stringWithUTF8String:argv[3]];
        NSString *domain = [[NSBundle mainBundle] bundleIdentifier];
        Check([domain hasPrefix:@"org.nvalt.kingsbury-review."], @"only a unique test defaults domain is allowed");
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *notes = [TestRoot stringByAppendingPathComponent:flavor];
        if ([command isEqual:@"copy-control"]) notes = [notes stringByAppendingString:@"-copy"];
        Check([[NSFileManager defaultManager] createDirectoryAtPath:notes withIntermediateDirectories:YES attributes:nil error:NULL], @"temporary notes directory exists");
        notes = [CanonicalURL([NSURL fileURLWithPath:notes]) path];
        ProbeLibrary *library = [[[ProbeLibrary alloc] initWithLocation:[NSURL fileURLWithPath:notes]] autorelease];
        ProbeBackup *backup = [[[ProbeBackup alloc] init] autorelease];

        if ([command isEqual:@"seed"]) {
            Check([defaults dictionaryForKey:SettingsKey] == nil, @"a fresh flavor does not inherit the other domain's backup settings");
            Check([defaults dictionaryForKey:ClaimsKey] == nil, @"a fresh flavor does not inherit the other domain's claims");
            [backup setLibrary:library];
            NSMutableDictionary *settings = [backup valueForKey:@"librarySettings"];
            [settings setObject:([flavor isEqual:@"release"] ? @601 : @907) forKey:@"interval"];
            [backup saveSettings];
            [defaults setObject:[flavor dataUsingEncoding:NSUTF8StringEncoding] forKey:@"DirectoryAlias"];
            Check([defaults synchronize], @"acknowledged defaults synchronization succeeds");
        } else if ([command isEqual:@"read"]) {
            [backup setLibrary:library];
            NSNumber *expected = [flavor isEqual:@"release"] ? @601 : @907;
            Check([[[backup valueForKey:@"librarySettings"] objectForKey:@"interval"] isEqual:expected], @"relaunch retains the flavor's backup interval");
            Check([[defaults dataForKey:@"DirectoryAlias"] isEqual:[flavor dataUsingEncoding:NSUTF8StringEncoding]], @"relaunch retains the flavor's alias bytes");
            Check([[[[defaults dictionaryForKey:ClaimsKey] objectForKey:SharedLibraryID] objectForKey:@"path"] isEqual:notes], @"relaunch retains the flavor's physical-library claim");
        } else if ([command isEqual:@"destination"]) {
            [backup setLibrary:library];
            Check([[backup valueForKey:@"libraryIdentifier"] isEqual:SharedLibraryID], @"the copied library keeps its UUID in the other flavor domain");
            NSURL *root = [NSURL fileURLWithPath:[TestRoot stringByAppendingPathComponent:@"shared-custom-backups"] isDirectory:YES];
            Check([[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL], @"temporary custom backup root exists");
            NSData *bookmark = [root bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
            Check(bookmark != nil, @"Foundation creates a real bookmark to the temporary root");
            [[backup valueForKey:@"librarySettings"] setObject:bookmark forKey:@"destinationBookmark"];
            [backup saveSettings];
            Check([defaults synchronize], @"custom bookmark persists");
            printf("DESTINATION:%s\n", [[[backup destinationURL] path] UTF8String]);
        } else if ([command isEqual:@"destination-relaunch"]) {
            [backup setLibrary:library];
            printf("DESTINATION:%s\n", [[[backup destinationURL] path] UTF8String]);
        } else if ([command isEqual:@"copy-control"]) {
            [backup setLibrary:library];
            Check(![[backup valueForKey:@"libraryIdentifier"] isEqual:SharedLibraryID], @"a second physical copy in the SAME domain renews its UUID");
        } else Check(NO, @"unknown command");
        Check(NSApp == nil, @"no NSApplication or GUI session was created");
        printf("PASS:%s:%s\n", [flavor UTF8String], [command UTF8String]);
    }
    return 0;
}
