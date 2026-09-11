// The runner inserts the production keychain and automatic import methods below.
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import "NVAppIdentity.h"
#import "Sources/ImportExport/TemporaryFileCachePreparer.m"

static NSString *ExpectedService;
static NSString *ExpectedAccount;
static BOOL ExistingItem;
static unsigned Finds, Adds, Modifies, Deletes, FreedContents;

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void CheckIdentity(UInt32 serviceLength, const char *service, UInt32 accountLength, const char *account) {
    NSString *serviceValue = [[[NSString alloc] initWithBytes:service length:serviceLength encoding:NSUTF8StringEncoding] autorelease];
    NSString *accountValue = [[[NSString alloc] initWithBytes:account length:accountLength encoding:NSUTF8StringEncoding] autorelease];
    Check([serviceValue isEqual:ExpectedService], @"keychain call uses the current flavor's service");
    Check([accountValue isEqual:ExpectedAccount], @"keychain call preserves the library account identifier");
}
static OSStatus ProbeFind(CFTypeRef keychain, UInt32 serviceLength, const char *service,
                         UInt32 accountLength, const char *account, UInt32 *length, void **bytes,
                         SecKeychainItemRef *item) {
    Finds++;
    CheckIdentity(serviceLength, service, accountLength, account);
    if (!ExistingItem) return errSecItemNotFound;
    if (item) *item = (SecKeychainItemRef)CFRetain(CFSTR("probe-item"));
    if (bytes) { *bytes = strdup("test-secret"); if (length) *length = 11; }
    return noErr;
}
static OSStatus ProbeAdd(SecKeychainRef keychain, UInt32 serviceLength, const char *service,
                        UInt32 accountLength, const char *account, UInt32 length, const void *bytes,
                        SecKeychainItemRef *item) {
    Adds++;
    CheckIdentity(serviceLength, service, accountLength, account);
    return noErr;
}
static OSStatus ProbeModify(SecKeychainItemRef item, const SecKeychainAttributeList *attributes,
                           UInt32 length, const void *bytes) {
    Modifies++;
    const SecKeychainAttribute *service = NULL, *account = NULL;
    for (UInt32 index = 0; index < attributes->count; index++) {
        const SecKeychainAttribute *attribute = &attributes->attr[index];
        if (attribute->tag == kSecServiceItemAttr) service = attribute;
        if (attribute->tag == kSecAccountItemAttr) account = attribute;
    }
    Check(service && account, @"updates retain service and account attributes");
    CheckIdentity(service->length, service->data, account->length, account->data);
    return noErr;
}
static OSStatus ProbeDelete(SecKeychainItemRef item) { Deletes++; return noErr; }
static OSStatus ProbeFree(SecKeychainAttributeList *attributes, void *bytes) {
    FreedContents++;
    Check(!memcmp(bytes, "\0\0\0\0\0\0\0\0\0\0\0", 11), @"retrieved password buffer was cleared");
    free(bytes);
    return noErr;
}

#define SecKeychainFindGenericPassword ProbeFind
#define SecKeychainAddGenericPassword ProbeAdd
#define SecKeychainItemModifyAttributesAndData ProbeModify
#define SecKeychainItemDelete ProbeDelete
#define SecKeychainItemFreeContent ProbeFree
@SERVICE@

@interface NVKeychainProbe : NSObject {
    NSString *keychainDatabaseIdentifier;
    BOOL preferencesChanged, storesPasswordInKeychain, offlineBackupRestore;
}
- (const char *)setKeychainIdentifier;
- (SecKeychainItemRef)currentKeychainItem;
- (void)removeKeychainData;
- (NSData *)passwordDataFromKeychain;
- (void)setKeychainData:(NSData *)data;
- (void)setStoresPasswordInKeychain:(BOOL)value;
@end
@implementation NVKeychainProbe
@KEYCHAIN@
- (void)dealloc { [keychainDatabaseIdentifier release]; [super dealloc]; }
@end

