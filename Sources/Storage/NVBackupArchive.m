#import "NVBackupArchive.h"
#import "FrozenNotation.h"
#import "NotationPrefs.h"
#import "NoteObject.h"

NSString * const NVBackupArchiveErrorDomain = @"NVBackupArchiveErrorDomain";

static NSError *NVRestoreError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:NVBackupArchiveErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: description}];
}

@implementation NVBackupArchive

+ (NSDictionary*)restoredArchiveFromData:(NSData*)data error:(NSError**)error {
    return [self restoredArchiveFromData:data passphraseData:nil error:error];
}

+ (NSDictionary*)restoredArchiveFromData:(NSData*)data passphraseData:(NSData*)passphrase error:(NSError**)error {
    if (error) *error = nil;
    if (![NSThread isMainThread] || ![data isKindOfClass:[NSData class]] || ![data length]) {
        if (error) *error = NVRestoreError(10, @"The backup archive is empty or recovery is not running on the main thread.");
        return nil;
    }
    @try {
        id decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if (![decoded isKindOfClass:[FrozenNotation class]] || ![[decoded notationPrefs] isKindOfClass:[NotationPrefs class]]) {
            if (error) *error = NVRestoreError(11, @"The backup does not contain a supported library archive.");
            return nil;
        }
        FrozenNotation *archive = decoded;
        NotationPrefs *prefs = [archive notationPrefs];
        BOOL encrypted = [prefs doesEncryption];
        NSDate *captureDate = [[[prefs backupCheckpointDate] copy] autorelease];
        // Never let password retrieval read, alter, or delete the active library's keychain item.
        [prefs prepareForOfflineBackupRestore];
        OSStatus decodeError = noErr;
        NSMutableArray *notes = nil;
        if (encrypted && passphrase) {
            if (![prefs canLoadPassphraseData:passphrase]) {
                if (error) *error = NVRestoreError(kNoAuthErr, @"The backup password is incorrect.");
                return nil;
            }
            notes = [archive unpackedNotesWithPrefs:prefs returningError:&decodeError];
        } else notes = [archive unpackedNotesReturningError:&decodeError];
        if (decodeError != noErr || ![notes isKindOfClass:[NSArray class]]) {
            if (error) *error = decodeError == kPassCanceledErr ?
                [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil] :
                NVRestoreError(decodeError ?: 12, @"The backup note payload could not be decoded.");
            return nil;
        }
        NSMutableSet *identifiers = [NSMutableSet set];
        CFUUIDBytes emptyIdentifier = {0};
        for (id candidate in notes) {
            NoteObject *note = candidate;
            if (![candidate isKindOfClass:[NoteObject class]] ||
                ![note->titleString isKindOfClass:[NSString class]] ||
                (note->labelString && ![note->labelString isKindOfClass:[NSString class]]) ||
                ![[note contentString] isKindOfClass:[NSAttributedString class]]) {
                if (error) *error = NVRestoreError(13, @"The backup contains an invalid note record.");
                return nil;
            }
            NSData *identifier = [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
            if (!memcmp([note uniqueNoteIDBytes], &emptyIdentifier, sizeof(CFUUIDBytes)) || [identifiers containsObject:identifier]) {
                if (error) *error = NVRestoreError(14, @"The backup contains missing or duplicate note identities.");
                return nil;
            }
            [identifiers addObject:identifier];
            [note prepareForBackupRestore];
        }
        [prefs setBackupCheckpointGeneration:1 date:[NSDate date]];
        NSData *restoredData = [FrozenNotation frozenDataWithExistingNotes:notes prefs:prefs];
        if (![restoredData length]) {
            if (error) *error = NVRestoreError(15, @"The restored library archive could not be created.");
            return nil;
        }
        return @{ @"data": [[restoredData copy] autorelease], @"libraryIdentifier": [prefs backupLibraryIdentifier],
            @"noteCount": @([notes count]), @"encrypted": @(encrypted), @"generation": @1,
            @"captureDate": captureDate ?: [NSDate date], @"unlockedPrefs": prefs };
    } @catch (NSException *exception) {
        // Exception text can contain archived note content. Keep recovery errors content-free.
        if (error) *error = NVRestoreError(16, @"The backup archive is damaged or unsupported.");
        return nil;
    }
}
@end
