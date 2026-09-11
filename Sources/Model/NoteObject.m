#import "NVAppIdentity.h"
#import "AppController.h"
#import "NVApplicationController.h"
//
//  NoteObject.m
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


#import "NoteObject.h"
#import "NVNoteEditingSession.h"
#import "GlobalPrefs.h"
#import "LabelObject.h"
#import "WALController.h"
#import "NotationController.h"
#import "NotationPrefs.h"
#import "AttributedPlainText.h"
#import "NSString_CustomTruncation.h"
#import "NSFileManager_NV.h"
#include "BufferUtils.h"
#import "NotationFileManager.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "NSCollection_utils.h"
#import "NotesTableView.h"
#import "UnifiedCell.h"
#import "LabelColumnCell.h"
#import "ODBEditor.h"
#import "EncodingsManager.h"

NSString *const NVNoteSyntaxDidChangeNotification = @"NVNoteSyntaxDidChangeNotification";

#if __LP64__
// Needed for compatability with data created by 32bit app
typedef struct NSRange32 {
    unsigned int location;
    unsigned int length;
} NSRange32;
#else
typedef NSRange NSRange32;
#endif

@interface NoteObject ()
- (NSString*)sourceMetadataUUID;
- (NSDictionary*)sourceMetadata;
- (void)setSourceMetadata:(NSDictionary*)metadata;
- (void)rememberSourceBaselineData:(NSData*)data encoding:(NSStringEncoding)encoding;
@end

static NSUInteger NVSourceBOMLength(NSData *data, NSStringEncoding *encoding) {
	const unsigned char *bytes = [data bytes];
	NSUInteger length = [data length];
	if (length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0 && bytes[3] == 0) { if (encoding) *encoding = NSUTF32LittleEndianStringEncoding; return 4; }
	if (length >= 4 && bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0xFE && bytes[3] == 0xFF) { if (encoding) *encoding = NSUTF32BigEndianStringEncoding; return 4; }
	if (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) { if (encoding) *encoding = NSUTF8StringEncoding; return 3; }
	if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) { if (encoding) *encoding = NSUTF16LittleEndianStringEncoding; return 2; }
	if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) { if (encoding) *encoding = NSUTF16BigEndianStringEncoding; return 2; }
	return 0;
}

@implementation NoteObject

static FSRef *noteFileRefInit(NoteObject* obj);
static void setAttrModifiedDate(NoteObject *note, UTCDateTime *dateTime);
static void setCatalogNodeID(NoteObject *note, UInt32 cnid);

+ (NSString*)sourceSyntaxIdentifierForPathExtension:(NSString*)extension {
	extension = [extension lowercaseString];
	if ([@[@"md", @"markdown", @"mdown", @"mkd", @"mmd", @"multimarkdown"] containsObject:extension]) return @"markdown";
	if ([extension isEqualToString:@"textile"]) return @"textile";
	if ([@[@"html", @"htm", @"shtml", @"xhtml", @"xht"] containsObject:extension]) return @"html";
	if ([extension isEqualToString:@"json"]) return @"json";
	if ([extension isEqualToString:@"org"]) return @"org";
	return @"plain";
}

+ (NSString*)sourceStringFromData:(NSData*)data encoding:(NSStringEncoding*)encoding path:(NSString*)path {
	if (!data) return nil;
	NSStringEncoding detectedEncoding = NSUTF8StringEncoding;
	NSUInteger bomLength = NVSourceBOMLength(data, &detectedEncoding);
	if (bomLength) {
		// NSString consumes a UTF-8 BOM itself. Skipping it first would also
		// consume a literal leading U+FEFF from the source that follows it.
		NSUInteger skip = detectedEncoding == NSUTF8StringEncoding ? 0 : bomLength;
		NSString *source = [[[NSString alloc] initWithBytes:(const char*)[data bytes] + skip length:[data length] - skip encoding:detectedEncoding] autorelease];
		if (source && encoding) *encoding = detectedEncoding;
		return source;
	}
	NSStringEncoding fileAttributeEncoding = path ? [[NSFileManager defaultManager] textEncodingAttributeOfFSPath:[path fileSystemRepresentation]] : 0;
	NSStringEncoding candidates[] = {fileAttributeEncoding, encoding ? *encoding : 0, NSUTF8StringEncoding, NSMacOSRomanStringEncoding, NSWindowsCP1252StringEncoding};
	for (NSUInteger index = 0; index < sizeof(candidates) / sizeof(candidates[0]); index++) {
		if (!candidates[index]) continue;
		NSString *source = [[[NSString alloc] initWithData:data encoding:candidates[index]] autorelease];
		if (source) {
			if (encoding) *encoding = candidates[index];
			return source;
		}
	}
	return nil;
}

- (NSString*)sourceMetadataUUID {
	CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, uniqueNoteIDBytes);
	NSString *identifier = [(NSString*)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
	CFRelease(uuid);
	return identifier;
}

- (NSDictionary*)sourceMetadata {
	if (delegate) return [[delegate notationPrefs] sourceMetadataForNoteUUID:[self sourceMetadataUUID]] ?: @{};
	return pendingSourceMetadata ?: @{};
}

- (void)setSourceMetadata:(NSDictionary*)metadata {
	if (delegate) [[delegate notationPrefs] setSourceMetadata:metadata forNoteUUID:[self sourceMetadataUUID]];
	else {
		[pendingSourceMetadata release];
		pendingSourceMetadata = [metadata copy];
	}
}

- (NSString*)sourceSyntaxIdentifier {
	NSString *syntax = [[self sourceMetadata] objectForKey:@"syntax"];
	return [syntax isKindOfClass:[NSString class]] && [@[@"plain", @"markdown", @"textile", @"html", @"json", @"org"] containsObject:syntax] ? syntax : @"plain";
}

- (void)setSourceSyntaxIdentifier:(NSString*)identifier {
	if (![identifier isKindOfClass:[NSString class]] || ![@[@"plain", @"markdown", @"textile", @"html", @"json", @"org"] containsObject:identifier]) identifier = @"plain";
	if ([[self sourceSyntaxIdentifier] isEqualToString:identifier]) return;
	NSMutableDictionary *metadata = [[[self sourceMetadata] mutableCopy] autorelease];
	[metadata setObject:identifier forKey:@"syntax"];
	[self setSourceMetadata:metadata];
	[[NSNotificationCenter defaultCenter] postNotificationName:NVNoteSyntaxDidChangeNotification object:self];
}

- (void)rememberSourceBaselineData:(NSData*)data encoding:(NSStringEncoding)encoding {
	NSData *retainedData = [data copy];
	[sourceOriginalData release];
	sourceOriginalData = retainedData;
	sourceOriginalEncoding = encoding;
}

- (void)rememberSourceData:(NSData*)data encoding:(NSStringEncoding)encoding {
	if (!data) return;
	fileEncoding = encoding;
	[self rememberSourceBaselineData:data encoding:encoding];
	[sourceByteOrderMark release];
	NSUInteger bomLength = NVSourceBOMLength(sourceOriginalData, NULL);
	sourceByteOrderMark = bomLength ? [[sourceOriginalData subdataWithRange:NSMakeRange(0, bomLength)] retain] : nil;
}

- (NSData*)sourceDataReturningError:(NSError**)error {
	if (error) *error = nil;
	NSData *originalData = sourceOriginalData;
	NSStringEncoding originalEncoding = sourceOriginalEncoding;
	NSString *source = [contentString string];
	// Legacy archives sign-extend the 32-bit file encoding identifier.
	if ([originalData isKindOfClass:[NSData class]] && (uint32_t)originalEncoding == (uint32_t)fileEncoding &&
		[source isEqualToString:[[self class] sourceStringFromData:originalData encoding:&originalEncoding path:nil]]) return originalData;
	NSData *body = [source dataUsingEncoding:fileEncoding allowLossyConversion:NO];
	if (!body) {
		if (error) *error = [NSError errorWithDomain:@"NVSourceEncodingError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The source contains characters that its file encoding cannot store.", NSLocalizedRecoverySuggestionErrorKey: @"Convert this note to UTF-8 before saving or exporting it."}];
		return nil;
	}
	NSData *bom = sourceByteOrderMark;
	if (![bom isKindOfClass:[NSData class]] || ![bom length]) return body;
	NSMutableData *result = [NSMutableData dataWithData:bom];
	[result appendData:body];
	return result;
}

- (BOOL)sourceConversionPending {
	return sourceConversionPending;
}

