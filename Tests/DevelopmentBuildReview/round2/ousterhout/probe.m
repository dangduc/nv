// Frozen production methods and helpers replace the marked sections.
// NSFileManager, NSURL bookmarks, and stat use temporary paths without mocks.
#import <Cocoa/Cocoa.h>
#include <sys/stat.h>
@IDENTITY@

static NSString *TestRoot, *SupportRoot;
static NSUInteger Checks, SchemeReads;
static BOOL SnapshotBoundaryReached;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
    Checks++;
}
@HELPERS@

@interface NSFileManager (ProbeSupport)
- (NSString *)applicationSupportDirectory;
@end
@implementation NSFileManager (ProbeSupport)
- (NSString *)applicationSupportDirectory { return SupportRoot; }
@end

@interface ProbeLibrary : NSObject
- (NSURL *)notesDirectoryURL;
@end
@implementation ProbeLibrary
- (NSURL *)notesDirectoryURL {
    return [NSURL fileURLWithPath:[TestRoot stringByAppendingPathComponent:@"unused-notes"] isDirectory:YES];
}
@end

@interface ProbeBackup : NSObject {
    ProbeLibrary *library;
    NSString *libraryIdentifier;
    NSMutableDictionary *librarySettings;
    BOOL busy;
    NSError *latestError;
    NSTimeInterval lastDelay;
}
- (id)initWithBookmark:(NSData *)bookmark;
- (BOOL)hasLibrary;
- (void)scheduleNextAttemptAfterDelay:(NSTimeInterval)delay fromDate:(NSDate *)date;
- (void)setError:(NSError *)error;
- (NSURL *)rootURLWithError:(NSError **)error;
- (NSURL *)destinationURL;
- (NSURL *)checkedDestinationWithError:(NSError **)error;
- (void)beginBackupAtDate:(NSDate *)date manual:(BOOL)manual;
- (NSError *)latestError;
- (NSTimeInterval)lastDelay;
@end
@implementation ProbeBackup
- (id)initWithBookmark:(NSData *)bookmark {
    if ((self = [super init])) {
        library = [[ProbeLibrary alloc] init];
        libraryIdentifier = [@"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE" copy];
        librarySettings = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@900, @"interval", nil];
        if (bookmark) [librarySettings setObject:bookmark forKey:@"destinationBookmark"];
    }
    return self;
}
- (void)dealloc {
    [library release]; [libraryIdentifier release]; [librarySettings release]; [latestError release];
    [super dealloc];
}
- (BOOL)hasLibrary { return YES; }
- (void)scheduleNextAttemptAfterDelay:(NSTimeInterval)delay fromDate:(NSDate *)date { lastDelay = delay; }
- (void)setError:(NSError *)error { [latestError release]; latestError = [error retain]; }
- (NSError *)latestError { return latestError; }
- (NSTimeInterval)lastDelay { return lastDelay; }
@METHODS@
@PREFLIGHT@
@end

