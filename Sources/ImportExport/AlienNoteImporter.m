//
//  AlienNoteImporter.m
//  Notation
//
//  Created by Zachary Schneirov on 11/15/06.

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


#import "AlienNoteImporter.h"
#import "BlorPasswordRetriever.h"
#import "GlobalPrefs.h"
#import "AttributedPlainText.h"
#import "NSData_transformations.h"
#import "NSCollection_utils.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NotationPrefs.h"
#import "NotationController.h"
#import "NoteObject.h"

NSString *PasswordWasRetrievedFromKeychainKey = @"PasswordRetrievedFromKeychain";
NSString *RetrievedPasswordKey = @"RetrievedPassword";
NSString *ShouldImportCreationDates = @"ShouldImportCreationDates";

@interface AlienNoteImporter (Private)
- (NSArray*)_importBlorNotes:(NSString*)filename;
@end

@implementation AlienNoteImporter

- (id)init {
	if (self=[super init]) {
		shouldGrabCreationDates = NO;
		documentSettings = [[NSMutableDictionary alloc] init];
        return self;
	}
	return nil;
}

+ (void)importBlorOrHelpFilesIfNecessaryIntoNotation:(NotationController*)notation {
	GlobalPrefs *prefsController = [GlobalPrefs defaultPrefs];
	NotationPrefs *prefs = [prefsController notationPrefs];
	if (![prefsController triedToImportBlor] && [prefs firstTimeUsed]) {
		AlienNoteImporter *importer = [AlienNoteImporter importerWithPath:[AlienNoteImporter blorPath]];
		NSArray *noteArray = [importer importedNotes];
		if ([noteArray count] > 0) {
			NSLog(@"importing BLOR");
			NSData *passData = [[[importer documentSettings] objectForKey:RetrievedPasswordKey] dataUsingEncoding:NSUTF8StringEncoding];
			BOOL shouldStoreInKeychain = [[[importer documentSettings] objectForKey:PasswordWasRetrievedFromKeychainKey] boolValue];
			[prefs setPassphraseData:passData inKeychain:shouldStoreInKeychain];
			[prefs setDoesEncryption:YES];
			
			[notation addNotes:noteArray];
		}
		[prefsController setBlorImportAttempted:YES];
	}
}

+ (AlienNoteImporter *)importerWithPath:(NSString*)path {
	AlienNoteImporter *importer = [[AlienNoteImporter alloc] initWithStoragePath:path];
	return [importer autorelease];
}

+ (NSString*)blorPath {
	NSDictionary *oldDict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.scrod.notationalvelocity"];
	NSString *blorPath = [oldDict objectForKey:@"DatabaseLocation"];
	if (!blorPath) {
		NSLog(@"Couldn't read old defaults--reverting to default location in prefs directory");
		blorPath = [NSString stringWithFormat:@"%@/Library/Preferences/%@", NSHomeDirectory(), @"NotationalDatabase.blor"];
	}
	return blorPath;
}

- (id)initWithStoragePaths:(NSArray*)filenames {
	if (self=[self init]) {
		if ((source = [filenames retain])) {
		
			importerSelector = @selector(notesWithPaths:);
		} else {
			return nil;
		}
        return self;
	}
	
	return nil;
}

