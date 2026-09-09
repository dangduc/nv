//
//  NotationPrefs.m
//  Notation
//
//  Created by Zachary Schneirov on 4/1/06.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
	 conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission. */

#import "AppController.h"
#import "NotationPrefs.h"
#import "GlobalPrefs.h"
#import "NSString_NV.h"
#import "NSCollection_utils.h"
#import "NotationPrefsViewController.h"
#import "NSData_transformations.h"
#import "NotationFileManager.h"
#import "SecureTextEntryManager.h"
#import "DiskUUIDEntry.h"
#include <CoreServices/CoreServices.h>
#include <Security/Security.h>
#include <ApplicationServices/ApplicationServices.h>

#define DEFAULT_HASH_ITERATIONS 8000
#define DEFAULT_KEY_LENGTH 256

#define KEYCHAIN_SERVICENAME "Notational Velocity"

NSString *NotationPrefsDidChangeNotification = @"NotationPrefsDidChangeNotification";

static BOOL NVUnsupportedSourceExtension(NSString *extension) {
	return [extension length] && [@[@"rtf", @"rtfd", @"rtx", @"html", @"htm", @"shtml", @"xhtml", @"xht", @"webarchive", @"doc", @"docx", @"pdf", @"nvhelp"] containsObject:[extension lowercaseString]];
}

@implementation NotationPrefs

+ (int)appVersion {
	return [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] intValue];
}

- (id)init {
    if (self=[super init]) {
		allowedTypes = NULL;
		
		unsigned int i;
		for (i=0; i<4; i++) {
			typeStrings[i] = [[NotationPrefs defaultTypeStringsForFormat:i] retain];
			pathExtensions[i] = [[NotationPrefs defaultPathExtensionsForFormat:i] retain];
			chosenExtIndices[i] = 0;
		}
		
		confirmFileDeletion = YES;
		storesPasswordInKeychain = secureTextEntry = doesEncryption = NO;
		sourceMetadataByNoteUUID = [[NSMutableDictionary alloc] init];
		backupLibraryIdentifier = [[[NSUUID UUID] UUIDString] copy];
		seenDiskUUIDEntries = [[NSMutableArray alloc] init];
		notesStorageFormat = SingleDatabaseFormat;
		hashIterationCount = DEFAULT_HASH_ITERATIONS;
		keyLengthInBits = DEFAULT_KEY_LENGTH;
		baseBodyFont = [[[GlobalPrefs defaultPrefs] noteBodyFont] retain];
		//foregroundColor = [[[GlobalPrefs defaultPrefs] foregroundTextColor] retain];
		foregroundColor = [[[NSApp delegate] foregrndColor]retain];
		epochIteration = 0;
		
		[self updateOSTypesArray];
		
		firstTimeUsed = preferencesChanged = YES;
		
        return self;
    }
    return nil;
}