- (void)markAsSourceConflictCopyOfNote:(NoteObject*)note {
	[sourceConflictOriginUUID release];
	sourceConflictOriginUUID = [[NSData alloc] initWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
}

- (BOOL)isSourceConflictCopyOfNote:(NoteObject*)note data:(NSData*)data encoding:(NSStringEncoding)encoding {
	return [sourceConflictOriginUUID length] == sizeof(CFUUIDBytes) &&
		memcmp([sourceConflictOriginUUID bytes], [note uniqueNoteIDBytes], sizeof(CFUUIDBytes)) == 0 &&
		// Legacy archives decode the 32-bit encoding identifier through a signed int.
		(uint32_t)fileEncoding == (uint32_t)encoding && [[self sourceDataReturningError:NULL] isEqual:data];
}

- (BOOL)preservePendingSourceFileChanges {
	if (!sourceConversionPending || [delegate currentNoteStorageFormat] != PlainTextFormat) return YES;
	NSString *path = [self noteFilePath];
	if (!path) path = [[[delegate notesDirectoryURL] path] stringByAppendingPathComponent:filename];
	NSError *readError = nil;
	NSData *diskData = [NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:&readError];
	if (!diskData) {
		if ([[readError domain] isEqualToString:NSCocoaErrorDomain] && [readError code] == NSFileReadNoSuchFileError) return YES;
		[delegate noteDidNotWrite:self errorCode:kDataFormattingErr];
		return NO;
	}
	if ([diskData isEqual:sourceOriginalData]) return YES;
	NSStringEncoding diskEncoding = sourceOriginalEncoding ?: fileEncoding;
	NSString *diskSource = [[self class] sourceStringFromData:diskData encoding:&diskEncoding path:path];
	if (!diskSource) {
		[delegate noteDidNotWrite:self errorCode:kDataFormattingErr];
		return NO;
	}
	NSStringEncoding previousEncoding = sourceOriginalEncoding;
	NSString *previousSource = [[self class] sourceStringFromData:sourceOriginalData encoding:&previousEncoding path:nil];
	if (![diskSource isEqualToString:previousSource] && ![diskSource isEqualToString:[contentString string]] &&
		![delegate preserveExternalSourceData:diskData encoding:diskEncoding forNote:self]) return NO;
	// Advance the disk baseline only after its distinct source has a durable copy.
	// Keep this note's selected encoding and BOM until its own write succeeds.
	[self rememberSourceBaselineData:diskData encoding:diskEncoding];
	[self makeNoteDirtyUpdateTime:NO updateFile:NO];
	return YES;
}

- (id)init {
    if (self=[super init]) {
	
		perDiskInfoGroups = calloc(1, sizeof(PerDiskInfo));
		perDiskInfoGroups[0].diskIDIndex = -1;
		perDiskInfoGroupCount = 1;
		
		currentFormatID = SingleDatabaseFormat;
		fileEncoding = NSUTF8StringEncoding;
		selectedRange = NSMakeRange(NSNotFound, 0);
		
		//other instance variables initialized on demand
        return self;
    }
	return nil;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[self invalidateFSRef];
	
	[tableTitleString release];
	[titleString release];
	[labelString release];
	[labelSet release];
	[undoManager release];
	[filename release];
	[pendingSourceMetadata release];
	[sourceOriginalData release];
	[sourceByteOrderMark release];
	[sourceConflictOriginUUID release];
	[contentString release];
	[dateModifiedString release];
	[dateCreatedString release];
	[prefixParentNotes release];
	
	if (perDiskInfoGroups)
		free(perDiskInfoGroups);
		
	if (cTitle)
		free(cTitle);
	if (cContents)
		free(cContents);
	if (cLabels)
	    free(cLabels);
	
	[super dealloc];
}

- (id)delegate {
	return delegate;
}

- (void)setDelegate:(id)theDelegate {
	
	if (theDelegate) {
		delegate = theDelegate;
		if (pendingSourceMetadata) {
			[[delegate notationPrefs] setSourceMetadata:pendingSourceMetadata forNoteUUID:[self sourceMetadataUUID]];
			[pendingSourceMetadata release];
			pendingSourceMetadata = nil;
		}
		
		//do things that ought to have been done during init, but were not possible due to lack of delegate information
		if (!filename) filename = [[delegate uniqueFilenameForTitle:titleString fromNote:self] retain];
		if (!tableTitleString && !didUnarchive) [self updateTablePreviewString];
		if (!labelSet && !didUnarchive) [self updateLabelConnectionsAfterDecoding];
	}
}

static FSRef *noteFileRefInit(NoteObject* obj) {
	if (!(obj->noteFileRef)) {
		obj->noteFileRef = (FSRef*)calloc(1, sizeof(FSRef));
	}
	return obj->noteFileRef;
}

static void setAttrModifiedDate(NoteObject *note, UTCDateTime *dateTime) {
	unsigned int idx = SetPerDiskInfoWithTableIndex(dateTime, NULL, (UInt32)diskUUIDIndexForNotation(note->delegate),
													&(note->perDiskInfoGroups), &(note->perDiskInfoGroupCount));
	note->attrsModifiedDate = &(note->perDiskInfoGroups[idx].attrTime);
}
static void setCatalogNodeID(NoteObject *note, UInt32 cnid) {
	SetPerDiskInfoWithTableIndex(NULL, &cnid, (UInt32)diskUUIDIndexForNotation(note->delegate),
								 &(note->perDiskInfoGroups), &(note->perDiskInfoGroupCount));
	note->nodeID = cnid;
}

UTCDateTime *attrsModifiedDateOfNote(NoteObject *note) {
	//once unarchived, the disk UUID index won't change, so this pointer will always reflect the current attr mod time
	if (!note->attrsModifiedDate) {
		//init from delegate based on disk table index
		unsigned int i, tableIndex = (UInt32)diskUUIDIndexForNotation(note->delegate);
		
		for (i=0; i<note->perDiskInfoGroupCount; i++) {
			//check if this date has actually been initialized; this entry could be here only because setCatalogNodeID was called
			if (note->perDiskInfoGroups[i].diskIDIndex == tableIndex && !UTCDateTimeIsEmpty(note->perDiskInfoGroups[i].attrTime)) {
				note->attrsModifiedDate = &(note->perDiskInfoGroups[i].attrTime);
				goto giveDate;
			}
		}
		//this note doesn't have a file-modified date, so initialize a fairly reasonable one here
		setAttrModifiedDate(note, &(note->fileModifiedDate));
	}
giveDate:	
	return note->attrsModifiedDate;
}

UInt32 fileNodeIDOfNote(NoteObject *note) {
	if (!note->nodeID) {
		unsigned int i, tableIndex = (UInt32)diskUUIDIndexForNotation(note->delegate);
		
		for (i=0; i<note->perDiskInfoGroupCount; i++) {
			//check if this nodeID has actually been initialized; this entry could be here only because setAttrModifiedDate was called
			if (note->perDiskInfoGroups[i].diskIDIndex == tableIndex && note->perDiskInfoGroups[i].nodeID != 0U) {
				note->nodeID = note->perDiskInfoGroups[i].nodeID;
				goto giveID;
			}
		}
		//this note doesn't have a file-modified date, so initialize something that at least won't repeat this lookup
		setCatalogNodeID(note, 1);
	}
giveID:	
	return note->nodeID;
}

NSInteger compareFilename(id *one, id *two) {
    
    return (NSInteger)CFStringCompare((CFStringRef)((*(NoteObject**)one)->filename), 
				(CFStringRef)((*(NoteObject**)two)->filename), kCFCompareCaseInsensitive);
}

NSInteger compareDateModified(id *a, id *b) {
    return (*(NoteObject**)a)->modifiedDate - (*(NoteObject**)b)->modifiedDate;
}
NSInteger compareDateCreated(id *a, id *b) {
    return (*(NoteObject**)a)->createdDate - (*(NoteObject**)b)->createdDate;
}
NSInteger compareLabelString(id *a, id *b) {    
    return (NSInteger)CFStringCompare((CFStringRef)(labelsOfNote(*(NoteObject **)a)), 
								(CFStringRef)(labelsOfNote(*(NoteObject **)b)), kCFCompareCaseInsensitive);
}
NSInteger compareTitleString(id *a, id *b) {
	//add kCFCompareNumerically to options for natural order sort
    CFComparisonResult stringResult = CFStringCompare((CFStringRef)(titleOfNote(*(NoteObject**)a)), 
													  (CFStringRef)(titleOfNote(*(NoteObject**)b)), 
													  kCFCompareCaseInsensitive);
	if (stringResult == kCFCompareEqualTo) {
		
		NSInteger dateResult = compareDateCreated(a, b);
		if (!dateResult)
			return compareUniqueNoteIDBytes(a, b);
		
		return dateResult;
	}
	
	return (NSInteger)stringResult;
}
NSInteger compareUniqueNoteIDBytes(id *a, id *b) {
	return memcmp((&(*(NoteObject**)a)->uniqueNoteIDBytes), (&(*(NoteObject**)b)->uniqueNoteIDBytes), sizeof(CFUUIDBytes));
}


NSInteger compareDateModifiedReverse(id *a, id *b) {
    return (*(NoteObject**)b)->modifiedDate - (*(NoteObject**)a)->modifiedDate;
}
NSInteger compareDateCreatedReverse(id *a, id *b) {
    return (*(NoteObject**)b)->createdDate - (*(NoteObject**)a)->createdDate;
}
NSInteger compareLabelStringReverse(id *a, id *b) {    
    return (NSInteger)CFStringCompare((CFStringRef)(labelsOfNote(*(NoteObject **)b)), 
								(CFStringRef)(labelsOfNote(*(NoteObject **)a)), kCFCompareCaseInsensitive);
}
NSInteger compareTitleStringReverse(id *a, id *b) {
    CFComparisonResult stringResult = CFStringCompare((CFStringRef)(titleOfNote(*(NoteObject **)b)), 
													  (CFStringRef)(titleOfNote(*(NoteObject **)a)), 
													  kCFCompareCaseInsensitive);
	
	if (stringResult == kCFCompareEqualTo) {
		NSInteger dateResult = compareDateCreatedReverse(a, b);
		if (!dateResult)
			return compareUniqueNoteIDBytes(b, a);
		
		return dateResult;
	}
	return (NSInteger)stringResult;	
}

NSInteger compareNodeID(id *a, id *b) {
    return fileNodeIDOfNote(*(NoteObject**)a) - fileNodeIDOfNote(*(NoteObject**)b);
}
NSInteger compareFileSize(id *a, id *b) {
    return (*(NoteObject**)a)->logicalSize - (*(NoteObject**)b)->logicalSize;
}


#include "LogNoteMixIns.h"

// Journal identity and ordering.

DefModelAttrAccessor(filenameOfNote, filename)
DefModelAttrAccessor(fileSizeOfNote, logicalSize)
DefModelAttrAccessor(titleOfNote, titleString)
DefModelAttrAccessor(labelsOfNote, labelString)
DefModelAttrAccessor(fileModifiedDateOfNote, fileModifiedDate)
DefModelAttrAccessor(modifiedDateOfNote, modifiedDate)
DefModelAttrAccessor(createdDateOfNote, createdDate)
DefModelAttrAccessor(storageFormatOfNote, currentFormatID)
DefModelAttrAccessor(fileEncodingOfNote, fileEncoding)
DefModelAttrAccessor(prefixParentsOfNote, prefixParentNotes)

//DefColAttrAccessor(wordCountOfNote, wordCountString)
DefColAttrAccessor(titleOfNote2, titleString)
DefColAttrAccessor(dateCreatedStringOfNote, dateCreatedString)
DefColAttrAccessor(dateModifiedStringOfNote, dateModifiedString)

force_inline id tableTitleOfNote(NotesTableView *tv, NoteObject *note, NSInteger row) {
	id preview = [NVControllerForView(tv) tablePreviewForRow:row];
    if (preview) return preview;
	return titleOfNote(note);
}
force_inline id properlyHighlightingTableTitleOfNote(NotesTableView *tv, NoteObject *note, NSInteger row) {
    id preview = tableTitleOfNote(tv, note, row);
    return [tv isRowSelected:row] && [preview isKindOfClass:[NSAttributedString class]] ? [preview string] : preview;
}

force_inline id labelColumnCellForNote(NotesTableView *tv, NoteObject *note, NSInteger row) {
	
	LabelColumnCell *cell = [[tv tableColumnWithIdentifier:NoteLabelsColumnString] dataCellForRow:row];
	[cell setNoteObject:note];
	
	return labelsOfNote(note);
}

force_inline id unifiedCellSingleLineForNote(NotesTableView *tv, NoteObject *note, NSInteger row) {
	
	id obj = tableTitleOfNote(tv, note, row);
	
	UnifiedCell *cell = [[[tv tableColumns] objectAtIndex:0] dataCellForRow:row];
	[cell setNoteObject:note];
	[cell setPreviewIsHidden:YES];
	
	return obj;
}

force_inline id unifiedCellForNote(NotesTableView *tv, NoteObject *note, NSInteger row) {
	//snow leopard is stricter about applying the default highlight-attributes (e.g., no shadow unless no paragraph formatting)
	//so add the shadow here for snow leopard on selected rows
	
	UnifiedCell *cell = [[[tv tableColumns] objectAtIndex:0] dataCellForRow:row];
	[cell setNoteObject:note];
	[cell setPreviewIsHidden:NO];

	BOOL rowSelected = [tv isRowSelected:row];
	BOOL drawShadow = IsSnowLeopardOrLater || (IsLeopardOrLater && rowSelected && [tv currentEditor]);
	
	id preview = tableTitleOfNote(tv, note, row);
    id obj = rowSelected && [preview isKindOfClass:[NSAttributedString class]] ? AttributedStringForSelection(preview, drawShadow) : preview;
	
	
	return obj;
}

//make notationcontroller should send setDelegate: and setLabelString: (if necessary) to each note when unarchiving this way

//there is no measurable difference in speed when using decodeValuesOfObjCTypes, oddly enough
//the overhead of the _decodeObject* C functions must be significantly greater than the objc_msgSend and argument passing overhead
#define DECODE_INDIVIDUALLY 1

- (id)initWithCoder:(NSCoder*)decoder {
	if (self=[self init]) {
		
		if ([decoder allowsKeyedCoding]) {
			//(hopefully?) no versioning necessary here
			
			//for knowing when to delay certain initializations during launch (e.g., preview generation)
			didUnarchive = YES;
			
			modifiedDate = [decoder decodeDoubleForKey:VAR_STR(modifiedDate)];
			createdDate = [decoder decodeDoubleForKey:VAR_STR(createdDate)];
			selectedRange.location = [decoder decodeInt32ForKey:@"selectionRangeLocation"];
			selectedRange.length = [decoder decodeInt32ForKey:@"selectionRangeLength"];
			contentsWere7Bit = [decoder decodeBoolForKey:VAR_STR(contentsWere7Bit)];
			
			logSequenceNumber = [decoder decodeInt32ForKey:VAR_STR(logSequenceNumber)];

			currentFormatID = [decoder decodeInt32ForKey:VAR_STR(currentFormatID)];
			logicalSize = [decoder decodeInt32ForKey:VAR_STR(logicalSize)];
			
			int64_t fileModifiedDate64 = [decoder decodeInt64ForKey:VAR_STR(fileModifiedDate)];
			memcpy(&fileModifiedDate, &fileModifiedDate64, sizeof(int64_t));
						
			NSUInteger decodedPerDiskByteCount = 0;
			const uint8_t *decodedPerDiskBytes = [decoder decodeBytesForKey:VAR_STR(perDiskInfoGroups) returnedLength:&decodedPerDiskByteCount];
			if (decodedPerDiskBytes && decodedPerDiskByteCount) {
				CopyPerDiskInfoGroupsToOrder(&perDiskInfoGroups, &perDiskInfoGroupCount, (PerDiskInfo *)decodedPerDiskBytes, decodedPerDiskByteCount, 1);
			}
			
			fileEncoding = [decoder decodeInt32ForKey:VAR_STR(fileEncoding)];
			id originalData = [decoder decodeObjectForKey:VAR_STR(sourceOriginalData)];
			id byteOrderMark = [decoder decodeObjectForKey:VAR_STR(sourceByteOrderMark)];
			sourceOriginalData = [originalData isKindOfClass:[NSData class]] ? [originalData copy] : nil;
			sourceByteOrderMark = [byteOrderMark isKindOfClass:[NSData class]] ? [byteOrderMark copy] : nil;
			sourceOriginalEncoding = [decoder decodeIntegerForKey:VAR_STR(sourceOriginalEncoding)];
			sourceConversionPending = [decoder decodeBoolForKey:VAR_STR(sourceConversionPending)];
			if (sourceConversionPending) shouldWriteToFile = YES;
			id conflictOrigin = [decoder decodeObjectForKey:VAR_STR(sourceConflictOriginUUID)];
			sourceConflictOriginUUID = [conflictOrigin isKindOfClass:[NSData class]] && [conflictOrigin length] == sizeof(CFUUIDBytes) ? [conflictOrigin copy] : nil;

			NSUInteger decodedUUIDByteCount = 0;
			const uint8_t *decodedUUIDBytes = [decoder decodeBytesForKey:VAR_STR(uniqueNoteIDBytes) returnedLength:&decodedUUIDByteCount];
			if (decodedUUIDBytes) memcpy(&uniqueNoteIDBytes, decodedUUIDBytes, MIN(decodedUUIDByteCount, sizeof(CFUUIDBytes)));
			
			titleString = [[decoder decodeObjectForKey:VAR_STR(titleString)] retain];
			labelString = [[decoder decodeObjectForKey:VAR_STR(labelString)] retain];
			contentString = [[NSMutableAttributedString alloc] initWithAttributedString: [decoder decodeObjectForKey:VAR_STR(contentString)]];
			filename = [[decoder decodeObjectForKey:VAR_STR(filename)] retain];
			
		} else {
            NSRange32 range32;
			// Preserve the obsolete server timestamp slot in the legacy archive layout.
			unsigned int serverModifiedTime = 0;
			float scrolledProportion = 0.0;
            #if __LP64__
            unsigned long longTemp;
            #endif
#if DECODE_INDIVIDUALLY
			[decoder decodeValueOfObjCType:@encode(CFAbsoluteTime) at:&modifiedDate];
			[decoder decodeValueOfObjCType:@encode(CFAbsoluteTime) at:&createdDate];
            #if __LP64__
			[decoder decodeValueOfObjCType:"{_NSRange=II}" at:&range32];
            #else
            [decoder decodeValueOfObjCType:@encode(NSRange) at:&range32];
            #endif
			[decoder decodeValueOfObjCType:@encode(float) at:&scrolledProportion];
			
			[decoder decodeValueOfObjCType:@encode(unsigned int) at:&logSequenceNumber];
			
			[decoder decodeValueOfObjCType:@encode(int) at:&currentFormatID];
            #if __LP64__
            [decoder decodeValueOfObjCType:"L" at:&longTemp];
            nodeID = (UInt32)longTemp;
            #else
			[decoder decodeValueOfObjCType:@encode(UInt32) at:&nodeID];
            #endif
			[decoder decodeValueOfObjCType:@encode(UInt16) at:&fileModifiedDate.highSeconds];
            #if __LP64__
			[decoder decodeValueOfObjCType:"L" at:&longTemp];
            fileModifiedDate.lowSeconds = (UInt32)longTemp;
            #else
            [decoder decodeValueOfObjCType:@encode(UInt32) at:&fileModifiedDate.lowSeconds];
            #endif
			[decoder decodeValueOfObjCType:@encode(UInt16) at:&fileModifiedDate.fraction];	
            
            #if __LP64__
            [decoder decodeValueOfObjCType:"I" at:&fileEncoding];
            #else
            [decoder decodeValueOfObjCType:@encode(NSStringEncoding) at:&fileEncoding];
            #endif
			
			[decoder decodeValueOfObjCType:@encode(CFUUIDBytes) at:&uniqueNoteIDBytes];
			[decoder decodeValueOfObjCType:@encode(unsigned int) at:&serverModifiedTime];
			
			titleString = [[decoder decodeObject] retain];
			labelString = [[decoder decodeObject] retain];
			contentString = [[decoder decodeObject] mutableCopy];
			filename = [[decoder decodeObject] retain];
#else 
			[decoder decodeValuesOfObjCTypes: "dd{NSRange=ii}fIiI{UTCDateTime=SIS}I[16C]I@@@@", &modifiedDate, &createdDate, &range32, 
				&scrolledProportion, &logSequenceNumber, &currentFormatID, &nodeID, &fileModifiedDate, &fileEncoding, &uniqueNoteIDBytes, 
				&serverModifiedTime, &titleString, &labelString, &contentString, &filename];
#endif
            selectedRange.location = range32.location;
            selectedRange.length = range32.length;
			contentsWere7Bit = (*(unsigned int*)&scrolledProportion) != 0; //hacko wacko
		}
	
		// Attributed legacy archives supply characters only.
		if (contentString) [contentString setAttributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes] range:NSMakeRange(0, [contentString length])];
		//re-created at runtime to save space
		[self initContentCacheCString];
		cTitleFoundPtr = cTitle = titleString ? strdup([titleString lowercaseUTF8String]) : NULL;
		cLabelsFoundPtr = cLabels = labelString ? strdup([labelString lowercaseUTF8String]) : NULL;
		
		dateCreatedString = [[NSString relativeDateStringWithAbsoluteTime:createdDate] retain];
		dateModifiedString = [[NSString relativeDateStringWithAbsoluteTime:modifiedDate] retain];
		
		if (!titleString && !contentString && !labelString) return nil;
        return self;
	}
    return nil;
}