static NSURL *TemporaryDirectory(NSString *name) {
    NSURL *url = [NSURL fileURLWithPath:[TestRoot stringByAppendingPathComponent:name] isDirectory:YES];
    Check([[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:NULL],
          @"create disposable directory");
    return CanonicalURL(url);
}
static NSData *Bookmark(NSURL *url) {
    NSError *error = nil;
    NSData *bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                        includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    Check(bookmark != nil && error == nil, @"create native bookmark");
    return bookmark;
}
static void Attempt(ProbeBackup *backup, BOOL expectedReach, NSString *scenario) {
    for (NSNumber *manual in @[@NO, @YES]) {
        SnapshotBoundaryReached = NO;
        [backup beginBackupAtDate:[NSDate date] manual:[manual boolValue]];
        Check(SnapshotBoundaryReached == expectedReach,
              [NSString stringWithFormat:@"%@, manual=%@", scenario, manual]);
        if (!expectedReach) Check([backup latestError] != nil && [backup lastDelay] == 300,
                                 @"rejected preflight reports an error and schedules a retry");
    }
    printf("OBSERVED: %s: snapshot-boundary=%s error=%s\n", [scenario UTF8String],
           expectedReach ? "reached" : "blocked", [[[backup latestError] localizedDescription] UTF8String] ?: "none");
}
static void BackupChecks(BOOL development) {
    NSFileManager *manager = [NSFileManager defaultManager];
    SupportRoot = [TestRoot stringByAppendingPathComponent:development ? @"support/nvALT Development" : @"support/nvALT"];
    ProbeBackup *standard = [[[ProbeBackup alloc] initWithBookmark:nil] autorelease];
    NSError *error = nil;
    NSURL *standardRoot = [standard rootURLWithError:&error];
    Check([[standardRoot path] isEqual:[SupportRoot stringByAppendingPathComponent:@"Backups"]] && error == nil,
          @"default root retains the support-directory contract");
    Check(![manager fileExistsAtPath:[standardRoot path]], @"default root does not exist before first backup");
    Attempt(standard, YES, @"default root before creation");
    SupportRoot = nil;
    error = nil;
    Check([standard rootURLWithError:&error] == nil && [[error localizedDescription] isEqual:@"The application support folder is unavailable."],
          @"unavailable support root returns its explicit error");
    Attempt(standard, NO, @"unavailable default support");
    SupportRoot = [TestRoot stringByAppendingPathComponent:@"support-unused"];

    NSURL *parent = TemporaryDirectory(@"selected-custom-parent");
    ProbeBackup *custom = [[[ProbeBackup alloc] initWithBookmark:Bookmark(parent)] autorelease];
    NSURL *expectedRoot = CanonicalURL(development ? [parent URLByAppendingPathComponent:@"nvALT Development" isDirectory:YES] : parent);
    error = nil;
    NSURL *actualRoot = [custom rootURLWithError:&error];
    // Bookmarks can return /private/var while Foundation shortens /var aliases.
    // Compare the selected parent by native filesystem identity, then its child.
    NSURL *actualParent = development ? [actualRoot URLByDeletingLastPathComponent] : actualRoot;
    struct stat selectedInfo, actualInfo;
    Check(stat([[parent path] fileSystemRepresentation], &selectedInfo) == 0 &&
          stat([[actualParent path] fileSystemRepresentation], &actualInfo) == 0 &&
          selectedInfo.st_dev == actualInfo.st_dev && selectedInfo.st_ino == actualInfo.st_ino &&
          (!development || [[actualRoot lastPathComponent] isEqual:@"nvALT Development"]) && error == nil,
          @"real custom bookmark resolves to flavor-specific destination root");
    Check([[[custom destinationURL] lastPathComponent] isEqual:@"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"],
          @"copied library UUID stays the final path component");
    if (development) Check(![manager fileExistsAtPath:[expectedRoot path]], @"new development child is absent");
    Attempt(custom, !development, @"existing custom parent before development child creation");
    if (development) {
        Check([manager createDirectoryAtURL:expectedRoot withIntermediateDirectories:NO attributes:nil error:NULL],
              @"manually provision the development child for the control");
        ProbeBackup *provisioned = [[[ProbeBackup alloc] initWithBookmark:Bookmark(parent)] autorelease];
        Attempt(provisioned, YES, @"custom parent after manual development child creation");
    }

    NSURL *removed = TemporaryDirectory(@"removed-custom-parent");
    ProbeBackup *unavailable = [[[ProbeBackup alloc] initWithBookmark:Bookmark(removed)] autorelease];
    Check([manager removeItemAtURL:removed error:NULL], @"delete disposable bookmarked parent");
    error = nil;
    Check([unavailable rootURLWithError:&error] == nil && [[error localizedDescription] isEqual:
          @"The selected backup folder is unavailable. Connect its volume or choose another folder."],
          @"unavailable bookmark does not fall back to support root");
    Attempt(unavailable, NO, @"removed bookmarked parent");
    Check(![manager fileExistsAtPath:[removed path]], @"error handling does not recreate a missing parent");

    NSURL *file = [NSURL fileURLWithPath:[TestRoot stringByAppendingPathComponent:@"selected-file"]];
    Check([[@"fixture" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES], @"create disposable file");
    ProbeBackup *fileSelection = [[[ProbeBackup alloc] initWithBookmark:Bookmark(file)] autorelease];
    error = nil;
    Check([fileSelection rootURLWithError:&error] == nil && error != nil, @"file bookmark cannot become a backup root");
    Attempt(fileSelection, NO, @"bookmark targets a file");
    ProbeBackup *invalid = [[[ProbeBackup alloc] initWithBookmark:[NSData data]] autorelease];
    error = nil;
    Check([invalid rootURLWithError:&error] == nil && error != nil, @"invalid bookmark does not select the default");
    Attempt(invalid, NO, @"invalid bookmark bytes");
}

static NSString *CountedScheme(void) { SchemeReads++; return NVNoteURLScheme(); }
#define NVNoteURLScheme CountedScheme
@interface NSString (ProbeEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (ProbeEscape)
@ESCAPE@
@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *, NSRange);
@interface NSMutableAttributedString (ProbeWiki)
- (void)_addDoubleBracketedNVLinkAttributesForRange:(NSRange)range;
@end
@implementation NSMutableAttributedString (ProbeWiki)
@SCAN@
@end
@WIKI_HELPER@
#undef NVNoteURLScheme

static void WikiChecks(BOOL development) {
    for (NSString *plain in @[@"", @"No links", @"[[unterminated", @"[[ leading]] [[trailing ]]", @"[[first\nsecond]]"] ) {
        NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:plain] autorelease];
        SchemeReads = 0;
        [text _addDoubleBracketedNVLinkAttributesForRange:NSMakeRange(0, [text length])];
        Check(SchemeReads == 0, @"empty, malformed, and rejected links do not resolve the prefix");
        for (NSUInteger i = 0; i < [text length]; i++)
            Check([text attribute:NSLinkAttributeName atIndex:i effectiveRange:NULL] == nil,
                  @"rejected scan does not add link attributes");
    }
    NSString *plain = @"[[outside]] [[ leading]] [[Café / A&B]] [[second]] [[after]]";
    NSRange range = [plain rangeOfString:@"[[ leading]] [[Café / A&B]] [[second]]"];
    NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:plain] autorelease];
    SchemeReads = 0;
    for (NSUInteger pass = 0; pass < 2; pass++) {
        [text _addDoubleBracketedNVLinkAttributesForRange:range];
        Check(SchemeReads == pass + 1, @"each scan resolves one lazy prefix for all accepted links");
    }
    NSRange unicode = [plain rangeOfString:@"Café / A&B"];
    NSString *expected = [(development ? @"nvalt-dev" : @"nvalt") stringByAppendingString:@"://find/Caf%C3%A9%20%2F%20A%26B"];
    Check([[[text attribute:NSLinkAttributeName atIndex:unicode.location effectiveRange:NULL] absoluteString] isEqual:expected],
          @"unicode and reserved characters retain production escaping and build scheme");
    for (NSString *unlinked in @[@"outside", @"leading", @"after"]) {
        Check([text attribute:NSLinkAttributeName atIndex:[plain rangeOfString:unlinked].location effectiveRange:NULL] == nil,
              @"range boundaries and rejected links remain untouched");
    }
    __block NSUInteger links = 0;
    [text enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [text length]) options:0
                 usingBlock:^(id value, NSRange linkRange, BOOL *stop) { if (value) links++; }];
    Check(links == 2, @"only the two accepted links receive attributes");
    printf("PASS: wiki negative/ranged/unicode checks; two scans resolved two prefixes\n");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 3, @"expected temporary root and flavor");
        NSString *flavor = [NSString stringWithUTF8String:argv[2]];
        TestRoot = [[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:flavor];
        BOOL development = [flavor isEqual:@"development"];
        Check(NVIsDevelopmentBuild() == development, @"copied bundle flavor and absent metadata fallback");
        BackupChecks(development);
        WikiChecks(development);
        Check(NSApp == nil, @"no application or GUI session exists");
        printf("PASS: %s (%lu assertions)\n", [flavor UTF8String], (unsigned long)Checks);
    }
    return 0;
}