- (id)initWithCoder:(NSCoder*)decoder {
    if ([super init]) {
		NSAssert([decoder allowsKeyedCoding], @"Keyed decoding only!");
		
		//if we're initializing from an archive, we've obviously been run at least once before
		firstTimeUsed = NO;
		
		preferencesChanged = NO;
        id savedIdentifier = [decoder decodeObjectForKey:VAR_STR(backupLibraryIdentifier)];
        if ([savedIdentifier isKindOfClass:[NSString class]] && [[[NSUUID alloc] initWithUUIDString:savedIdentifier] autorelease])
            backupLibraryIdentifier = [savedIdentifier copy];
        else {
            backupLibraryIdentifier = [[[NSUUID UUID] UUIDString] copy];
            preferencesChanged = YES;
        }
        int64_t savedGeneration = [decoder decodeInt64ForKey:VAR_STR(backupCheckpointGeneration)];
        backupCheckpointGeneration = savedGeneration > 0 ? (unsigned long long)savedGeneration : 0;
        id savedDate = [decoder decodeObjectForKey:VAR_STR(backupCheckpointDate)];
        backupCheckpointDate = [savedDate isKindOfClass:[NSDate class]] ? [savedDate copy] : nil;
        if (!backupCheckpointGeneration || !backupCheckpointDate) preferencesChanged = YES;

		epochIteration = [decoder decodeInt32ForKey:VAR_STR(epochIteration)];
		notesStorageFormat = [decoder decodeIntForKey:VAR_STR(notesStorageFormat)];
		// Old document files remain untouched. Only archived characters remain supported.
		if (notesStorageFormat != SingleDatabaseFormat && notesStorageFormat != PlainTextFormat) {
			notesStorageFormat = SingleDatabaseFormat;
			preferencesChanged = YES;
		}
		id localMetadata = [decoder decodeObjectForKey:VAR_STR(sourceMetadataByNoteUUID)];
		sourceMetadataByNoteUUID = [localMetadata isKindOfClass:[NSDictionary class]] ? [localMetadata mutableCopy] : [[NSMutableDictionary alloc] init];
		doesEncryption = [decoder decodeBoolForKey:VAR_STR(doesEncryption)];
		storesPasswordInKeychain = [decoder decodeBoolForKey:VAR_STR(storesPasswordInKeychain)];
		secureTextEntry = [decoder decodeBoolForKey:VAR_STR(secureTextEntry)];
		
		if (!(hashIterationCount = [decoder decodeIntForKey:VAR_STR(hashIterationCount)]))
			hashIterationCount = DEFAULT_HASH_ITERATIONS;
		if (!(keyLengthInBits = [decoder decodeIntForKey:VAR_STR(keyLengthInBits)]))
			keyLengthInBits = DEFAULT_KEY_LENGTH;
		
		@try {
			baseBodyFont = [[decoder decodeObjectForKey:VAR_STR(baseBodyFont)] retain];
		} @catch (NSException *e) {
			NSLog(@"Error trying to unarchive default base body font (%@, %@)", [e name], [e reason]);
		}
		if (!baseBodyFont || ![baseBodyFont isKindOfClass:[NSFont class]]) {
			baseBodyFont = [[[GlobalPrefs defaultPrefs] noteBodyFont] retain];
			NSLog(@"setting base body to current default: %@", baseBodyFont);
			preferencesChanged = YES;
		}
		//foregroundColor does not receive the same treatment as basebodyfont; in the event of a discrepancy between global and per-db settings,
		//the former is applied to the notes in the database, while the latter is restored from the database itself
		@try {
			foregroundColor = [[decoder decodeObjectForKey:VAR_STR(foregroundColor)] retain];
		} @catch (NSException *e) {
			NSLog(@"Error trying to unarchive foreground text color (%@, %@)", [e name], [e reason]);
		}
		if (!foregroundColor || ![foregroundColor isKindOfClass:[NSColor class]]) {
			//foregroundColor = [[[GlobalPrefs defaultPrefs] foregroundTextColor] retain];
			
			foregroundColor = [[[NSApp delegate] foregrndColor]retain];
			preferencesChanged = YES;
		}
		
		confirmFileDeletion = [decoder decodeBoolForKey:VAR_STR(confirmFileDeletion)];
		
		unsigned int i;
		for (i=0; i<4; i++) {
			if (!(typeStrings[i] = [[decoder decodeObjectForKey:[VAR_STR(typeStrings) stringByAppendingFormat:@".%d",i]] retain]))
				typeStrings[i] = [[NotationPrefs defaultTypeStringsForFormat:i] retain];
			if (!(pathExtensions[i] = [[decoder decodeObjectForKey:[VAR_STR(pathExtensions) stringByAppendingFormat:@".%d",i]] retain]))
				pathExtensions[i] = [[NotationPrefs defaultPathExtensionsForFormat:i] retain];
			chosenExtIndices[i] = [decoder decodeIntForKey:[VAR_STR(chosenExtIndices) stringByAppendingFormat:@".%d",i]];
		}
		
		// Older libraries stored remote account settings. Omit them from the next snapshot.
		if ([decoder containsValueForKey:@"syncServiceAccounts"]) preferencesChanged = YES;
		keychainDatabaseIdentifier = [[decoder decodeObjectForKey:VAR_STR(keychainDatabaseIdentifier)] retain];
		
		if (!(seenDiskUUIDEntries = [[decoder decodeObjectForKey:VAR_STR(seenDiskUUIDEntries)] retain]))
			seenDiskUUIDEntries = [[NSMutableArray alloc] init];
		
		masterSalt = [[decoder decodeObjectForKey:VAR_STR(masterSalt)] retain];
		dataSessionSalt = [[decoder decodeObjectForKey:VAR_STR(dataSessionSalt)] retain];
		verifierKey = [[decoder decodeObjectForKey:VAR_STR(verifierKey)] retain];
		
		doesEncryption = doesEncryption && verifierKey && masterSalt;
		
		[self updateOSTypesArray];
    }
	
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	NSAssert([coder allowsKeyedCoding], @"Keyed encoding only!");
	
	/* epochIteration:
	 0: .Blor files
	 1: First NSArchiver (was unused--maps to 0)
	 2: First NSKeyedArchiver
	 3: First syncServicesMD and date created/modified syncing to files
	 4: tracking of file size and attribute mod dates, font foreground colors, openmeta labels
	 */
	[coder encodeInt32:EPOC_ITERATION forKey:VAR_STR(epochIteration)];
	
	[coder encodeInteger:notesStorageFormat forKey:VAR_STR(notesStorageFormat)];
	[coder encodeBool:doesEncryption forKey:VAR_STR(doesEncryption)];
	[coder encodeBool:storesPasswordInKeychain forKey:VAR_STR(storesPasswordInKeychain)];
	[coder encodeInt:hashIterationCount forKey:VAR_STR(hashIterationCount)];
	[coder encodeInt:keyLengthInBits forKey:VAR_STR(keyLengthInBits)];
	[coder encodeBool:secureTextEntry forKey:VAR_STR(secureTextEntry)];
	
	[coder encodeBool:confirmFileDeletion forKey:VAR_STR(confirmFileDeletion)];
	[coder encodeObject:baseBodyFont forKey:VAR_STR(baseBodyFont)];
	[coder encodeObject:foregroundColor forKey:VAR_STR(foregroundColor)];
	
	unsigned int i;
	for (i=0; i<4; i++) {	
		[coder encodeObject:typeStrings[i] forKey:[VAR_STR(typeStrings) stringByAppendingFormat:@".%d",i]];
		[coder encodeObject:pathExtensions[i] forKey:[VAR_STR(pathExtensions) stringByAppendingFormat:@".%d",i]];
		[coder encodeInt:chosenExtIndices[i] forKey:[VAR_STR(chosenExtIndices) stringByAppendingFormat:@".%d",i]];
	}
	
	[coder encodeObject:sourceMetadataByNoteUUID forKey:VAR_STR(sourceMetadataByNoteUUID)];
    [coder encodeObject:backupLibraryIdentifier forKey:VAR_STR(backupLibraryIdentifier)];
    [coder encodeInt64:(int64_t)backupCheckpointGeneration forKey:VAR_STR(backupCheckpointGeneration)];
    [coder encodeObject:backupCheckpointDate forKey:VAR_STR(backupCheckpointDate)];
	
	[coder encodeObject:keychainDatabaseIdentifier forKey:VAR_STR(keychainDatabaseIdentifier)];
	
	[coder encodeObject:seenDiskUUIDEntries forKey:VAR_STR(seenDiskUUIDEntries)];
	
	[coder encodeObject:masterSalt forKey:VAR_STR(masterSalt)];
	[coder encodeObject:dataSessionSalt forKey:VAR_STR(dataSessionSalt)];
	[coder encodeObject:verifierKey forKey:VAR_STR(verifierKey)];
}


- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    unsigned int i;
    for (i=0; i<4; i++) {
	[typeStrings[i] release];
	[pathExtensions[i] release];
    }
    if (allowedTypes)
	free(allowedTypes);
	
	[sourceMetadataByNoteUUID release];
	[backupLibraryIdentifier release];
	[backupCheckpointDate release];
	[seenDiskUUIDEntries release];
	[keychainDatabaseIdentifier release];
	[baseBodyFont release];
	[foregroundColor release];
    [masterSalt release];
    [dataSessionSalt release];
    [verifierKey release];
    [masterKey release];
    
    [super dealloc];
}

+ (NSMutableArray*)defaultTypeStringsForFormat:(int)formatID {
	if (formatID == PlainTextFormat) return [NSMutableArray arrayWithObjects:[(id)UTCreateStringForOSType(TEXT_TYPE_ID) autorelease], [(id)UTCreateStringForOSType(UTXT_TYPE_ID) autorelease], nil];
	return [NSMutableArray array];
}

+ (NSMutableArray*)defaultPathExtensionsForFormat:(int)formatID {
	if (formatID == PlainTextFormat) return [NSMutableArray arrayWithObjects:@"txt", @"text", @"utf8", @"taskpaper", @"md", @"markdown", @"mdown", @"mkd", @"mmd", @"multimarkdown", @"textile", @"json", @"csv", @"tsv", nil];
	return [NSMutableArray array];
}

- (NSDictionary*)sourceMetadataForNoteUUID:(NSString*)noteUUID {
	id metadata = [sourceMetadataByNoteUUID objectForKey:noteUUID];
	return [metadata isKindOfClass:[NSDictionary class]] ? metadata : nil;
}

- (void)setSourceMetadata:(NSDictionary*)metadata forNoteUUID:(NSString*)noteUUID {
	if (![noteUUID length] || [[self sourceMetadataForNoteUUID:noteUUID] isEqual:metadata]) return;
	if ([metadata count]) [sourceMetadataByNoteUUID setObject:[[metadata copy] autorelease] forKey:noteUUID];
	else [sourceMetadataByNoteUUID removeObjectForKey:noteUUID];
	preferencesChanged = YES;
	// Saving library settings does not dirty the note.
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(storeSourceMetadata) object:nil];
	[self performSelector:@selector(storeSourceMetadata) withObject:nil afterDelay:0.2];
}

- (void)storeSourceMetadata {
	if ([delegate respondsToSelector:@selector(flushAllNoteChanges)]) [delegate flushAllNoteChanges];
}