- (void)encodeWithCoder:(NSCoder *)coder {
		
	if ([coder allowsKeyedCoding]) {
		
		[coder encodeDouble:modifiedDate forKey:VAR_STR(modifiedDate)];
		[coder encodeDouble:createdDate forKey:VAR_STR(createdDate)];
		[coder encodeInt32:(unsigned int)selectedRange.location forKey:@"selectionRangeLocation"];
		[coder encodeInt32:(unsigned int)selectedRange.length forKey:@"selectionRangeLength"];
		[coder encodeBool:contentsWere7Bit forKey:VAR_STR(contentsWere7Bit)];
		
		[coder encodeInt32:logSequenceNumber forKey:VAR_STR(logSequenceNumber)];
		
		[coder encodeInteger:currentFormatID forKey:VAR_STR(currentFormatID)];
		[coder encodeInt32:logicalSize forKey:VAR_STR(logicalSize)];

		uint8_t *flippedPerDiskInfoGroups = calloc(perDiskInfoGroupCount, sizeof(PerDiskInfo));
		CopyPerDiskInfoGroupsToOrder((PerDiskInfo**)&flippedPerDiskInfoGroups, &perDiskInfoGroupCount, perDiskInfoGroups, perDiskInfoGroupCount * sizeof(PerDiskInfo), 0);
		
		[coder encodeBytes:flippedPerDiskInfoGroups length:perDiskInfoGroupCount * sizeof(PerDiskInfo) forKey:VAR_STR(perDiskInfoGroups)];
		free(flippedPerDiskInfoGroups);
		
		[coder encodeInt64:*(int64_t*)&fileModifiedDate forKey:VAR_STR(fileModifiedDate)];
        
		[coder encodeInt32:fileEncoding forKey:VAR_STR(fileEncoding)];
		[coder encodeObject:sourceOriginalData forKey:VAR_STR(sourceOriginalData)];
		[coder encodeObject:sourceByteOrderMark forKey:VAR_STR(sourceByteOrderMark)];
		[coder encodeInteger:sourceOriginalEncoding forKey:VAR_STR(sourceOriginalEncoding)];
		[coder encodeBool:sourceConversionPending forKey:VAR_STR(sourceConversionPending)];
		[coder encodeObject:sourceConflictOriginUUID forKey:VAR_STR(sourceConflictOriginUUID)];
		
		[coder encodeBytes:(const uint8_t *)&uniqueNoteIDBytes length:sizeof(CFUUIDBytes) forKey:VAR_STR(uniqueNoteIDBytes)];
		
		[coder encodeObject:titleString forKey:VAR_STR(titleString)];
		[coder encodeObject:labelString forKey:VAR_STR(labelString)];
		[coder encodeObject:contentString forKey:VAR_STR(contentString)];
		[coder encodeObject:filename forKey:VAR_STR(filename)];
		
	} else {
// 64bit encoding would break 32bit reading - keyed archives should be used
#if !__LP64__
		unsigned int serverModifiedTime = 0;
		float scrolledProportion = 0.0;
		*(unsigned int*)&scrolledProportion = (unsigned int)contentsWere7Bit;
#if DECODE_INDIVIDUALLY
		[coder encodeValueOfObjCType:@encode(CFAbsoluteTime) at:&modifiedDate];
		[coder encodeValueOfObjCType:@encode(CFAbsoluteTime) at:&createdDate];
        [coder encodeValueOfObjCType:@encode(NSRange) at:&selectedRange];
		[coder encodeValueOfObjCType:@encode(float) at:&scrolledProportion];
		
		[coder encodeValueOfObjCType:@encode(unsigned int) at:&logSequenceNumber];
		
		[coder encodeValueOfObjCType:@encode(int) at:&currentFormatID];
		[coder encodeValueOfObjCType:@encode(UInt32) at:&nodeID];
		[coder encodeValueOfObjCType:@encode(UInt16) at:&fileModifiedDate.highSeconds];
		[coder encodeValueOfObjCType:@encode(UInt32) at:&fileModifiedDate.lowSeconds];
		[coder encodeValueOfObjCType:@encode(UInt16) at:&fileModifiedDate.fraction];
		[coder encodeValueOfObjCType:@encode(NSStringEncoding) at:&fileEncoding];
		
		[coder encodeValueOfObjCType:@encode(CFUUIDBytes) at:&uniqueNoteIDBytes];
		[coder encodeValueOfObjCType:@encode(unsigned int) at:&serverModifiedTime];
		
		[coder encodeObject:titleString];
		[coder encodeObject:labelString];
		[coder encodeObject:contentString];
		[coder encodeObject:filename];
		
#else
		[coder encodeValuesOfObjCTypes: "dd{NSRange=ii}fIiI{UTCDateTime=SIS}I[16C]I@@@@", &modifiedDate, &createdDate, &range32, 
			&scrolledProportion, &logSequenceNumber, &currentFormatID, &nodeID, &fileModifiedDate, &fileEncoding, &uniqueNoteIDBytes, 
			&serverModifiedTime, &titleString, &labelString, &contentString, &filename];
#endif
#endif // !__LP64__
	}
}

