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
#import <objc/runtime.h>

@class NotesTableView;
@class NoteObject;
@class GlobalPrefs;

@interface LinkingEditor : NSTextView
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
<NSLayoutManagerDelegate>
#endif
{	
    id textFinder;
    IBOutlet NSTextField *controlField;
    IBOutlet NotesTableView *notesTableView;
	
	GlobalPrefs *prefsController;
	BOOL didRenderFully;
	
	NSRange lastAutomaticallySelectedRange;
	NSRange changedRange;
	
	BOOL backgroundIsDark, mouseInside;
    BOOL searchHighlightsInvalidated;
	
	//ludicrous ivars used to hack NSTextFinder. just write your own, damnit!
	NSRange selectedRangeDuringFind;
	NSString *lastImportedFindString;
	NSString *stringDuringFind;
	NoteObject *noteDuringFind;
	
	IMP defaultIBeamCursorIMP, whiteIBeamCursorIMP;
    
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
- (void)highlightRangesTemporarily:(CFArrayRef)ranges;
- (NSRange)highlightTermsTemporarilyReturningFirstRange:(NSString*)typedString avoidHighlight:(BOOL)noHighlight;
- (NSString *)sourceSyntaxIdentifier;
- (id)highlightLinkAtIndex:(NSUInteger)givenIndex;

- (void)indicateRange:(NSValue*)rangeValue;

- (void)fixTypingAttributesForSubstitutedFonts;
- (void)fixCursorForBackgroundUpdatingMouseInside:(BOOL)checkMouseLoc;

- (BOOL)didRenderFully;

#pragma mark - nvALT additions
- (void)setMouseInside:(BOOL)inside;
- (BOOL)mouseIsHere;
- (void)resetInset;
- (void)updateInsetAndForceLayout:(BOOL)force;
- (void)updateInsetForFrame:(NSRect)frameRect andForceLayout:(BOOL)force;
- (BOOL)setInsetForFrame:(NSRect)frameRect alwaysSet:(BOOL)always;
- (IBAction)performFindPanelAction:(id)sender;
- (void)updateTextColors;
- (void)prepareTextFinder;
- (void)prepareTextFinderPreLion;
- (BOOL)textFinderIsVisible;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
- (void)textFinderShouldResetContext:(NSNotification *)aNotification;
- (void)textFinderShouldUpdateContext:(NSNotification *)aNotification;
- (void)textFinderShouldNoteChanges:(NSNotification *)aNotification;
- (void)hideTextFinderIfNecessary:(NSNotification *)aNotification;
#endif
//
- (void)undo:(id)sender;
- (void)redo:(id)sender;
@end

@interface NSTextView (Private)
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_6
- (void)toggleAutomaticTextReplacement:(id)sender;
- (BOOL)isAutomaticTextReplacementEnabled;
- (void)setAutomaticTextReplacementEnabled:(BOOL)flag;
- (void)moveToLeftEndOfLine:(id)sender;
#endif

@end