- (NSString*)backupLibraryIdentifier { return backupLibraryIdentifier; }
- (unsigned long long)backupCheckpointGeneration { return backupCheckpointGeneration; }
- (NSDate*)backupCheckpointDate { return backupCheckpointDate; }

- (void)setBackupCheckpointGeneration:(unsigned long long)generation date:(NSDate*)date {
    backupCheckpointGeneration = generation;
    [backupCheckpointDate release];
    backupCheckpointDate = [date copy];
}

- (void)renewBackupLibraryIdentifier {
    [backupLibraryIdentifier release];
    backupLibraryIdentifier = [[[NSUUID UUID] UUIDString] copy];
    [self setBackupCheckpointGeneration:0 date:nil];
    preferencesChanged = YES;
}

- (void)prepareForOfflineBackupRestore {
    NSAssert(!delegate, @"Restore preferences must not belong to an open library");
    offlineBackupRestore = YES;
    storesPasswordInKeychain = NO;
    [self forgetKeychainIdentifier];
    [seenDiskUUIDEntries removeAllObjects];
    [self renewBackupLibraryIdentifier];
    [self setNotesStorageFormat:SingleDatabaseFormat];
}

- (void)finishOfflineBackupRestore { offlineBackupRestore = NO; }

- (BOOL)matchesBackupEncryptionSettings:(NotationPrefs*)other {
    if (![other isKindOfClass:[NotationPrefs class]] || notesStorageFormat != SingleDatabaseFormat ||
        other->notesStorageFormat != SingleDatabaseFormat || doesEncryption != other->doesEncryption ||
        backupCheckpointGeneration != other->backupCheckpointGeneration ||
        ![backupLibraryIdentifier isEqual:other->backupLibraryIdentifier]) return NO;
    if (!doesEncryption) return YES;
    return keyLengthInBits == other->keyLengthInBits && hashIterationCount == other->hashIterationCount &&
        [masterSalt isEqual:other->masterSalt] && [dataSessionSalt isEqual:other->dataSessionSalt] &&
        [verifierKey isEqual:other->verifierKey];
}

- (BOOL)preferencesChanged {
	return preferencesChanged;
}

- (BOOL)storesPasswordInKeychain {
	return storesPasswordInKeychain;
}

- (NSInteger)notesStorageFormat {
	return notesStorageFormat;
}
- (BOOL)confirmFileDeletion {
    return confirmFileDeletion;
}

- (BOOL)doesEncryption {
	return doesEncryption;
}

- (BOOL)secureTextEntry {
	return secureTextEntry;
}

- (unsigned int)keyLengthInBits {
    return keyLengthInBits;
}

- (unsigned int)hashIterationCount {
	return hashIterationCount;
}

- (void)setPreferencesAreStored {
	preferencesChanged = NO;
}

- (UInt32)epochIteration {
	return epochIteration;
}

- (BOOL)firstTimeUsed {
	return firstTimeUsed;
}

- (void)setForegroundTextColor:(NSColor*)aColor {
    if (foregroundColor == aColor || [foregroundColor isEqual:aColor]) return;
	[foregroundColor autorelease];
	foregroundColor = [aColor retain];
	
	preferencesChanged = YES;
}

- (NSColor*)foregroundColor {
	return foregroundColor;
}

- (void)setBaseBodyFont:(NSFont*)aFont {
    if (baseBodyFont == aFont || [baseBodyFont isEqual:aFont]) return;
	[baseBodyFont autorelease];
	baseBodyFont = [aFont retain];
		
	preferencesChanged = YES;
}

- (NSFont*)baseBodyFont {
	
	return baseBodyFont;
}

- (void)forgetKeychainIdentifier {
	
	[keychainDatabaseIdentifier release];
	keychainDatabaseIdentifier = nil;
	
	preferencesChanged = YES;
}

- (const char *)setKeychainIdentifier {
	if (!keychainDatabaseIdentifier) {
		CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
		keychainDatabaseIdentifier = (NSString*)CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
		CFRelease(uuidRef);

		preferencesChanged = YES;
	}
	
	return [keychainDatabaseIdentifier UTF8String];
}

- (SecKeychainItemRef)currentKeychainItem {
	SecKeychainItemRef returnedItem = NULL;
	
	const char *accountName = [self setKeychainIdentifier];
	
	OSStatus err = SecKeychainFindGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
											 strlen(accountName), accountName, NULL, NULL, &returnedItem);
	if (err != noErr)
		return NULL;
	
	return returnedItem;
}

- (void)removeKeychainData {
    if (offlineBackupRestore) return;
	SecKeychainItemRef itemRef = [self currentKeychainItem];
	if (itemRef) {
		OSStatus err = SecKeychainItemDelete(itemRef);
		if (err != noErr)
			NSLog(@"Error deleting keychain item: %d", err);
		CFRelease(itemRef);
	}
}

