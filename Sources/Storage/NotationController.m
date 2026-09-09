//
//  NotationController.m
//  Notation
//
//  Created by Zachary Schneirov on 12/19/05.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
    This file is part of Notational Velocity.

    Notational Velocity is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Notational Velocity is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */


#import "AppController.h"
#import "NotationController.h"
#import "NSCollection_utils.h"
#import "NoteObject.h"
#import "DeletedNoteObject.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "BufferUtils.h"
#import "GlobalPrefs.h"
#import "NotationPrefs.h"
#import "NoteAttributeColumn.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "ODBEditor.h"
#import "NotationFileManager.h"
#import "NotationDirectoryManager.h"
#import "BookmarksController.h"
#import "DeletionManager.h"
#import "nvaDevConfig.h"
#import "EncodingsManager.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

static NSError *NVCheckpointError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"NVBackupArchiveErrorDomain" code:code
        userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL NVSynchronizeBackupCheckpoint(NSData *data, NSURL *directory) {
    int directoryFD = open([[directory path] fileSystemRepresentation], O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (directoryFD < 0) return NO;
    int descriptor = openat(directoryFD, [NotesDatabaseFileName fileSystemRepresentation], O_RDWR | O_NOFOLLOW);
    BOOL valid = descriptor >= 0;
    struct stat info;
    if (valid) valid = fstat(descriptor, &info) == 0 && S_ISREG(info.st_mode) && info.st_size == [data length];
    unsigned char buffer[65536];
    NSUInteger offset = 0;
    while (valid && offset < [data length]) {
        size_t amount = MIN(sizeof(buffer), [data length] - offset);
        ssize_t count = pread(descriptor, buffer, amount, (off_t)offset);
        if (count <= 0 || memcmp(buffer, (const unsigned char*)[data bytes] + offset, (size_t)count)) valid = NO;
        else offset += count;
    }
    if (valid) valid = fsync(descriptor) == 0 && fsync(directoryFD) == 0;
    if (descriptor >= 0) close(descriptor);
    close(directoryFD);
    return valid;
}

@implementation NotationController

- (id)init {
    if (self=[super init]) {
		directoryChangesFound = notesChanged = aliasNeedsUpdating = NO;
		
		allNotes = [[NSMutableArray alloc] init]; //<--the authoritative list of all memory-accessible notes
		labelsListController = [[LabelsListController alloc] init];
		prefsController = [GlobalPrefs defaultPrefs];
		notesListDataSource = [[FastListDataSource alloc] init];
		deletionManager = [[DeletionManager alloc] initWithNotationController:self];
		
		allNotesBuffer = NULL;
		allNotesBufferSize = 0;
		manglingString = currentFilterStr = NULL;
		lastWordInFilterStr = 0;
		selectedNoteIndex = NSNotFound;
		
		fsCatInfoArray = NULL;
		HFSUniNameArray = NULL;
		catalogEntries = NULL;
		sortedCatalogEntries = NULL;
		catEntriesCount = totalCatEntriesCount = 0;

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
		subscriptionCallback = NewFNSubscriptionUPP(NotesDirFNSubscriptionProc);
		bzero(&noteDirSubscription, sizeof(FNSubscriptionRef));
#endif
		bzero(&noteDatabaseRef, sizeof(FSRef));
		bzero(&noteDirectoryRef, sizeof(FSRef));
		volumeSupportsExchangeObjects = -1;
		
		lastLayoutStyleGenerated = -1;
		lastCheckedDateInHours = hoursFromAbsoluteTime(CFAbsoluteTimeGetCurrent());
		blockSize = 0;
		
		lastWriteError = noErr;
		unwrittenNotes = [[NSMutableSet alloc] init];
    }
    return self;
}


- (id)initWithAliasData:(NSData*)data error:(OSStatus*)err {
    OSStatus anErr = noErr;
    
    if (data && (anErr = PtrToHand([data bytes], (Handle*)&aliasHandle, [data length])) == noErr) {
	
	FSRef targetRef;
	Boolean changed;
	
	if ((anErr = FSResolveAliasWithMountFlags(NULL, aliasHandle, &targetRef, &changed, 0)) == noErr) {
	    if (self=[self initWithDirectoryRef:&targetRef error:&anErr]) {
		aliasNeedsUpdating = changed;
		*err = noErr;
		
		return self;
	    }
	}
    }
    
    *err = anErr;
    
    return nil;
}

- (id)initWithDefaultDirectoryReturningError:(OSStatus*)err {
    FSRef targetRef;
    
    OSStatus anErr = noErr;
    if ((anErr = [NotationController getDefaultNotesDirectoryRef:&targetRef]) == noErr) {
		
		if (self=[self initWithDirectoryRef:&targetRef error:&anErr]) {
			*err = noErr;
			return self;
		}
    }
    
    *err = anErr;
    
    return nil;
}

- (id)initWithRestoredDirectoryRef:(FSRef*)directoryRef error:(OSStatus*)err {
    return [self initWithRestoredDirectoryRef:directoryRef unlockedPrefs:nil error:err];
}

- (id)initWithRestoredDirectoryRef:(FSRef*)directoryRef unlockedPrefs:(NotationPrefs*)prefs error:(OSStatus*)err {
    restoreUnlockedPrefs = [prefs retain];
    openingRestoredLibrary = YES;
    self = [self initWithDirectoryRef:directoryRef error:err];
    if (self) {
        if (![walWriter synchronize] || ![walWriter synchronizeParentDirectory]) {
            [walWriter destroyLogFilePreservingWriterOnFailure];
            [walWriter release]; walWriter = nil;
            *err = kJournalingError;
            [self release];
            return nil;
        }
        openingRestoredLibrary = NO;
        [notationPrefs finishOfflineBackupRestore];
        [restoreUnlockedPrefs release]; restoreUnlockedPrefs = nil;
        // The coordinator binds GlobalPrefs only after browsers detach from the old library.
    }
    return self;
}

- (id)initWithDirectoryRef:(FSRef*)directoryRef error:(OSStatus*)err {
    
    *err = noErr;
    
    if (self=[self init]) {
		aliasNeedsUpdating = YES; //we don't know if we have an alias yet
		
		noteDirectoryRef = *directoryRef;
		
		//check writable and readable perms, warning user if necessary
		
		//first read cache file
		OSStatus anErr = noErr;
		if ((anErr = [self _readAndInitializeSerializedNotes]) != noErr) {
			*err = anErr;
            [self release];
			return nil;
		}
		
		//set up the directory subscription, if necessary
		//and sync based on notes in directory and their mod. dates
		[self databaseSettingsChangedFromOldFormat:[notationPrefs notesStorageFormat]];
		if (!walWriter) {
			*err = kJournalingError;
            [self stopFileNotifications];
            [NSObject cancelPreviousPerformRequestsWithTarget:self];
            [self release];
			return nil;
		}
		
		[self upgradeDatabaseIfNecessary];
		
		[self updateTitlePrefixConnections];
    }
    
    return self;
}

- (id)delegate {
	return delegate;
}

- (void)setDelegate:(id)theDelegate {
	
	delegate = theDelegate;

}

- (void)mirrorAllOMToFinderTags
{
    if(IsMavericksOrLater&&([self currentNoteStorageFormat]!=SingleDatabaseFormat)&&(allNotes!=nil)&&(allNotes.count>0)){
        NSUInteger mirroredCount=0;
        for (NoteObject *note in allNotes) {
            if(![note mirrorTags]){
                break;
            }
            mirroredCount++;
        }
        if (mirroredCount!=allNotes.count) {
            NSLog(@"didn't mirror every note");
        }else{
            [self performSelector:@selector(sortAndRedisplayNotes) withObject:nil afterDelay:2.5f];
        }
    }
}

- (void)upgradeDatabaseIfNecessary {
	if (![notationPrefs firstTimeUsed]) {
		
		const UInt32 epochIteration = [notationPrefs epochIteration];
		
		//upgrade note-text-encodings here if there might exist notes with the wrong encoding (check NotationPrefs values)
		if (epochIteration < 2) {
			//this would have to be a database from epoch 1, where the default file-encoding was system-default
			NSLog(@"trying to upgrade note encodings");
			[allNotes makeObjectsPerformSelector:@selector(upgradeToUTF8IfUsingSystemEncoding)];
			//move aside the old database as the new format breaks compatibility
			(void)[self renameAndForgetNoteDatabaseFile:@"Notes & Settings (old version from 2.0b)"];
		}
		if (epochIteration < 3) {
			[allNotes makeObjectsPerformSelector:@selector(writeFileDatesAndUpdateTrackingInfo)];
		}
		if (epochIteration < 4) {
			if ([self removeSpuriousDatabaseFileNotes]) {
				NSLog(@"found and removed spurious DB notes");
				[self refilterNotes];
			}
			
			//TableColumnsVisible was renamed NoteAttributesVisible to coincide with shifted emphasis; remove old key to declutter prefs
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TableColumnsVisible"];
			
			//remove and re-add link attributes for all notes
			//remove underline attribute for all notes
			//add automatic strike-through attribute for all notes
			[allNotes makeObjectsPerformSelector:@selector(_resanitizeContent)];
		}
		
		if (epochIteration < EPOC_ITERATION) {
			NSLog(@"epochIteration was upgraded from %u to %u", epochIteration, EPOC_ITERATION);
			notesChanged = YES;
			[self flushEverything];
		} else if ([notationPrefs epochIteration] > EPOC_ITERATION) {
			if (NSRunCriticalAlertPanel(NSLocalizedString(@"Warning: this database was created by a newer version of Notational Velocity. Continue anyway?", nil), 
										NSLocalizedString(@"If you make changes, some settings and metadata will be lost.", nil), 
										NSLocalizedString(@"Quit", nil), NSLocalizedString(@"Continue", nil), nil) == NSAlertDefaultReturn)
			exit(0);
		}
	}	
}

//used to ensure a newly-written Notes & Settings file is valid before finalizing the save
//read the file back from disk, deserialize it, decrypt and decompress it, and compare the notes roughly to our current notes
- (NSNumber*)verifyDataAtTemporaryFSRef:(NSValue*)fsRefValue withFinalName:(NSString*)filename {
	
	NSDate *date = [NSDate date];
	
	NSAssert([filename isEqualToString:NotesDatabaseFileName], @"attempting to verify something other than the database");
	
	FSRef *notesFileRef = [fsRefValue pointerValue];
	UInt64 fileSize = 0;
	char *notesData = NULL;
	OSStatus err = noErr, result = noErr;
    NSMutableArray *notesToVerify = nil;
	if ((err = FSRefReadData(notesFileRef, BlockSizeForNotation(self), &fileSize, (void**)&notesData, forceReadMask)) != noErr)
		return [NSNumber numberWithInt:err];
	
	FrozenNotation *frozenNotation = nil;
	if (!fileSize) {
		result = eofErr;
		goto returnResult;
	}
	NSData *archivedNotation = [[[NSData alloc] initWithBytesNoCopy:notesData length:fileSize freeWhenDone:NO] autorelease];
	@try {
		frozenNotation = [NSKeyedUnarchiver unarchiveObjectWithData:archivedNotation];
	} @catch (NSException *e) {
		NSLog(@"(VERIFY) Error unarchiving notes and preferences from data (%@, %@)", [e name], [e reason]);
		result = kCoderErr;
		goto returnResult;
	}
	//unpack notes using the current NotationPrefs instance (not the just-unarchived one), with which we presumably just used to encrypt it
	notesToVerify = [[frozenNotation unpackedNotesWithPrefs:notationPrefs returningError:&err] retain];
	if (noErr != err) {
		result = err;
		goto returnResult;
	}
	// Compare the unpacked notes and library preferences.
	if (!notesToVerify || [notesToVerify count] != [allNotes count] ||
		[[frozenNotation notationPrefs] notesStorageFormat] != [notationPrefs notesStorageFormat] ||
		[[frozenNotation notationPrefs] hashIterationCount] != [notationPrefs hashIterationCount]) {
		result = kItemVerifyErr;
		goto returnResult;
	}
	unsigned int i;
	for (i=0; i<[notesToVerify count]; i++) {
		if ([[[notesToVerify objectAtIndex:i] contentString] length] != [[[allNotes objectAtIndex:i] contentString] length]) {
			result = kItemVerifyErr;
			goto returnResult;
		}
	}
	
	NSLog(@"verified %lu notes in %g s", [notesToVerify count], (float)[[NSDate date] timeIntervalSinceDate:date]);
returnResult:
    [notesToVerify release];
	if (notesData) free(notesData);
	return [NSNumber numberWithInt:result];
}


- (OSStatus)_readAndInitializeSerializedNotes {

    OSStatus err = noErr;
	if ((err = [self createFileIfNotPresentInNotesDirectory:&noteDatabaseRef forFilename:NotesDatabaseFileName fileWasCreated:nil]) != noErr)
		return err;
	
	UInt64 fileSize = 0;
	char *notesData = NULL;
	if ((err = FSRefReadData(&noteDatabaseRef, BlockSizeForNotation(self), &fileSize, (void**)&notesData, noCacheMask)) != noErr)
		return err;
	
	FrozenNotation *frozenNotation = nil;
	
	if (fileSize > 0) {
		NSData *archivedNotation = [[NSData alloc] initWithBytesNoCopy:notesData length:fileSize freeWhenDone:NO];
		@try {
			frozenNotation = [NSKeyedUnarchiver unarchiveObjectWithData:archivedNotation];
		} @catch (NSException *e) {
			NSLog(@"Error unarchiving notes and preferences from data (%@, %@)", [e name], [e reason]);
			
			if (notesData)
				free(notesData);
			
			//perhaps this shouldn't be an error, but the user should instead have the option of overwriting the DB with a new one?
			return kCoderErr;
		}
	
		[archivedNotation autorelease];
	}
	
	
	[notationPrefs release];
	
    if ((openingRestoredLibrary && [[frozenNotation notationPrefs] doesEncryption] && !restoreUnlockedPrefs) ||
        (restoreUnlockedPrefs && ![restoreUnlockedPrefs matchesBackupEncryptionSettings:[frozenNotation notationPrefs]])) {
        if (notesData) free(notesData);
        notationPrefs = nil;
        return kNoAuthErr;
    }
    notationPrefs = [(restoreUnlockedPrefs ?: [frozenNotation notationPrefs]) retain];
    if (!notationPrefs) notationPrefs = [[NotationPrefs alloc] init];
	[notationPrefs setDelegate:self];

	//notationPrefs will have the index of the current disk UUID (or we will add it otherwise) 
	//which will be used to determine which attr-mod-time to use for each note after decoding
	[self initializeDiskUUIDIfNecessary];
	
	[allNotes release];
    allNotes = nil;
	
	//frozennotation will work out passwords, keychains, decryption, etc...
    NSMutableArray *decodedNotes = restoreUnlockedPrefs ?
        [frozenNotation unpackedNotesWithPrefs:restoreUnlockedPrefs returningError:&err] :
        [frozenNotation unpackedNotesReturningError:&err];
	if (!(allNotes = [decodedNotes retain])) {
		//notes could be nil because the user cancelled password authentication
		//or because they were corrupted, or for some other reason
		if (err != noErr) {
            if (notesData) free(notesData);
			return err;
        }
		
		allNotes = [[NSMutableArray alloc] init];
	} else {
		[allNotes makeObjectsPerformSelector:@selector(setDelegate:) withObject:self];
	}
	
    if (!openingRestoredLibrary) [prefsController setNotationPrefs:notationPrefs sender:self];
	
	[self makeForegroundTextColorMatchGlobalPrefs];
	
	if (fileSize && notesData) {
        [backupCheckpointData release];
        backupCheckpointData = [[NSData alloc] initWithBytes:notesData length:fileSize];
    }
    if(notesData)
	    free(notesData);
	
	return noErr;
}

- (BOOL)initializeJournaling {
    
//    const UInt32 maxPathSize = 8 * 1024;
    //char *convertedPath;// = (UInt8*)malloc(maxPathSize * sizeof(UInt8));
//    OSStatus err = noErr;
	NSData *walSessionKey = [notationPrefs WALSessionKey];
    
    NSString *cPath=nil;
    //nvALT change to store Interim Note-Changes in ~/Library/Caches/
#if kUseCachesFolderForInterimNoteChanges
    cPath=[self createCachesFolder];
#else
    CFURLRef myURLRef=CFURLCreateFromFSRef(kCFAllocatorDefault, &noteDirectoryRef);
    if (myURLRef!=NULL)        {
        cPath =[NSString stringWithString:[(NSURL *) myURLRef path]];
        CFRelease(myURLRef);
    }
//    if ((err = FSRefMakePath(&noteDirectoryRef, convertedPath, maxPathSize)) == noErr) {
#endif
    
    if (cPath!=nil) {
        char *convertedPath=strdup([cPath UTF8String]);
		//initialize the journal if necessary
		if (!(walWriter = [[WALStorageController alloc] initWithParentFSRep:convertedPath encryptionKey:walSessionKey])) {
            if (openingRestoredLibrary) {
                free(convertedPath);
                goto bail;
            }
			//journal file probably already exists, so try to recover it
			WALRecoveryController *walReader = [[[WALRecoveryController alloc] initWithParentFSRep:convertedPath encryptionKey:walSessionKey] autorelease];
			if (walReader) {
				
				BOOL databaseCouldNotBeFlushed = NO;
				NSDictionary *recoveredNotes = [walReader recoveredNotes];
				if ([recoveredNotes count] > 0) {
					[self processRecoveredNotes:recoveredNotes];
					
					if (![self flushAllNoteChanges]) {
						//we shouldn't continue because the journal is still the sole record of the unsaved notes, so we can't delete it
						//BUT: what if the database can't be verified? We should be able to continue, and just keep adding to the WAL
						//in this case the WAL should be destroyed, re-initialized, and the recovered (and de-duped) notes added back
						NSLog(@"Unable to flush recovered notes back to database");
						databaseCouldNotBeFlushed = YES;
						//goto bail;
					}
				}
				//is there a way that recoverNextObject could fail that would indicate a failure with the file as opposed to simple non-recovery?
				//if so, it perhaps the recoveredNotes method should also return an error condition, to be checked here
				
				//there could be other issues, too (1)
				
				if (![walReader destroyLogFile]) {
					//couldn't delete the log file, so we can't create a new one
					NSLog(@"Unable to delete the old write-ahead-log file");
                    free(convertedPath);
					goto bail;
				}
				
				if (!(walWriter = [[WALStorageController alloc] initWithParentFSRep:convertedPath encryptionKey:walSessionKey])) {
					//couldn't create a journal after recovering the old one
					//if databaseCouldNotBeFlushed is true here, then we've potentially lost notes; perhaps exchangeobjects would be better here?
					NSLog(@"Unable to create a new write-ahead-log after deleting the old one");
					free(convertedPath);
                    goto bail;
				}
				
				if ([recoveredNotes count] > 0) {
					if (databaseCouldNotBeFlushed) {
						//re-add the contents of recoveredNotes to walWriter; LSNs should take care of the order; no need to sort
						//this allows for an ever-growing journal in the case of broken database serialization
						//it should not be an acceptable condition for permanent use; hopefully an update would come soon
						//warn the user, perhaps
						[walWriter writeNoteObjects:[recoveredNotes allValues]];
					}
					[self refilterNotes];
				}
			} else {
				NSLog(@"Unable to recover unsaved notes from write-ahead-log");
				//1) should we let the user attempt to remove it without recovery?
                free(convertedPath);
				goto bail;
			}
		}
		[walWriter setDelegate:self];
		free(convertedPath);
		return YES;
    } else {
		NSLog(@"FSRefMakePath error");//: %d", err);
		goto bail;
    }
    
bail:
    return NO;
}

//stick the newest unique recovered notes into allNotes
- (void)processRecoveredNotes:(NSDictionary*)dict {
    const unsigned int vListBufCount = 16;
    void* keysBuffer[vListBufCount], *valuesBuffer[vListBufCount];
    NSUInteger i, count = [dict count];
    
    void **keys = (count <= vListBufCount) ? keysBuffer : (void **)malloc(sizeof(void*) * count);
    void **values = (count <= vListBufCount) ? valuesBuffer : (void **)malloc(sizeof(void*) * count);
    
    if (keys && values && dict) {
	CFDictionaryGetKeysAndValues((CFDictionaryRef)dict, (const void **)keys, (const void **)values);
	
		for (i=0; i<count; i++) {
			
			CFUUIDBytes *objUUIDBytes = (CFUUIDBytes *)keys[i];
			id<LogNote> obj = (id)values[i];
			
			NSUInteger existingNoteIndex = [allNotes indexOfNoteWithUUIDBytes:objUUIDBytes];
			
			if ([obj isKindOfClass:[DeletedNoteObject class]]) {
				
				if (existingNoteIndex != NSNotFound) {
					
					NoteObject *existingNote = [allNotes objectAtIndex:existingNoteIndex];
					if ([existingNote youngerThanLogObject:obj]) {
						NSLog(@"got a newer deleted note %@", obj);
						//except that normally the undomanager doesn't exist by this point			
						[self _registerDeletionUndoForNote:existingNote];
						[allNotes removeObjectAtIndex:existingNoteIndex];
						notesChanged = YES;
					} else {
						NSLog(@"got an older deleted note %@", obj);
					}
				}
			} else if (existingNoteIndex != NSNotFound) {
				
				if ([[allNotes objectAtIndex:existingNoteIndex] youngerThanLogObject:obj]) {
					// NSLog(@"replacing old note with new: %@", [[(NoteObject*)obj contentString] string]);
					
					[(NoteObject*)obj setDelegate:self];
					[(NoteObject*)obj updateLabelConnectionsAfterDecoding];
					[allNotes replaceObjectAtIndex:existingNoteIndex withObject:obj];
					notesChanged = YES;
				} else {
					// NSLog(@"note %@ is not being replaced because its LSN is %u, while the old note's LSN is %u", 
					//  [[(NoteObject*)obj contentString] string], [(NoteObject*)obj logSequenceNumber], [[allNotes objectAtIndex:existingNoteIndex] logSequenceNumber]);
				}
			} else {
				//NSLog(@"Found new note: %@", [(NoteObject*)obj contentString]);
				
				[self _addNote:obj];
				[(NoteObject*)obj updateLabelConnectionsAfterDecoding];
			}
		}
		
	if (keys != keysBuffer)
	    free(keys);
	if (values != valuesBuffer)
	    free(values);
	
    } else {
	    free(keys);
	    free(values);
	NSLog(@"_makeChangesInDictionary: Could not get values or keys!");
    }
}

- (void)closeJournal {
    //remove journal file if we have one
    if (walWriter) {
		if (![walWriter destroyLogFile])
			NSLog(@"couldn't remove wal file--is this an error for note flushing?");
		
		[walWriter release];
		walWriter = nil;	
    }
}

- (void)checkJournalExistence {
    if (walWriter && ![walWriter logFileStillExists])
	[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
}

- (void)flushEverything {
	
	//if we could flush the database and there was a journal, then close it
	if ([self flushAllNoteChanges] && walWriter) {
		[self closeJournal];
		
		//re-start the journal if we had one
		if (![self initializeJournaling]) {
			[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
		}
	}
}

- (BOOL)flushAllNoteChanges {
    if (!(notesChanged || [notationPrefs preferencesChanged])) return YES;

    [backupCheckpointError release];
    backupCheckpointError = nil;
    [self synchronizeNoteChanges:changeWritingTimer];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(synchronizeNoteChanges:) object:nil];
    backupJournalSyncFailed = walWriter && ![walWriter synchronize];
    if (backupJournalSyncFailed) NSLog(@"The note journal could not be synchronized.");
    [NSObject cancelPreviousPerformRequestsWithTarget:walWriter selector:@selector(synchronize) object:nil];
    [self purgeOldPerDiskInfoFromNotes];

    unsigned long long previousGeneration = [notationPrefs backupCheckpointGeneration];
    NSDate *previousDate = [[notationPrefs backupCheckpointDate] retain];
    NSData *serializedData = nil;
    OSStatus writeError = noErr;
    @try {
        if (previousGeneration >= INT64_MAX) {
            backupCheckpointError = [NVCheckpointError(1, @"The library checkpoint counter is exhausted.") retain];
        } else {
            [notationPrefs setBackupCheckpointGeneration:previousGeneration + 1 date:[NSDate date]];
            serializedData = [FrozenNotation frozenDataWithExistingNotes:allNotes prefs:notationPrefs];
            if (!serializedData)
                backupCheckpointError = [NVCheckpointError(2, @"The library archive could not be created.") retain];
            else {
                writeError = [self storeDataAtomicallyInNotesDirectory:serializedData withName:NotesDatabaseFileName
                    destinationRef:&noteDatabaseRef verifyWithSelector:@selector(verifyDataAtTemporaryFSRef:withFinalName:) verificationDelegate:self];
                if (writeError != noErr)
                    backupCheckpointError = [NVCheckpointError(writeError, @"The library checkpoint could not be written and verified.") retain];
            }
        }
    } @catch (NSException *exception) {
        backupCheckpointError = [NVCheckpointError(3, @"The library archive could not be encoded or verified.") retain];
    }
    if (backupCheckpointError) {
        [notationPrefs setBackupCheckpointGeneration:previousGeneration date:previousDate];
        [previousDate release];
        return NO;
    }
    [previousDate release];
    [backupCheckpointData release];
    backupCheckpointData = [serializedData copy];
    [notationPrefs setPreferencesAreStored];
    notesChanged = NO;
    return YES;
}

- (NSDictionary*)backupSnapshotWithError:(NSError**)error {
    if (error) *error = nil;
    if (![NSThread isMainThread] || capturingBackup || backupRestorePrepared) {
        if (error) *error = NVCheckpointError(4, @"The library is not available for backup capture.");
        return nil;
    }
    capturingBackup = YES;
    BOOL flushed = NO;
    @try { flushed = [self flushAllNoteChanges]; }
    @catch (NSException *exception) {
        [backupCheckpointError release];
        backupCheckpointError = [NVCheckpointError(8, @"The library checkpoint could not finish.") retain];
    }
    @finally { capturingBackup = NO; }
    if (flushed && backupJournalSyncFailed && walWriter) {
        backupJournalSyncFailed = ![walWriter synchronize];
        if (!backupJournalSyncFailed && lastWriteError == kWriteJournalErr) lastWriteError = noErr;
    }
    if (!flushed) {
        if (error) *error = backupCheckpointError ?: NVCheckpointError(5, @"The library checkpoint failed.");
        return nil;
    }
    if (!backupCheckpointData) {
        // A clean library can use its already committed bytes without a new encryption session.
        NSError *readError = nil;
        backupCheckpointData = [[NSData dataWithContentsOfURL:[[self notesDirectoryURL] URLByAppendingPathComponent:NotesDatabaseFileName]
            options:NSDataReadingUncached error:&readError] copy];
        if (![backupCheckpointData length]) {
            [backupCheckpointData release]; backupCheckpointData = nil;
            if (error) *error = readError ?: NVCheckpointError(6, @"The committed library archive could not be read.");
            return nil;
        }
    }
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        backupCheckpointData, @"data", [notationPrefs backupLibraryIdentifier], @"libraryIdentifier",
        @([notationPrefs backupCheckpointGeneration]), @"generation", @([notationPrefs doesEncryption]), @"encrypted",
        @([allNotes count]), @"noteCount", [notationPrefs backupCheckpointDate] ?: [NSDate date], @"captureDate", nil];
    if (lastWriteError != noErr)
        [snapshot setObject:NVCheckpointError(lastWriteError, @"Some primary note files or journal records could not be written; the backup includes their committed note content.") forKey:@"sourceWriteError"];
    if (backupJournalSyncFailed)
        [snapshot setObject:NVCheckpointError(kWriteJournalErr, @"The primary recovery journal could not be synchronized.") forKey:@"journalWriteError"];
    return [[snapshot copy] autorelease];
}

- (BOOL)prepareForBackupRestoreWithError:(NSError**)error {
    if (![NSThread isMainThread] || capturingBackup || backupRestorePrepared) {
        if (error) *error = NVCheckpointError(4, @"The library is not available for a restore switch.");
        return NO;
    }
    // A historical autosave error is not evidence that storage is still unavailable.
    // Retry the note's own pending-write flag; the legacy batch can have cleared its set.
    lastWriteError = noErr;
    if ([self currentNoteStorageFormat] != SingleDatabaseFormat) {
        for (NoteObject *note in allNotes) if ([note hasPendingSourceFileWrite]) [self scheduleWriteForNote:note];
    }
    NSDictionary *snapshot = [self backupSnapshotWithError:error];
    if (!snapshot) return NO;
    if ([self currentNoteStorageFormat] != SingleDatabaseFormat) {
        for (NoteObject *note in allNotes) {
            if ([note sourceConversionPending]) {
                if (error) *error = NVCheckpointError(7, @"A note still needs a source-file encoding conversion. Finish the conversion before replacing the library.");
                return NO;
            }
        }
    }
    if ([snapshot objectForKey:@"sourceWriteError"] || [snapshot objectForKey:@"journalWriteError"]) {
        if (error) *error = [snapshot objectForKey:@"sourceWriteError"] ?: [snapshot objectForKey:@"journalWriteError"];
        return NO;
    }
    if (!NVSynchronizeBackupCheckpoint([snapshot objectForKey:@"data"], [self notesDirectoryURL])) {
        if (error) *error = NVCheckpointError(9, @"The active library checkpoint could not be synchronized. Its recovery journal remains open.");
        return NO;
    }
    if (walWriter && (![walWriter synchronize] || ![walWriter destroyLogFilePreservingWriterOnFailure])) {
        if (error) *error = NVCheckpointError(kWriteJournalErr, @"The active recovery journal could not be closed. The library was not replaced.");
        return NO;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:walWriter];
    [walWriter release]; walWriter = nil;
    [self stopFileNotifications];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (changeWritingTimer) {
        [changeWritingTimer invalidate]; [changeWritingTimer release]; changeWritingTimer = nil;
    }
    backupRestorePrepared = YES;
    return YES;
}

- (void)finishPreparedBackupRestore {
    NSAssert(backupRestorePrepared, @"Only a safely checkpointed library can finish a restore switch");
    // ODB cancellation removes callbacks; it does not read or commit the external file.
    [allNotes makeObjectsPerformSelector:@selector(abortEditingInExternalEditor)];
    [deletionManager cancelPanelReturningCode:NSRunStoppedResponse];
    [allNotes makeObjectsPerformSelector:@selector(disconnectLabels)];
    [allNotes makeObjectsPerformSelector:@selector(detachFromClosedLibrary)];
    [notationPrefs setDelegate:nil];
    delegate = nil;
}

- (BOOL)resumeAfterBackupRestoreFailureWithError:(NSError**)error {
    if (error) *error = nil;
    if (!backupRestorePrepared) return YES;
    if (![self initializeJournaling]) {
        if (error) *error = NVCheckpointError(kWriteJournalErr, @"The original library recovery journal could not be reopened.");
        return NO;
    }
    backupRestorePrepared = NO;
    [self databaseSettingsChangedFromOldFormat:[self currentNoteStorageFormat]];
    return YES;
}

- (void)handleJournalError {
    
    //we can be static because the resulting action (exit) is global to the app
    static BOOL displayedAlert = NO;
    
    if (delegate && !displayedAlert) {
	//we already have a delegate, so this must be a result of the format or file changing after initialization
	
	displayedAlert = YES;
	
	[self flushAllNoteChanges];
	
	NSRunAlertPanel(NSLocalizedString(@"Unable to create or access the Interim Note-Changes file. Is another copy of Notational Velocity currently running?",nil), 
			NSLocalizedString(@"Open Console in /Applications/Utilities/ for more information.",nil), NSLocalizedString(@"Quit",nil), NULL, NULL);
	
	
	exit(1);
    }
}

//notation prefs delegate method
- (void)databaseEncryptionSettingsChanged {
	//we _must_ re-init the journal (if fmt is single-db and jrnl exists) in addition to flushing DB
	[self flushEverything];
	
	//called whenever note-storage format or encryption-activation changes
	[[ODBEditor sharedODBEditor] initializeDatabase:notationPrefs];
}

//notation prefs delegate method
- (void)databaseSettingsChangedFromOldFormat:(NSInteger)oldFormat {
	NSInteger currentStorageFormat = [notationPrefs notesStorageFormat];
    
	if (!walWriter && ![self initializeJournaling]) {
        if (openingRestoredLibrary) return;
		[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
	}
	
    if (currentStorageFormat == SingleDatabaseFormat) {
		[self stopFileNotifications];
		
		/*if (![self initializeJournaling]) {
			[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
		}*/
		
    } else {
		//write to disk any unwritten notes; do this before flushing database to make sure that when it is flushed, it gets the new file mod. dates
		//otherwise it would be necessary to set notesChanged = YES; after this method
		
		//also make sure not to write new notes unless changing to a different format; don't rewrite deleted notes upon launch
		if (currentStorageFormat != oldFormat)
			[allNotes makeObjectsPerformSelector:@selector(writeUsingCurrentFileFormatIfNonExistingOrChanged)];
		// A canceled conversion keeps the edited source in the archive. Retry its
		// explicit conversion request after reopening, without changing encoding.
		for (NoteObject *note in allNotes) {
			if ([note sourceConversionPending]) [self scheduleWriteForNote:note];
		}

		//flush and close the journal if necessary
		/*if (walWriter) {
			if ([self flushAllNoteChanges])
				[self closeJournal];
		}*/
		//notationPrefs should call flushAllNoteChanges after this method, anyway
		
		[self startFileNotifications];
		
		[self synchronizeNotesFromDirectory];
    }
	//perform after delay because this could trigger the mounting of a RAM disk in a background  NSTask
	[[ODBEditor sharedODBEditor] performSelector:@selector(initializeDatabase:) withObject:notationPrefs afterDelay:0.0];
}

- (NSURL *)notesDirectoryURL {
    return [(NSURL *)CFURLCreateFromFSRef(kCFAllocatorDefault, &noteDirectoryRef) autorelease];
}

- (NSInteger)currentNoteStorageFormat {
    return [notationPrefs notesStorageFormat];
}

- (void)noteDidNotWrite:(NoteObject*)note errorCode:(OSStatus)error {
    [unwrittenNotes addObject:note];
    
    if (capturingBackup) { lastWriteError = error; return; }
    if (error != lastWriteError) {
		NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Changed notes could not be saved because %@.",
																	 @"alert title appearing when notes couldn't be written"), 
			[NSString reasonStringFromCarbonFSError:error]], @"", NSLocalizedString(@"OK",nil), NULL, NULL);
		
		lastWriteError = error;
    }
}

