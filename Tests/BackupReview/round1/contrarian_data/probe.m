#import <Cocoa/Cocoa.h>
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "NVBackupArchive.h"

static NSUInteger checks;
static void Check(BOOL value, NSString *label) {
    if (!value) { NSLog(@"FAIL: %@", label); exit(1); }
    checks++;
}
static NoteObject *MakeNote(NSString *source) {
    return [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:source] autorelease]
        title:@"Disposable source fixture" delegate:nil format:PlainTextFormat labels:@"one, two"] autorelease];
}
static NSArray *Unpack(NSDictionary *restored, NSData *password) {
    Check(restored != nil, @"recovery produced a prepared archive");
    FrozenNotation *archive = [NSKeyedUnarchiver unarchiveObjectWithData:restored[@"data"]];
    NotationPrefs *prefs = [archive notationPrefs];
    if ([prefs doesEncryption]) Check([prefs canLoadPassphraseData:password], @"restored archive retains its password");
    OSStatus status = noErr;
    NSArray *notes = [archive unpackedNotesWithPrefs:prefs returningError:&status];
    Check(status == noErr && notes != nil, @"restored bytes decode independently");
    return notes;
}
int main(void) { @autoreleasepool {
    // Retain original bytes, line endings, BOM, and export behavior across restore.
    NSStringEncoding encodings[] = {NSUTF8StringEncoding, NSUTF16LittleEndianStringEncoding,
        NSUTF16BigEndianStringEncoding, NSUTF32LittleEndianStringEncoding,
        NSUTF32BigEndianStringEncoding, NSMacOSRomanStringEncoding};
    for (NSUInteger i = 0; i < sizeof(encodings) / sizeof(encodings[0]); i++) {
        for (NSUInteger withBOM = 0; withBOM < (i == 5 ? 1 : 2); withBOM++) {
        @autoreleasepool {
            NSString *source = @"caf\u00e9\r\nsecond line\r\n";
            NSData *body = [source dataUsingEncoding:encodings[i]];
            const unsigned char marks[][4] = {{0xef,0xbb,0xbf,0}, {0xff,0xfe,0,0},
                {0xfe,0xff,0,0}, {0xff,0xfe,0,0}, {0,0,0xfe,0xff}};
            const NSUInteger markLengths[] = {3,2,2,4,4};
            NSMutableData *bytes = [NSMutableData data];
            if (withBOM) [bytes appendBytes:marks[i] length:markLengths[i]];
            [bytes appendData:body];
            Check(bytes != nil, @"fixture encoding is representable");
            NoteObject *note = MakeNote(source);
            [note rememberSourceData:bytes encoding:encodings[i]];
            NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
            [prefs prepareForOfflineBackupRestore];
            [prefs setNotesStorageFormat:PlainTextFormat];
            [prefs setSourceMetadata:@{@"syntax": @"json"} forNoteUUID:[note sourceMetadataUUID]];
            NSData *archive = [FrozenNotation frozenDataWithExistingNotes:[NSMutableArray arrayWithObject:note] prefs:prefs];
            NSError *error = nil;
            NSDictionary *restored = [NVBackupArchive restoredArchiveFromData:archive error:&error];
            NoteObject *copy = [Unpack(restored, nil) objectAtIndex:0];
            Check([[[copy contentString] string] isEqualToString:source], @"CRLF and Unicode source survive");
            Check([[copy sourceDataReturningError:&error] isEqualToData:bytes] && !error, @"export remains byte-exact after recovery");
            Check([[copy valueForKey:@"sourceOriginalData"] isEqual:bytes], @"archived original source data survives");
            Check((uint32_t)[[copy valueForKey:@"fileEncoding"] unsignedLongLongValue] == (uint32_t)encodings[i], @"32-bit encoding identity survives recovery");
            Check([[[restored objectForKey:@"unlockedPrefs"] sourceMetadataForNoteUUID:[copy sourceMetadataUUID]] isEqual:@{@"syntax": @"json"}], @"syntax stays associated with note UUID");
        }
    }
        }
    // Password rotation must not silently rewrite old history or require the new password.
    NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
    [prefs prepareForOfflineBackupRestore];
    NSData *oldPassword = [@"old disposable password" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *newPassword = [@"new disposable password" dataUsingEncoding:NSUTF8StringEncoding];
    NoteObject *note = MakeNote(@"first source\n");
    NSMutableArray *notes = [NSMutableArray arrayWithObject:note];
    NSData *plainArchive = [[FrozenNotation frozenDataWithExistingNotes:notes prefs:prefs] copy];
    [prefs setPassphraseData:oldPassword inKeychain:NO]; [prefs setDoesEncryption:YES];
    NSData *oldArchive = [[FrozenNotation frozenDataWithExistingNotes:notes prefs:prefs] copy];
    NSData *oldBytes = [[oldArchive copy] autorelease];
    [prefs setPassphraseData:newPassword inKeychain:NO];
    NSData *newArchive = [FrozenNotation frozenDataWithExistingNotes:notes prefs:prefs];
    NSError *error = nil;
    Check(![NVBackupArchive restoredArchiveFromData:oldArchive passphraseData:newPassword error:&error] && error, @"new password cannot open old backup");
    Check(![NVBackupArchive restoredArchiveFromData:newArchive passphraseData:oldPassword error:&error] && error, @"old password cannot open new backup");
    for (NSUInteger attempt = 0; attempt < 2; attempt++) {
        NSDictionary *restored = [NVBackupArchive restoredArchiveFromData:oldArchive passphraseData:oldPassword error:&error];
        Check([Unpack(restored, oldPassword) count] == 1, @"old backup remains reusable after password rotation");
        Check(![[restored objectForKey:@"unlockedPrefs"] storesPasswordInKeychain], @"restore does not enable keychain storage");
    }
    Check([oldArchive isEqualToData:oldBytes], @"offline restore never mutates input archive bytes");
    NSDictionary *newRestored = [NVBackupArchive restoredArchiveFromData:newArchive passphraseData:newPassword error:&error];
    Check([Unpack(newRestored, newPassword) count] == 1, @"new backup accepts its own password");
    NSDictionary *plainRestored = [NVBackupArchive restoredArchiveFromData:plainArchive error:&error];
    Check(plainRestored && ![plainRestored[@"encrypted"] boolValue], @"enabling encryption does not rewrite plaintext history");
    [plainArchive release]; [oldArchive release];

    // A duplicated model object is a simple invalid library fixture, with no crafted decoder.
    NotationPrefs *duplicatePrefs = [[[NotationPrefs alloc] init] autorelease];
    NSData *duplicateArchive = [FrozenNotation frozenDataWithExistingNotes:[NSMutableArray arrayWithObjects:note, note, nil] prefs:duplicatePrefs];
    Check(![NVBackupArchive restoredArchiveFromData:duplicateArchive error:&error] && [error code] == 14,
        @"duplicate note identity rejected before restore setup");
    NSLog(@"CONTRARIAN DATA REVIEW PASS: %lu checks; native AES provider; no application lifecycle", (unsigned long)checks);
    return 0;
}}