- (id)initWithNoteBody:(NSAttributedString*)bodyText title:(NSString*)aNoteTitle delegate:(id)aDelegate format:(NSInteger)formatID labels:(NSString*)aLabelString {
	//delegate optional here
    if (self=[self init]) {
		
		if (!bodyText || !aNoteTitle) {
			return nil;
		}
		delegate = aDelegate;

		contentString = [[NSMutableAttributedString alloc] initWithString:[bodyText string] attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
		[self initContentCacheCString];
		if (!cContents) {
			NSLog(@"couldn't get UTF8 string from contents?!?");
			return nil;
		}

		if (![self _setTitleString:aNoteTitle])
		    titleString = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		
		if (![self _setLabelString:aLabelString]) {
			labelString = @"";
			cLabelsFoundPtr = cLabels = strdup("");
		}
		
		currentFormatID = (formatID == PlainTextFormat ? PlainTextFormat : SingleDatabaseFormat);
		filename = [[delegate uniqueFilenameForTitle:titleString fromNote:nil] retain];
		
		CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
		uniqueNoteIDBytes = CFUUIDGetUUIDBytes(uuidRef);
		CFRelease(uuidRef);
		
		createdDate = modifiedDate = CFAbsoluteTimeGetCurrent();
		dateCreatedString = [dateModifiedString = [[NSString relativeDateStringWithAbsoluteTime:modifiedDate] retain] retain];
		UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &fileModifiedDate);
		
		if (delegate)
			[self updateTablePreviewString];
        
        
        return self;
    }
    return nil;
}

//only get the fsrefs until we absolutely need them

- (id)initWithCatalogEntry:(NoteCatalogEntry*)entry delegate:(id)aDelegate {
	NSAssert(aDelegate != nil, @"must supply a delegate");
    if (self=[self init]) {
		delegate = aDelegate;
		filename = [(NSString*)entry->filename copy];
		currentFormatID = [delegate currentNoteStorageFormat];
		fileModifiedDate = entry->lastModified;
		setAttrModifiedDate(self, &(entry->lastAttrModified));
		setCatalogNodeID(self, entry->nodeID);
		logicalSize = entry->logicalSize;
		
		CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
		uniqueNoteIDBytes = CFUUIDGetUUIDBytes(uuidRef);
		CFRelease(uuidRef);
		
		[self setSourceSyntaxIdentifier:[[self class] sourceSyntaxIdentifierForPathExtension:[filename pathExtension]]];

		if (![self _setTitleString:[filename stringByDeletingPathExtension]])
			titleString = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		
		labelString = @""; //set by updateFromCatalogEntry if there are openmeta extended attributes 
		cLabelsFoundPtr = cLabels = strdup("");	
				
		contentString = [[NSMutableAttributedString alloc] initWithString:@""];
		[self initContentCacheCString];
		
		if (![self updateFromCatalogEntry:entry]) {						
			//just initialize a blank note for now; if the file becomes readable again we'll be updated
			//but if we make modifications, well, the original is toast
			//so warn the user here and offer to trash it?
			//perhaps also offer to re-interpret using another text encoding?
			
			//additionally, it is possible that the file was deleted before we could read it
		}
		if (!modifiedDate || !createdDate) {
			modifiedDate = createdDate = CFAbsoluteTimeGetCurrent();
			dateModifiedString = [dateCreatedString = [[NSString relativeDateStringWithAbsoluteTime:createdDate] retain] retain];	
		}
	
        [self updateTablePreviewString];
    
        return self;
    }
    return nil;
}

//assume any changes have been synchronized with undomanager
- (void)setContentString:(NSAttributedString*)attributedString {
	[self setContentString:attributedString updateTime:YES];
}

- (void)setContentString:(NSAttributedString*)attributedString updateTime:(BOOL)updateTime {
	if (attributedString) {
		[contentString setAttributedString:[[[NSAttributedString alloc] initWithString:[attributedString string] attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]] autorelease]];
		
		[self updateTablePreviewString];
		contentCacheNeedsUpdate = YES;
		//[self updateContentCacheCStringIfNecessary];
		
		[delegate note:self attributeChanged:NotePreviewString];
	
		[self makeNoteDirtyUpdateTime:updateTime updateFile:YES];

        [[NSNotificationCenter defaultCenter] postNotificationName:NVNoteContentsDidChangeNotification object:self];
	}
}
- (NSAttributedString*)contentString {
	return contentString;
}

- (void)updateContentCacheCStringIfNecessary {
	if (contentCacheNeedsUpdate) {
		//NSLog(@"updating ccache strs");
		cContentsFoundPtr = cContents = replaceString(cContents, [[contentString string] lowercaseUTF8String]);
		contentCacheNeedsUpdate = NO;
		
		unsigned long len = strlen(cContents);
		contentsWere7Bit = !(ContainsHighAscii(cContents, len));
		
		//could cache dumbwordcount here for faster launch, but string creation takes more time, anyway
		//if (wordCountString) CFRelease((CFStringRef*)wordCountString); //this is CFString, so bridge will just call back to CFRelease, anyway
		//wordCountString = (NSString*)CFStringFromBase10Integer(DumbWordCount(cContents, len));
	}
}

- (void)initContentCacheCString {

	if (contentsWere7Bit) {
		if (!(cContentsFoundPtr = cContents = [[contentString string] copyLowercaseASCIIString]))
			contentsWere7Bit = NO;
	}
	
	size_t len = -1;
	
	if (!contentsWere7Bit) {
		const char *cStringData = [[contentString string] lowercaseUTF8String];
		cContentsFoundPtr = cContents = cStringData ? strdup(cStringData) : NULL;
		
		contentsWere7Bit = cContents ? !(ContainsHighAscii(cContents, (len = strlen(cContents)))) : NO;
	}
	
	//if (len < 0) len = strlen(cContents);
	//wordCountString = (NSString*)CFStringFromBase10Integer(DumbWordCount(cContents, len));
	
	contentCacheNeedsUpdate = NO;
}

- (BOOL)contentsWere7Bit {
	return contentsWere7Bit;
}

- (NSString*)description {
	return titleString;
}