- (void)synchronizeNoteChanges:(NSTimer*)timer {
    
    if ([unwrittenNotes count] > 0) {
		lastWriteError = noErr;
		if ([notationPrefs notesStorageFormat] != SingleDatabaseFormat) {
			//to avoid mutation enumeration if writing this file triggers a filename change which then triggers another makeNoteDirty which then triggers another scheduleWriteForNote:
			//loose-coupling? what?
			[[[unwrittenNotes copy] autorelease] makeObjectsPerformSelector:@selector(writeUsingCurrentFileFormatIfNecessary)];
			
			//this always seems to call ourselves
			FNNotify(&noteDirectoryRef, kFNDirectoryModifiedMessage, kFNNoImplicitAllSubscription);
		}
		if (walWriter) {
			//append unwrittenNotes to journal, if one exists
			[unwrittenNotes makeObjectsPerformSelector:@selector(writeUsingJournal:) withObject:walWriter];
		}
				
		//NSLog(@"wrote %d unwritten notes", [unwrittenNotes count]);
		
		[unwrittenNotes removeAllObjects];
		
		[self scheduleUpdateListForAttribute:NoteDateModifiedColumnString];

    }
    
    if (changeWritingTimer) {
		[changeWritingTimer invalidate];
		[changeWritingTimer release];
		changeWritingTimer = nil;
    }
}

