#import <Cocoa/Cocoa.h>
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "DeletedNoteObject.h"
#import "NSString_NV.h"
#import "NSData_transformations.h"

static void Check(BOOL result, NSString *description);
static NSUInteger OfflineKeychainCleanupCalls;

// The old setter calls removeKeychainData even for inKeychain:NO. Intercept that
// unrelated boundary, while inheriting the real passphrase and cipher methods.
@interface NVEncryptedFixturePrefs : NotationPrefs
@end
@implementation NVEncryptedFixturePrefs
- (void)removeKeychainData { OfflineKeychainCleanupCalls++; }
- (Class)classForKeyedArchiver { return [NotationPrefs class]; }
- (Class)classForCoder { return [NotationPrefs class]; }
- (SecKeychainItemRef)currentKeychainItem { [NSException raise:@"UnexpectedKeychainAccess" format:@"Fixture must not access keychain"]; return NULL; }
- (NSData *)passwordDataFromKeychain { [NSException raise:@"UnexpectedKeychainAccess" format:@"Fixture must not access keychain"]; return nil; }
- (void)setKeychainData:(NSData *)data { [NSException raise:@"UnexpectedKeychainAccess" format:@"Fixture must not access keychain"]; }
@end

@interface NSObject (NVOldEncryptedFixtureMethods)
+ (NSString *)serviceName;
- (BOOL)syncServiceIsEnabled:(NSString *)name;
- (NSDictionary *)syncServicesMD;
- (NSSet *)deletedNotes;
@end
@interface FrozenNotation (NVOldEncryptedWriter)
+ (NSData *)frozenDataWithExistingNotes:(NSMutableArray *)notes deletedNotes:(NSMutableSet *)deleted prefs:(NotationPrefs *)prefs;
@end

static NSData *FixturePassphrase(void) { return [@"synthetic round two café password" dataUsingEncoding:NSUTF8StringEncoding]; }
static NSString *FixtureSource(void) { return @"\uFEFF<h1>Encrypted fixture 日本語 😀</h1>\r\n\t<p>café &amp; £</p>\n"; }
static CFUUIDBytes FixtureUUID(void) { return (CFUUIDBytes){0x29,0x38,0x47,0x56,0x65,0x74,0x83,0x92,0xa1,0xb0,0xc9,0xd8,0xe7,0xf6,0x15,0x24}; }
static NSData *FixtureSourceBytes(void) {
    const UInt8 bom[] = {0xff,0xfe,0x00,0x00};
    NSMutableData *data = [NSMutableData dataWithBytes:bom length:sizeof(bom)];
    [data appendData:[FixtureSource() dataUsingEncoding:NSUTF32LittleEndianStringEncoding]];
    return data;
}
static NSDictionary *FixtureSyntax(void) { return @{@"syntax": @"html"}; }
static BOOL HasArchiveKey(NSData *data, NSString *key) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    for (id object in [plist objectForKey:@"$objects"])
        if ([object isKindOfClass:[NSDictionary class]] && [object objectForKey:key]) return YES;
    return NO;
}
static void CheckLocalSource(NoteObject *note, NotationPrefs *prefs) {
    CFUUIDBytes uuid = FixtureUUID();
    Check(memcmp([note uniqueNoteIDBytes],&uuid,sizeof(uuid)) == 0 && [note logSequenceNumber] == 23,
        @"encrypted note retains its fixed UUID and journal sequence");
    Check([[[note contentString] string] isEqual:FixtureSource()] && [[note valueForKey:@"titleString"] isEqual:@"Encrypted local source"] &&
          [[note valueForKey:@"labelString"] isEqual:@"local, café"] && [[note valueForKey:@"createdDate"] doubleValue] == 711234500.25 &&
          [[note valueForKey:@"modifiedDate"] doubleValue] == 711234567.75,
          @"encrypted note retains exact Unicode, whitespace, title, tags, and dates");
    Check([[note sourceDataReturningError:NULL] isEqual:FixtureSourceBytes()] &&
          [[note valueForKey:@"sourceOriginalData"] isEqual:FixtureSourceBytes()] &&
          (uint32_t)[[note valueForKey:@"fileEncoding"] unsignedLongLongValue] == (uint32_t)NSUTF32LittleEndianStringEncoding &&
          [[note valueForKey:@"sourceByteOrderMark"] isEqual:[FixtureSourceBytes() subdataWithRange:NSMakeRange(0,4)]],
          @"UTF-32 original bytes, transport BOM, and literal leading U+FEFF survive together");
    Check([[prefs sourceMetadataForNoteUUID:[NSString uuidStringWithBytes:uuid]] isEqual:FixtureSyntax()],
          @"local syntax remains associated with the same note UUID");
}

// Use the explicit no-UI decrypt method. This is the same passphrase verifier
// used by the prompt, followed by the app's normal archive decryption method.
static FrozenNotation *ReadEncryptedArchive(NSData *data, BOOL legacyRemoteFields) {
    FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    NotationPrefs *prefs = [frozen notationPrefs];
    Check([prefs doesEncryption] && ![prefs storesPasswordInKeychain], @"archive retains encryption without a keychain password");
    Check(HasArchiveKey(data,@"syncServiceAccounts") == legacyRemoteFields && HasArchiveKey(data,@"deletedNoteSet") == legacyRemoteFields,
          @"outer obsolete account and tombstone fields match this archive generation");
    Check(HasArchiveKey(data,@"sourceMetadataByNoteUUID") && !HasArchiveKey(data,@"sourceOriginalData"),
          @"syntax stays in public library preferences while original source data stays in the note payload");
    Check([data rangeOfData:FixtureSourceBytes() options:0 range:NSMakeRange(0,[data length])].location == NSNotFound &&
          [data rangeOfData:[FixtureSource() dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0,[data length])].location == NSNotFound,
          @"outer archive contains neither exact source bytes nor the literal UTF-8 source marker");
    NSData *ciphertext = [[[frozen valueForKey:@"notesData"] copy] autorelease];
    Check(![prefs canLoadPassphraseData:[@"wrong synthetic round two password" dataUsingEncoding:NSUTF8StringEncoding]],
          @"wrong passphrase is rejected by the original verifier");
    Check([prefs valueForKey:@"masterKey"] == nil, @"rejected passphrase does not install a master key");
    OSStatus error = noErr;
    Check([frozen unpackedNotesWithPrefs:prefs returningError:&error] == nil && error == kNoAuthErr,
          @"archive cannot release notes without an accepted passphrase");
    Check([[frozen valueForKey:@"notesData"] isEqual:ciphertext], @"failed no-key read leaves ciphertext intact for a retry");
    Check([prefs canLoadPassphraseData:FixturePassphrase()], @"correct synthetic passphrase succeeds after the rejected attempt");
    NSArray *notes = [frozen unpackedNotesWithPrefs:prefs returningError:&error];
    Check(error == noErr && [notes count] == 1, @"correct passphrase restores exactly one local note");
    CheckLocalSource([notes firstObject],prefs);
    Check(HasArchiveKey([frozen valueForKey:@"notesData"],@"syncServicesMD") == legacyRemoteFields,
          @"decrypted note metadata matches the original or rewritten archive generation");
    Check(![[frozen valueForKey:@"notesData"] isEqual:ciphertext], @"successful read actually decrypts and unpacks the note payload");
    return frozen;
}