static unsigned LegacyDefaultsReads, LegacyPathReads, LegacyImports;
static BOOL LegacyAttempted;
static NSString *RetrievedPasswordKey = @"unused-password";
static NSString *PasswordWasRetrievedFromKeychainKey = @"unused-keychain";
@interface NSObject (NVLegacyLibraryProbe)
- (void)addNotes:(NSArray *)notes;
@end
@interface NVLegacyPrefs : NSObject
- (BOOL)firstTimeUsed;
- (void)setPassphraseData:(NSData *)data inKeychain:(BOOL)value;
- (void)setDoesEncryption:(BOOL)value;
@end
@implementation NVLegacyPrefs
- (BOOL)firstTimeUsed { return YES; }
- (void)setPassphraseData:(NSData *)data inKeychain:(BOOL)value { Check(NO, @"empty import cannot set a passphrase"); }
- (void)setDoesEncryption:(BOOL)value { Check(NO, @"empty import cannot enable encryption"); }
@end
@interface NVLegacyGlobalPrefs : NSObject
+ (id)defaultPrefs;
- (id)notationPrefs;
- (BOOL)triedToImportBlor;
- (void)setBlorImportAttempted:(BOOL)value;
@end
@implementation NVLegacyGlobalPrefs
+ (id)defaultPrefs { LegacyDefaultsReads++; return [[[self alloc] init] autorelease]; }
- (id)notationPrefs { return [[[NVLegacyPrefs alloc] init] autorelease]; }
- (BOOL)triedToImportBlor { return NO; }
- (void)setBlorImportAttempted:(BOOL)value { LegacyAttempted = value; }
@end
@interface NVLegacyImporter : NSObject
+ (id)importerWithPath:(NSString *)path;
+ (NSString *)blorPath;
- (NSArray *)importedNotes;
- (NSDictionary *)documentSettings;
@end
@implementation NVLegacyImporter
+ (id)importerWithPath:(NSString *)path { LegacyImports++; return [[[self alloc] init] autorelease]; }
+ (NSString *)blorPath { LegacyPathReads++; return @"/unused-legacy-file"; }
- (NSArray *)importedNotes { return @[]; }
- (NSDictionary *)documentSettings { Check(NO, @"empty import cannot read password settings"); return nil; }
@LEGACY@
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"expected build flavor argument");
        BOOL development = !strcmp(argv[1], "development");
        Check(NVIsDevelopmentBuild() == development, @"flavor comes from the running bundle");
        NSString *suffix = development ? @"-Development" : @"";
        Check([RAMDiskMountPath() isEqual:[NSTemporaryDirectory() stringByAppendingPathComponent:
              [@"NVProtectedEditingSpace" stringByAppendingString:suffix]]], @"protected external editing path");
        Check([TempDirectoryPathForEditing() isEqual:[NSTemporaryDirectory() stringByAppendingPathComponent:
              [@"NVPlainTextEditingSpace" stringByAppendingString:suffix]]], @"plain text external editing path");

        ExpectedService = development ? @"Notational Velocity Development" : @"Notational Velocity";
        ExpectedAccount = @"LIBRARY-COPIED-FROM-RELEASE";
        NVKeychainProbe *probe = [[[NVKeychainProbe alloc] init] autorelease];
        [probe setValue:ExpectedAccount forKey:@"keychainDatabaseIdentifier"];
        NSData *secret = [@"test-secret" dataUsingEncoding:NSUTF8StringEncoding];
        ExistingItem = NO;
        [probe setKeychainData:secret];
        Check(Finds == 1 && Adds == 1 && !Modifies, @"missing service account creates its own item");
        ExistingItem = YES;
        [probe setKeychainData:secret];
        Check(Finds == 2 && Modifies == 1, @"existing service account updates its own item");
        Check([[probe passwordDataFromKeychain] isEqual:secret], @"password lookup returns captured test bytes");
        Check(Finds == 3 && FreedContents == 1, @"password lookup uses intercepted content cleanup");
        [probe setStoresPasswordInKeychain:NO];
        Check(Finds == 4 && Deletes == 1, @"disabling keychain storage deletes only the selected service item");
        [probe setValue:@YES forKey:@"offlineBackupRestore"];
        [probe setKeychainData:secret];
        [probe removeKeychainData];
        Check(Finds == 4 && Adds == 1 && Modifies == 1 && Deletes == 1, @"offline backup restore remains free of keychain writes");

        [NVLegacyImporter importBlorOrHelpFilesIfNecessaryIntoNotation:nil];
        Check(LegacyDefaultsReads == !development && LegacyPathReads == !development &&
              LegacyImports == !development && LegacyAttempted == !development,
              @"Development skips legacy discovery; release retains first-launch import");
        printf("PASS: runtime flavor %s\n", argv[1]);
    }
    return 0;
}