- (NSData*)aliasDataForNoteDirectory {
    NSData* theData = nil;
    
    FSRef userHomeFoundRef, *relativeRef = &userHomeFoundRef;
    
    if (aliasNeedsUpdating) {
		OSErr err = FSFindFolder(kUserDomain, kCurrentUserFolderType, kCreateFolder, &userHomeFoundRef);
		if (err != noErr) {
			relativeRef = NULL;
			NSLog(@"FSFindFolder error: %d", err);
		}
    }
	
    //re-fill handle from fsref if necessary, storing path relative to user directory
    if (aliasNeedsUpdating && FSNewAlias(relativeRef, &noteDirectoryRef, &aliasHandle ) != noErr)
		return nil;
	
    if (aliasHandle != NULL) {
		aliasNeedsUpdating = NO;
		
		HLock((Handle)aliasHandle);
		theData = [NSData dataWithBytes:*aliasHandle length:GetHandleSize((Handle) aliasHandle)];
		HUnlock((Handle)aliasHandle);
	    
		return theData;
    }
    
    return nil;
}

- (void)setAliasNeedsUpdating:(BOOL)needsUpdate {
	aliasNeedsUpdating = needsUpdate;
}

- (BOOL)aliasNeedsUpdating {
	return aliasNeedsUpdating;
}

