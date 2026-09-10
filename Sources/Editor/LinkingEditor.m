#import "NVApplicationController.h"
#import "NVNoteEditingSession.h"
#import "NVSourceHighlighter.h"
#import "NVSearchQuery.h"
#import "NoteObject.h"
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


#import "LinkingEditor.h"
#import "GlobalPrefs.h"
#import "AppController.h"
#import "NotesTableView.h"
#import "ETClipView.h"
//#import "NSTextFinder.h"
//#import "NVTextFinderAdditions.h"


#define kDefaultTextInsetWidth 8.0
#define kDefaultTextInsetHeight 8.0

@interface NSCursor (WhiteIBeamCursor)
+ (NSCursor*)whiteIBeamCursor;
@end

@implementation NSCursor (WhiteIBeamCursor)

+ (NSCursor*)whiteIBeamCursor {
	static NSCursor *invertedIBeamCursor = nil;
	if (!invertedIBeamCursor) {
		invertedIBeamCursor = [[NSCursor alloc] initWithImage:[NSImage imageNamed:@"IBeamInverted"] hotSpot:NSMakePoint(4,5)];
	}
	return invertedIBeamCursor;	
}

@end


@implementation LinkingEditor
- (NSString *)sourceSyntaxIdentifier { return [[NVControllerForView(self) selectedNoteObject] sourceSyntaxIdentifier] ?: @"plain"; }
- (void)undo:(id)sender { if ([self isHiddenOrHasHiddenAncestor]) return; [[[NVApplicationController sharedController] editingSessionForNote:[NVControllerForView(self) selectedNoteObject]] undo]; }
- (void)redo:(id)sender { if ([self isHiddenOrHasHiddenAncestor]) return; [[[NVApplicationController sharedController] editingSessionForNote:[NVControllerForView(self) selectedNoteObject]] redo]; }


@synthesize managesTextWidth;

CGFloat _perceptualDarkness(NSColor*a);

//+ (BOOL)stronglyReferencesTextStorage{
//    return NO;
//}

- (void)awakeFromNib {
	
    // The application owns the shared preferences; this editor borrows them.
    prefsController = [GlobalPrefs defaultPrefs];

    [prefsController registerWithTarget:self forChangesInSettings:
	 @selector(setNoteBodyFont:sender:),
	 @selector(setMakeURLsClickable:sender:),
	 @selector(setSearchTermHighlightColor:sender:),
	 @selector(setDarkSearchTermHighlightColor:sender:),
	 @selector(setShouldHighlightSearchTerms:sender:), nil];
	
    self.managesTextWidth=[prefsController managesTextWidthInWindow];
	[self setUsesRuler:NO];
	[self setUsesFontPanel:NO];
	[self setDrawsBackground:YES];
	[self updateTextColors];
    [self updateInsetAndForceLayout:YES];
    [self prepareTextFinder];
    
	[[self window] setAcceptsMouseMovedEvents:YES];
	if (IsLeopardOrLater) {
		defaultIBeamCursorIMP = method_getImplementation(class_getClassMethod([NSCursor class], @selector(IBeamCursor)));
		whiteIBeamCursorIMP = method_getImplementation(class_getClassMethod([NSCursor class], @selector(whiteIBeamCursor)));
	}
	
	didRenderFully = NO;
	[[self layoutManager] setDelegate:self];


    [self setRichText:NO];
    [self setImportsGraphics:NO];

    //	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
//	[center addObserver:self selector:@selector(windowBecameOrResignedMain:) name:NSWindowDidBecomeMainNotification object:[self window]];
//	[center addObserver:self selector:@selector(windowBecameOrResignedMain:) name:NSWindowDidResignMainNotification object:[self window]];
    
	//[center addObserver:self selector:@selector(updateTextColors) name:NSSystemColorsDidChangeNotification object:nil]; // recreate gradient if needed
    //	NoMods = YES;
   
	outletObjectAwoke(self);
}

- (void)settingChangedForSelectorString:(NSString*)selectorString {
    if ([selectorString isEqualToString:SEL_STR(setNoteBodyFont:sender:)]) {

		[self setTypingAttributes:[prefsController noteBodyAttributes]];
		//[textView setFont:[prefsController noteBodyFont]];
	} else if ([selectorString isEqualToString:SEL_STR(setMakeURLsClickable:sender:)]) {
		
		[self setLinkTextAttributes:[self preferredLinkAttributes]];
    
	//} else if ([selectorString isEqualToString:SEL_STR(setBackgroundTextColor:sender:)]) {
		
		//link-color is derived both from foreground and background colors
		//[self updateTextColors];
		
	//} else if ([selectorString isEqualToString:SEL_STR(setForegroundTextColor:sender:)]) {
		
		//[self updateTextColors];
		//[self setTypingAttributes:[prefsController noteBodyAttributes]];
		
	} else if ([selectorString isEqualToString:SEL_STR(setSearchTermHighlightColor:sender:)] || 
               [selectorString isEqualToString:SEL_STR(setDarkSearchTermHighlightColor:sender:)] ||
			   [selectorString isEqualToString:SEL_STR(setShouldHighlightSearchTerms:sender:)]) {
		
        [NVControllerForView(self) refreshSearchHighlights];
	}
}

