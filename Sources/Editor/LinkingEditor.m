#import "NVApplicationController.h"
#import "NVNoteEditingSession.h"
#import "NVSourceAnalysis.h"
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
#define kDefaultTextInsetWidth 8.0
#define kDefaultTextInsetHeight 8.0


@implementation LinkingEditor
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
	
	didRenderFully = NO;
	[[self layoutManager] setDelegate:self];


    [self setRichText:NO];
    [self setImportsGraphics:NO];

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
	return [super becomeFirstResponder];
}

- (void)indicateRange:(NSValue*)rangeValue {
	[self showFindIndicatorForRange:[rangeValue rangeValue]];
}

- (BOOL)resignFirstResponder {
	[notesTableView setShouldUseSecondaryHighlightColor:NO];
	
	return [super resignFirstResponder];
}

- (void)setBackgroundColor:(NSColor*)aColor {
	backgroundIsDark = (_perceptualDarkness([aColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace]) > 0.5);
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
    if ([self textFinderIsVisible]) {
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

- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:(const CGGlyph *)glyphs
                 properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes
                       font:(NSFont *)font forGlyphRange:(NSRange)range {
    if (!range.length || range.length > SIZE_MAX / sizeof(NSGlyphProperty)) return 0;
    NSString *source = [[manager textStorage] string];
    NSUInteger sourceLength = [source length];
    NSGlyphProperty *adjusted = NULL;
    for (NSUInteger i = 0; i < range.length; i++) {
        if ((properties[i] & NSGlyphPropertyElastic) &&
            !(properties[i] & NSGlyphPropertyControlCharacter) && indexes[i] < sourceLength &&
            [source characterAtIndex:indexes[i]] == ' ') {
            if (!adjusted) {
                adjusted = malloc(range.length * sizeof(NSGlyphProperty));
                if (!adjusted) return 0;
                memcpy(adjusted, properties, range.length * sizeof(NSGlyphProperty));
            }
            // Elastic spaces collect at the right margin instead of wrapping.
            // Give ordinary spaces their font width without changing the source,
            // glyph IDs, or native editing and insertion-point behavior.
            adjusted[i] &= ~NSGlyphPropertyElastic;
        }
    }
    if (!adjusted) return 0;
    [manager setGlyphs:glyphs properties:adjusted characterIndexes:indexes font:font forGlyphRange:range];
    free(adjusted);
    return range.length;
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
    if (!hasSearchHighlights || searchHighlightsInvalidated) return;
    searchHighlightsInvalidated = YES;
    // TextKit has not adjusted its glyph ranges during storage notifications.
    // Suppress stale backgrounds now and remove them after edit processing.
    [self performSelector:@selector(removeHighlightedTerms) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
}
- (void)removeHighlightedTerms {
    if (!hasSearchHighlights && !searchHighlightsInvalidated) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];
    if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) {
        searchHighlightsInvalidated = YES;
        // A nested run loop can run before endEditing. Avoid retrying at zero delay.
        [self performSelector:@selector(removeHighlightedTerms) withObject:nil afterDelay:0.01 inModes:@[NSRunLoopCommonModes]];
        return;
    }
    searchHighlightsInvalidated = NO;
    hasSearchHighlights = NO;
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
    if (searchHighlightsInvalidated || ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)) return;
    NSColor *color = [[self currentSearchHighlightAttributes] objectForKey:NSBackgroundColorAttributeName];
    if (!color) return;
    NSUInteger length = [[self string] length];
    NSUInteger displayed = 0;
    for (NSValue *value in ranges) {
        if (displayed++ == NVSearchMaximumDisplayedRanges) break;
        NSRange range = [value rangeValue];
        if (range.location <= length && range.length <= length - range.location && range.length) {
            [[self layoutManager] addTemporaryAttribute:NSBackgroundColorAttributeName value:color forCharacterRange:range];
            hasSearchHighlights = YES;
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

    
- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
	//need to fix this for better style detection
	
	SEL action = [menuItem action];
    if ([self isHiddenOrHasHiddenAncestor]) return NO;
    if (action == @selector(undo:)) return [[[NVApplicationController sharedController] editingSessionForNote:[NVControllerForView(self) selectedNoteObject]] canUndo];
    if (action == @selector(redo:)) return [[[NVApplicationController sharedController] editingSessionForNote:[NVControllerForView(self) selectedNoteObject]] canRedo];
    if (action==@selector(performFindPanelAction:)) {
        //for ElasticThreads Find... fix. Also make sure all Find menuItems point their targets to LinkingEditor instead of firstResponder
        
        if ([menuItem tag] == 7 && ![textFinder validateAction:[menuItem tag]]) {
            return NO;
        }
        return YES;
    }

	return [super validateMenuItem:menuItem];
}

- (id)highlightLinkAtIndex:(NSUInteger)givenIndex {
	NSUInteger totalLength = [[self string] length];
	if (!totalLength || !NVSourceLinksAreCurrent([self textStorage])) return nil;
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
	if (!NVSourceLinksAreCurrent([self textStorage])) {
		// Treat obsolete link attributes as ordinary source text until analysis finishes.
		[self setSelectedRange:NSMakeRange(MIN(charIndex, [[self string] length]), 0)];
		return;
	}
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

- (NSMenu *)menuForEvent:(NSEvent *)event {
    // NSTextView creates Open/Copy Link actions directly from its attributes.
    // Drop obsolete targets before it builds that menu. This runs in response
    // to a mouse event, after character processing, and never on the typing path.
    if (!NVSourceLinksAreCurrent([self textStorage]))
        [[self textStorage] removeAttribute:NSLinkAttributeName range:NSMakeRange(0, [[self textStorage] length])];
    return [super menuForEvent:event];
}

- (void)dealloc {
    NSLog(@"dealloc linkinged");
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [textFinder release];
    
	[super dealloc];
}


#pragma mark - nvALT additions

- (BOOL)isOpaque{
    return YES;
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


- (void)prepareTextFinder {
    [self setUsesFindBar:YES];
    [self setIncrementalSearchingEnabled:YES];
    textFinder = [[NSTextFinder alloc] init];
    [textFinder setClient:self];
    [textFinder setIncrementalSearchingEnabled:YES];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(textFinderShouldUpdateContext:) name:@"TextFindContextShouldUpdate" object:nil];
    [center addObserver:self selector:@selector(textFinderShouldResetContext:) name:@"TextFindContextShouldReset" object:nil];
    [center addObserver:self selector:@selector(hideTextFinderIfNecessary:) name:@"TextFinderShouldHide" object:nil];
}

- (void)textFinderShouldResetContext:(NSNotification *)aNotification{
    if ([aNotification object] != NVControllerForView(self)) return;
    [textFinder cancelFindIndicator];
    [textFinder noteClientStringWillChange];
}

- (void)textFinderShouldUpdateContext:(NSNotification *)aNotification{
    if ([aNotification object] != NVControllerForView(self)) return;
    [textFinder setFindIndicatorNeedsUpdate:YES];
}

- (void)hideTextFinderIfNecessary:(NSNotification *)aNotification{
    if ([aNotification object] != NVControllerForView(self)) return;
    if([self textFinderIsVisible]){
        [textFinder setFindIndicatorNeedsUpdate:YES];
        [textFinder cancelFindIndicator];
        [textFinder performAction:NSTextFinderActionHideFindInterface];
    }
}

- (BOOL)textFinderIsVisible{
    NSView *findBarView = [[self enclosingScrollView] findBarView];
    return findBarView && [[[self enclosingScrollView] subviews] containsObject:findBarView];
}

- (IBAction)performFindPanelAction:(id)sender {
    id controller = NVControllerForView(self);
    if(![controller setNoteIfNecessary])
        return;

    if ([[self window] firstResponder]!=self) {
        [[self window]makeFirstResponder:self];
    }

    NSInteger findTag=[sender tag];
    id newSender=[sender copy];
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
        findTag=NSTextFinderActionSetSearchString;
    }else if (findTag==9) {
        findTag=NSTextFinderActionSelectAll;
    }else if (findTag==12) {
        findTag=NSTextFinderActionShowReplaceInterface;
    }
    [newSender setTag:findTag];
    [super performTextFinderAction:newSender];
    [newSender release];
}

@end