- (void)closeAllResources {
	[allNotes makeObjectsPerformSelector:@selector(abortEditingInExternalEditor)];
	
	[deletionManager cancelPanelReturningCode:NSRunStoppedResponse];
	[self stopFileNotifications];
	if ([self flushAllNoteChanges])
		[self closeJournal];
	[allNotes makeObjectsPerformSelector:@selector(disconnectLabels)];
}

- (void)checkIfNotationIsTrashed {
	if ([self notesDirectoryIsTrashed]) {
		
		NSString *trashLocation = [[[NSFileManager defaultManager] pathWithFSRef:&noteDirectoryRef] stringByAbbreviatingWithTildeInPath];
		if (!trashLocation) trashLocation = @"unknown";
		NSInteger result = NSRunCriticalAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Your notes directory (%@) appears to be in the Trash.",nil), trashLocation], 
											 NSLocalizedString(@"If you empty the Trash now, you could lose your notes. Relocate the notes to a less volatile folder?",nil),
											 NSLocalizedString(@"Relocate Notes",nil), NSLocalizedString(@"Quit",nil), NULL);
		if (result == NSAlertDefaultReturn)
			[self relocateNotesDirectory];
		else [NSApp terminate:nil];
	}
}

- (void)trashRemainingNoteFilesInDirectory {
	NSAssert([notationPrefs notesStorageFormat] == SingleDatabaseFormat, @"We shouldn't be removing files if the storage is not single-database");	
	[allNotes makeObjectsPerformSelector:@selector(moveFileToTrash)];
	[self notifyOfChangedTrash];
}