- (BOOL)becomeFirstResponder {
    [NVControllerForView(self) cancelSearchIntents];
	[notesTableView setShouldUseSecondaryHighlightColor:YES];

	if ([[[self window] currentEvent] type] == NSKeyDown && [[[self window] currentEvent] firstCharacter] == '\t') {
		//"indicate" the current cursor/selection when moving focus to this field, but only if the user did not click here
		NSRange range = [self selectedRange];
		if (range.length) {
			range = NSMakeRange(MIN([[self string] length] - 1, range.location), range.length);
			[self performSelector:@selector(indicateRange:) withObject:[NSValue valueWithRange:range] afterDelay:0];
		}
	}
	[self setTypingAttributes:[prefsController noteBodyAttributes]];
//    NSLog(@"exist :>%@<",self.defaultParagraphStyle);
//    [self.textStorage setAttributes:@{NSParagraphStyleAttributeName:[NSParagraphStyle defaultParagraphStyle]} range:NSMakeRange(0, self.string.length)];
//    NSLog(@"exist :>%@<",self.defaultParagraphStyle);
	[self performSelector:@selector(_fixCursorForBackgroundUpdatingMouseInside:) withObject:[NSNumber numberWithBool:YES] afterDelay:0.0];
	
	return [super becomeFirstResponder];
}

- (void)indicateRange:(NSValue*)rangeValue {
	if (IsLeopardOrLater) {
		[self showFindIndicatorForRange:[rangeValue rangeValue]];
	}
}

- (BOOL)resignFirstResponder {
	[notesTableView setShouldUseSecondaryHighlightColor:NO];
	
	[self performSelector:@selector(_fixCursorForBackgroundUpdatingMouseInside:) withObject:[NSNumber numberWithBool:YES] afterDelay:0.0];
	
	return [super resignFirstResponder];
}

- (void)changeColor:(id)sender {
	//NSLog(@"You do not change the color.");
	return;
}

- (void)setBackgroundColor:(NSColor*)aColor {
	backgroundIsDark = (_perceptualDarkness([aColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace]) > 0.5);
    [self fixCursorForBackgroundUpdatingMouseInside:YES];
	[super setBackgroundColor:aColor];
}

- (void)updateTextColors {
	NSColor *fgColor = [NVControllerForView(self) foregrndColor] ?: [NSColor textColor];
	NSColor *bgColor = [self backgroundColor];
    if (bgColor!=[(AppController *)NVControllerForView(self)backgrndColor]) {
        bgColor=[NVControllerForView(self) backgrndColor] ?: [NSColor textBackgroundColor];
        [self setBackgroundColor:bgColor];
    }
	[[self enclosingScrollView] setBackgroundColor:bgColor];
    if (IsLionOrLater&&[self textFinderIsVisible]) {
        [[self window]invalidateCursorRectsForView:[[self enclosingScrollView]findBarView]];
    }
    
	//[self setBackgroundColor:bgColor];
	//[nvTextScroller setBackgroundColor:bgColor];
	//[[self enclosingScrollView] setNeedsDisplay:YES];
    
	[self setInsertionPointColor:[self _insertionPointColorForForegroundColor:fgColor backgroundColor:bgColor]];
	[self setLinkTextAttributes:[self preferredLinkAttributes]];
	[self setSelectedTextAttributes:[NSDictionary dictionaryWithObject:[self _selectionColorForForegroundColor:fgColor backgroundColor:bgColor] 
																forKey:NSBackgroundColorAttributeName]];
	[self setTypingAttributes:[prefsController noteBodyAttributes]];
    [[self enclosingScrollView]setNeedsDisplay:YES];
//    [[[self enclosingScrollView]contentView]setNeedsDisplay:YES];
    [self setNeedsDisplay:YES];
}

#define _CM(__ch) ((__ch) * 255.0)
CGFloat _perceptualDarkness(NSColor*a) {
	//0 to 1; the higher the darker
	
	CGFloat aRed, aGreen, aBlue;
	[a getRed:&aRed green:&aGreen blue:&aBlue alpha:NULL];

	return 1 - (0.299 * _CM(aRed) + 0.587 * _CM(aGreen) + 0.114 * _CM(aBlue))/255;
}
CGFloat _perceptualColorDifference(NSColor*a, NSColor*b) {
	//acceptable: 500
	CGFloat aRed, aGreen, aBlue, bRed, bGreen, bBlue;
	[a getRed:&aRed green:&aGreen blue:&aBlue alpha:NULL];
	[b getRed:&bRed green:&bGreen blue:&bBlue alpha:NULL];

	return (MAX(_CM(aRed), _CM(bRed)) - MIN(_CM(aRed), _CM(bRed))) + (MAX(_CM(aGreen), _CM(bGreen)) - MIN(_CM(aGreen), _CM(bGreen))) + 
	(MAX(_CM(aBlue), _CM(bBlue)) - MIN(_CM(aBlue), _CM(bBlue)));
}