- (id)initWithStoragePath:(NSString*)filename {
	if (self=[self init]) {
		if ((source = [filename retain])) {
			
			//auto-detect based on bundle/extension/metadata
            NSDictionary *pathAttributes = [[NSFileManager defaultManager]attributesAtPath:filename followLink:YES];
//			NSDictionary *pathAttributes = [[NSFileManager defaultManager] fileAttributesAtPath:filename traverseLink:YES];
			if ([[filename pathExtension] caseInsensitiveCompare:@"rtfd"] != NSOrderedSame &&
				[[pathAttributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
				
				importerSelector = @selector(notesInDirectory:);
			} else {
				importerSelector = @selector(notesInFile:);
			}
		} else {
			return nil;
		}
        return self;
	}
	
	return nil;
}

- (void)dealloc {
	[documentSettings release];
	[source release];
	
	[super dealloc];
}

- (NSDictionary*)documentSettings {
	return documentSettings;
}

- (NSView*)accessoryView {
	if (!importAccessoryView) {
		if (![NSBundle loadNibNamed:@"ImporterAccessory" owner:self])  {
			NSLog(@"Failed to load ImporterAccessory.nib");
			NSBeep();
			return nil;
		}
	}
	return importAccessoryView;
}


//- (void)openPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void  *)contextInfo {
//	id delegate = (id)contextInfo;
//	
//	if (delegate && [delegate respondsToSelector:@selector(noteImporter:importedNotes:)]) {
//		
//		if (returnCode == NSOKButton) {
//			shouldGrabCreationDates = [grabCreationDatesButton state] == NSOnState;
//			[[NSUserDefaults standardUserDefaults] setBool:shouldGrabCreationDates forKey:ShouldImportCreationDates];
//            NSArray *importedFiles=[[panel URLs]valueForKey:@"path"];
//            if (!importedFiles||importedFiles.count==0) {
//                return;
//            }
//			NSArray *notes = [self notesWithPaths:importedFiles];
//			if (notes && [notes count])
//				[delegate noteImporter:self importedNotes:notes];
//			else
//				NSRunAlertPanel(NSLocalizedString(@"None of the selected files could be imported.",nil), 
//								NSLocalizedString(@"Please choose other files.",nil), NSLocalizedString(@"OK",nil),nil,nil);
//		}
//	} else {
//		NSLog(@"Where's my note importing delegate?");
//		NSBeep();
//	}
//	
//	[self release];
//}

- (void)importNotesFromDialogAroundWindow:(NSWindow*)mainWindow receptionDelegate:(id)receiver {
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowsMultipleSelection:YES];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setPrompt:NSLocalizedString(@"Import",@"title of button in import dialog")];
	[openPanel setTitle:NSLocalizedString(@"Import Notes",@"title of import dialog")];
	[openPanel setMessage:NSLocalizedString(@"Select files and folders from which to import notes.",@"import dialog message")];
	[openPanel setAccessoryView:[self accessoryView]];
	[grabCreationDatesButton setState:[[NSUserDefaults standardUserDefaults] boolForKey:ShouldImportCreationDates]];
	
	[self retain];
	
//	[openPanel beginSheetForDirectory:nil file:nil types:nil modalForWindow:mainWindow modalDelegate:self didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:) contextInfo:receiver];
    if (receiver && [receiver respondsToSelector:@selector(noteImporter:importedNotes:)]) {
        [openPanel beginSheetModalForWindow:mainWindow completionHandler:^(NSInteger result) {
            if (result == NSFileHandlingPanelOKButton) {
                shouldGrabCreationDates = [grabCreationDatesButton state] == NSOnState;
                [[NSUserDefaults standardUserDefaults] setBool:shouldGrabCreationDates forKey:ShouldImportCreationDates];
                NSArray *filePaths=[[openPanel URLs]valueForKey:@"path"];
                
                NSArray *notes=[NSArray array];
                if (filePaths&&[filePaths count]>0) {
                    notes = [self notesWithPaths:filePaths];
                }
                if (notes && [notes count]){
                    [receiver noteImporter:self importedNotes:notes];
                }else{
                    NSRunAlertPanel(NSLocalizedString(@"None of the selected files could be imported.",nil),
                                    NSLocalizedString(@"Please choose other files.",nil), NSLocalizedString(@"OK",nil),nil,nil);
                }
            }
        }];
    } else {
        NSLog(@"Where's my note importing delegate?");
        NSBeep();
    }
}

- (NSArray*)importedNotes {
	if (!importerSelector) return nil;
	return [self performSelector:importerSelector withObject:source];
}