- (void)updateLinksToNote:(NoteObject*)aNoteObject fromOldName:(NSString*)oldname {
    //O(n)
}

- (void)updateTitlePrefixConnections {
	//used to auto-complete titles to the first, shortest title of the same prefix--
	//to prevent auto-completing "Chicago Brauhaus" before "Chicago" when search string is "Chi", for example.
	//builds a tree-overlay in the list of notes, to find, for any given note, 
	//all other notes whose complete titles are a prefix of it
	
	//***
	//*** this method must run after any note is added, deleted, or retitled **
	//***
	
	if (![prefsController autoCompleteSearches] || ![allNotes count])
		return;
	
	//sort alphabetically to find shorter prefixes first
	NSMutableArray *allNotesAlpha = [allNotes mutableCopy];
	[allNotesAlpha sortStableUsingFunction:compareTitleString usingBuffer:&allNotesBuffer ofSize:&allNotesBufferSize];
	[allNotes makeObjectsPerformSelector:@selector(removeAllPrefixParentNotes)];

	NSUInteger j, i = 0, count = [allNotesAlpha count];
	for (i=0; i<count - 1; i++) {
		NoteObject *shorterNote = [allNotesAlpha objectAtIndex:i];
		BOOL isAPrefix = NO;
		//scan all notes sorted beneath this one for matching prefixes
		j = i + 1;
		do {
			NoteObject *longerNote = [allNotesAlpha objectAtIndex:j];
			if ((isAPrefix = noteTitleIsAPrefixOfOtherNoteTitle(longerNote, shorterNote))) {
				[longerNote addPrefixParentNote:shorterNote];
			}
		} while (isAPrefix && ++j<count);
	}

	[allNotesAlpha release];
}

- (BOOL)preserveExternalSourceData:(NSData*)data encoding:(NSStringEncoding)encoding forNote:(NoteObject*)note {
	NSString *source = [NoteObject sourceStringFromData:data encoding:&encoding path:nil];
	if (!source || !walWriter) return NO;
	NoteObject *copy = nil;
	BOOL filePreserved = NO;
	for (NoteObject *candidate in allNotes) {
		if (![candidate isSourceConflictCopyOfNote:note data:data encoding:encoding]) continue;
		NSString *path = [candidate noteFilePath] ?: [[[self notesDirectoryURL] path] stringByAppendingPathComponent:filenameOfNote(candidate)];
		NSError *error = nil;
		NSData *savedData = [NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:&error];
		// Do not overwrite a separately edited conflict file while retrying its journal.
		if (savedData && ![savedData isEqual:data]) continue;
		if (!savedData && !([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code] == NSFileReadNoSuchFileError)) return NO;
		copy = candidate;
		filePreserved = savedData != nil;
		break;
	}
	if (!copy) {
		NSString *title = [titleOfNote(note) stringByAppendingFormat:@" (%@)", NSLocalizedString(@"external changes", nil)];
		copy = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:source] autorelease]
			title:title delegate:nil format:SingleDatabaseFormat labels:labelsOfNote(note)] autorelease];
		[copy rememberSourceData:data encoding:encoding];
		[copy markAsSourceConflictCopyOfNote:note];
		[copy setSourceSyntaxIdentifier:[note sourceSyntaxIdentifier]];
		[self _addNote:copy];
		[copy makeNoteDirtyUpdateTime:NO updateFile:YES];
	}
	// Do not reenter the batched writer or directory scan while preserving a version.
	// The original file may be replaced only after the copy has a file and a synced WAL record.
	BOOL preserved = (filePreserved || [copy writeUsingCurrentFileFormat]) && [copy writeUsingJournal:walWriter] && [walWriter synchronize];
	[self performSelector:@selector(sortAndRedisplayNotes) withObject:nil afterDelay:0.0];
	return preserved;
}