- (NSAttributedString*)printableStringRelativeToBodyFont:(NSFont*)bodyFont {
	NSFont *titleFont = [NSFont fontWithName:[bodyFont fontName] size:[bodyFont pointSize] + 6.0f];
	
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:titleFont, NSFontAttributeName, nil];
	
	NSMutableAttributedString *largeAttributedTitleString = [[[NSMutableAttributedString alloc] initWithString:titleString attributes:dict] autorelease];
	
	NSAttributedString *noAttrBreak = [[NSAttributedString alloc] initWithString:@"\n\n\n" attributes:nil];
	[largeAttributedTitleString appendAttributedString:noAttrBreak];
	[noAttrBreak release];

	//other header things here, too? like date created/mod/printed? tags?
	NSMutableAttributedString *contentMinusColor = [[self contentString] mutableCopy];
	[contentMinusColor removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [contentMinusColor length])];
	
	[largeAttributedTitleString appendAttributedString:contentMinusColor];
	
	[contentMinusColor release];
	
	return largeAttributedTitleString;
}

- (void)updateTablePreviewString {
	//delegate required for this method
	[tableTitleString release];
	GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];

	if ([prefs tableColumnsShowPreview]) {
		if ([prefs horizontalLayout]) {
			//is called for visible notes at launch and resize only, generation of images for invisible notes is delayed until after launch
			
			NSSize labelBlockSize = ColumnIsSet(NoteLabelsColumn, [prefs tableColumnsBitmap]) ? [self sizeOfLabelBlocks] : NSZeroSize;
			tableTitleString = [[titleString attributedMultiLinePreviewFromBodyText:contentString upToWidth:[delegate titleColumnWidth] 
																	 intrusionWidth:labelBlockSize.width] retain];
		} else {
			tableTitleString = [[titleString attributedSingleLinePreviewFromBodyText:contentString upToWidth:[delegate titleColumnWidth]] retain];
		}
	} else {
		if ([prefs horizontalLayout]) {
			tableTitleString = [[titleString attributedSingleLineTitle] retain];
		} else {
			tableTitleString = nil;
		}
	}
}

- (void)setTitleString:(NSString*)aNewTitle {
	
	NSString *oldTitle = [titleString retain];
	
    if ([self _setTitleString:aNewTitle]) {
		//do you really want to do this when the format is a single DB and the file on disk hasn't been removed?
		//the filename could get out of sync if we lose the fsref and we could end up with a second file after note is rewritten
		
		//solution: don't change the name in that case and allow its new name to be generated
		//when the format is changed and the file rewritten?
		
		
		
		//however, the filename is used for exporting and potentially other purposes, so we should also update
		//it if we know that is has no currently existing (older) counterpart in the notes directory
		
		//woe to the exporter who also left the note files in the notes directory after switching to a singledb format
		//his note names might not be up-to-date
		if ([delegate currentNoteStorageFormat] != SingleDatabaseFormat || 
			![delegate notesDirectoryContainsFile:filename returningFSRef:noteFileRefInit(self)]) {
			
			[self setFilenameFromTitle];
		}
		
		//yes, the given extension could be different from what we had before
		//but makeNoteDirty will eventually cause it to be re-written in the current format
		//and thus the format ID will be changed if that was the case
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		
		[self updateTablePreviewString];
		
		/*NSUndoManager *undoMan = [delegate undoManager];
		[undoMan registerUndoWithTarget:self selector:@selector(setTitleString:) object:oldTitle];
		if (![undoMan isUndoing] && ![undoMan isRedoing])
			[undoMan setActionName:[NSString stringWithFormat:@"Rename Note \"%@\"", titleString]];
		*/
		[oldTitle release];
		
		[delegate note:self attributeChanged:NoteTitleColumnString];
    }
}

- (BOOL)_setTitleString:(NSString*)aNewTitle {
    if (!aNewTitle || ![aNewTitle length] || (titleString && [aNewTitle isEqualToString:titleString]))
	return NO;

    [titleString release];
    titleString = [aNewTitle copy];
    
    cTitleFoundPtr = cTitle = replaceString(cTitle, [titleString lowercaseUTF8String]);
    
    return YES;
}

- (void)setFilenameFromTitle {
	[self setFilename:[delegate uniqueFilenameForTitle:titleString fromNote:self] withExternalTrigger:NO];
}

- (void)setFilename:(NSString*)aString withExternalTrigger:(BOOL)externalTrigger {
    
    if (!filename || ![aString isEqualToString:filename]) {
		NSString *oldName = filename;
		filename = [aString copy];
		
		if (!externalTrigger) {
			if ([delegate noteFileRenamed:noteFileRefInit(self) fromName:oldName toName:filename] != noErr) {
				NSLog(@"Couldn't rename note %@", titleString);
				
				//revert name
				[filename release];
				filename = [oldName retain];
				return;
			}
		} else {
			[self _setTitleString:[aString stringByDeletingPathExtension]];	
			
			[self updateTablePreviewString];
			[delegate note:self attributeChanged:NoteTitleColumnString];
		}
		
		[self makeNoteDirtyUpdateTime:YES updateFile:NO];
		
		[delegate updateLinksToNote:self fromOldName:oldName];
		//update all the notes that link to the old filename as well!!
		
		[oldName release];
    }
}


- (void)_resanitizeContent {
	[contentString setAttributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes] range:NSMakeRange(0, [contentString length])];
	
	//renormalize the title, in case it is still somehow derived from decomposed HFS+ filenames
	CFMutableStringRef normalizedString = CFStringCreateMutableCopy(NULL, 0, (CFStringRef)titleString);
	CFStringNormalize(normalizedString, kCFStringNormalizationFormC);
	
	[self _setTitleString:(NSString*)normalizedString];
	CFRelease(normalizedString);
	

}


- (void)updateDateStrings {
	[dateModifiedString release];
	[dateCreatedString release];
	
	dateCreatedString = [[NSString relativeDateStringWithAbsoluteTime:createdDate] retain];
	dateModifiedString = [[NSString relativeDateStringWithAbsoluteTime:modifiedDate] retain];
}

- (void)setDateModified:(CFAbsoluteTime)newTime {
	modifiedDate = newTime;
	
	[dateModifiedString release];
	
	dateModifiedString = [[NSString relativeDateStringWithAbsoluteTime:modifiedDate] retain];
}

- (void)setDateAdded:(CFAbsoluteTime)newTime {
	createdDate = newTime;
	
	[dateCreatedString release];
	
	dateCreatedString = [[NSString relativeDateStringWithAbsoluteTime:createdDate] retain];	
}


- (void)setSelectedRange:(NSRange)newRange {
	//if (!newRange.length) newRange = NSMakeRange(0,0);
	
	//don't save the range if it's invalid, it's equal to the current range, or the entire note is selected
	if ((newRange.location != NSNotFound) && !NSEqualRanges(newRange, selectedRange) && 
		!NSEqualRanges(newRange, NSMakeRange(0, [contentString length]))) {
	//	NSLog(@"saving: old range: %@, new range: %@", NSStringFromRange(selectedRange), NSStringFromRange(newRange));
		selectedRange = newRange;
		[self makeNoteDirtyUpdateTime:NO updateFile:NO];
	}
}

- (NSRange)lastSelectedRange {
	return selectedRange;
}

//these two methods let us get the actual label objects in use by other notes
//they assume that the label string already contains the title of the label object(s); that there is only replacement and not addition
- (void)replaceMatchingLabelSet:(NSSet*)aLabelSet {
    [labelSet minusSet:aLabelSet];
    [labelSet unionSet:aLabelSet];
}

- (void)replaceMatchingLabel:(LabelObject*)aLabel {
    [aLabel retain]; // just in case this is actually the same label
    
    //remove the old label and add the new one; if this is the same one, well, too bad
    [labelSet removeObject:aLabel];
    [labelSet addObject:aLabel];
    [aLabel release];
}

- (void)updateLabelConnectionsAfterDecoding {
	if ([labelString length] > 0) {
		[self updateLabelConnections];
	}
}

- (void)updateLabelConnections {
	//find differences between previous labels and new ones	
	if (delegate) {
		NSMutableSet *oldLabelSet = labelSet;
		NSMutableSet *newLabelSet = [self labelSetFromCurrentString];
		
		if (!oldLabelSet) {
			oldLabelSet = labelSet = [[NSMutableSet alloc] initWithCapacity:[newLabelSet count]];
		}
		
		//what's left-over
		NSMutableSet *oldLabels = [oldLabelSet mutableCopy];
		[oldLabels minusSet:newLabelSet];
		
		//what wasn't there last time
		NSMutableSet *newLabels = newLabelSet;
		[newLabels minusSet:oldLabelSet];
		
		//update the currently known labels
		[labelSet minusSet:oldLabels];
		[labelSet unionSet:newLabels];
		
		//update our status within the list of all labels, adding or removing from the list and updating the labels where appropriate
		//these end up calling replaceMatchingLabel*
		[delegate note:self didRemoveLabelSet:oldLabels];
        [oldLabels release];
		[delegate note:self didAddLabelSet:newLabels];
	}
}

- (void)disconnectLabels {
	//when removing this note from NotationController, other LabelObjects as well as LabelsListController should know not to list it
	if (delegate) {
		[delegate note:self didRemoveLabelSet:labelSet];
		[labelSet autorelease];
		labelSet = nil;
	} else {
		NSLog(@"not disconnecting labels because no delegate exists");
	}
}

- (BOOL)_setLabelString:(NSString*)newLabelString {
	if (newLabelString && ![newLabelString isEqualToString:labelString]) {
		
		[labelString release];
		labelString = [newLabelString copy];
		
		cLabelsFoundPtr = cLabels = replaceString(cLabels, [labelString lowercaseUTF8String]);
		
		[self updateLabelConnections];
		return YES;
	}
	return NO;
}

- (void)setLabelString:(NSString*)newLabelString {
	
	if ([self _setLabelString:newLabelString]) {
	
		if ([[GlobalPrefs defaultPrefs] horizontalLayout]) {
			[self updateTablePreviewString];
		}
		
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		
		[delegate note:self attributeChanged:NoteLabelsColumnString];
	}
}

- (NSMutableSet*)labelSetFromCurrentString {
	
	NSArray *words = [self orderedLabelTitles];
	NSMutableSet *newLabelSet = [NSMutableSet setWithCapacity:[words count]];
	
	unsigned int i;
	for (i=0; i<[words count]; i++) {
		NSString *aWord = [words objectAtIndex:i];
		
		if ([aWord length] > 0) {
			LabelObject *aLabel = [[LabelObject alloc] initWithTitle:aWord];
			[aLabel addNote:self];
			
			[newLabelSet addObject:aLabel];
			[aLabel autorelease];
		}
	}
	
	return newLabelSet; 
}


