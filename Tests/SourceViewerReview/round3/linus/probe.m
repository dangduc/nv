#import <Cocoa/Cocoa.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Block.h>

static NSUInteger checks = 0, failures = 0;
#define Check(condition, label) do { checks++; if (!(condition)) { failures++; fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__); } } while (0)
#define VAR_STR(variable) @#variable

@interface NSFileManager (ReviewEncoding)
- (NSStringEncoding)textEncodingAttributeOfFSPath:(const char*)path;
@end
@implementation NSFileManager (ReviewEncoding)
- (NSStringEncoding)textEncodingAttributeOfFSPath:(const char*)path { return 0; }
@end

/* BOM */
@interface SourceNote : NSObject <NSCoding> {
@public
    NSData *sourceOriginalData, *sourceByteOrderMark, *sourceConflictOriginUUID;
    NSStringEncoding sourceOriginalEncoding, fileEncoding;
    NSMutableAttributedString *contentString;
    CFUUIDBytes uuid;
    BOOL sourceConversionPending, shouldWriteToFile;
}
- (CFUUIDBytes*)uniqueNoteIDBytes;
- (void)rememberSourceData:(NSData*)data encoding:(NSStringEncoding)encoding;
- (NSData*)sourceDataReturningError:(NSError**)error;
+ (NSString*)sourceStringFromData:(NSData*)data encoding:(NSStringEncoding*)encoding path:(NSString*)path;
@end
// The extracted provenance selectors keep their production parameter type.
#define NoteObject SourceNote
@implementation SourceNote
- (id)init {
    if ((self = [super init])) {
        CFUUIDRef identity = CFUUIDCreate(NULL); uuid = CFUUIDGetUUIDBytes(identity); CFRelease(identity);
        contentString = [[NSMutableAttributedString alloc] initWithString:@""];
        fileEncoding = NSUTF8StringEncoding;
    }
    return self;
}
- (void)dealloc { [sourceOriginalData release]; [sourceByteOrderMark release]; [sourceConflictOriginUUID release]; [contentString release]; [super dealloc]; }
- (CFUUIDBytes*)uniqueNoteIDBytes { return &uuid; }
/* DECODE */
/* BYTES */
/* PROVENANCE */
- (void)encodeWithCoder:(NSCoder*)coder {
/* ARCHIVE_WRITE */
    [coder encodeBytes:(const uint8_t*)&uuid length:sizeof(uuid) forKey:@"uuid"];
    [coder encodeObject:contentString forKey:@"content"];
}
- (id)initWithCoder:(NSCoder*)decoder {
    if ((self = [self init])) {
/* ARCHIVE_READ */
        NSUInteger size = 0;
        const uint8_t *bytes = [decoder decodeBytesForKey:@"uuid" returnedLength:&size];
        if (size == sizeof(uuid)) memcpy(&uuid, bytes, size);
        [contentString release]; contentString = [[decoder decodeObjectForKey:@"content"] mutableCopy];
    }
    return self;
}
@end
#undef NoteObject