- (NSData*)passwordDataFromKeychain {
	void *passwordData = NULL;
	UInt32 passwordLength = 0;
	const char *accountName = [self setKeychainIdentifier];
	SecKeychainItemRef returnedItem = NULL;	
	
	OSStatus err = SecKeychainFindGenericPassword(NULL,
												  strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
												  strlen(accountName), accountName,
												  &passwordLength, &passwordData,
												  &returnedItem);
	if (err != noErr) {
		NSLog(@"Error finding keychain password for account %s: %d\n", accountName, err);
		return nil;
	}
	NSData *data = [NSData dataWithBytes:passwordData length:passwordLength];
	
	bzero(passwordData, passwordLength);
	
	SecKeychainItemFreeContent(NULL, passwordData);
	
	return data;
}

- (void)setKeychainData:(NSData*)data {
    if (offlineBackupRestore) return;
	
	OSStatus status = noErr;
	
	SecKeychainItemRef itemRef = [self currentKeychainItem];
	if (itemRef) {
		//modify existing data; item already exists
		
		const char *accountName = [self setKeychainIdentifier];
		
		SecKeychainAttribute attrs[] = {
		{ kSecAccountItemAttr, strlen(accountName), (char*)accountName },
		{ kSecServiceItemAttr, strlen(KEYCHAIN_SERVICENAME), (char*)KEYCHAIN_SERVICENAME } };
		
		const SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]), attrs };
		
		if (noErr != (status = SecKeychainItemModifyAttributesAndData(itemRef, &attributes, [data length], [data bytes]))) {
			NSLog(@"Error modifying keychain data with new passphrase-data: %d", status);
		}
		
		CFRelease(itemRef);
		
	} else {
		const char *accountName = [self setKeychainIdentifier];
		
		//add new data; item does not exist
		if (noErr != (status = SecKeychainAddGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
															 strlen(accountName), accountName, [data length], [data bytes], NULL))) {
			NSLog(@"Error adding new passphrase item to keychain: %d", status);
		}
	}
}

- (void)setStoresPasswordInKeychain:(BOOL)value {
    if (offlineBackupRestore) { storesPasswordInKeychain = NO; return; }
	storesPasswordInKeychain = value;
	preferencesChanged = YES;
	
	if (!storesPasswordInKeychain)
		[self removeKeychainData];
}

- (BOOL)canLoadPassphraseData:(NSData*)passData {
	
	int keyLength = keyLengthInBits/8;
	
	//compute master key given stored salt and # of iterations
	NSData *computedMasterKey = [passData derivedKeyOfLength:keyLength salt:masterSalt iterations:hashIterationCount];

	//compute verify key given "verify" salt and 1 iteration
	NSData *verifySalt = [NSData dataWithBytesNoCopy:VERIFY_SALT length:sizeof(VERIFY_SALT) freeWhenDone:NO];
	NSData *computedVerifyKey = [computedMasterKey derivedKeyOfLength:keyLength salt:verifySalt iterations:1];
	
	//check against verify key data
	if ([computedVerifyKey isEqualToData:verifierKey]) {
		//if computedMasterKey is good, and we don't already have a master key, then this is it
		if (!masterKey)
			masterKey = [computedMasterKey retain];
		
		return YES;
	}
	
	return NO;
	
}

- (BOOL)canLoadPassphrase:(NSString*)pass {
	return [self canLoadPassphraseData:[pass dataUsingEncoding:NSUTF8StringEncoding]];
}

- (BOOL)encryptDataInNewSession:(NSMutableData*)data {
	//ideally we would vary AES algo between 128 and 256 bits depending on key length, 
	//and scale beyond with triplets, quintuplets, and septuplets--but key is not currently user-settable

	//create new dataSessionSalt and key here
	[dataSessionSalt release];
	dataSessionSalt = [[NSData randomDataOfLength:256] retain];
	
	NSData *dataSessionKey = [masterKey derivedKeyOfLength:keyLengthInBits/8 salt:dataSessionSalt iterations:1];
	
	return [data encryptAESDataWithKey:dataSessionKey iv:[dataSessionSalt subdataWithRange:NSMakeRange(0, 16)]];
}
- (BOOL)decryptDataWithCurrentSettings:(NSMutableData*)data {
	
	NSData *dataSessionKey = [masterKey derivedKeyOfLength:keyLengthInBits/8 salt:dataSessionSalt iterations:1];
	
	return [data decryptAESDataWithKey:dataSessionKey iv:[dataSessionSalt subdataWithRange:NSMakeRange(0, 16)]];
}

