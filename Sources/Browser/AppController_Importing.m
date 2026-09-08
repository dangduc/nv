//
//  AppController_Importing.m
//  Notation
//
//  Created by Zachary Schneirov on 1/14/11.

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


#import "AppController_Importing.h"
#import "NotationController.h"
#import "NotationFileManager.h"
#import "BookmarksController.h"
#import "DualField.h"
#import "NotationDirectoryManager.h"
#import "AlienNoteImporter.h"
#import "NSString_NV.h"
#import "GlobalPrefs.h"
#import "NSData_transformations.h"
#import "AttributedPlainText.h"
#import "NSCollection_utils.h"
#import "NoteObject.h"
#import "NotationPrefs.h"

@implementation AppController (Importing)

- (BOOL)addNotesFromPasteboard:(NSPasteboard*)pasteboard {
	
    NSArray *types = [pasteboard types];
    if ([types containsObject:NSFilenamesPboardType]) {
        NSArray *files = [pasteboard propertyListForType:NSFilenamesPboardType];
        if ([files isKindOfClass:[NSArray class]] && [notationController openFiles:files]) return YES;
    }
    NSString *source = [pasteboard stringForType:NSStringPboardType];
    if (!source && [types containsObject:NSURLPboardType]) source = [[NSURL URLFromPasteboard:pasteboard] absoluteString];
    if (![source length]) return NO;
    NSString *title = [source syntheticTitleAndSeparatorWithContext:NULL bodyLoc:NULL maxTitleLen:36];
    NSAttributedString *body = [[[NSAttributedString alloc] initWithString:source] autorelease];
    NoteObject *note = [[[NoteObject alloc] initWithNoteBody:body title:title delegate:[self sharedNotationController]
        format:[notationController currentNoteStorageFormat] labels:nil] autorelease];
    [self setViewingNote:NO];
    [notationController addNewNote:note];
    return note != nil;
}

- (BOOL)interpretNVURL:(NSURL*)aURL {
    
//    NSLog(@"interpret URL:|||%@|||",[aURL absoluteString]);
    
	// currently supported:
	// hostname -> command
	// first level -> search term / title
	// second level -> local note UUID as a parameter
	// example: nv://find/url%20test/?NV=5WJ0eP3YRaCjyQn%2F8p62iQ%3D%3D
	
	NSUInteger i = 0;
	
	if ([[aURL host] isEqualToString:@"find"]) {
		//dispatch searchForString: and revealNote:options: as appropriate
		
		//add currentNote to the snapback button back-stack
		if (currentNote) {
			[field pushFollowedLink:[[[NoteBookmark alloc] initWithNoteObject:currentNote searchString:[self fieldSearchString]] autorelease]];
		}
		
		NSString *terms = [aURL path];
		[self searchForString:([terms length] && [terms characterAtIndex:0] == '/') ? [terms substringFromIndex:1] : terms];
		
		NSArray *params = [[aURL query] componentsSeparatedByString:@"&"];
		NoteObject *foundNote = nil;
		
		for (i=0; i<[params count]; i++) {
			NSString *idStr = [params objectAtIndex:i];
			
			if ([idStr hasPrefix:@"NV="] && [idStr length] > 3) {
				NSData *uuidData = [[[idStr substringFromIndex:3] stringByReplacingPercentEscapes] decodeBase64WithNewlines:NO];
				if ([uuidData length] == sizeof(CFUUIDBytes) &&
                    (foundNote = [notationController noteForUUIDBytes:(CFUUIDBytes*)[uuidData bytes]]))
					goto handleFound;
			}
		}
	handleFound:
		//if this search had initiated a clearing of the history, then make sure it doesn't happen
		[NSObject cancelPreviousPerformRequestsWithTarget:field selector:@selector(clearFollowedLinks) object:nil];
		
		if (foundNote) [self revealNote:foundNote options:NVOrderFrontWindow];
		return YES;
		
	} else if ([[aURL host] isEqualToString:@"make"]) {
		
		NSArray *params = [[aURL query] componentsSeparatedByString:@"&"];
		
		// The make action accepts plain text. Web-page and HTML import are disabled.
		NSString *title = nil, *txtBody = nil, *tags = nil;
		for (NSString *compStr in params) {
			if ([compStr hasPrefix:@"title="] && [compStr length] > 6) {
				title = [[compStr substringFromIndex:6] stringByReplacingPercentEscapes];
			} else if ([compStr hasPrefix:@"txt="] && [compStr length] > 4) {
				txtBody = [[compStr substringFromIndex:4] stringByReplacingPercentEscapes];
			} else if ([compStr hasPrefix:@"tags="] && [compStr length] > 5) {
				tags = [[compStr substringFromIndex:5] stringByReplacingPercentEscapes];
			}
		}
		if (title && txtBody) {
			NSMutableAttributedString *contents = [[[NSMutableAttributedString alloc]
				initWithString:txtBody attributes:[prefsController noteBodyAttributes]] autorelease];
			NoteObject *note = [[[NoteObject alloc] initWithNoteBody:contents title:title delegate:[self sharedNotationController]
				format:[notationController currentNoteStorageFormat] labels:tags] autorelease];
			[notationController addNewNote:note];
			return YES;
		} else if (txtBody) {
			NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
			[pboard declareTypes:@[NSStringPboardType] owner:nil];
			[pboard setString:txtBody forType:NSStringPboardType];
			BOOL added = [self addNotesFromPasteboard:pboard];
			[pboard releaseGlobally];
			return added;
		}
	} else if ([[aURL host] length]) {
		//assume find by default
		if (currentNote) {
			[field pushFollowedLink:[[[NoteBookmark alloc] initWithNoteObject:currentNote searchString:[self fieldSearchString]] autorelease]];
		}
		[self searchForString:[aURL host]];
		return YES;
	}
	
	return NO;
}