static NSUInteger noteDeallocs = 0, libraryDeallocs = 0, upgrades = 0;
@class RequestLibrary;
@interface RequestNote : NSObject { @public RequestLibrary *library; CFUUIDBytes uuid; BOOL representable; }
- (RequestLibrary*)delegate;
- (CFUUIDBytes*)uniqueNoteIDBytes;
- (NSData*)sourceDataReturningError:(NSError**)error;
- (void)upgradeEncodingToUTF8;
@end
@implementation RequestNote
- (id)init { if ((self = [super init])) { CFUUIDRef value = CFUUIDCreate(NULL); uuid = CFUUIDGetUUIDBytes(value); CFRelease(value); } return self; }
- (RequestLibrary*)delegate { return library; }
- (CFUUIDBytes*)uniqueNoteIDBytes { return &uuid; }
- (NSData*)sourceDataReturningError:(NSError**)error { return representable ? [NSData data] : nil; }
- (void)upgradeEncodingToUTF8 { upgrades++; }
- (void)dealloc { noteDeallocs++; [super dealloc]; }
@end
@interface RequestLibrary : NSObject { @public RequestNote *liveNote; }
- (RequestNote*)noteForUUIDBytes:(CFUUIDBytes*)bytes;
@end
@implementation RequestLibrary
- (RequestNote*)noteForUUIDBytes:(CFUUIDBytes*)bytes { return liveNote && memcmp(bytes, &liveNote->uuid, sizeof(*bytes)) == 0 ? liveNote : nil; }
- (void)dealloc { libraryDeallocs++; [super dealloc]; }
@end
static RequestLibrary *currentLibrary;
@interface ReviewCoordinator : NSObject
+ (id)sharedController;
- (RequestLibrary*)library;
@end
@implementation ReviewCoordinator
+ (id)sharedController { static id controller; if (!controller) controller = [[self alloc] init]; return controller; }
- (RequestLibrary*)library { return currentLibrary; }
@end
@interface ReviewApplication : NSObject
- (NSWindow*)mainWindow;
- (NSWindow*)keyWindow;
@end
@implementation ReviewApplication
- (NSWindow*)mainWindow { return (NSWindow*)self; }
- (NSWindow*)keyWindow { return nil; }
@end
static ReviewApplication *ReviewApp;
static NSMutableArray *alerts;
@interface ReviewAlert : NSObject { void (^callback)(NSModalResponse); }
- (void)setMessageText:(NSString*)value;
- (void)setInformativeText:(NSString*)value;
- (void)addButtonWithTitle:(NSString*)value;
- (void)beginSheetModalForWindow:(NSWindow*)window completionHandler:(void (^)(NSModalResponse))handler;
- (NSModalResponse)runModal;
- (void)complete:(NSModalResponse)response;
@end
@implementation ReviewAlert
- (void)setMessageText:(NSString*)value {}
- (void)setInformativeText:(NSString*)value {}
- (void)addButtonWithTitle:(NSString*)value {}
- (void)beginSheetModalForWindow:(NSWindow*)window completionHandler:(void (^)(NSModalResponse))handler { callback = Block_copy(handler); [alerts addObject:self]; }
- (NSModalResponse)runModal { return NSAlertSecondButtonReturn; }
- (void)complete:(NSModalResponse)response { if (callback) { callback(response); Block_release(callback); callback = nil; } }
- (void)dealloc { if (callback) Block_release(callback); [super dealloc]; }
@end
static NSString *titleOfNote(RequestNote *note) { return @"Disposable ownership fixture"; }
@interface RequestManager : NSObject { NSMutableDictionary *pendingConversionRequests; }
- (void)offerUTF8ConversionForNote:(RequestNote*)note;
- (void)cancelUTF8ConversionForNote:(RequestNote*)note;
- (void)presentUTF8Conversion:(NSArray*)request;
- (NSUInteger)count;
@end
@implementation RequestManager
/* REQUESTS */
- (NSUInteger)count { return [pendingConversionRequests count]; }
- (void)dealloc { [pendingConversionRequests release]; [super dealloc]; }
@end

static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
static NSData *Bytes(NSString *text, NSStringEncoding encoding, NSData *bom) {
    NSMutableData *result = [NSMutableData dataWithData:bom ?: [NSData data]];
    [result appendData:[text dataUsingEncoding:encoding allowLossyConversion:NO]];
    return result;
}
static SourceNote *Note(NSString *text, NSStringEncoding encoding, NSData *bytes) {
    SourceNote *note = [[[SourceNote alloc] init] autorelease];
    [note->contentString replaceCharactersInRange:NSMakeRange(0, [note->contentString length]) withString:text];
    [note rememberSourceData:bytes encoding:encoding];
    return note;
}
static SourceNote *RoundTrip(SourceNote *note) {
    return [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:note]];
}