- (NSArray*)orderedLabelTitles {
	return [labelString labelCompatibleWords];
}

- (NSSize)sizeOfLabelBlocks {
	NSSize size = NSZeroSize;
	[self _drawLabelBlocksInRect:NSZeroRect rightAlign:NO highlighted:NO getSizeOnly:&size];
	return size;
}

- (void)drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted {
	return [self _drawLabelBlocksInRect:aRect rightAlign:onRight highlighted:isHighlighted getSizeOnly:NULL];
}

- (void)_drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted getSizeOnly:(NSSize*)reqSize {
	//used primarily by UnifiedCell, but also by LabelColumnCell, as well as to determine the width of all label-block-images for this note
	//iterate over words in orderedLabelTitles, retrieving images via -[LabelsListController cachedLabelImageForWord:highlighted:]
	//if right-align is enabled, then the label-images are queued on the first pass and drawn in reverse on the second
	
	CGFloat totalWidth = 0.0, height = 0.0;
	
	if (![labelString length]) goto returnSizeIfNecessary;
	
	NSArray *words = [self orderedLabelTitles];
	if (![words count]) goto returnSizeIfNecessary;
	
	NSPoint nextBoxPoint = onRight ? NSMakePoint(NSMaxX(aRect), aRect.origin.y) : aRect.origin;
	NSMutableArray *images = reqSize || !onRight ? nil : [NSMutableArray arrayWithCapacity:[words count]];
    CGFloat tableFontSize = [[GlobalPrefs defaultPrefs] tableFontSize] - 1.0f;
    nextBoxPoint.y-=round(tableFontSize * 1.3f);
    NSRect dRect=NSZeroRect;
	NSInteger i;
	
	for (i=0; i<(NSInteger)[words count]; i++) {
		NSString *word = [words objectAtIndex:i];
		if ([word length]) {
			NSImage *img = [[delegate labelsListDataSource] cachedLabelImageForWord:word highlighted:isHighlighted];
			
            dRect.origin=nextBoxPoint;
            dRect.size=[img size];
			if (!reqSize) {
				if (onRight) {
					[images addObject:img];
				} else {
//					[img compositeToPoint:nextBoxPoint operation:NSCompositeSourceOver];
                    
                    [img drawInRect:dRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f respectFlipped:YES hints:nil];
					nextBoxPoint.x += [img size].width + 4.0;
				}
			} else {
				totalWidth += [img size].width + 4.0;
				height = MAX(height, [img size].height);
			}
		}
	}
	
	if (!reqSize) {
		if (onRight) {
			//draw images in reverse instead
			for (i = [images count] - 1; i>=0; i--) {
				NSImage *img = [images objectAtIndex:i];
				nextBoxPoint.x -= [img size].width + 4.0;
                dRect.origin=nextBoxPoint;
                dRect.size=[img size];
//				[img compositeToPoint:nextBoxPoint operation:NSCompositeSourceOver];
              [img drawInRect:dRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f respectFlipped:YES hints:nil];
			}
		}
	} else {
	returnSizeIfNecessary:
		if (reqSize) *reqSize = NSMakeSize(totalWidth, height);
	}
}


- (NSURL*)uniqueNoteLink {
		
	NSMutableDictionary *idsDict = [NSMutableDictionary dictionaryWithCapacity:1];

	[idsDict setObject:[[NSData dataWithBytes:&uniqueNoteIDBytes length:16] encodeBase64WithNewlines:NO] forKey:@"NV"];
	
	return [NSURL URLWithString:[[NVNoteURLScheme() stringByAppendingString:@"://find/"] stringByAppendingFormat:@"%@/?%@", [titleString stringWithPercentEscapes],
								 [idsDict URLEncodedString]]];
}

- (NSString*)noteFilePath {
	UniChar chars[256];
	if ([delegate refreshFileRefIfNecessary:noteFileRefInit(self) withName:filename charsBuffer:chars] == noErr)
		return [[NSFileManager defaultManager] pathWithFSRef:noteFileRefInit(self)];
	return nil;
}

- (void)detachFromClosedLibrary { delegate = nil; }

- (void)prepareForBackupRestore {
    NSAssert(!delegate, @"Restore notes must not belong to an open library");
    [self invalidateFSRef];
    [filename release];
    filename = nil;
    nodeID = logicalSize = logSequenceNumber = 0;
    memset(&fileModifiedDate, 0, sizeof(fileModifiedDate));
    free(perDiskInfoGroups);
    perDiskInfoGroups = calloc(1, sizeof(PerDiskInfo));
    perDiskInfoGroups[0].diskIDIndex = -1;
    perDiskInfoGroupCount = 1;
    attrsModifiedDate = &perDiskInfoGroups[0].attrTime;
    currentFormatID = SingleDatabaseFormat;
    // Pending conversion and original bytes remain archived even in database storage.
    shouldWriteToFile = sourceConversionPending;
    selectedRange = NSMakeRange(NSNotFound, 0);
}

- (void)invalidateFSRef {
	//bzero(&noteFileRef, sizeof(FSRef));
	if (noteFileRef)
		free(noteFileRef);
	noteFileRef = NULL;
}

- (BOOL)hasPendingSourceFileWrite { return shouldWriteToFile; }

- (BOOL)writeUsingCurrentFileFormatIfNecessary {
	//if note had been updated via makeNoteDirty and needed file to be rewritten
	if (shouldWriteToFile) {
		return [self writeUsingCurrentFileFormat];
	}
	return NO;
}

- (BOOL)writeUsingCurrentFileFormatIfNonExistingOrChanged {
    BOOL fileWasCreated = NO;
    BOOL fileIsOwned = NO;
	
    if ([delegate createFileIfNotPresentInNotesDirectory:noteFileRefInit(self) forFilename:filename fileWasCreated:&fileWasCreated] != noErr)
		return NO;
    
    if (fileWasCreated) {
		NSLog(@"writing note %@, because it didn't exist", titleString);
		return [self writeUsingCurrentFileFormat];
    }
    
	//createFileIfNotPresentInNotesDirectory: works by name, so if this file is not owned by us at this point, it was a race with moving it
    FSCatalogInfo info;
    if ([delegate fileInNotesDirectory:noteFileRefInit(self) isOwnedByUs:&fileIsOwned hasCatalogInfo:&info] != noErr)
		return NO;
    
    CFAbsoluteTime timeOnDisk, lastTime;
    OSStatus err = noErr;
    if ((err = (UCConvertUTCDateTimeToCFAbsoluteTime(&fileModifiedDate, &lastTime) == noErr)) &&
		(err = (UCConvertUTCDateTimeToCFAbsoluteTime(&info.contentModDate, &timeOnDisk) == noErr))) {
		
		if (lastTime > timeOnDisk) {
			NSLog(@"writing note %@, because it was modified", titleString);
			return [self writeUsingCurrentFileFormat];
		}
    } else {
		NSLog(@"Could not convert dates: %d", err);
		return NO;
    }
    
    return YES;
}

- (BOOL)writeUsingJournal:(WALStorageController*)wal {
    BOOL wroteAllOfNote = [wal writeEstablishedNote:self];
	
    if (wroteAllOfNote) {
		//update formatID to absolutely ensure we don't reload an earlier note back from disk, from text encoding menu, for example
		//currentFormatID = SingleDatabaseFormat;
	} else {
		[delegate noteDidNotWrite:self errorCode:kWriteJournalErr];
	}
    
    return wroteAllOfNote;
}

- (BOOL)mirrorTags {
	if ([delegate currentNoteStorageFormat] == SingleDatabaseFormat)
		return NO;

	@try {
        
		NSArray *newTags=[[NSFileManager defaultManager] mergedTagsForFileAtPath:[[self noteFilePath] UTF8String]];
        NSString *newLabelString=nil;
        if ((newTags==nil)||newTags.count==0) {
            newLabelString=@"";
        }else{
            newLabelString=[newTags componentsJoinedByString:@","];
        }
        [self setLabelString:newLabelString];
        if([self writeUsingCurrentFileFormat]){
            return YES;
        }
        
	}
	@catch (NSException *exception) {
		NSLog(@"%@",exception);
	}
    NSLog(@"didn't mirrror:>%@<",titleString);
    return NO;

}


- (BOOL)writeUsingCurrentFileFormat {

    NSInteger formatID = [delegate currentNoteStorageFormat];
	if (formatID != PlainTextFormat) return NO;
	if (![self preservePendingSourceFileChanges]) return NO;
	NSError *encodingError = nil;
	NSData *formattedData = [self sourceDataReturningError:&encodingError];
	if (!formattedData) {
		if (!sourceConversionPending) {
			sourceConversionPending = YES;
			[self makeNoteDirtyUpdateTime:NO updateFile:YES];
		}
		[[EncodingsManager sharedManager] offerUTF8ConversionForNote:self];
		return NO;
	}

    if (formattedData) {
		BOOL resetFilename = NO;
		if (!filename || currentFormatID != formatID) {
			//file will (probably) be renamed
			//NSLog(@"resetting the file name due to format change: to %d from %d", formatID, currentFormatID);
			[self setFilenameFromTitle];
			resetFilename = YES;
		}
		
		currentFormatID = formatID;
		
		//perhaps check here to see if the file was updated on disk before we had a chance to do it ourselves
		//see if the file's fileModDate (if it exists) is newer than this note's current fileModificationDate
		//could offer to merge or revert changes
		
		OSStatus err = noErr;
		if ((err = [delegate storeDataAtomicallyInNotesDirectory:formattedData withName:filename destinationRef:noteFileRefInit(self)]) != noErr) {
			NSLog(@"Unable to save note file %@", filename);
			
			[delegate noteDidNotWrite:self errorCode:err];
			return NO;
		}
		//if writing plaintext set the file encoding with setxattr
		if (PlainTextFormat == formatID) {
			(void)[self writeCurrentFileEncodingToFSRef:noteFileRefInit(self)];
		}
		NSFileManager *fileMan = [NSFileManager defaultManager];
		[fileMan setTags:[self orderedLabelTitles] atFSPath:[[fileMan pathWithFSRef:noteFileRefInit(self)] fileSystemRepresentation]];
		
		//always hide the file extension for all types
		LSSetExtensionHiddenForRef(noteFileRefInit(self), TRUE);
		
		if (!resetFilename) {
			//NSLog(@"resetting the file name just because.");
			[self setFilenameFromTitle];
		}
		
		(void)[self writeFileDatesAndUpdateTrackingInfo];
		
		
		//finished writing to file successfully
		[self rememberSourceData:formattedData encoding:fileEncoding];
		shouldWriteToFile = NO;
		sourceConversionPending = NO;
		
		
		//tell any external editors that we've changed
		
    } else {
		[delegate noteDidNotWrite:self errorCode:kDataFormattingErr];
		NSLog(@"Unable to convert note contents into format %ld", (long)formatID);
		return NO;
    }
    
    return YES;
}