- (void)setPassphraseData:(NSData*)passData inKeychain:(BOOL)inKeychain {
	[self setPassphraseData:passData inKeychain:inKeychain withIterations:hashIterationCount];
}

- (void)setPassphraseData:(NSData*)passData inKeychain:(BOOL)inKeychain withIterations:(int)iterationCount {
	
	hashIterationCount = iterationCount;
	int keyLength = keyLengthInBits/8;
	
	//generate and set random salt
	[masterSalt release];
	masterSalt = [[NSData randomDataOfLength:256] retain];

	//compute and set master key given salt and # of iterations
	[masterKey release];
	masterKey = [[passData derivedKeyOfLength:keyLength salt:masterSalt iterations:hashIterationCount] retain];
	
	//compute and set verify key from master key
	[verifierKey release];
	NSData *verifySalt = [NSData dataWithBytesNoCopy:VERIFY_SALT length:sizeof(VERIFY_SALT) freeWhenDone:NO];
	verifierKey = [[masterKey derivedKeyOfLength:keyLength salt:verifySalt iterations:1] retain];

	//update keychain
	[self setStoresPasswordInKeychain:inKeychain];
	if (inKeychain)
		[self setKeychainData:passData];
	
	preferencesChanged = YES;
	
	if ([delegate respondsToSelector:@selector(databaseEncryptionSettingsChanged)])
		[delegate databaseEncryptionSettingsChanged];
}

- (NSData*)WALSessionKey {
	#define CONST_WAL_KEY "This is a 32 byte temporary key"
	NSData *sessionSalt = [NSData dataWithBytesNoCopy:LOG_SESSION_SALT length:sizeof(LOG_SESSION_SALT) freeWhenDone:NO];
	
	if (!doesEncryption)
		return [NSData dataWithBytesNoCopy:CONST_WAL_KEY length:sizeof(CONST_WAL_KEY) freeWhenDone:NO];

	return [masterKey derivedKeyOfLength:keyLengthInBits/8 salt:sessionSalt iterations:1];
}

- (void)setNotesStorageFormat:(NSInteger)formatID {
	if (formatID != SingleDatabaseFormat && formatID != PlainTextFormat) return;
	if (formatID != notesStorageFormat) {
		NSInteger oldFormat = notesStorageFormat;
		notesStorageFormat = formatID;	
		preferencesChanged = YES;
		
		[self updateOSTypesArray];
		
		if ([delegate respondsToSelector:@selector(databaseSettingsChangedFromOldFormat:)])
			[delegate databaseSettingsChangedFromOldFormat:oldFormat];
		
		//should notationprefs need to do this?
		if ([delegate respondsToSelector:@selector(flushEverything)])
			[delegate flushEverything];
	}
}

- (BOOL)shouldDisplaySheetForProposedFormat:(NSInteger)proposedFormat {
	BOOL notesExist = YES;
	
	if ([delegate respondsToSelector:@selector(totalNoteCount)])
		notesExist = [delegate totalNoteCount] > 0;

	return (proposedFormat == SingleDatabaseFormat && notesStorageFormat != SingleDatabaseFormat && notesExist);
}

- (void)noteFilesCleanupSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	
	NSAssert(contextInfo, @"No contextInfo passed to noteFilesCleanupSheetDidEnd");
	NSAssert([(id)contextInfo respondsToSelector:@selector(notesStorageFormatInProgress)],
			 @"can't get notesStorageFormatInProgress method for changing");

	NSInteger newNoteStorageFormat = [(NotationPrefsViewController*)contextInfo notesStorageFormatInProgress];
	
	if (returnCode != NSAlertAlternateReturn)
		//didn't cancel
		[self setNotesStorageFormat:newNoteStorageFormat];
	
	if (returnCode == NSAlertOtherReturn)
		//tell delegate to delete all its notes' files
		[delegate trashRemainingNoteFilesInDirectory];
	//but what if the files remain after switching to a single-db format--and then the user deletes a bunch of the files themselves?
	//should we switch the currentFormatIDs of those notes to single-db? I guess.
	
	if ([(id)contextInfo respondsToSelector:@selector(notesStorageFormatDidChange)])
		[(NotationPrefsViewController*)contextInfo notesStorageFormatDidChange];
	
	if (returnCode != NSAlertAlternateReturn) {
		//run queued method
		NSAssert([(id)contextInfo respondsToSelector:@selector(runQueuedStorageFormatChangeInvocation)],
				 @"can't get runQueuedStorageFormatChangeInvocation method for changing");

		[(NotationPrefsViewController*)contextInfo runQueuedStorageFormatChangeInvocation];
	}
}

- (void)setConfirmsFileDeletion:(BOOL)value {
    confirmFileDeletion = value;
    preferencesChanged = YES;
}

