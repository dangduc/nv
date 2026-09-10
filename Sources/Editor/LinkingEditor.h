/* LinkingEditor */

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


#import <Cocoa/Cocoa.h>
@class NotesTableView;
@class GlobalPrefs;

@interface LinkingEditor : NSTextView <NSLayoutManagerDelegate, NSTextFinderClient>
{	
    NSTextFinder *textFinder;
    IBOutlet NSTextField *controlField;
    IBOutlet NotesTableView *notesTableView;
	
	GlobalPrefs *prefsController;
	BOOL didRenderFully;
	
	NSRange lastAutomaticallySelectedRange;
	
	BOOL backgroundIsDark;
    BOOL searchHighlightsInvalidated;
    
    BOOL managesTextWidth;
}

@property (readwrite) BOOL managesTextWidth;


- (NSColor*)_insertionPointColorForForegroundColor:(NSColor*)fgColor backgroundColor:(NSColor*)bgColor;
- (NSColor*)_linkColorForForegroundColor:(NSColor*)fgColor backgroundColor:(NSColor*)bgColor;
- (NSColor*)_selectionColorForForegroundColor:(NSColor*)fgColor backgroundColor:(NSColor*)bgColor;
- (NSDictionary*)preferredLinkAttributes;
- (NSRange)selectedRangeWasAutomatic:(BOOL*)automatic;
- (void)setAutomaticallySelectedRange:(NSRange)newRange;
- (void)removeHighlightedTerms;
- (void)invalidateSearchHighlights;
- (void)setSearchHighlightRanges:(NSArray *)ranges;
- (NSRange)highlightTermsTemporarilyReturningFirstRange:(NSString*)typedString avoidHighlight:(BOOL)noHighlight;
- (id)highlightLinkAtIndex:(NSUInteger)givenIndex;

- (void)indicateRange:(NSValue*)rangeValue;

- (BOOL)didRenderFully;

#pragma mark - nvALT additions
- (void)resetInset;
- (void)updateInsetAndForceLayout:(BOOL)force;
- (void)updateInsetForFrame:(NSRect)frameRect andForceLayout:(BOOL)force;
- (BOOL)setInsetForFrame:(NSRect)frameRect alwaysSet:(BOOL)always;
- (IBAction)performFindPanelAction:(id)sender;
- (void)updateTextColors;
- (void)prepareTextFinder;
- (BOOL)textFinderIsVisible;
- (void)textFinderShouldResetContext:(NSNotification *)aNotification;
- (void)textFinderShouldUpdateContext:(NSNotification *)aNotification;
- (void)hideTextFinderIfNecessary:(NSNotification *)aNotification;
//
- (void)undo:(id)sender;
- (void)redo:(id)sender;
@end