- (OSStatus)writeFileDatesAndUpdateTrackingInfo {
	if (SingleDatabaseFormat == currentFormatID) return noErr;
	
	//sync the file's creation and modification date:
	FSCatalogInfo catInfo;
	UCConvertCFAbsoluteTimeToUTCDateTime(createdDate, &catInfo.createDate);
	UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &catInfo.contentModDate);
	
	// if this method is called anywhere else, then use [delegate refreshFileRefIfNecessary:noteFileRefInit(self) withName:filename charsBuffer:chars]; instead
	// for now, it is not called in any situations where the fsref might accidentally point to a moved file
	OSStatus err = noErr;
	do {
		if (noErr != err || IsZeros(noteFileRefInit(self), sizeof(FSRef))) {
			if (![delegate notesDirectoryContainsFile:filename returningFSRef:noteFileRefInit(self)]) return fnfErr;
		}
		err = FSSetCatalogInfo(noteFileRefInit(self), kFSCatInfoCreateDate | kFSCatInfoContentMod, &catInfo);
	} while (fnfErr == err);

	if (noErr != err) {
		NSLog(@"could not set catalog info: %d", err);
		return err;
	}
	
	//regardless of whether FSSetCatalogInfo was successful, the file mod date could still have changed
	
	if ((err = [delegate fileInNotesDirectory:noteFileRefInit(self) isOwnedByUs:NULL hasCatalogInfo:&catInfo]) != noErr) {
		NSLog(@"Unable to get new modification date of file %@: %d", filename, err);
		return err;
	}
	fileModifiedDate = catInfo.contentModDate;
	setAttrModifiedDate(self, &catInfo.attributeModDate);
	setCatalogNodeID(self, catInfo.nodeID);
	logicalSize = (UInt32)(catInfo.dataLogicalSize & 0xFFFFFFFF);
	
	return noErr;
}

- (OSStatus)writeCurrentFileEncodingToFSRef:(FSRef*)fsRef {
	NSAssert(fsRef, @"cannot write file encoding to a NULL FSRef");
	//this is not the note's own fsRef; it could be anywhere
	
	NSMutableData *pathData = [NSMutableData dataWithLength:4 * 1024];
	OSStatus err = noErr;
	if ((err = FSRefMakePath(fsRef, [pathData mutableBytes], [pathData length])) == noErr) {
		[[NSFileManager defaultManager] setTextEncodingAttribute:fileEncoding atFSPath:[pathData bytes]];
	} else {
		NSLog(@"%@: error getting path from FSRef: %d (IsZeros: %d)", NSStringFromSelector(_cmd), err, IsZeros(fsRef, sizeof(fsRef)));
	}
	return err;
}

- (BOOL)upgradeToUTF8IfUsingSystemEncoding {
	// Automatic legacy upgrades no longer change a source file encoding.
	return NO;
}

- (BOOL)upgradeEncodingToUTF8 {
	//"convert" the file to have a UTF-8 encoding
	BOOL didUpgrade = YES;
	
	if (NSUTF8StringEncoding != fileEncoding) {
		[self _setFileEncoding:NSUTF8StringEncoding];
		
		if ([delegate currentNoteStorageFormat] == PlainTextFormat) didUpgrade = [self writeUsingCurrentFileFormat];

		//make note dirty to ensure these changes are saved
		[self makeNoteDirtyUpdateTime:NO updateFile:NO];
	} else if (sourceConversionPending && [delegate currentNoteStorageFormat] == PlainTextFormat) {
		didUpgrade = [self writeUsingCurrentFileFormat];
		[self makeNoteDirtyUpdateTime:NO updateFile:NO];
	}
	return didUpgrade;
}

- (void)_setFileEncoding:(NSStringEncoding)encoding {
	if (fileEncoding != encoding) {
		[sourceByteOrderMark release];
		sourceByteOrderMark = nil;
	}
	fileEncoding = encoding;
}

- (BOOL)setFileEncodingAndReinterpret:(NSStringEncoding)encoding {
	if (sourceConversionPending) return NO;
	//"reinterpret" the file using this encoding, also setting the actual file's extended attributes to match
	BOOL updated = YES;
	
	if (encoding != fileEncoding) {
		[self _setFileEncoding:encoding];
		
		//write the file encoding extended attribute before updating from disk. why?
		//a) to ensure -updateFromData: finds the right encoding when re-reading the file, and
		//b) because the file is otherwise not being rewritten, and the extended attribute--if it existed--may have been different
		
		UniChar chars[256];
		if ([delegate refreshFileRefIfNecessary:noteFileRefInit(self) withName:filename charsBuffer:chars] != noErr)
			return NO;
		
		if ([self writeCurrentFileEncodingToFSRef:noteFileRefInit(self)] != noErr)
			return NO;		
		
		if ((updated = [self updateFromFile])) {
			[self makeNoteDirtyUpdateTime:NO updateFile:NO];
			//[[delegate delegate] contentsUpdatedForNote:self];
		}
	}
	
	return updated;
}

- (BOOL)updateFromFile {
    NSMutableData *data = [delegate dataFromFileInNotesDirectory:noteFileRefInit(self) forFilename:filename];
    if (!data) {
		NSLog(@"Couldn't update note from file on disk");
		return NO;
    }
	
    if ([self updateFromData:data inFormat:currentFormatID]) {
		FSCatalogInfo info;
		if ([delegate fileInNotesDirectory:noteFileRefInit(self) isOwnedByUs:NULL hasCatalogInfo:&info] == noErr) {
			fileModifiedDate = info.contentModDate;
			setAttrModifiedDate(self, &info.attributeModDate);
			setCatalogNodeID(self, info.nodeID);
			logicalSize = (UInt32)(info.dataLogicalSize & 0xFFFFFFFF);
			
			return YES;
		}
    }
    return NO;
}

- (BOOL)updateFromCatalogEntry:(NoteCatalogEntry*)catEntry {
	BOOL didRestoreLabels = NO;
	
    NSMutableData *data = [delegate dataFromFileInNotesDirectory:noteFileRefInit(self) forCatalogEntry:catEntry];
    if (!data) {
		NSLog(@"Couldn't update note from file on disk given catalog entry");
		return NO;
    }
	    
    if (![self updateFromData:data inFormat:currentFormatID])
		return NO;
	
	[self setFilename:(NSString*)catEntry->filename withExternalTrigger:YES];
    
    fileModifiedDate = catEntry->lastModified;
	setAttrModifiedDate(self, &(catEntry->lastAttrModified));
    setCatalogNodeID(self, catEntry->nodeID);
	logicalSize = catEntry->logicalSize;
	
	NSMutableData *pathData = [NSMutableData dataWithLength:4 * 1024];
	if (FSRefMakePath(noteFileRefInit(self), [pathData mutableBytes], [pathData length]) == noErr) {
		
		NSArray *openMetaTags = [[NSFileManager defaultManager] getTagsAtFSPath:[pathData bytes]];
		if (openMetaTags) {
			//overwrite this note's labels with those from the file; merging may be the wrong thing to do here
			if ([self _setLabelString:[openMetaTags componentsJoinedByString:@" "]])
				[self updateTablePreviewString];
		} else if ([labelString length]) {
			//this file has either never had tags or has had them cleared by accident (e.g., non-user intervention)
			//so if this note still has tags, then restore them now.
			
			NSLog(@"restoring lost tags for %@", titleString);
			[[NSFileManager defaultManager] setTags:[self orderedLabelTitles] atFSPath:[pathData bytes]];
			didRestoreLabels = YES;
		}
	}
	
	OSStatus err = noErr;
	CFAbsoluteTime aModDate, aCreateDate;
	if (noErr == (err = UCConvertUTCDateTimeToCFAbsoluteTime(&fileModifiedDate, &aModDate))) {
		[self setDateModified:aModDate];
	}
	
	if (createdDate == 0.0 || didRestoreLabels) {
		//when reading files from disk for the first time, grab their creation date
		//or if this file has just been altered, grab its newly-changed modification dates
		
		FSCatalogInfo info;
		if ([delegate fileInNotesDirectory:noteFileRefInit(self) isOwnedByUs:NULL hasCatalogInfo:&info] == noErr) {
			if (createdDate == 0.0 && UCConvertUTCDateTimeToCFAbsoluteTime(&info.createDate, &aCreateDate) == noErr) {
				[self setDateAdded:aCreateDate];
			}
			if (didRestoreLabels) {
				fileModifiedDate = info.contentModDate;
				setAttrModifiedDate(self, &info.attributeModDate);
			}
		}
	}
	
    return YES;
}