- (NSArray*)notesWithPaths:(NSArray*)paths {
	if ([paths isKindOfClass:[NSArray class]]) {
		
		NSMutableArray *array = [NSMutableArray array];
		NSFileManager *fileMan = [NSFileManager defaultManager];
		unsigned int i;
		for (i=0; i<[paths count]; i++) {
			NSString *path = [paths objectAtIndex:i];
			NSArray *notes = nil;
			 NSDictionary *pathAttributes = [fileMan attributesAtPath:path followLink:YES];
//			NSDictionary *pathAttributes = [fileMan fileAttributesAtPath:path traverseLink:YES];
			if ([[path pathExtension] caseInsensitiveCompare:@"rtfd"] != NSOrderedSame &&
				[[pathAttributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
				notes = [self notesInDirectory:path];
			} else {
				notes = [self notesInFile:path];
			}
			
			if (notes)
				[array addObjectsFromArray:notes];
		}
		
		return array;
	} else {
		NSLog(@"notesWithPaths: has the wrong kind of object!");
	}
	
	return nil;
}

// Import text source without extracting a rendered document or normalizing whitespace.
- (NoteObject*)noteWithFile:(NSString*)filename {
	NSString *extension = [[filename pathExtension] lowercaseString];
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesAtPath:filename followLink:YES];
	unsigned long fileType = [[attributes objectForKey:NSFileHFSTypeCode] unsignedLongValue];
	if (![[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) return nil;
	if (fileType == HTML_TYPE_ID || fileType == RTF_TYPE_ID || fileType == RTFD_TYPE_ID || fileType == WORD_DOC_TYPE_ID || fileType == PDF_TYPE_ID ||
		[@[@"htm", @"html", @"shtml", @"xhtml", @"xht", @"webarchive", @"rtf", @"rtfd", @"rtx", @"nvhelp", @"doc", @"docx", @"pdf"] containsObject:extension] ||
		[filename UTIOfFileConformsToType:@"public.html"] || [filename UTIOfFileConformsToType:@"com.apple.webarchive"]) return nil;
	if (fileType != TEXT_TYPE_ID &&
		![@[@"txt", @"text", @"utf8", @"taskpaper", @"md", @"markdown", @"mdown", @"mkd", @"mmd", @"multimarkdown", @"textile", @"json", @"csv", @"tsv"] containsObject:extension] &&
		![filename UTIOfFileConformsToType:@"public.plain-text"]) return nil;
	NSData *data = [NSData dataWithContentsOfFile:filename options:NSDataReadingUncached error:NULL];
	NSStringEncoding encoding = NSUTF8StringEncoding;
	NSString *sourceText = [NoteObject sourceStringFromData:data encoding:&encoding path:filename];
	if (!sourceText) return nil;
	NSAttributedString *body = [[[NSAttributedString alloc] initWithString:sourceText attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]] autorelease];
	NSArray *tags = [[NSFileManager defaultManager] getTagsAtFSPath:[filename fileSystemRepresentation]];
	NoteObject *note = [[[NoteObject alloc] initWithNoteBody:body title:[[filename lastPathComponent] stringByDeletingPathExtension] delegate:nil format:SingleDatabaseFormat labels:[tags componentsJoinedByString:@" "]] autorelease];
	[note rememberSourceData:data encoding:encoding];
	[note setSourceSyntaxIdentifier:[NoteObject sourceSyntaxIdentifierForPathExtension:extension]];
	NSDate *created = [attributes objectForKey:NSFileCreationDate];
	NSDate *modified = [attributes objectForKey:NSFileModificationDate];
	if (shouldGrabCreationDates && created) [note setDateAdded:[created timeIntervalSinceReferenceDate]];
	if (modified) [note setDateModified:[modified timeIntervalSinceReferenceDate]];
	return note;
}

- (NSArray*)notesInDirectory:(NSString*)filename {
	
	//recurse through all subdirectories calling notesInFile where appropriate and collecting arrays into one
	//NSDirectoryEnumerator *enumerator  = [[NSFileManager defaultManager] enumeratorAtPath:filename];
	
    NSArray *filenames = [[NSFileManager defaultManager] folderContentsAtPath:filename];
    //[[NSFileManager defaultManager] directoryContentsAtPath:filename];
	NSEnumerator *enumerator = [filenames objectEnumerator];
	
	NSMutableArray *array = [NSMutableArray array];
	
	NSString *curObject = nil;
	NSFileManager *fileMan = [NSFileManager defaultManager];
	while ((curObject = [enumerator nextObject])) {
		NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
		
		NSString *itemPath = [filename stringByAppendingPathComponent:curObject];

		if ([[[fileMan attributesAtPath:itemPath followLink:YES] objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) {
			NSArray *notes = [self notesInFile:itemPath];
			if (notes)
				[array addObjectsFromArray:notes];
		}
		[innerPool release];
	}
	
	return array;
}

- (NSArray*)notesInFile:(NSString*)filename {
	NSString *extension = [[filename pathExtension] lowercaseString];
	
	if ([extension isEqualToString:@"blor"]) {
		return [self _importBlorNotes:filename];
	} else {
		NoteObject *note = [self noteWithFile:filename];
		if (note)
			return [NSArray arrayWithObject:note];
	}
	return nil;
}


@end

@implementation AlienNoteImporter (Private)

- (NSArray*)_importBlorNotes:(NSString*)filename {
	
	BlorPasswordRetriever *retriever = [[[BlorPasswordRetriever alloc] initWithBlor:filename] autorelease];
	NSData *keyData = [retriever validPasswordHashData];
	if (!keyData) {
		NSLog(@"Couldn't get a valid pass-key to decrypt the blor!");
		return nil;
	}
	
	[documentSettings setObject:[NSNumber numberWithBool:[retriever canRetrieveFromKeychain]]
						 forKey:PasswordWasRetrievedFromKeychainKey];
	[documentSettings setObject:[retriever originalPasswordString] forKey:RetrievedPasswordKey];
	
    NSDictionary *dbAttrs = [[NSFileManager defaultManager]attributesAtPath:filename followLink:YES];
    //[[NSFileManager defaultManager] fileAttributesAtPath:filename traverseLink:YES];
	NSDate *creationDate = [dbAttrs objectForKey:NSFileCreationDate];
	NSDate *modificationDate = [dbAttrs objectForKey:NSFileModificationDate];
	
	CFAbsoluteTime creationTime = CFAbsoluteTimeGetCurrent();
	CFAbsoluteTime modificationTime = creationTime;
	if (creationDate) creationTime = CFDateGetAbsoluteTime((CFDateRef)creationDate);
	if (modificationDate) modificationTime = CFDateGetAbsoluteTime((CFDateRef)modificationDate);
	
	//iterate over notes with blorenumerator and return array
	BlorNoteEnumerator *enumerator = [[BlorNoteEnumerator alloc] initWithBlor:filename passwordHashData:keyData];
	if (!enumerator) {
		NSLog(@"couldn't initialize blor note enumerator!");
		return nil;
	}
	NSMutableArray *array = [NSMutableArray array];
	NoteObject *note = nil;
	unsigned int count = 0;
	while ((note = [enumerator nextNote])) {
		count ++;
		
		[array addObject:note];
		
		[note setDateAdded:(creationTime += 1.0)];
		[note setDateModified:(modificationTime += 1.0)];
	}
	
	if (count != [enumerator suspectedNoteCount]) {
		NSLog(@"read notes (%d) != stated note count (%d)!", count, [enumerator suspectedNoteCount]);
	}
	
	[enumerator release];
	
	return array;
}

@end