- (void)setDoesEncryption:(BOOL)value {
	BOOL oldValue = doesEncryption;
	doesEncryption = value;
	
	preferencesChanged = YES;

	if (!doesEncryption) {
		[self removeKeychainData];
	
		//clear out the verifier key and salt?
		[verifierKey release]; verifierKey = nil;
		[masterKey release]; masterKey = nil;
	}
	
	if (oldValue != value) {
		if ([delegate respondsToSelector:@selector(databaseEncryptionSettingsChanged)])
			[delegate databaseEncryptionSettingsChanged];
	}
}

- (void)setSecureTextEntry:(BOOL)value {
	
	secureTextEntry = value;
	
	preferencesChanged = YES;
	
	SecureTextEntryManager *tem = [SecureTextEntryManager sharedInstance];
	
	if (secureTextEntry) {
		[tem enableSecureTextEntry];
		[tem checkForIncompatibleApps];
	} else {
		//"forget" that the user had disabled the warning dialog when disabling this feature permanently
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:ShouldHideSecureTextEntryWarningKey];
		[tem disableSecureTextEntry];
	}
}

- (NSUInteger)tableIndexOfDiskUUID:(CFUUIDRef)UUIDRef {
	//if this UUID doesn't yet exist, then add it and return the last index
	
	DiskUUIDEntry *diskEntry = [[[DiskUUIDEntry alloc] initWithUUIDRef:UUIDRef] autorelease];
	
	NSUInteger idx = [seenDiskUUIDEntries indexOfObject: diskEntry];
	if (NSNotFound != idx) {
		[[seenDiskUUIDEntries objectAtIndex:idx] see];
		return idx;
	}
	
	NSLog(@"saw new disk UUID: %@ (other disks are: %@)", diskEntry, seenDiskUUIDEntries);
	[seenDiskUUIDEntries addObject:diskEntry];
	
	preferencesChanged = YES;
	
	return [seenDiskUUIDEntries count] - 1;
}

- (void)setKeyLengthInBits:(unsigned int)newLength {
	//can't do this because we don't have password string
    /*keyLengthInBits = newLength;
    preferencesChanged = YES;
    */
}

+ (NSString*)pathExtensionForFormat:(NSInteger)format {
	return (format == SingleDatabaseFormat || format == PlainTextFormat) ? @"txt" : @"";
}

//for our nstableview data source
- (NSInteger)typeStringsCount {
	if (typeStrings[notesStorageFormat])
		return (NSInteger)[typeStrings[notesStorageFormat] count];
	
	return 0;
}
- (NSInteger)pathExtensionsCount {
	if (pathExtensions[notesStorageFormat])
	    return (NSInteger)[pathExtensions[notesStorageFormat] count];
	
	return 0;
}

- (NSString*)typeStringAtIndex:(NSInteger)typeIndex {

    return [typeStrings[notesStorageFormat] objectAtIndex:typeIndex];
}
- (NSString*)pathExtensionAtIndex:(NSInteger)pathIndex {
    return [pathExtensions[notesStorageFormat] objectAtIndex:pathIndex];
}
- (unsigned int)indexOfChosenPathExtension {
	return chosenExtIndices[notesStorageFormat];
}
- (NSString*)chosenPathExtensionForFormat:(NSInteger)format {
	if (format != PlainTextFormat) return @"txt";
	if (chosenExtIndices[format] >= [pathExtensions[format] count] || NVUnsupportedSourceExtension([pathExtensions[format] objectAtIndex:chosenExtIndices[format]]))
		return [NotationPrefs pathExtensionForFormat:format];
	
	return [pathExtensions[format] objectAtIndex:chosenExtIndices[format]];
}

- (void)updateOSTypesArray {
    if (!typeStrings[notesStorageFormat])
	return;
    
    unsigned int i, newSize = sizeof(OSType) * [typeStrings[notesStorageFormat] count];
    allowedTypes = (OSType*)realloc(allowedTypes, newSize);
	
    for (i=0; i<[typeStrings[notesStorageFormat] count]; i++)
		allowedTypes[i] = UTGetOSTypeFromString((CFStringRef)[typeStrings[notesStorageFormat] objectAtIndex:i]);
}

- (void)addAllowedPathExtension:(NSString*)extension {
    
    NSString *actualExt = [extension stringAsSafePathExtension];
	if (NVUnsupportedSourceExtension(actualExt)) return;
	[pathExtensions[notesStorageFormat] addObject:actualExt];
	
	preferencesChanged = YES;
}