- (BOOL)updateFromData:(NSMutableData*)data inFormat:(NSInteger)fmt {
    
    if (!data) {
		NSLog(@"%@: Data is nil!", NSStringFromSelector(_cmd));
		return NO;
    }
    
    if (fmt != PlainTextFormat) return NO;
	NSString *stringFromData = [[self class] sourceStringFromData:data encoding:&fileEncoding path:[self noteFilePath]];
	if (!stringFromData) return NO;
	NSMutableAttributedString *attributedStringFromData = [[NSMutableAttributedString alloc] initWithString:stringFromData attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
	[self rememberSourceData:data encoding:fileEncoding];
	[contentString release];
	contentString = [attributedStringFromData retain];
	//NSLog(@"%s(%@): %@", _cmd, [self noteFilePath], [contentString string]);
	
	//[contentString setAttributedString:attributedStringFromData];
	contentCacheNeedsUpdate = YES;
    [self updateContentCacheCStringIfNecessary];
	[undoManager removeAllActions];
	
	[self updateTablePreviewString];
    
	//don't update the date modified here, as this could be old data
    
    [attributedStringFromData release];
    
    return YES;
}

- (void)moveFileToTrash {
	OSStatus err = noErr;
	if ((err = [delegate moveFileToTrash:noteFileRefInit(self) forFilename:filename]) != noErr) {
		NSLog(@"Couldn't move file to trash: %d", err);
	} else {
		//file's gone! don't assume it's not coming back. if the storage format was not single-db, this note better be removed
		//currentFormatID = SingleDatabaseFormat;
	}
}

- (void)removeFileFromDirectory {
#if PERMADELETE
	OSStatus err = noErr;
	if ((err = [delegate deleteFileInNotesDirectory:noteFileRefInit(self) forFilename:filename]) != noErr) {
		
		if (err != fnfErr) {
			//what happens if we wanted to undo the deletion? moveFileToTrash will now tell the note that it shouldn't look for the file
			//so it would not be rewritten on re-creation?
			NSLog(@"Unable to delete file %@ (%d); moving to trash instead", filename, err);
			[self moveFileToTrash];
		}
	}
#else
	[self moveFileToTrash];
#endif
}

- (BOOL)removeUsingJournal:(WALStorageController*)wal {
    return [wal writeRemovalForNote:self];
}

- (void)makeNoteDirtyUpdateTime:(BOOL)updateTime updateFile:(BOOL)updateFile {
	
	if (updateFile)
		shouldWriteToFile = YES;
	//else we don't turn file updating off--we might be overwriting the state of a previous note-dirty message
	
	if (updateTime) {
		[self setDateModified:CFAbsoluteTimeGetCurrent()];
		
		if ([delegate currentNoteStorageFormat] == SingleDatabaseFormat) {
			//only set if we're not currently synchronizing to avoid re-reading old data
			//this will be updated again when writing to a file, but for now we have the newest version
			//we must do this to allow new notes to be written when switching formats, and for encodingmanager checks
			if (UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &fileModifiedDate) != noErr)
				NSLog(@"Unable to set file modification date from current date");
		}
	}
	
	//queue note to be written
    [delegate scheduleWriteForNote:self];	
	
	//tell delegate that the date modified changed
	//[delegate note:self attributeChanged:NoteDateModifiedColumnString];
	//except we don't want this here, as it will cause unnecessary (potential) re-sorting and updating of list view while typing
	//so expect the delegate to know to schedule the same update itself
}

- (OSStatus)exportToDirectoryRef:(FSRef*)directoryRef withFilename:(NSString*)userFilename usingFormat:(int)storageFormat overwrite:(BOOL)overwrite {
	
	if (storageFormat != PlainTextFormat) return kDataFormattingErr;
	NSError *error = nil;
	NSData *formattedData = [self sourceDataReturningError:&error];
	if (!formattedData) [[EncodingsManager sharedManager] offerUTF8ConversionForNote:self];
	if (!formattedData)
		return kDataFormattingErr;
		
	//can use our already-determined filename to write here
	//but what about file names that were the same except for their extension? e.g., .txt vs. .text
	//this will give them the same extension and cause an overwrite
	NSString *newextension = [NotationPrefs pathExtensionForFormat:storageFormat];
	NSString *newfilename = userFilename ? userFilename : [[filename stringByDeletingPathExtension] stringByAppendingPathExtension:newextension];
	//one last replacing, though if the unique file-naming method worked this should be unnecessary
	newfilename = [newfilename stringByReplacingOccurrencesOfString:@":" withString:@"/"];
	
	BOOL fileWasCreated = NO;
	
	FSRef fileRef;
	OSStatus err = FSCreateFileIfNotPresentInDirectory(directoryRef, &fileRef, (CFStringRef)newfilename, (Boolean*)&fileWasCreated);
	if (err != noErr) {
		NSLog(@"FSCreateFileIfNotPresentInDirectory: %d", err);
		return err;
	}
	if (!fileWasCreated && !overwrite) {
		NSLog(@"File already existed!");
		return dupFNErr;
	}
	//yes, the file is probably not on the same volume as our notes directory
	if ((err = FSRefWriteData(&fileRef, BlockSizeForNotation(delegate), [formattedData length], [formattedData bytes], 0, true)) != noErr) {
		NSLog(@"error writing to temporary file: %d", err);
		return err;
    }
	if (PlainTextFormat == storageFormat) {
		(void)[self writeCurrentFileEncodingToFSRef:&fileRef];
	}
	NSFileManager *fileMan = [NSFileManager defaultManager];
	[fileMan setTags:[self orderedLabelTitles] atFSPath:[[fileMan pathWithFSRef:&fileRef] fileSystemRepresentation]];
	
	//also export the note's modification and creation dates
	FSCatalogInfo catInfo;
	UCConvertCFAbsoluteTimeToUTCDateTime(createdDate, &catInfo.createDate);
	UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &catInfo.contentModDate);
	FSSetCatalogInfo(&fileRef, kFSCatInfoCreateDate | kFSCatInfoContentMod, &catInfo);
			
	return noErr;
}

- (void)editExternallyUsingEditor:(ExternalEditor*)ed {
	[[ODBEditor sharedODBEditor] editNote:self inEditor:ed context:nil];
}

- (void)previewUsingMarked {
	NSWorkspace * ws = [NSWorkspace sharedWorkspace];
	if ([[ws URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked2"] isFileURL] || [[ws URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked-setapp"] isFileURL] || [[ws URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked2.beta"] isFileURL])
    {
		[ws openFile:[self noteFilePath] withApplication:@"Marked 2" andDeactivate:NO];
	} else if ([[ws URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marky"] isFileURL])
	{
		[ws openFile:[self noteFilePath] withApplication:@"Marked" andDeactivate:NO];
	}
}

- (void)abortEditingInExternalEditor {
	[[ODBEditor sharedODBEditor] abortAllEditingSessionsForClient:self];
}

-(void)odbEditor:(ODBEditor *)editor didModifyFile:(NSString *)path newFileLocation:(NSString *)newPath  context:(NSDictionary *)context {

	//read path/newPath into NSData and update note contents
	
	//can't use updateFromCatalogEntry because it would assign ownership via various metadata
	
	if ([self updateFromData:[NSMutableData dataWithContentsOfFile:path options:NSUncachedRead error:NULL] inFormat:PlainTextFormat]) {
		//reflect the temp file's changes directly back to the backing source file and database
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		
		[delegate note:self attributeChanged:NotePreviewString];
		[[delegate delegate] contentsUpdatedForNote:self];
	} else {
		NSBeep();
		NSLog(@"odbEditor:didModifyFile: unable to get data from %@", path);
	}	
}
-(void)odbEditor:(ODBEditor *)editor didClosefile:(NSString *)path context:(NSDictionary *)context {
	//remove the temp file	
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

}

- (NSRange)nextRangeForWords:(NSArray*)words options:(unsigned)opts range:(NSRange)inRange {
	//opts indicate forwards or backwards, inRange allows us to continue from where we left off
	//return location of NSNotFound and length 0 if none of the words could be found inRange
	
	//an optimization would be to fall back on cached cString if contentsWere7Bit is true, but then we have to handle opts ourselves
	unsigned int i;
	NSString *haystack = [contentString string];
	NSRange nextRange = NSMakeRange(NSNotFound, 0);
	for (i=0; i<[words count]; i++) {
		NSString *word = [words objectAtIndex:i];
		if ([word length] > 0) {
			nextRange = [haystack rangeOfString:word options:opts range:inRange];
			if (nextRange.location != NSNotFound && nextRange.length)
				break;
		}
	}

	return nextRange;
}

force_inline void resetFoundPtrsForNote(NoteObject *note) {
	note->cTitleFoundPtr = note->cTitle;
	note->cContentsFoundPtr = note->cContents;
	note->cLabelsFoundPtr = note->cLabels;	
}

BOOL noteContainsUTF8String(NoteObject *note, NoteFilterContext *context) {
	
    if (!context->useCachedPositions) {
		resetFoundPtrsForNote(note);
    }
	
	char *needle = context->needle;
    
	/* NOTE: strstr in Darwin is heinously, supernaturally optimized; it blows boyer-moore out of the water. 
	implementations on other OSes will need considerably more code in this function. */
	
    if (note->cTitleFoundPtr)
		note->cTitleFoundPtr = strstr(note->cTitleFoundPtr, needle);
    
    if (note->cContentsFoundPtr)
		note->cContentsFoundPtr = strstr(note->cContentsFoundPtr, needle);
    
    if (note->cLabelsFoundPtr)
		note->cLabelsFoundPtr = strstr(note->cLabelsFoundPtr, needle);
        
    return note->cContentsFoundPtr || note->cTitleFoundPtr || note->cLabelsFoundPtr;
}

BOOL noteTitleHasPrefixOfUTF8String(NoteObject *note, const char* fullString, size_t stringLen) {
	return !strncmp(note->cTitle, fullString, stringLen);
}
BOOL noteTitleIsAPrefixOfOtherNoteTitle(NoteObject *longerNote, NoteObject *shorterNote) {
	return !strncmp(longerNote->cTitle, shorterNote->cTitle, strlen(shorterNote->cTitle));
}

- (void)addPrefixParentNote:(NoteObject*)aNote {
	if (!prefixParentNotes) {
		prefixParentNotes = [[NSMutableArray alloc] initWithObjects:&aNote count:1];
	} else {
		[prefixParentNotes addObject:aNote];
	}
}
- (void)removeAllPrefixParentNotes {
	[prefixParentNotes removeAllObjects];
}

- (NSSet*)labelSet {
    return labelSet;
}

/*
- (CFArrayRef)rangesForWords:(NSString*)string inRange:(NSRange)rangeLimit {
	//use cstring caches if note is all 7-bit, as we [REALLY OUGHT TO] be able to assume a 1-to-1 character mapping
	
	if (contentsWere7Bit) {
		char *manglingString = strdup([string UTF8String]);
		char *token, *separators = separatorsForCString(manglingString);
		
		while ((token = strsep(&manglingString, separators))) {
			if (*token != '\0') {
				//find all occurrences of token in cContents and add cfranges to cfmutablearray
			}
		}
	}
}*/

- (NSUndoManager*)undoManager {
    if (!undoManager) {
	undoManager = [[NSUndoManager alloc] init];
	
	id center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(_undoManagerDidChange:)
		       name:NSUndoManagerDidUndoChangeNotification
		     object:undoManager];
	
	[center addObserver:self selector:@selector(_undoManagerDidChange:)
		       name:NSUndoManagerDidRedoChangeNotification
		     object:undoManager];
    }
    
    return undoManager;
}

- (void)_undoManagerDidChange:(NSNotification *)notification {
	[self makeNoteDirtyUpdateTime:YES updateFile:YES];
    //queue note to be written to disk
}



@end