- (void)addNewNote:(NoteObject*)note {
    [self _addNote:note];
	
	[note makeNoteDirtyUpdateTime:YES updateFile:YES];
	
	[self updateTitlePrefixConnections];
	
	//force immediate update
	[self synchronizeNoteChanges:nil];
	
	if ([[self undoManager] isUndoing]) {
		//prohibit undoing of creation--only redoing of deletion
		//NSLog(@"registering %s", _cmd);
		[undoManager registerUndoWithTarget:self selector:@selector(removeNote:) object:note];
		if (! [[self undoManager] isUndoing] && ! [[self undoManager] isRedoing])
			[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Create Note quotemark%@quotemark",@"undo action name for creating a single note"), titleOfNote(note)]];
	}
    
	[self resortAllNotes];
    [self refilterNotes];
    
    [delegate notation:self revealNote:note options:NVEditNoteToReveal | NVOrderFrontWindow];	
}

//do not update the view here (why not?)
- (NoteObject*)addNoteFromCatalogEntry:(NoteCatalogEntry*)catEntry {
	NoteObject *newNote = [[NoteObject alloc] initWithCatalogEntry:catEntry delegate:self];
	[self _addNote:newNote];
	[newNote release];
	
	directoryChangesFound = YES;
	
	return newNote;
}

- (void)addNotes:(NSArray*)noteArray {
	
	if (![noteArray count]) return; 
	
	unsigned int i;
	
	if ([[self undoManager] isUndoing]) [undoManager beginUndoGrouping];
	for (i=0; i<[noteArray count]; i++) {
		NoteObject * note = [noteArray objectAtIndex:i];
		
		[self _addNote:note];
		
		[note makeNoteDirtyUpdateTime:YES updateFile:YES];
	}
	if ([[self undoManager] isUndoing]) [undoManager endUndoGrouping];
	
	[self updateTitlePrefixConnections];
	
	[self synchronizeNoteChanges:nil];
	
	if ([[self undoManager] isUndoing]) {
		//prohibit undoing of creation--only redoing of deletion
		//NSLog(@"registering %s", _cmd);
		[undoManager registerUndoWithTarget:self selector:@selector(removeNotes:) object:noteArray];		
		if (! [[self undoManager] isUndoing] && ! [[self undoManager] isRedoing])
			[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Add %d Notes", @"undo action name for creating multiple notes"), [noteArray count]]];	
	}
	[self resortAllNotes];
	[self refilterNotes];
	
	if ([noteArray count] > 1)
		[delegate notation:self revealNotes:noteArray];
	else
		[delegate notation:self revealNote:[noteArray lastObject] options:NVOrderFrontWindow];
}

- (void)note:(NoteObject*)note attributeChanged:(NSString*)attribute {
    // Tags are also shown in editor headers, even when the Tags column is hidden.
    if ([attribute isEqualToString:NoteLabelsColumnString] && [delegate respondsToSelector:@selector(noteMetadataUpdated:)])
        [delegate performSelector:@selector(noteMetadataUpdated:) withObject:note];
	
	if ([attribute isEqualToString:NotePreviewString]) {
		if ([prefsController tableColumnsShowPreview]) {
			NSUInteger idx = [notesListDataSource indexOfObjectIdenticalTo:note];
			if (NSNotFound != idx) {
				[delegate rowShouldUpdate:idx];
			}
		}
		//this attribute is not displayed as a column
		return;
	}
	
	//[self scheduleUpdateListForAttribute:attribute];
	[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:attribute afterDelay:0.0];

	//special case for title requires this method, as app controller needs to know a few note-specific things
	if ([attribute isEqualToString:NoteTitleColumnString]) {
		[delegate titleUpdatedForNote:note];
		
		//also update notationcontroller's psuedo-prefix tree for autocompletion
		[self updateTitlePrefixConnections];
		//should perhaps instead trigger a coalesced notification that also updates wiki-link-titles
	}
}

- (BOOL)openFiles:(NSArray*)filenames {
	//reveal notes that already exist with any of these filenames
	//for paths left over that weren't in the notes-folder/database, import those files as new notes
	
	if (![filenames count]) return NO;
	
	NSArray *unknownPaths = filenames; //(this is not a requirement for -notesWithFilenames:unknownFiles:)
	
	if ([self currentNoteStorageFormat] != SingleDatabaseFormat) {
		//notes are stored as separate files, so if these paths are in the notes folder then NV can claim ownership over them
		
		//probably should sync directory here to make sure notesWithFilenames has the freshest data
		[self synchronizeNotesFromDirectory];
		
		NSSet *existingNotes = [self notesWithFilenames:filenames unknownFiles:&unknownPaths];
		if ([existingNotes count] > 1) {
			[delegate notation:self revealNotes:[existingNotes allObjects]];
			return YES;
		} else if ([existingNotes count] == 1) {
			[delegate notation:self revealNote:[existingNotes anyObject] options:NVEditNoteToReveal];
			return YES;
		}
	}
	//NSLog(@"paths not found in DB: %@", unknownPaths);
	NSArray *createdNotes = [[[[AlienNoteImporter alloc] initWithStoragePaths:unknownPaths] autorelease] importedNotes];
	if (!createdNotes) return NO;
	
	[self addNotes:createdNotes];
	
	return YES;
}



- (void)scheduleUpdateListForAttribute:(NSString*)attribute {
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(scheduleUpdateListForAttribute:) object:attribute];
	
	if ([[sortColumn identifier] isEqualToString:attribute]) {
		
		if ([delegate notationListShouldChange:self]) {
			[self sortAndRedisplayNotes];
		} else {
			[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:attribute afterDelay:1.5];
		}
	} else {
		//catch col updates even if they aren't the sort key
		
		NSEnumerator *enumerator = [[prefsController visibleTableColumns] objectEnumerator];
		NSString *colIdentifier = nil;
		
		//check to see if appropriate col is visible
		while ((colIdentifier = [enumerator nextObject])) {
			if ([colIdentifier isEqualToString:attribute]) {
				if ([delegate notationListShouldChange:self]) {
					[delegate notationListMightChange:self];
					[delegate notationListDidChange:self];
				} else {
					[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:attribute afterDelay:1.5];
				}
				break;
			}
		}
	}
}

- (void)scheduleWriteForNote:(NoteObject*)note {

	if ([allNotes containsObject:note]) {
	
		BOOL immediately = NO;
		notesChanged = YES;
		
		[unwrittenNotes addObject:note];
		
		//always synchronize absolutely no matter what 15 seconds after any change
		if (!changeWritingTimer)
			changeWritingTimer = [[NSTimer scheduledTimerWithTimeInterval:(immediately ? 0.0 : 15.0) target:self 
									 selector:@selector(synchronizeNoteChanges:)
									 userInfo:nil repeats:NO] retain];
		
		//next user change always invalidates queued write from performSelector, but not queued write from timer
		//this avoids excessive writing and any potential and unnecessary disk access while user types
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(synchronizeNoteChanges:) object:nil];
		
		if (walWriter) {
			//perhaps a more general user interface activity timer would be better for this? update process syncs every 30 secs, anyway...
			[NSObject cancelPreviousPerformRequestsWithTarget:walWriter selector:@selector(synchronize) object:nil];
			//fsyncing WAL to disk can cause noticeable interruption when run from main thread
			[walWriter performSelector:@selector(synchronize) withObject:nil afterDelay:15.0];
		}
		
		if (!immediately) {
			//timer is already scheduled if immediately is true
			//queue to write 2.7 seconds after last user change; 
			[self performSelector:@selector(synchronizeNoteChanges:) withObject:nil afterDelay:2.7];
		}
	} else {
		NSLog(@"not writing note %@ because it is not controlled by NoteController", note);
	}
}

//the gatekeepers!
- (void)_addNote:(NoteObject*)aNoteObject {
    [aNoteObject setDelegate:self];	
	
    [allNotes addObject:aNoteObject];
    
    notesChanged = YES;
}


- (void)removeNotesAtIndexes:(NSIndexSet *)indexes{
    //just delete the notes outright
    if (!indexes||([indexes count]==0)) {
        return;
    }else if ([indexes count]>1) {
        [self removeNotes:[self notesAtIndexes:indexes]];
    }else{
        [self removeNote:[self noteObjectAtFilteredIndex:[indexes firstIndex]]];
    }
}