- (NSColor*)_linkColorForForegroundColor:(NSColor*)fgColor backgroundColor:(NSColor*)bgColor {
	//if fgColor is black, choose blue; otherwise, rotate hue (keeping the same sat.) until color is different enough
	
	fgColor = [fgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	bgColor = [bgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	
	CGFloat hue, brightness, saturation, alpha, diffInc = 0.5;
	NSUInteger rotationsLeft = 25;
	[fgColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];

	//if foreground color is too dark for hue changes to matter, then just use blue
	if (brightness <= 0.24)
		return [NSColor blueColor];
	
	brightness = _perceptualDarkness(bgColor) > 0.5 ? MAX(0.75, brightness) : MIN(0.35, brightness);
	
	saturation = MAX(0.5, saturation);
	
	//adjust hue until the perceptual differences between the proposed link
	//and current foreground and background colors are great enough
	NSColor *proposedLinkColor = nil;
	do {
		hue -= diffInc;
		if (hue < 0.0)
			hue += 1.0;
		
		proposedLinkColor = [NSColor colorWithCalibratedHue:hue saturation:saturation brightness:brightness alpha:alpha];
		
		diffInc = rotationsLeft > 15 ? 0.125 : 0.0625;
		
	} while ((_perceptualColorDifference(proposedLinkColor, bgColor) < 360.0 || 
			  _perceptualColorDifference(proposedLinkColor, fgColor) < 170.0) && --rotationsLeft > 0);
	return proposedLinkColor;
}

- (NSColor*)_selectionColorForForegroundColor:(NSColor*)fgColor backgroundColor:(NSColor*)bgColor {
	fgColor = [fgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	bgColor = [bgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    
	NSColor *proposedBlend = [fgColor blendedColorWithFraction:0.5 ofColor:bgColor];
	NSColor *defaultColor = [[NSColor selectedTextBackgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	
	CGFloat fgDiff = _perceptualColorDifference(proposedBlend, fgColor);
	CGFloat fgSelDiff = _perceptualColorDifference(defaultColor, fgColor);
	
	//selection color should be between foreground and background in terms of brightness
	//but the selection-color-difference from the foreground text needs to be great enough as well,
	//and the proposed-color-difference from the foreground can't be too poor
	//this heuristic chooses all the system-highlight colors in default fg/bg combinations and fg/bg blends in all others
    
	if ((_perceptualDarkness(fgColor) > _perceptualDarkness(defaultColor) &&
		 _perceptualDarkness(defaultColor) > (_perceptualDarkness(bgColor)+0.22) && fgSelDiff > 300.0) || fgDiff < 160.0){
		return defaultColor;
	}
	//amplify the background balance after testing
	return [fgColor blendedColorWithFraction:0.69 ofColor:bgColor];
}


- (NSColor*)_insertionPointColorForForegroundColor:(NSColor*)fgColor backgroundColor:(NSColor*)bgColor {
	fgColor = [fgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	bgColor = [bgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

	CGFloat hue, brightness, saturation;
	[fgColor getHue:&hue saturation:&saturation brightness:&brightness alpha:NULL];
	
	//make the insertion point lighter than the foreground color if the background is dark and vise versa
	NSColor *brighter = [fgColor blendedColorWithFraction:0.4 ofColor:[NSColor whiteColor]];
	NSColor *darker = [fgColor blendedColorWithFraction:0.4 ofColor:[NSColor blackColor]];

	return _perceptualColorDifference(brighter, bgColor) > _perceptualColorDifference(darker, bgColor) ? brighter : darker;
}

- (NSDictionary*)preferredLinkAttributes {
	if (![prefsController URLsAreClickable])
		return [NSDictionary dictionary];
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSCursor pointingHandCursor], NSCursorAttributeName,
			[NSNumber numberWithInt:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName,
			[self _linkColorForForegroundColor:[(AppController *)NVControllerForView(self) foregrndColor] backgroundColor:[(AppController *)NVControllerForView(self) backgrndColor]],
			NSForegroundColorAttributeName, nil];
	
	/*
	 return [NSDictionary dictionaryWithObjectsAndKeys:
	 [NSCursor pointingHandCursor], NSCursorAttributeName,
	 [NSNumber numberWithInt:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName,
	 [self _linkColorForForegroundColor:[prefsController foregroundTextColor] backgroundColor:[prefsController backgroundTextColor]],
	 NSForegroundColorAttributeName, nil];
	 */
}

/*
- (BOOL)acceptsFirstResponder {
	
    return ([[controlField stringValue] length] > 0);
}*/

- (BOOL)didRenderFully {
	return didRenderFully;
}

- (void)layoutManager:(NSLayoutManager *)aLayoutManager didCompleteLayoutForTextContainer:(NSTextContainer *)aTextContainer atEnd:(BOOL)flag {
	didRenderFully = YES;
}
- (void)layoutManagerDidInvalidateLayout:(NSLayoutManager *)aLayoutManager {
	didRenderFully = NO;
}

- (NSColor *)sourceColorForCapture:(NSString *)capture {
    if (!capture || [capture isEqualToString:@"none"]) return nil;
    CGFloat hue = 0.61, saturation = 0.72;
    if ([capture hasPrefix:@"comment"]) { hue = 0.34; saturation = 0.28; }
    else if ([capture hasSuffix:@".key"] || [capture hasPrefix:@"attribute"]) hue = 0.08;
    else if ([capture hasPrefix:@"string"] || [capture isEqualToString:@"text.literal"]) hue = 0.34;
    else if ([capture hasPrefix:@"number"] || [capture hasPrefix:@"constant"]) hue = 0.04;
    else if ([capture hasPrefix:@"tag"] || [capture isEqualToString:@"text.title"]) hue = 0.78;
    else if ([capture hasPrefix:@"punctuation"]) { hue = 0.59; saturation = 0.30; }
    return [NSColor colorWithCalibratedHue:hue saturation:saturation brightness:backgroundIsDark ? 0.94 : 0.58 alpha:1.0];
}
- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:(NSDictionary *)attributes
            forDrawingToScreen:(BOOL)screen atCharacterIndex:(NSUInteger)index effectiveRange:(NSRangePointer)range {
    if (searchHighlightsInvalidated && [attributes objectForKey:NSBackgroundColorAttributeName]) {
        NSMutableDictionary *display = [[attributes mutableCopy] autorelease];
        [display removeObjectForKey:NSBackgroundColorAttributeName];
        attributes = display;
    }
    if (!screen || index >= [[manager textStorage] length]) return attributes;
    // Base appearance < syntax < links. Search backgrounds and native selection
    // remain independent; the input method owns marked-text appearance.
    NSRange linkRange;
    id link = [[manager textStorage] attribute:NSLinkAttributeName atIndex:index effectiveRange:&linkRange];
    if (range) *range = NSIntersectionRange(*range, linkRange);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:attributes ?: @{}];
    NSString *capture = NVSourceCapturesCanDisplay(manager) ? [result objectForKey:NVSourceCaptureAttributeName] : nil;
    [result removeObjectForKey:NVSourceCaptureAttributeName];
    NSRange marked = [self markedRange];
    if (marked.location != NSNotFound) {
        if (NSLocationInRange(index, marked)) {
            if (range) *range = NSIntersectionRange(*range, marked);
            return result;
        }
        if (range && index < marked.location && NSMaxRange(*range) > marked.location) range->length = marked.location - range->location;
    }
    NSColor *color = link ? [[self preferredLinkAttributes] objectForKey:NSForegroundColorAttributeName] : [self sourceColorForCapture:capture];
    if (!color) color = [NVControllerForView(self) foregrndColor];
    if (color) [result setObject:color forKey:NSForegroundColorAttributeName];
    return result;
}

- (void)invalidateSearchHighlights {
    if (searchHighlightsInvalidated) return;
    searchHighlightsInvalidated = YES;
    // TextKit has not adjusted its glyph ranges during storage notifications.
    // Suppress stale backgrounds now and remove them after edit processing.
    [self performSelector:@selector(removeHighlightedTerms) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
}
- (void)removeHighlightedTerms {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];
    if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) {
        searchHighlightsInvalidated = YES;
        // A nested run loop can run before endEditing. Avoid retrying at zero delay.
        [self performSelector:@selector(removeHighlightedTerms) withObject:nil afterDelay:0.01 inModes:@[NSRunLoopCommonModes]];
        return;
    }
    searchHighlightsInvalidated = NO;
    [[self layoutManager] removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0, [[self string] length])];
}


//use with rangesOfWordsInString:(NSString*)findString earliestRange:(NSRange*)aRange inRange:
- (NSDictionary *)currentSearchHighlightAttributes {
    AppController *browser = NVControllerForView(self);
    __block NSDictionary *attributes = nil;
    void (^resolve)(void) = ^{
        attributes = [[prefsController searchTermHighlightAttributesForDarkAppearance:[browser usesDarkUserColorScheme]
            backgroundColor:[browser backgrndColor] ?: [self backgroundColor]] retain];
    };
    // Search completions arrive outside drawing, where named colors need an explicit appearance.
    if (@available(macOS 11.0, *)) [[self effectiveAppearance] performAsCurrentDrawingAppearance:resolve];
    else {
        NSAppearance *previousAppearance = [[NSAppearance currentAppearance] retain];
        @try {
            [NSAppearance setCurrentAppearance:[self effectiveAppearance]];
            resolve();
        } @finally {
            [NSAppearance setCurrentAppearance:previousAppearance];
            [previousAppearance release];
        }
    }
    return [attributes autorelease];
}

- (void)setSearchHighlightRanges:(NSArray *)ranges {
    [self removeHighlightedTerms];
    if (searchHighlightsInvalidated) return;
    NSColor *color = [[self currentSearchHighlightAttributes] objectForKey:NSBackgroundColorAttributeName];
    if (!color) return;
    NSUInteger length = [[self string] length];
    NSUInteger displayed = 0;
    for (NSValue *value in ranges) {
        if (displayed++ == NVSearchMaximumDisplayedRanges) break;
        NSRange range = [value rangeValue];
        if (range.location <= length && range.length <= length - range.location && range.length)
            [[self layoutManager] addTemporaryAttribute:NSBackgroundColorAttributeName value:color forCharacterRange:range];
    }
}

- (void)highlightRangesTemporarily:(CFArrayRef)ranges {
	CFIndex rangeIndex;
	long bodyLength = (long)[[self string] length];
	NSDictionary *highlightDict = [self currentSearchHighlightAttributes];
	
	for (rangeIndex = 0; rangeIndex < MIN(CFArrayGetCount(ranges), NVSearchMaximumDisplayedRanges); rangeIndex++) {
		CFRange *range = (CFRange *)CFArrayGetValueAtIndex(ranges, rangeIndex);
		
		if (range && range->length > 0 && range->location + range->length <= bodyLength) {
			[[self layoutManager] addTemporaryAttributes:highlightDict forCharacterRange:*(NSRange*)range];
		} else {
			NSLog(@"highlightRangesTemporarily: Invalid range (%@)", range ? NSStringFromRange(*(NSRange*)range) : @"null");
		}
	}
}

- (NSRange)highlightTermsTemporarilyReturningFirstRange:(NSString*)typedString avoidHighlight:(BOOL)noHighlight {
    NSRange first = NSMakeRange(NSNotFound, 0);
    NSString *separator = [typedString rangeOfString:@"\""].location == NSNotFound ? @" " : @"\"";
    for (NSString *term in [typedString componentsSeparatedByString:separator]) {
        if (![term length]) continue;
        CFRange found = CFStringFind((CFStringRef)[self string], (CFStringRef)term, kCFCompareCaseInsensitive);
        if (found.location != kCFNotFound && (NSUInteger)found.location < first.location) {
            first = NSMakeRange(found.location, found.length);
            if (noHighlight) break;
        }
    }
    // Preserve the legacy first-match caret lookup. Backgrounds are installed
    // asynchronously, without constructing another complete match array here.
    return first;
}

- (NSRange)selectedRangeWasAutomatic:(BOOL*)automatic {
	NSRange myRange = [self selectedRange];
	if (automatic) {
		*automatic = !didRenderFully || NSEqualRanges(lastAutomaticallySelectedRange, myRange);
	}
	return myRange;
}

- (void)setAutomaticallySelectedRange:(NSRange)newRange {
	lastAutomaticallySelectedRange = newRange;
	[self setSelectedRange:newRange];
}

    
- (void)mouseEntered:(NSEvent*)anEvent {
//	mouseInside = YES;
	[self fixCursorForBackgroundUpdatingMouseInside:YES];
    [super mouseEntered:anEvent];
}
- (void)mouseExited:(NSEvent*)anEvent {
	mouseInside = NO;
	[self fixCursorForBackgroundUpdatingMouseInside:NO];
    
    //fix for tooltip hanging around
    [super mouseExited:anEvent];
}

- (void)_fixCursorForBackgroundUpdatingMouseInside:(NSNumber*)num {
	[self fixCursorForBackgroundUpdatingMouseInside:[num boolValue]];
}

- (void)fixCursorForBackgroundUpdatingMouseInside:(BOOL)checkMouseLoc {
	
	if (IsLeopardOrLater && whiteIBeamCursorIMP && defaultIBeamCursorIMP) {
        if (checkMouseLoc) {
            mouseInside=[self mouseIsHere];
        }
//          NSLog(@"mouseInside :>%d<",mouseInside);
		BOOL shouldBeWhite = mouseInside && backgroundIsDark && ![self isHidden];
      
		Class class = [NSCursor class];
		
		//set method implementation directly; whiteIBeamCursorIMP and defaultIBeamCursorIMP always point to the same respective blocks of code
		Method defaultIBeamCursorMethod = class_getClassMethod(class, @selector(IBeamCursor));
		method_setImplementation(defaultIBeamCursorMethod, shouldBeWhite ? whiteIBeamCursorIMP : defaultIBeamCursorIMP);
		
		NSCursor *currentCursor = [NSCursor currentCursor];
		NSCursor *whiteCursor = whiteIBeamCursorIMP;
		NSCursor *defaultCursor = defaultIBeamCursorIMP;
      
		//if the current cursor is set incorrectly, and and it's not a non-IBeam cursor, then update it (IBeamCursor points to our recently-set implementation)
		if ((currentCursor == whiteCursor) != shouldBeWhite && (currentCursor == whiteCursor || currentCursor == defaultCursor)) {
			[[NSCursor IBeamCursor] set];
		}
	}
}

//hiding or showing the view does not always produce mouseEntered/Exited events
- (void)viewDidUnhide {
	[self performSelector:@selector(_fixCursorForBackgroundUpdatingMouseInside:) withObject:[NSNumber numberWithBool:YES] afterDelay:0.0];

	[super viewDidUnhide];
}
- (void)viewDidHide {
	[self fixCursorForBackgroundUpdatingMouseInside:YES];
	[super viewDidHide];
}

- (void)windowBecameOrResignedMain:(NSNotification *)aNotification  {
	//changing the window ordering seems to occasionally trigger mouseExited events w/o a corresponding mouseEntered
//	[self fixCursorForBackgroundUpdatingMouseInside:YES];
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
	//need to fix this for better style detection
	
	SEL action = [menuItem action];
    if ([self isHiddenOrHasHiddenAncestor]) return NO;
    if (action == @selector(undo:)) return [[[NVApplicationController sharedController] editingSessionForNote:[NVControllerForView(self) selectedNoteObject]] canUndo];
    if (action == @selector(redo:)) return [[[NVApplicationController sharedController] editingSessionForNote:[NVControllerForView(self) selectedNoteObject]] canRedo];
    if (action==@selector(performFindPanelAction:)) {
        //for ElasticThreads Find... fix. Also make sure all Find menuItems point their targets to LinkingEditor instead of firstResponder
        
        //hide Find and Replace... on Pre-Lion machines
        if (!IsLionOrLater){
            if([menuItem tag]==12) {
            [menuItem setHidden:YES];
            return NO;
            }
        }else{
            if ([menuItem tag]==7) {
                if (![textFinder validateAction:[menuItem tag]]) {
                    return NO;
                }
            }
        }
        return YES;
    }

	return [super validateMenuItem:menuItem];
}

- (id)highlightLinkAtIndex:(NSUInteger)givenIndex {
	NSUInteger totalLength = [[self string] length];
	NSUInteger charIndex = givenIndex;
	if (charIndex >= totalLength)
		charIndex = totalLength - 1;

	NSRange linkRange, maxRange = NSMakeRange(0, totalLength);
	id aLink = [[self textStorage] attribute:NSLinkAttributeName atIndex:charIndex longestEffectiveRange:&linkRange inRange:maxRange];
	
	if (aLink && linkRange.length && NSMaxRange(linkRange) <= maxRange.length)
		[self setAutomaticallySelectedRange:linkRange];
	return aLink;
}

- (void)clickedOnLink:(id)aLink atIndex:(NSUInteger)charIndex {
	NSEvent *currentEvent = [[self window] currentEvent];
//    NSLog(@"clicked:%@",[currentEvent description]);
	
	if (![prefsController URLsAreClickable] && [currentEvent modifierFlags] & NSCommandKeyMask) {
		
		[self highlightLinkAtIndex:charIndex];
		
	} else if (![prefsController URLsAreClickable]) {
		//pass normal mousedown?
		[self setSelectedRange:NSMakeRange(charIndex, 0)];
		return;
	}
	
	if ([aLink isKindOfClass:[NSURL class]] && [[aLink scheme] isEqualToString:@"nvalt"]) {
        NSUInteger flags=[currentEvent modifierFlags];
        if (((flags&NSDeviceIndependentModifierFlagsMask)==(flags&NSCommandKeyMask))&&((flags&NSDeviceIndependentModifierFlagsMask)>0)) {
            NSString *newURLString=[[aLink lastPathComponent]stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *txtString=[[NSString stringWithFormat:@"[[%@]]",[aLink lastPathComponent]] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            newURLString=[NSString stringWithFormat:@"nvalt://make/?title=%@&txt=%@",newURLString,txtString];
//            NSLog(@"newurlstring:%@",newURLString);
            NSURL *newURL=[NSURL URLWithString:newURLString];
//            NSLog(@"interpret from cmd-keydown OLD URL:||%@||  AND NEW URL:|%@|",[aLink absoluteString],[newURL absoluteString]);
            aLink=newURL;
        }
		[(AppController *)NVControllerForView(self) interpretNVURL:aLink];
	} else {
		[super clickedOnLink:aLink atIndex:charIndex];
	}
}

- (void)didChangeText {
	
	//if the text storage was somehow shortened since changedRange was set in -shouldChangeText, at least avoid an out of bounds exception
	changedRange = NSMakeRange(changedRange.location, (MIN(NSMaxRange(changedRange), [[self string] length]) - changedRange.location));


	//-removeAttribute:range: seems slow for some reason; try checking with -attributesAtIndex:effectiveRange: first
	if ([[self textStorage] attribute:NSLinkAttributeName existsInRange:changedRange])
		[[self textStorage] removeAttribute:NSLinkAttributeName range:changedRange];
	[[self textStorage] addLinkAttributesForRange:changedRange syntaxIdentifier:[self sourceSyntaxIdentifier]];
	

	//[[self window] invalidateCursorRectsForView:self];
	
	[super didChangeText];
}

- (BOOL)shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
    if (![self isEditable] || [self isHiddenOrHasHiddenAncestor]) return NO;
	
	//it's not exactly proper to alter typing attributes when we don't yet know whether the text should actually be changed, but NV shouldn't cause that to happen, anyway
	[self fixTypingAttributesForSubstitutedFonts];
	
	NSString *string = [self string];
		
	NSCharacterSet *separatorCharacterSet = [NSCharacterSet newlineCharacterSet];
	//even when only seeking newlines, this manual line-finding method is less laggy than -[NSString lineRangeForRange:]
	NSUInteger begin = [string rangeOfCharacterFromSet:separatorCharacterSet options:NSBackwardsSearch range:NSMakeRange(0, affectedCharRange.location)].location;
	if (begin == NSNotFound) {
		begin = 0;
	}
	
	NSUInteger end = [string rangeOfCharacterFromSet:separatorCharacterSet options:0 range:NSMakeRange(affectedCharRange.location + affectedCharRange.length, 
																									   [string length] - (affectedCharRange.location + affectedCharRange.length))].location;
	if (end == NSNotFound) {
		end = [string length];
	}
	changedRange = NSMakeRange(begin, (end - begin) + [replacementString length]);
		
	if (affectedCharRange.length > 0 && replacementString != nil) { // Deleting something
		changedRange.length -= affectedCharRange.length;
	}
	
	return [super shouldChangeTextInRange:affectedCharRange replacementString:replacementString];
}

- (void)fixTypingAttributesForSubstitutedFonts {
    [self setTypingAttributes:[prefsController noteBodyAttributes]];
}

- (void)dealloc {
    NSLog(@"dealloc linkinged");
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver: self];
    if (IsLionOrLater) {
        [textFinder release];
    }
    // Nib outlets, shared preferences, and computed substring results are borrowed.
    [lastImportedFindString release];
    [stringDuringFind release];
    [noteDuringFind release];
    
	[super dealloc];
}


#pragma mark - nvALT additions

- (BOOL)isOpaque{
    return YES;
}

- (void)flagsChanged:(NSEvent *)theEvent{
	[(AppController *)NVControllerForView(self) flagsChanged:theEvent];
}

- (BOOL)mouseIsHere{
    NSPoint mPt;
    NSRect vRect=[[self enclosingScrollView]visibleRect];
    if (IsLionOrLater) {
        NSRect aRect=NSZeroRect;
        aRect.origin=[NSEvent mouseLocation];
        mPt=[[self enclosingScrollView] convertPoint:[[self window] convertRectFromScreen:aRect].origin fromView:nil];
        if ([self textFinderIsVisible]) {
            NSView *fbView=[[self enclosingScrollView]findBarView];
            if (NSMouseInRect(mPt,[fbView frame],[fbView isFlipped])) {
                if (backgroundIsDark) {
                    [[self window]invalidateCursorRectsForView:fbView];
                }
                return NO;
            }
        }
    }else{
        mPt= [[self window]convertScreenToBase:[NSEvent mouseLocation]];
    }
    //    vRect.size.width=[[self enclosingScrollView]visibleRect].size.width;
    //     NSLog(@"mPt:%@     vRect :>%@<",NSStringFromPoint(mPt),NSStringFromRect(vRect));
    return NSMouseInRect(mPt,vRect,YES);
}


- (void)setMouseInside:(BOOL)inside{
    mouseInside=inside;
    [self fixCursorForBackgroundUpdatingMouseInside:NO];
}

- (void)resetInset{
    if ([self textContainerInset].width!=kDefaultTextInsetWidth) {
        [self setTextContainerInset:NSMakeSize(kDefaultTextInsetWidth, kDefaultTextInsetHeight)];
    }//||didRenderFully
    //    else if (didRenderFully) {
    //        NSLog(@"resetting but not");
    //    }
}


- (void)updateInsetAndForceLayout:(BOOL)force{
    [self updateInsetForFrame:[self frame] andForceLayout:force];
}

- (void)updateInsetForFrame:(NSRect)frameRect andForceLayout:(BOOL)force{
    if (managesTextWidth||([(AppController *)NVControllerForView(self)isInFullScreen])) {
        [self setInsetForFrame:frameRect alwaysSet:force];
    }else{
        [self resetInset];
    }
}

- (BOOL)setInsetForFrame:(NSRect)frameRect alwaysSet:(BOOL)always{
    CGFloat insX=kDefaultTextInsetWidth;
    CGFloat maxWidth=[prefsController maxNoteBodyWidth];
    if (frameRect.size.width>maxWidth) {
        insX=kTextMargins;
        CGFloat theMin=(maxWidth+(insX*1.9));
        if (frameRect.size.width<=theMin) {
            CGFloat diff=theMin-frameRect.size.width;
            diff=diff/2;
            insX=round(insX-diff);
            if (insX<kDefaultTextInsetWidth) {
                insX=kDefaultTextInsetWidth;
            }
        }
    }
    if (always||([self textContainerInset].width!=insX)) {
        [self setTextContainerInset:NSMakeSize(insX, kDefaultTextInsetHeight)];
        return YES;
    }
    return NO;
}


- (void)setFrame:(NSRect)frameRect{
    [self updateInsetForFrame:frameRect andForceLayout:NO];
    [super setFrame:frameRect];
}


- (void)prepareTextFinder{        
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if (IsLionOrLater) {
        
        
        [self setUsesFindBar:YES];
        
        [self setIncrementalSearchingEnabled:YES];
        textFinder=[[[NSTextFinder alloc]init]retain];
        [textFinder setClient:self];
        
        [textFinder setIncrementalSearchingEnabled:YES];
//        [textFinder setIncrementalSearchingShouldDimContentView:NO];
        NSNotificationCenter *dc=[NSNotificationCenter defaultCenter];
        [dc addObserver:self selector:@selector(textFinderShouldUpdateContext:) name:@"TextFindContextShouldUpdate" object:nil];
        [dc addObserver:self selector:@selector(textFinderShouldNoteChanges:) name:@"TextFindContextShouldNoteChanges" object:nil];
        [dc addObserver:self selector:@selector(textFinderShouldResetContext:) name:@"TextFindContextShouldReset" object:nil];
         [dc addObserver:self selector:@selector(hideTextFinderIfNecessary:) name:@"TextFinderShouldHide" object:nil];
        return;       
    }
#endif
    [self prepareTextFinderPreLion];
}

- (void)prepareTextFinderPreLion{
    [self setUsesFindPanel:YES];
    textFinder=[NSClassFromString(@"NSTextFinder")sharedTextFinder];
    [[textFinder findPanel:YES] setDelegate:self];
    NSArray *sViews = [[[textFinder findPanel:YES] contentView] subviews];
    for (id thing in sViews){
        if ([[thing className] isEqualToString:@"NSButton"]) {
            NSButton *aBut = thing;
            //            if (![aBut target]==nil) {
            [aBut setTarget:self];
            [aBut setAction:@selector(performFindPanelAction:)];
            //            }
        }
    }    
    [[textFinder findPanel:YES] update];
}


#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
- (void)textFinderShouldResetContext:(NSNotification *)aNotification{
    if ([aNotification object] != NVControllerForView(self)) return;
    
    if (IsLionOrLater){
        [textFinder cancelFindIndicator];
        [textFinder noteClientStringWillChange];
    }
}

- (void)textFinderShouldNoteChanges:(NSNotification *)aNotification{
    if ([aNotification object] != NVControllerForView(self)) return;
    if (IsLionOrLater){
        [textFinder noteClientStringWillChange];
    }
}

- (void)textFinderShouldUpdateContext:(NSNotification *)aNotification{
    if ([aNotification object] != NVControllerForView(self)) return;
    
    if (IsLionOrLater){
        [textFinder setFindIndicatorNeedsUpdate:YES];
    }
}

- (void)hideTextFinderIfNecessary:(NSNotification *)aNotification{
    if ([aNotification object] != NVControllerForView(self)) return;
    if (IsLionOrLater){        
        if([self textFinderIsVisible]){            
            [textFinder setFindIndicatorNeedsUpdate:YES];
            [textFinder cancelFindIndicator];
            [textFinder performAction:NSTextFinderActionHideFindInterface];
        }
    }
}
#endif

- (BOOL)textFinderIsVisible{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if ((IsLionOrLater)&&([[self enclosingScrollView]findBarView]!=nil)) {
        return [[[self enclosingScrollView] subviews]containsObject:[[self enclosingScrollView]findBarView]];
    }
#endif
    return NO;
}

- (IBAction)performFindPanelAction:(id)sender {
    id controller = NVControllerForView(self);
    if(![controller setNoteIfNecessary])
        return;
    
    NSInteger findTag=[sender tag];
    
    [sender setTarget:nil];
    if(!IsLionOrLater||([sender tag]!=7)){
        NSString *pbType;
        if (IsSnowLeopardOrLater) {
            pbType=NSPasteboardTypeString;
        }else{
            pbType=NSStringPboardType;
        }
        NSString *typedString = [controller typedString];
        if (!typedString) typedString = [controlField stringValue];
        if (!typedString||([typedString length]==0)) {
            typedString =[[NSPasteboard generalPasteboard]stringForType:pbType];
        }
         if (typedString&&([typedString length]>0)) {
             typedString = [typedString stringByReplacingOccurrencesOfString:@"\"" withString:@""];
             typedString=[typedString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
             if ([typedString length] > 0 && ![lastImportedFindString isEqualToString:typedString]) {
                 
                 NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
                 [pasteboard declareTypes:[NSArray arrayWithObject:pbType] owner:nil];
                 [pasteboard setString:typedString forType:pbType];
                 [lastImportedFindString release];
                 lastImportedFindString = [typedString retain];
             }
         }       
    
    }
    if ([[self window] firstResponder]!=self) {
        [[self window]makeFirstResponder:self];
    }
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if (IsLionOrLater) {
        
        id newSender=[sender copy];
        if((findTag!=1)&&(findTag!=12)&&(findTag!=7)&&(![self textFinderIsVisible])){            
            [newSender setTag:NSTextFinderActionShowFindInterface];
            [super performTextFinderAction:newSender];
        } 
        if (findTag==1) {
            findTag=NSTextFinderActionShowFindInterface;
        }else if (findTag==2) {            
            findTag=NSTextFinderActionNextMatch;
        }else if (findTag==3) {
            findTag=NSTextFinderActionPreviousMatch;
        }else if (findTag==4) {
            findTag=NSTextFinderActionReplaceAll;
        }else if (findTag==5) {
            findTag=NSTextFinderActionReplace;
        }else if (findTag==6) {
            findTag=NSTextFinderActionReplaceAndFind;
        }else if (findTag==7) {
            findTag=(NSTextFinderActionSetSearchString);
        }else if (findTag==9) {
            findTag=NSTextFinderActionSelectAll;
        }else if (findTag==12) {
            findTag=NSTextFinderActionShowReplaceInterface;
        }//NSTextFinderActionSelectAll = 9,
        [newSender setTag:findTag];
        
        if ([textFinder validateAction:findTag]) {
            [super performTextFinderAction:newSender]; 
            if ((findTag==NSTextFinderActionSetSearchString)&&(![self textFinderIsVisible])) {
                [newSender setTag:NSTextFinderActionShowFindInterface];
                [super performTextFinderAction:newSender];
            }
            
//            [textFinder setFindIndicatorNeedsUpdate:YES];
        }else{
            NSLog(@"find action was invalid");
        }
        [newSender release];
        return;
    }
#endif
    //not lion do it the old, hacky way
    if([sender tag]==1){
        if(lastImportedFindString&&(lastImportedFindString.length>0)&&([textFinder respondsToSelector:@selector(loadFindStringFromPasteboard)])){                
            if(![textFinder loadFindStringFromPasteboard]){
                [textFinder setFindString:lastImportedFindString writeToPasteboard:YES updateUI:YES];
            }
        }
//        else{
//            NSLog(@"Apple changed NSTextFinder (loadFindStringFromPasteboard)");
//        }	
    }
    [super performFindPanelAction:sender];    
}

@end