- (BOOL)removeAllowedPathExtensionAtIndex:(NSUInteger)extensionIndex {

	if ([pathExtensions[notesStorageFormat] count] > 1 && extensionIndex < [pathExtensions[notesStorageFormat] count]) {
		[pathExtensions[notesStorageFormat] removeObjectAtIndex:extensionIndex];
		
		if (chosenExtIndices[notesStorageFormat] >= [pathExtensions[notesStorageFormat] count])
			chosenExtIndices[notesStorageFormat] = 0;
		
		preferencesChanged = YES;
		return YES;
	}
	return NO;
}
- (BOOL)setChosenPathExtensionAtIndex:(NSUInteger)extensionIndex {
	if ([pathExtensions[notesStorageFormat] count] > extensionIndex &&
		[[pathExtensions[notesStorageFormat] objectAtIndex:extensionIndex] length] &&
		!NVUnsupportedSourceExtension([pathExtensions[notesStorageFormat] objectAtIndex:extensionIndex])) {
		chosenExtIndices[notesStorageFormat] = extensionIndex;
		
		preferencesChanged = YES;
		return YES;
	}
	return NO;
}

- (BOOL)addAllowedType:(NSString*)type {
    
	if (type) {
		[typeStrings[notesStorageFormat] addObject:[type fourCharTypeString]];
		[self updateOSTypesArray];
		
		preferencesChanged = YES;
		return YES;
	}
	return NO;
}

- (void)removeAllowedTypeAtIndex:(NSUInteger)typeIndex {
	[typeStrings[notesStorageFormat] removeObjectAtIndex:typeIndex];
	[self updateOSTypesArray];
	
	preferencesChanged = YES;
}

- (BOOL)setExtension:(NSString*)newExtension atIndex:(unsigned int)oldIndex {
	if (NVUnsupportedSourceExtension([newExtension stringAsSafePathExtension])) return NO;
	
    if (oldIndex < [pathExtensions[notesStorageFormat] count]) {
		
		if ([newExtension length] > 0) { 
			[pathExtensions[notesStorageFormat] replaceObjectAtIndex:oldIndex withObject:[newExtension stringAsSafePathExtension]];
			
			preferencesChanged = YES;
		} else if (![(NSString*)[pathExtensions[notesStorageFormat] objectAtIndex:oldIndex] length]) {
			return NO;
		}
    }
	
	return YES;
}

- (BOOL)setType:(NSString*)newType atIndex:(unsigned int)oldIndex {
	
    if (oldIndex < [typeStrings[notesStorageFormat] count]) {
		
		if ([newType length] > 0) {
			[typeStrings[notesStorageFormat] replaceObjectAtIndex:oldIndex withObject:[newType fourCharTypeString]];
			[self updateOSTypesArray];
				
			preferencesChanged = YES;
				
			return YES;
		}
		if (!UTGetOSTypeFromString((CFStringRef)[typeStrings[notesStorageFormat] objectAtIndex:oldIndex])) {
			return NO;
		}
    }
	
	return YES;
}

- (BOOL)pathExtensionAllowed:(NSString*)anExtension forFormat:(NSInteger)formatID {
	if (formatID != PlainTextFormat) return NO;
	if (NVUnsupportedSourceExtension(anExtension)) return NO;
	NSUInteger i;
    for (i=0; i<[pathExtensions[formatID] count]; i++) {
		if ([anExtension compare:[pathExtensions[formatID] objectAtIndex:i] 
						 options:NSCaseInsensitiveSearch] == NSOrderedSame) {
			return YES;
		}
    }
	return NO;
}

- (BOOL)catalogEntryAllowed:(NoteCatalogEntry*)catEntry {
    NSString *filename = (NSString*)catEntry->filename;
	
	if (![filename length])
		return NO;
	
	//ignore hidden files and our own database-related files (e.g. if by chance they are given a TEXT file type)
	if ([filename characterAtIndex:0] == '.') {
		return NO;
	}
	if ([filename isEqualToString:NotesDatabaseFileName]) {
		return NO;
	}
	if ([filename isEqualToString:@"Interim Note-Changes"]) {
		return NO;
	}
	
	if (notesStorageFormat != PlainTextFormat || NVUnsupportedSourceExtension([filename pathExtension]) ||
		catEntry->fileType == RTF_TYPE_ID || catEntry->fileType == RTFD_TYPE_ID || catEntry->fileType == HTML_TYPE_ID || catEntry->fileType == WORD_DOC_TYPE_ID || catEntry->fileType == PDF_TYPE_ID) return NO;
	if ([self pathExtensionAllowed:[filename pathExtension] forFormat:notesStorageFormat])
		return YES;
    
	NSUInteger i;
    for (i=0; i<[typeStrings[notesStorageFormat] count]; i++) {
		if (catEntry->fileType == allowedTypes[i]) {
			return YES;
		}
    }
    
    return NO;
    
}

- (id)delegate {
	return delegate;
}

- (void)setDelegate:(id)aDelegate {
	delegate = aDelegate;
}


@end