//the gateway methods must always show warnings, or else flash overlay window if show-warnings-pref is off
- (void)removeNotes:(NSArray*)noteArray {
	NSEnumerator *enumerator = [noteArray objectEnumerator];
	NoteObject* note;
	
	[undoManager beginUndoGrouping];
	while ((note = [enumerator nextObject])) {
		[self removeNote:note];
	}
	[undoManager endUndoGrouping];
	if (! [[self undoManager] isUndoing] && ! [[self undoManager] isRedoing])
		[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete %d Notes",@"undo action name for deleting notes"), [noteArray count]]];
	
}

- (void)removeNote:(NoteObject*)aNoteObject {
    //reset linking labels and their notes
    
	[aNoteObject retain];
	
	[aNoteObject disconnectLabels];
	[aNoteObject abortEditingInExternalEditor];
	
    [allNotes removeObjectIdenticalTo:aNoteObject];
	[[EncodingsManager sharedManager] cancelUTF8ConversionForNote:aNoteObject];
	
	updateForVerifiedDeletedNote(deletionManager, aNoteObject);
    
    notesChanged = YES;
	
	//force-write any cached note changes to make sure that their LSNs are smaller than this deleted note's LSN
	[self synchronizeNoteChanges:nil];
    
    //we do this after removing it from the array to avoid re-discovering a removed file
    if ([notationPrefs notesStorageFormat] != SingleDatabaseFormat) {
		[aNoteObject removeFileFromDirectory];
    }
	//add journal removal event
	if (walWriter && ![walWriter writeRemovalForNote:aNoteObject]) {
		NSLog(@"Couldn't log note removal");
	}
	
	[self _registerDeletionUndoForNote:aNoteObject];
		
	//delete note from bookmarks, too
	[[prefsController bookmarksController] removeBookmarkForNote:aNoteObject];
	
	//rebuild the prefix tree, as this note may have been a prefix of another, or vise versa
	[self updateTitlePrefixConnections];
    
    [aNoteObject release];
    
    [self refilterNotes];
}

- (void)_registerDeletionUndoForNote:(NoteObject*)aNote {	
	[undoManager registerUndoWithTarget:self selector:@selector(addNewNote:) object:aNote];			
	if (![undoManager isUndoing] && ![undoManager isRedoing])
		[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete quotemark%@quotemark",@"undo action name for deleting a single note"), titleOfNote(aNote)]];				
}			


- (void)setUndoManager:(NSUndoManager*)anUndoManager {
    [undoManager autorelease];
    undoManager = [anUndoManager retain];
}

- (NSUndoManager*)undoManager {
    return undoManager;
}

- (void)updateDateStringsIfNecessary {
	
	unsigned int currentHours = hoursFromAbsoluteTime(CFAbsoluteTimeGetCurrent());
	BOOL isHorizontalLayout = [prefsController horizontalLayout];
	
	if (currentHours != lastCheckedDateInHours || isHorizontalLayout != lastLayoutStyleGenerated) {
		lastCheckedDateInHours = currentHours;
		lastLayoutStyleGenerated = (int)isHorizontalLayout;
		
		[delegate notationListMightChange:self];
		resetCurrentDayTime();
		[allNotes makeObjectsPerformSelector:@selector(updateDateStrings)];
		[delegate notationListDidChange:self];
	}
}

- (void)makeForegroundTextColorMatchGlobalPrefs {
	NSColor *prefsFGColor = [notationPrefs foregroundColor];
	if (prefsFGColor) {
		NSColor *fgColor = [[NSApp delegate] foregrndColor];
		[self setForegroundTextColor:fgColor];
		//NSColor *fgColor = [prefsController foregroundTextColor];
		
		//if (!ColorsEqualWith8BitChannels(prefsFGColor, fgColor)) {			
		//	[self setForegroundTextColor:fgColor];
		//}
	}
}

- (void)setForegroundTextColor:(NSColor*)fgColor {
    NSAssert(fgColor != nil, @"foreground color cannot be nil");
    // Appearance settings never rewrite source or its archived wrapper attributes.
    [notationPrefs setForegroundTextColor:fgColor];
}

- (void)restyleAllNotes {
    // Keep the library's display preference. Cached editing sessions apply this
    // font to their live storage through the application's existing callback.
    [notationPrefs setBaseBodyFont:[prefsController noteBodyFont]];
}

//used by BookmarksController

- (NoteObject*)noteForUUIDBytes:(CFUUIDBytes*)bytes {
	NSUInteger noteIndex = [allNotes indexOfNoteWithUUIDBytes:bytes];
	if (noteIndex != NSNotFound) return [allNotes objectAtIndex:noteIndex];
	return nil;	
}

- (void)updateLabelConnectionsAfterDecoding {
	[allNotes makeObjectsPerformSelector:@selector(updateLabelConnectionsAfterDecoding)];
}

//re-searching for all notes each time a label is added or removed is unnecessary, I think
- (void)note:(NoteObject*)note didAddLabelSet:(NSSet*)labelSet {
	[labelsListController addLabelSet:labelSet toNote:note];
        
    //this can only happen while the note is visible
	
	//[self refilterNotes];
}

- (void)note:(NoteObject*)note didRemoveLabelSet:(NSSet*)labelSet {
	[labelsListController removeLabelSet:labelSet fromNote:note];
        
	//[self refilterNotes];
}

- (void)filterNotesFromLabelAtIndex:(int)labelIndex {
	NSArray *notes = [[labelsListController notesAtFilteredIndex:labelIndex] allObjects];
	
	[delegate notationListMightChange:self];
	[notesListDataSource fillArrayFromArray:notes];
	
	[delegate notationListDidChange:self];	
}

- (void)filterNotesFromLabelIndexSet:(NSIndexSet*)indexSet {
	NSArray *notes = [[labelsListController notesAtFilteredIndexes:indexSet] allObjects];
	
	[delegate notationListMightChange:self];
	[notesListDataSource fillArrayFromArray:notes];
	
	[delegate notationListDidChange:self];
}

- (BOOL)filterNotesFromString:(NSString*)string {
	
	[delegate notationListMightChange:self];
	if ([self filterNotesFromUTF8String:[string lowercaseUTF8String] forceUncached:NO]) {
		[delegate notationListDidChange:self];
		
		return YES;
	}
	
	return NO;
}

- (void)refilterNotes {
	
    [delegate notationListMightChange:self];
    [self filterNotesFromUTF8String:(currentFilterStr ? currentFilterStr : "") forceUncached:YES];
    [delegate notationListDidChange:self];
}

- (BOOL)filterNotesFromUTF8String:(const char*)searchString forceUncached:(BOOL)forceUncached {
    BOOL stringHasExistingPrefix = YES;
    BOOL didFilterNotes = NO;
    size_t oldLen = 0, newLen = 0;
	NSUInteger i, initialCount = [notesListDataSource count];
    
	NSAssert(searchString != NULL, @"filterNotesFromUTF8String requires a non-NULL argument");
	
	newLen = strlen(searchString);
    
	//PHASE 1: determine whether notes can be searched from where they are--if not, start on all the notes
    if (!currentFilterStr || forceUncached || ((oldLen = strlen(currentFilterStr)) > newLen) ||
		strncmp(currentFilterStr, searchString, oldLen)) {
		
		//the search must be re-initialized; our strings don't have the same prefix
		
		[notesListDataSource fillArrayFromArray:allNotes];
		//[labelsListController unfilterLabels];
		
		stringHasExistingPrefix = NO;
		lastWordInFilterStr = 0;
		didFilterNotes = YES;
		
		//		NSLog(@"filter: scanning all notes");
    }
    
	
	//PHASE 2: actually search for notes
	NoteFilterContext filterContext;
	
	//if there is a quote character in the string, use that as a delimiter, as we will search by phrase
	//perhaps we could add some additional delimiters like punctuation marks here
    char *token, *separators = (strchr(searchString, '"') ? "\"" : " :\t\r\n");
    manglingString = replaceString(manglingString, searchString);
    
    BOOL touchedNotes = NO;
    
    if (!didFilterNotes || newLen > 0) {
		//only bother searching each note if we're actually searching for something
		//otherwise, filtered notes already reflect all-notes-state
		
		char *preMangler = manglingString + lastWordInFilterStr;
		while ((token = strsep(&preMangler, separators))) {
			
			if (*token != '\0') {
				//if this is the same token that we had scanned previously
				filterContext.useCachedPositions = stringHasExistingPrefix && (token == manglingString + lastWordInFilterStr);
				filterContext.needle = token;
				
				touchedNotes = YES;
				
				if ([notesListDataSource filterArrayUsingFunction:(BOOL (*)(id, void*))noteContainsUTF8String context:&filterContext])
					didFilterNotes = YES;
								
				lastWordInFilterStr = token - manglingString;
			}
		}
    }
    
	//PHASE 3: reset found pointers in case have been cleared
	NSUInteger filteredNoteCount = [notesListDataSource count];
	NoteObject **notesBuffer = [notesListDataSource immutableObjects];
	
    if (didFilterNotes) {
		
		if (!touchedNotes) {
			//I can't think of any situation where notes were filtered and not touched--EXCEPT WHEN REMOVING A NOTE (>= vs. ==)
			NSAssert(filteredNoteCount >= [allNotes count], @"filtered notes were claimed to be filtered but were not");
			
			//reset found-ptr values; the search string was effectively blank and so no notes were examined
			for (i=0; i<filteredNoteCount; i++)
				resetFoundPtrsForNote(notesBuffer[i]);
		}
		
		//we have to re-create the array at each iteration while searching notes, but not here, so we can wait until the end
		//[labelsListController recomputeListFromFilteredSet];
    }
    
	//PHASE 4: autocomplete based on results
	//even if the controller didn't filter, the search string could have changed its representation wrt spacing
	//which will still influence note title prefixes 
	selectedNoteIndex = NSNotFound;
	
    if (newLen && [prefsController autoCompleteSearches]) {

		for (i=0; i<filteredNoteCount; i++) {			
			//because we already searched word-by-word up there, this is just way simpler
			if (noteTitleHasPrefixOfUTF8String(notesBuffer[i], searchString, newLen)) {
				selectedNoteIndex = i;
				//this note matches, but what if there are other note-titles that are prefixes of both this one and the search string?
				//find the first prefix-parent of which searchString is also a prefix
				NSUInteger j = 0, prefixParentIndex = NSNotFound;
				NSArray *prefixParents = prefixParentsOfNote(notesBuffer[i]);
				
				for (j=0; j<[prefixParents count]; j++) {
					NoteObject *obj = [prefixParents objectAtIndex:j];
					
					if (noteTitleHasPrefixOfUTF8String(obj, searchString, newLen) &&
						(prefixParentIndex = [notesListDataSource indexOfObjectIdenticalTo:obj]) != NSNotFound) {
						//figure out where this prefix parent actually is in the list--if it actually is in the list, that is
						//otherwise look at the next prefix parent, etc.
						//the prefix parents array should always be alpha-sorted, so the shorter prefixes will always be first
						selectedNoteIndex = prefixParentIndex;
						break;
					}
				}
				break;
			}
		}
    }
    
    currentFilterStr = replaceString(currentFilterStr, searchString);
	
	if (!initialCount && initialCount == filteredNoteCount)
		return NO;
    
    return didFilterNotes;
}

- (NSUInteger)preferredSelectedNoteIndex {
    return selectedNoteIndex;
}

- (NSArray*)noteTitlesPrefixedByString:(NSString*)prefixString indexOfSelectedItem:(NSInteger *)anIndex {
	NSMutableArray *objs = [NSMutableArray arrayWithCapacity:[allNotes count]];
	const char *searchString = [prefixString lowercaseUTF8String];
	NSUInteger i, titleLen, strLen = strlen(searchString), j = 0, shortestTitleLen = UINT_MAX;

	for (i=0; i<[allNotes count]; i++) {
		NoteObject *thisNote = [allNotes objectAtIndex:i];
		if (noteTitleHasPrefixOfUTF8String(thisNote, searchString, strLen)) {
			[objs addObject:titleOfNote(thisNote)];
			if (anIndex && (titleLen = CFStringGetLength((CFStringRef)titleOfNote(thisNote))) < shortestTitleLen) {
				*anIndex = j;
				shortestTitleLen = titleLen;
			}
			j++;
		}
	}
	return objs;
}

- (NoteObject*)noteObjectAtFilteredIndex:(NSUInteger)noteIndex {
	unsigned int theIndex = (unsigned int)noteIndex;
	
	if (theIndex < [notesListDataSource count])
		return [notesListDataSource immutableObjects][theIndex];
	
	return nil;
}

- (NSArray*)notesAtIndexes:(NSIndexSet*)indexSet {
	return [notesListDataSource objectsAtFilteredIndexes:indexSet];
}

//O(n^2) at best, but at least we're dealing with C arrays

- (NSIndexSet*)indexesOfNotes:(NSArray*)noteArray {
	NSMutableIndexSet *noteIndexes = [[NSMutableIndexSet alloc] init];
	
	NSUInteger i, noteCount = [noteArray count];
	
	id *notes = (id*)malloc(noteCount * sizeof(id));
	[noteArray getObjects:notes];
	
	for (i=0; i<noteCount; i++) {
		NSUInteger noteIndex = [notesListDataSource indexOfObjectIdenticalTo:notes[i]];
		
		if (noteIndex != NSNotFound)
			[noteIndexes addIndex:noteIndex];
	}
	
	free(notes);
	
	return [noteIndexes autorelease];
}

- (NSUInteger)indexInFilteredListForNoteIdenticalTo:(NoteObject*)note {
	return [notesListDataSource indexOfObjectIdenticalTo:note];
}

- (NSUInteger)totalNoteCount {
	return [allNotes count];
}

- (NSArray *)allNotes {
    return [[allNotes copy] autorelease];
}

- (NoteAttributeColumn*)sortColumn {
	return sortColumn;
}

- (void)setSortColumn:(NoteAttributeColumn*)col { 
	
    [sortColumn release];
	sortColumn = [col retain];
	
	[self sortAndRedisplayNotes];
}

//re-sort without refiltering, to avoid removing notes currently being edited
- (void)sortAndRedisplayNotes {
	
	[delegate notationListMightChange:self];

	NoteAttributeColumn *col = sortColumn;
	if (col) {
		BOOL reversed = [prefsController tableIsReverseSorted];
		NSInteger (*sortFunction) (id *, id *) = (reversed ? [col reverseSortFunction] : [col sortFunction]);
		NSInteger (*stringSortFunction) (id*, id*) = (reversed ? compareTitleStringReverse : compareTitleString);
		
		[allNotes sortStableUsingFunction:stringSortFunction usingBuffer:&allNotesBuffer ofSize:&allNotesBufferSize];
		if (sortFunction != stringSortFunction)
			[allNotes sortStableUsingFunction:sortFunction usingBuffer:&allNotesBuffer ofSize:&allNotesBufferSize];
		
		
		if ([notesListDataSource count] != [allNotes count]) {
				
			[notesListDataSource sortStableUsingFunction:stringSortFunction];	
		    if (sortFunction != stringSortFunction)
				[notesListDataSource sortStableUsingFunction:sortFunction];
			
		} else {
		    //mirror from allNotes; notesListDataSource is not filtered
		    [notesListDataSource fillArrayFromArray:allNotes];
		}
		
		[delegate notationListDidChange:self];
	}
}

- (void)resortAllNotes {
	
	NoteAttributeColumn *col = sortColumn;
	
	if (col) {
		BOOL reversed = [prefsController tableIsReverseSorted];
	
		NSInteger (*sortFunction) (id*, id*) = (reversed ? [col reverseSortFunction] : [col sortFunction]);
		NSInteger (*stringSortFunction) (id*, id*) = (reversed ? compareTitleStringReverse : compareTitleString);

		[allNotes sortStableUsingFunction:stringSortFunction usingBuffer:&allNotesBuffer ofSize:&allNotesBufferSize];
		if (sortFunction != stringSortFunction)
			[allNotes sortStableUsingFunction:sortFunction usingBuffer:&allNotesBuffer ofSize:&allNotesBufferSize];
	}
}

- (float)titleColumnWidth {
	return titleColumnWidth;
}

- (void)regeneratePreviewsForColumn:(NSTableColumn*)col visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force {
    float width = [col width];
    if(IsLionOrLater){
        width-=[NSScroller scrollerWidthForControlSize:NSRegularControlSize scrollerStyle:[NSScroller preferredScrollerStyle]];
    }else{
    width-=[NSScroller scrollerWidthForControlSize:NSRegularControlSize];
    }
	
	if (force || roundf(width) != roundf(titleColumnWidth)) {
		titleColumnWidth = width;
		
		//regenerate previews for visible rows immediately and post a delayed message to regenerate previews for all rows
		if (rows.length > 0) {
			CFArrayRef visibleNotes = CFArrayCreate(NULL, (const void **)([notesListDataSource immutableObjects] + rows.location), rows.length, NULL);
			[(NSArray*)visibleNotes makeObjectsPerformSelector:@selector(updateTablePreviewString)];
			CFRelease(visibleNotes);
		}
		
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(regenerateAllPreviews) object:nil];
		[self performSelector:@selector(regenerateAllPreviews) withObject:nil afterDelay:0.0];
	}
}

- (void)regenerateAllPreviews {
	[allNotes makeObjectsPerformSelector:@selector(updateTablePreviewString)];
}

- (NotationPrefs*)notationPrefs {
	return notationPrefs;
}

- (id)labelsListDataSource {
    return labelsListController;
}

- (id)notesListDataSource {
    return notesListDataSource;
}

- (void)dealloc {
 
	[walWriter setDelegate:nil];
	[notationPrefs setDelegate:nil];
	[allNotes makeObjectsPerformSelector:@selector(setDelegate:) withObject:nil];

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    DisposeFNSubscriptionUPP(subscriptionCallback);
#endif
	if (fsCatInfoArray)
		free(fsCatInfoArray);
	if (HFSUniNameArray)
		free(HFSUniNameArray);
    if (catalogEntries)
		free(catalogEntries);
    if (sortedCatalogEntries)
		free(sortedCatalogEntries);
    if (allNotesBuffer)
		free(allNotesBuffer);
	
    [undoManager release];
    [notesListDataSource release];
    [labelsListController release];
	[deletionManager release];
    [allNotes release];
	[notationPrefs release];
	[unwrittenNotes release];
    [backupCheckpointData release];
    [backupCheckpointError release];
    [restoreUnlockedPrefs release];
    
    [super dealloc];
}

#pragma mark nvALT stuff
- (NSString *)createCachesFolder{
    NSString *path = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([paths count])    {
        path = [[paths objectAtIndex:0] stringByAppendingPathComponent:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"]];
        NSError *theError=nil;
        if ((path!=nil)&&([[NSFileManager defaultManager]createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&theError])) {
//           NSLog(@"cache folder :>%@<",path);
            return path;
        }else{
            NSLog(@"error creating cache folder:");
            if (theError) {
                NSLog(@"%@",[theError description]);
            }
        }
    }else{
        NSLog(@"Unable to find or create cache folder:\n%@", path);
    }
    return nil;
}

@end