static void SourceChecks(void) {
    NSArray *encodings = @[@(NSUTF8StringEncoding), @(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding), @(NSUTF32LittleEndianStringEncoding), @(NSUTF32BigEndianStringEncoding)];
    const unsigned char b8[] = {0xef,0xbb,0xbf}, b16l[] = {0xff,0xfe}, b16b[] = {0xfe,0xff}, b32l[] = {0xff,0xfe,0,0}, b32b[] = {0,0,0xfe,0xff};
    NSArray *boms = @[[NSData dataWithBytes:b8 length:3], [NSData dataWithBytes:b16l length:2], [NSData dataWithBytes:b16b length:2], [NSData dataWithBytes:b32l length:4], [NSData dataWithBytes:b32b length:4]];
    unichar nulFixture[] = { 'A', 0, 'B', '\r', '\n', 0xd83d, 0xde00 };
    NSArray *texts = @[@"", @"A", @"\uFEFF", @"\uFEFF\uFEFFprefix\r\n", @"é中😀\r\nlast\r", [NSString stringWithCharacters:nulFixture length:7]];
    SourceNote *origin = [[[SourceNote alloc] init] autorelease];
    SourceNote *other = [[[SourceNote alloc] init] autorelease];
    for (NSUInteger i = 0; i < [encodings count]; i++) {
        NSStringEncoding encoding = [encodings[i] unsignedIntegerValue];
        for (NSString *text in texts) {
            NSData *bytes = Bytes(text, encoding, boms[i]);
            NSStringEncoding hint = NSMacOSRomanStringEncoding;
            NSString *decoded = [SourceNote sourceStringFromData:bytes encoding:&hint path:nil];
            Check([decoded isEqualToString:text] && hint == encoding, "BOM, literal marks, embedded NUL and surrogate pair decode exactly");
            SourceNote *note = Note(decoded, hint, bytes);
            [note markAsSourceConflictCopyOfNote:origin];
            note->sourceConversionPending = YES;
            NSMutableData *mutableInput = [NSMutableData dataWithData:bytes];
            [note rememberSourceData:mutableInput encoding:encoding];
            [mutableInput setLength:0];
            Check([[note sourceDataReturningError:NULL] isEqualToData:bytes], "rememberSourceData copies a mutable input");
            SourceNote *restored = RoundTrip(note);
            Check(restored->sourceConversionPending && restored->shouldWriteToFile, "pending conversion survives normal keyed archive recovery");
            Check([restored isSourceConflictCopyOfNote:origin data:bytes encoding:encoding], "archive conflict provenance matches origin and exact bytes across encoding signedness");
            Check(![restored isSourceConflictCopyOfNote:other data:bytes encoding:encoding], "matching bytes never match a different origin UUID");
            Check([[restored sourceDataReturningError:NULL] isEqualToData:bytes], "unchanged archived Unicode note preserves original bytes");
            NSString *edited = [text stringByAppendingString:@" changed😀\r\n"];
            [restored->contentString appendAttributedString:[[[NSAttributedString alloc] initWithString:@" changed😀\r\n"] autorelease]];
            NSData *editedBytes = Bytes(edited, encoding, boms[i]);
            Check([[restored sourceDataReturningError:NULL] isEqualToData:editedBytes], "edited archive retains encoding, BOM, literal marks, embedded NUL and line endings");
            Check(![restored isSourceConflictCopyOfNote:origin data:bytes encoding:encoding], "edited conflict content cannot authorize reuse of the old copy");
        }
    }
    // Untagged, unmarked UTF-8 should not gain a BOM when edited.
    for (NSString *text in @[@"", @"plain\r\n", @"é中😀", [NSString stringWithCharacters:nulFixture length:7]]) {
        NSData *bytes = Bytes(text, NSUTF8StringEncoding, nil);
        SourceNote *note = Note(text, NSUTF8StringEncoding, bytes);
        [note->contentString appendAttributedString:[[[NSAttributedString alloc] initWithString:@"X"] autorelease]];
        Check([[note sourceDataReturningError:NULL] isEqualToData:Bytes([text stringByAppendingString:@"X"], NSUTF8StringEncoding, nil)], "unmarked UTF-8 remains unmarked after edit");
    }
    SourceNote *plain = Note(@"plain", NSASCIIStringEncoding, [@"plain" dataUsingEncoding:NSASCIIStringEncoding]);
    NSError *error = [NSError errorWithDomain:@"sentinel" code:99 userInfo:nil];
    Check([plain sourceDataReturningError:&error] != nil && error == nil, "successful byte conversion clears a caller's stale error");
    [plain->contentString appendAttributedString:[[[NSAttributedString alloc] initWithString:@"😀"] autorelease]];
    Check([plain sourceDataReturningError:&error] == nil && [[error domain] isEqualToString:@"NVSourceEncodingError"], "unrepresentable source reports conversion error without lossy bytes");
    Check([plain sourceDataReturningError:NULL] == nil, "unrepresentable source accepts a nullable error output");
}

static void LegacyAliasChecks(void) {
    const unsigned char aliasBytes[] = {0xa3, 0xa0};
    NSStringEncoding encoding = 0x80000632; // GB 18030, in the application's supported encoding menu.
    NSData *bytes = [NSData dataWithBytes:aliasBytes length:2];
    NSString *source = [SourceNote sourceStringFromData:bytes encoding:&encoding path:nil];
    SourceNote *origin = [[[SourceNote alloc] init] autorelease];
    SourceNote *note = Note(source, encoding, bytes);
    [note markAsSourceConflictCopyOfNote:origin];
    Check([source isEqualToString:@"\u3000"], "GB 18030 alias fixture decodes to an ordinary ideographic space");
    Check([[note sourceDataReturningError:NULL] isEqualToData:bytes], "unarchived legacy alias retains its exact source bytes");
    SourceNote *restored = RoundTrip(note);
    NSData *output = [restored sourceDataReturningError:NULL];
    fprintf(stdout, "ALIAS ARCHIVE: encoding=%lx restored=%lx before=%s after=%s provenance=%d\n", (unsigned long)encoding, (unsigned long)restored->fileEncoding, [[bytes description] UTF8String], [[output description] UTF8String], [restored isSourceConflictCopyOfNote:origin data:bytes encoding:encoding]);
    Check([output isEqualToData:bytes], "archived unchanged GB 18030 alias retains exact source bytes");
    Check([restored isSourceConflictCopyOfNote:origin data:bytes encoding:encoding], "archived GB 18030 conflict retains retry identity");
}