- (NSString*)stringWithNoteURLsOnPasteboard:(NSPasteboard*)pboard {
	//paste as a file:// URL, so that it can be linked
	
	NSMutableString *allURLsString = [NSMutableString string];
	
	NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
	if ([files isKindOfClass:[NSArray class]]) {
		NSArray *unknownPaths = files;
		NSUInteger i;
		
		if ([notationController currentNoteStorageFormat] != SingleDatabaseFormat) {
			//notes are stored as separate files, so if these paths are in the notes folder then NV can create double-bracketed-links to them instead
			
			NSSet *existingNotes = [notationController notesWithFilenames:files unknownFiles:&unknownPaths];
			if ([existingNotes count]) {
				//create double-bracketed links using these notes' titles
				NSArray *existingArray = [existingNotes allObjects];
				for (i=0; i<[existingArray count]; i++) {
					[allURLsString appendFormat:@"[[%@]]%s", titleOfNote([existingArray objectAtIndex:i]), 
					 (i < [existingArray count] - 1) || [unknownPaths count] ? "\n" : ""];
				}
			}
		}
		//NSLog(@"paths not found in DB: %@", unknownPaths);
		
		for (i=0; i<[unknownPaths count]; i++) {
			NSURL *url = [NSURL fileURLWithPath:[unknownPaths objectAtIndex:i]];
			if (url) {
        NSString *linkFormat = @"<%@>%s";
        NSString *pathString = [url absoluteString];
        NSLog(@"%@",pathString);
        if ([pathString hasSuffix:@"jpg"]   || 
            [pathString hasSuffix:@"jpeg"]  ||
            [pathString hasSuffix:@"gif"]   ||
            [pathString hasSuffix:@"png"])
        {
          NSString *syntax = [currentNote sourceSyntaxIdentifier];
          if ([syntax isEqualToString:@"markdown"]) {
            linkFormat = @"![](%@)%s";
          } else if ([syntax isEqualToString:@"textile"]) {
            linkFormat = @"!%@()!%s"; 
          }
        }
        [allURLsString appendFormat:linkFormat, 
         [pathString stringByReplacingOccurrencesOfString:@"file://localhost" withString:@"file://"],
         (i < [unknownPaths count] - 1) ? "\n" : ""];          
			}
		}
	}
	return allURLsString;
}

@end