static void RequestChecks(void) {
    ReviewApp = [[ReviewApplication alloc] init]; alerts = [[NSMutableArray alloc] init];
    RequestManager *manager = [[RequestManager alloc] init];
    // A queued request owns its note and library, and cancellation releases both after the run loop drains.
    NSUInteger oldNotes = noteDeallocs, oldLibraries = libraryDeallocs;
    @autoreleasepool {
        RequestLibrary *library = [[RequestLibrary alloc] init];
        RequestNote *note = [[RequestNote alloc] init]; note->library = library; library->liveNote = note; currentLibrary = library;
        for (NSUInteger i = 0; i < 100; i++) [manager offerUTF8ConversionForNote:note];
        Check([manager count] == 1, "100 duplicate offers retain one request token");
        [manager cancelUTF8ConversionForNote:note];
        Check([manager count] == 0, "cancel removes the pending token synchronously");
        currentLibrary = nil; library->liveNote = nil; [note release]; [library release]; Pump();
        Check([alerts count] == 0, "cancelled queued offer never presents a sheet");
    }
    Check(noteDeallocs == oldNotes + 1 && libraryDeallocs == oldLibraries + 1, "cancelled queue releases both note and library ownership");
    [manager release]; manager = [[RequestManager alloc] init];
    // A displayed request retains its objects until its copied completion is released.
    oldNotes = noteDeallocs; oldLibraries = libraryDeallocs;
    @autoreleasepool {
        RequestLibrary *library = [[RequestLibrary alloc] init];
        RequestNote *note = [[RequestNote alloc] init]; note->library = library; library->liveNote = note; currentLibrary = library;
        [manager offerUTF8ConversionForNote:note]; Pump();
        Check([alerts count] == 1 && [manager count] == 1, "one live offer presents one copied completion");
        [manager cancelUTF8ConversionForNote:note];
        [manager offerUTF8ConversionForNote:note]; Pump();
        Check([alerts count] == 2 && [manager count] == 1, "cancel and reoffer creates a distinct active request");
        NSUInteger before = upgrades;
        [(ReviewAlert*)[alerts objectAtIndex:0] complete:NSAlertFirstButtonReturn];
        Check(upgrades == before && [manager count] == 1, "old retained completion neither upgrades nor removes the new request");
        if ([alerts count] > 1) [(ReviewAlert*)[alerts objectAtIndex:1] complete:NSAlertFirstButtonReturn];
        Check(upgrades == before + 1 && [manager count] == 0, "current completion upgrades once and clears its request");
        [alerts removeAllObjects];
        currentLibrary = nil; library->liveNote = nil; [note release]; [library release]; Pump();
    }
    Check(noteDeallocs == oldNotes + 1 && libraryDeallocs == oldLibraries + 1, "completed sheet closures leave no retained note or library");
    // A queued offer whose source becomes representable ends without allocating a sheet.
    oldNotes = noteDeallocs; oldLibraries = libraryDeallocs;
    @autoreleasepool {
        RequestLibrary *library = [[RequestLibrary alloc] init];
        RequestNote *note = [[RequestNote alloc] init]; note->library = library; library->liveNote = note; currentLibrary = library;
        [manager offerUTF8ConversionForNote:note]; note->representable = YES; Pump();
        Check([manager count] == 0 && [alerts count] == 0, "representable queued source releases request without presentation");
        currentLibrary = nil; library->liveNote = nil; [note release]; [library release]; Pump();
    }
    Check(noteDeallocs == oldNotes + 1 && libraryDeallocs == oldLibraries + 1, "early success releases request-owned note and library");
    [manager release]; [alerts release]; alerts = nil; [ReviewApp release]; ReviewApp = nil;
}
int main(void) {
    @autoreleasepool { SourceChecks(); RequestChecks(); LegacyAliasChecks(); }
    fprintf(stdout, "%s: checks=%lu failures=%lu note-deallocs=%lu library-deallocs=%lu upgrades=%lu\n", failures ? "FAIL" : "PASS", (unsigned long)checks, (unsigned long)failures, (unsigned long)noteDeallocs, (unsigned long)libraryDeallocs, (unsigned long)upgrades);
    return failures ? 1 : 0;
}
