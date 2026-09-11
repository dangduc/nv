//
//  GlobalPrefs.m
//  Notation
//
//  Created by Zachary Schneirov on 1/31/06.

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


#import "GlobalPrefs.h"
#import "NSData_transformations.h"
#import "NotationPrefs.h"
#import "BookmarksController.h"
#import "AttributedPlainText.h"
#import "FastListDataSource.h"
#import "NotesTableView.h"
#import "PTHotKey.h"
#import "PTKeyCombo.h"
#import "PTHotKeyCenter.h"
#import "NSString_NV.h"
#import "AppController.h"
#import "BufferUtils.h"

#define SEND_CALLBACKS() sendCallbacksForGlobalPrefs(self, _cmd, sender)

static NSString *TriedToImportBlorKey = @"TriedToImportBlor";
static NSString *DirectoryAliasKey = @"DirectoryAlias";
static NSString *AutoCompleteSearchesKey = @"AutoCompleteSearches";
static NSString *NoteAttributesVisibleKey = @"NoteAttributesVisible";
static NSString *TableFontSizeKey = @"TableFontPointSize";
static NSString *TableSortColumnKey = @"TableSortColumn";
static NSString *TableIsReverseSortedKey = @"TableIsReverseSorted";
static NSString *TableColumnsHaveBodyPreviewKey = @"TableColumnsHaveBodyPreview";
static NSString *ShowTitleInTopSectionKey = @"ShowTitleInTopSection";
static NSString *ShowTagsInTopSectionKey = @"ShowTagsInTopSection";
static NSString *ShowBodyControlsInTopSectionKey = @"ShowBodyControlsInTopSection";
static NSString *ShowNotesListKey = @"ShowNotesList";
static NSString *NoteBodyFontKey = @"NoteBodyFont";
static NSString *ConfirmNoteDeletionKey = @"ConfirmNoteDeletion";
static NSString *QuitWhenClosingMainWindowKey = @"QuitWhenClosingMainWindow";
static NSString *AutoFormatsDoneTagKey = @"AutoFormatsDoneTag";
static NSString *HighlightSearchTermsKey = @"HighlightSearchTerms";
static NSString *SearchTermHighlightColorKey = @"SearchTermHighlightColor";
static NSString *ForegroundTextColorKey = @"ForegroundTextColor";
static NSString *BackgroundTextColorKey = @"BackgroundTextColor";
static NSString *DarkSearchTermHighlightColorKey = @"DarkSearchTermHighlightColor";
static NSString *DarkForegroundTextColorKey = @"DarkForegroundTextColor";
static NSString *DarkBackgroundTextColorKey = @"DarkBackgroundTextColor";
static NSString *MakeURLsClickableKey = @"MakeURLsClickable";
static NSString *AppActivationKeyCodeKey = @"AppActivationKeyCode";
static NSString *AppActivationModifiersKey = @"AppActivationModifiers";
static NSString *HorizontalLayoutKey = @"HorizontalLayout";
static NSString *BookmarksKey = @"Bookmarks";
static NSString *LastScrollOffsetKey = @"LastScrollOffset";
static NSString *LastSearchStringKey = @"LastSearchString";
static NSString *LastSearchModeKey = @"LastSearchMode";
static NSString *LastSearchResultRowKey = @"LastSearchResultRowKey";
static NSString *LastSelectedNoteUUIDBytesKey = @"LastSelectedNoteUUIDBytes";
static NSString *LastSelectedPreferencesPaneKey = @"LastSelectedPrefsPane";
//elasticthreads prefs
static NSString *StatusBarItem = @"StatusBarItem";
static NSString	*ShowDockIcon = @"ShowDockIcon";
static NSString	*KeepsMaxTextWidth = @"KeepsMaxTextWidth";
static NSString	*NoteBodyMaxWidth = @"NoteBodyMaxWidth";
static NSString	*ColorScheme = @"ColorScheme";
static NSString *ShowGridKey = @"ShowGrid";
static NSString *AlternatingRowsKey = @"AlternatingRows";
static NSString *ShowWordCount = @"ShowWordCount";
static NSString *UseETScrollbarsOnLion = @"UseETScrollbarsOnLion";
static NSString *UseFinderTagsKey = @"UseFinderTags";
//static NSString *PasteClipboardOnNewNoteKey = @"PasteClipboardOnNewNote";

//these 4 strings manually localized
NSString *NoteTitleColumnString = @"Title";
NSString *NoteLabelsColumnString = @"Tags";
NSString *NoteDateModifiedColumnString = @"Date Modified";
NSString *NoteDateCreatedColumnString = @"Date Added";

//virtual column
NSString *NotePreviewString = @"Note Preview";

NSString *NVPTFPboardType = @"Notational Velocity Poor Text Format";

NSString *HotKeyAppToFrontName = @"bring Notational Velocity to the foreground";


@implementation GlobalPrefs

static void sendCallbacksForGlobalPrefs(GlobalPrefs* self, SEL selector, id originalSender) {
    // FIXME
	if (originalSender != self) {
		self->runCallbacksIMP(self, @selector(notifyCallbacksForSelector:excludingSender:), 
							 selector, originalSender);
	}
}

- (id)init {
	if (self=[super init]) {
        
		runCallbacksIMP = [self methodForSelector:@selector(notifyCallbacksForSelector:excludingSender:)];
		selectorObservers = [[NSMutableDictionary alloc] init];
		
		defaults = [NSUserDefaults standardUserDefaults];
		
		tableColumns = nil;

		[defaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithBool:NO], UseFinderTagsKey,
			[NSNumber numberWithBool:YES], AutoFormatsDoneTagKey, 
			[NSNumber numberWithBool:YES], ConfirmNoteDeletionKey,
			[NSNumber numberWithBool:YES], AutoCompleteSearchesKey,
			[NSNumber numberWithBool:YES], QuitWhenClosingMainWindowKey, 
			[NSNumber numberWithBool:NO], TriedToImportBlorKey,
			[NSNumber numberWithBool:NO], HorizontalLayoutKey,
			[NSNumber numberWithBool:YES], MakeURLsClickableKey,
			[NSNumber numberWithBool:YES], HighlightSearchTermsKey, 
			[NSNumber numberWithBool:YES], TableColumnsHaveBodyPreviewKey, 
			[NSNumber numberWithBool:NO], ShowTitleInTopSectionKey,
			[NSNumber numberWithBool:NO], ShowTagsInTopSectionKey,
			[NSNumber numberWithBool:NO], ShowBodyControlsInTopSectionKey,
			[NSNumber numberWithBool:YES], ShowNotesListKey,
			[NSNumber numberWithDouble:0.0], LastScrollOffsetKey,
			@"General", LastSelectedPreferencesPaneKey, 
			[NSNumber numberWithBool:NO], StatusBarItem, 
			[NSNumber numberWithBool:NO], KeepsMaxTextWidth,
			[NSNumber numberWithFloat:660.0], NoteBodyMaxWidth,
			[NSNumber numberWithInt:3], ColorScheme,
            [NSNumber numberWithBool:YES],ShowDockIcon,
            [NSNumber numberWithBool:YES], ShowWordCount,
            [NSNumber numberWithBool:NO], ShowGridKey,
            [NSNumber numberWithBool:YES], AlternatingRowsKey,
            [NSNumber numberWithBool:NO], UseETScrollbarsOnLion,

			[NSArchiver archivedDataWithRootObject:
			 [NSFont userFixedPitchFontOfSize:12.0f]], NoteBodyFontKey,
			
			[NSArchiver archivedDataWithRootObject:[NSColor blackColor]], ForegroundTextColorKey,
			[NSArchiver archivedDataWithRootObject:[NSColor whiteColor]], BackgroundTextColorKey,
			
			[NSArchiver archivedDataWithRootObject:
			 [NSColor colorWithCalibratedRed:0.945 green:0.702 blue:0.702 alpha:1.0f]], SearchTermHighlightColorKey,
			[NSArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedWhite:0.90 alpha:1.0]], DarkForegroundTextColorKey,
			[NSArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedWhite:0.10 alpha:1.0]], DarkBackgroundTextColorKey,
			[NSArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedRed:0.38 green:0.28 blue:0.10 alpha:1.0]], DarkSearchTermHighlightColorKey,
			
			[NSNumber numberWithFloat:[NSFont smallSystemFontSize]], TableFontSizeKey, 
			[NSArray arrayWithObjects:NoteTitleColumnString, NoteDateModifiedColumnString, nil], NoteAttributesVisibleKey,
			NoteDateModifiedColumnString, TableSortColumnKey,
			[NSNumber numberWithBool:YES], TableIsReverseSortedKey, nil]];
		
		autoCompleteSearches = [defaults boolForKey:AutoCompleteSearchesKey];
	}
	return self;
}

+ (GlobalPrefs *)defaultPrefs {
	static GlobalPrefs *prefs = nil;
	if (!prefs)
		prefs = [[GlobalPrefs alloc] init];
	return prefs;
}

- (void)dealloc {
	
	[tableColumns release];
	[super dealloc];
}

- (void)registerWithTarget:(id)sender forChangesInSettings:(SEL)firstSEL, ... {
	NSAssert(firstSEL != NULL, @"need at least one selector");

	if ([sender respondsToSelector:(@selector(settingChangedForSelectorString:))]) {
	
		va_list argList;
		va_start(argList, firstSEL);
		SEL aSEL = firstSEL;
		do {
			NSString *selectorKey = NSStringFromSelector(aSEL);
			
			NSMutableArray *senders = [selectorObservers objectForKey:selectorKey];
			if (!senders) {
				senders = [[[NSMutableArray alloc] initWithCapacity:1] autorelease];
				[selectorObservers setObject:senders forKey:selectorKey];
			}
			[senders addObject:sender];
//            [senders release];
		} while (( aSEL = va_arg( argList, SEL) ) != nil);
		va_end(argList);
		
	} else {
		NSLog(@"%@: target %@ does not respond to callback selector!", NSStringFromSelector(_cmd), [sender description]);
	}
}

- (void)registerForSettingChange:(SEL)selector withTarget:(id)sender {
	[self registerWithTarget:sender forChangesInSettings:selector, nil];
}

- (void)unregisterTarget:(id)target {
    for (NSString *key in [selectorObservers allKeys]) {
        [[selectorObservers objectForKey:key] removeObjectIdenticalTo:target];
        if (![[selectorObservers objectForKey:key] count]) [selectorObservers removeObjectForKey:key];
    }
}

- (void)unregisterForNotificationsFromSelector:(SEL)selector sender:(id)sender {
	NSString *selectorKey = NSStringFromSelector(selector);
	
	NSMutableArray *senders = [selectorObservers objectForKey:selectorKey];
	if (senders) {
		[senders removeObjectIdenticalTo:sender];
		
		if (![senders count])
			[selectorObservers removeObjectForKey:selectorKey];
	} else {
		NSLog(@"Selector %@ has no observers?", NSStringFromSelector(selector));
	}
}

- (void)notifyCallbacksForSelector:(SEL)selector excludingSender:(id)sender {
	NSArray *observers = nil;
	id observer = nil;
	
	NSString *selectorKey = NSStringFromSelector(selector);
	
	if ((observers = [selectorObservers objectForKey:selectorKey])) {
		unsigned int i;
		
		for (i=0; i<[observers count]; i++) {
			
			if ((observer = [observers objectAtIndex:i]) != sender && observer)
				[observer performSelector:@selector(settingChangedForSelectorString:) withObject:selectorKey];
		}
	}
}

- (void)setNotationPrefs:(NotationPrefs*)newNotationPrefs sender:(id)sender {
	[notationPrefs autorelease];
	notationPrefs = [newNotationPrefs retain];
	
	[self resolveNoteBodyFontFromNotationPrefsFromSender:sender];
	
	SEND_CALLBACKS();
}

- (NotationPrefs*)notationPrefs {
	return notationPrefs;
}

- (BOOL)autoCompleteSearches {
	return autoCompleteSearches;
}

- (void)setAutoCompleteSearches:(BOOL)value sender:(id)sender {
	autoCompleteSearches = value;
	[defaults setBool:value forKey:AutoCompleteSearchesKey];
	
	SEND_CALLBACKS();
}

- (void)setConfirmNoteDeletion:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:ConfirmNoteDeletionKey];
    
    SEND_CALLBACKS();
}
- (BOOL)confirmNoteDeletion {
    return [defaults boolForKey:ConfirmNoteDeletionKey];
}

- (void)setQuitWhenClosingWindow:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:QuitWhenClosingMainWindowKey];
    
    SEND_CALLBACKS();
}
- (BOOL)quitWhenClosingWindow {
    return [defaults boolForKey:QuitWhenClosingMainWindowKey];
}

- (void)setAppActivationKeyCombo:(PTKeyCombo*)aCombo sender:(id)sender {
	if (aCombo) {
		[appActivationKeyCombo release];
		appActivationKeyCombo = [aCombo retain];
		
		[[self appActivationHotKey] setKeyCombo:appActivationKeyCombo];
	
		[defaults setInteger:[aCombo keyCode] forKey:AppActivationKeyCodeKey];
		[defaults setInteger:[aCombo modifiers] forKey:AppActivationModifiersKey];
		
		SEND_CALLBACKS();
	}
}

- (PTHotKey*)appActivationHotKey {
	if (!appActivationHotKey) {
		appActivationHotKey = [[PTHotKey alloc] init];
		[appActivationHotKey setName:HotKeyAppToFrontName];
		[appActivationHotKey setKeyCombo:[self appActivationKeyCombo]];
	}
	
	return appActivationHotKey;
}

- (PTKeyCombo*)appActivationKeyCombo {
	if (!appActivationKeyCombo) {
		appActivationKeyCombo = [[PTKeyCombo alloc] initWithKeyCode:[[defaults objectForKey:AppActivationKeyCodeKey] intValue]
														  modifiers:[[defaults objectForKey:AppActivationModifiersKey] intValue]];
	}
	return appActivationKeyCombo;
}

- (BOOL)registerAppActivationKeystrokeWithTarget:(id)target selector:(SEL)selector {
	PTHotKey *hotKey = [self appActivationHotKey];
	
	[hotKey setTarget:target];
	[hotKey setAction:selector];
	
	[[PTHotKeyCenter sharedCenter] unregisterHotKeyForName:HotKeyAppToFrontName];
	
	return [[PTHotKeyCenter sharedCenter] registerHotKey:hotKey];
}

- (void)setAutoFormatsDoneTag:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:AutoFormatsDoneTagKey];
	
	SEND_CALLBACKS();
}
- (BOOL)autoFormatsDoneTag {
	return [defaults boolForKey:AutoFormatsDoneTagKey];
}
- (void)setMakeURLsClickable:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:MakeURLsClickableKey];
	
	SEND_CALLBACKS();
}
- (BOOL)URLsAreClickable {
	return [defaults boolForKey:MakeURLsClickableKey];
}

- (BOOL)showWordCount{
	return [defaults boolForKey:ShowWordCount];
}

- (void)setShowWordCount:(BOOL)value{
	[defaults setBool:value forKey:ShowWordCount];
	sendCallbacksForGlobalPrefs(self, _cmd, nil);
}

- (void)setUseETScrollbarsOnLion:(BOOL)value sender:(id)sender{
	[defaults setBool:value forKey:UseETScrollbarsOnLion];
	SEND_CALLBACKS();
}

- (BOOL)useETScrollbarsOnLion{
	return [defaults boolForKey:UseETScrollbarsOnLion];
}


- (void)setShowGrid:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:ShowGridKey];
	
	SEND_CALLBACKS();
}
- (BOOL)showGrid {
	return [defaults boolForKey:ShowGridKey];
}
- (void)setAlternatingRows:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:AlternatingRowsKey];
	
	SEND_CALLBACKS();
}
- (BOOL)alternatingRows {
	return [defaults boolForKey:AlternatingRowsKey];
}

- (void)setShouldHighlightSearchTerms:(BOOL)shouldHighlight sender:(id)sender {
	[defaults setBool:shouldHighlight forKey:HighlightSearchTermsKey];
	
	SEND_CALLBACKS();
}
- (BOOL)highlightSearchTerms {
	return [defaults boolForKey:HighlightSearchTermsKey];
}

- (void)setSearchTermHighlightColor:(NSColor*)color sender:(id)sender {
	if (color) {
		[defaults setObject:[NSArchiver archivedDataWithRootObject:color] forKey:SearchTermHighlightColorKey];
		
		SEND_CALLBACKS();
	}
}

- (NSColor*)searchTermHighlightColorRaw:(BOOL)isRaw {
	
	NSData *theData = [defaults dataForKey:SearchTermHighlightColorKey];
	if (theData) {
		NSColor *color = (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
		if (isRaw) return color;
		if (color) {
			//nslayoutmanager temporary attributes don't seem to like alpha components, so synthesize translucency using the bg color
			NSColor *fauxAlphaSTHC = [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] colorWithAlphaComponent:1.0];
			return [fauxAlphaSTHC blendedColorWithFraction:(1.0 - [color alphaComponent]) ofColor:[self backgroundTextColor]];
		}
	}

	return nil;
}

- (NSDictionary*)searchTermHighlightAttributes {
    return [self searchTermHighlightAttributesForDarkAppearance:NO backgroundColor:[self backgroundTextColor]];
}

- (void)setDarkSearchTermHighlightColor:(NSColor*)color sender:(id)sender {
    if (color) {
        [defaults setObject:[NSArchiver archivedDataWithRootObject:color] forKey:DarkSearchTermHighlightColorKey];
        SEND_CALLBACKS();
    }
}

- (NSColor*)darkSearchTermHighlightColor {
    NSData *data = [defaults dataForKey:DarkSearchTermHighlightColorKey];
    return data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
}

- (NSDictionary*)searchTermHighlightAttributesForDarkAppearance:(BOOL)dark backgroundColor:(NSColor*)background {
    NSColor *color = dark ? [self darkSearchTermHighlightColor] : [self searchTermHighlightColorRaw:YES];
    if (!color) return nil;
    // Temporary backgrounds use an opaque blend against this editor's actual background.
    NSColor *opaque = [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] colorWithAlphaComponent:1.0];
    NSColor *highlight = [opaque blendedColorWithFraction:1.0 - [color alphaComponent] ofColor:background];
    return highlight ? [NSDictionary dictionaryWithObject:highlight forKey:NSBackgroundColorAttributeName] : nil;
}

- (void)setUseFinderTags:(id)sender {
	if (!IsMavericksOrLater) {
		[defaults setBool:NO forKey:UseFinderTagsKey];
		return;
	}
	[defaults setBool:YES forKey:UseFinderTagsKey];
	SEND_CALLBACKS();
}

- (BOOL)useFinderTags
{
    if (!IsMavericksOrLater) {
        return NO;
    }
	return [defaults boolForKey:UseFinderTagsKey];
}

BOOL ColorsEqualWith8BitChannels(NSColor *c1, NSColor *c2) {
	//sometimes floating point numbers really don't like to be compared to each other

	CGFloat pRed, pGreen, pBlue, gRed, gGreen, gBlue, pAlpha, gAlpha;
	[[c1 colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&pRed green:&pGreen blue:&pBlue alpha:&pAlpha];
	[[c2 colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&gRed green:&gGreen blue:&gBlue alpha:&gAlpha];
	
#define SCR(__ch) ((int)roundf(((__ch) * 255.0)))
	
	return (SCR(pRed) == SCR(gRed) && SCR(pBlue) == SCR(gBlue) && SCR(pGreen) == SCR(gGreen) && SCR(pAlpha) == SCR(gAlpha));
}

- (void)resolveNoteBodyFontFromNotationPrefsFromSender:(id)sender {
	
	NSFont *prefsFont = [notationPrefs baseBodyFont];
	if (prefsFont) {
		NSFont *noteFont = [self noteBodyFont];
		
		if (![[prefsFont fontName] isEqualToString:[noteFont fontName]] || 
			[prefsFont pointSize] != [noteFont pointSize]) {
			
			NSLog(@"archived notationPrefs base font does not match current global default font!");
			[self _setNoteBodyFont:prefsFont];
			
			SEND_CALLBACKS();
		}
	}
}

- (void)_setNoteBodyFont:(NSFont*)aFont {
	NSFont *oldFont = noteBodyFont;
	noteBodyFont = [aFont retain];
	
	[noteBodyAttributes release];
	noteBodyAttributes = nil; //cause method to re-update
	
	[defaults setObject:[NSArchiver archivedDataWithRootObject:noteBodyFont] forKey:NoteBodyFontKey]; 
	
	[oldFont release];
}

- (void)setNoteBodyFont:(NSFont*)aFont sender:(id)sender {
	
	if (aFont) {
		[self _setNoteBodyFont:aFont];
		
		SEND_CALLBACKS();
	}
}

- (NSFont*)noteBodyFont {
	BOOL triedOnce = NO;
	
	if (!noteBodyFont) {
		retry:
		@try {
			noteBodyFont = [[NSUnarchiver unarchiveObjectWithData:[defaults objectForKey:NoteBodyFontKey]] retain];
		} @catch (NSException *e) {
			NSLog(@"Error trying to unarchive default note body font (%@, %@)", [e name], [e reason]);
		}
		
		if ((!noteBodyFont || ![noteBodyFont isKindOfClass:[NSFont class]]) && !triedOnce) {
			triedOnce = YES;
			[defaults removeObjectForKey:NoteBodyFontKey];
			goto retry;
		}
	}
	
    return noteBodyFont;
}

- (NSDictionary*)noteBodyAttributes {
	NSFont *bodyFont = [self noteBodyFont];
	if (!noteBodyAttributes && bodyFont) {
		//NSLog(@"notebody att2");
		
		NSMutableDictionary *attrs = [[NSMutableDictionary dictionaryWithObjectsAndKeys:bodyFont, NSFontAttributeName, nil] retain];
		
		//not storing the foreground color in each note will make the database smaller, and black is assumed when drawing text
		NSColor *fgColor = [(AppController *)[NSApp delegate] foregrndColor];
		
		if (!ColorsEqualWith8BitChannels([NSColor blackColor], fgColor)) {
			[attrs setObject:fgColor forKey:NSForegroundColorAttributeName];
		}
		// background text color is handled directly by the NSTextView subclass and so does not need to be stored here
		noteBodyAttributes = attrs;
	}else {
		//NSLog(@"notebody att4");
		NSMutableDictionary *attrs = [[NSMutableDictionary dictionaryWithObjectsAndKeys:bodyFont, NSFontAttributeName, nil] retain];
		NSColor *fgColor = [(AppController *)[NSApp delegate] foregrndColor];
		
		//	if (!ColorsEqualWith8BitChannels([NSColor blackColor], fgColor)) {
		[attrs setObject:fgColor forKey:NSForegroundColorAttributeName];
		noteBodyAttributes = attrs;
		//	}
	}

	// NVSourceTypesetter supplies word boundaries over native character layout.
	// The character base keeps the editor's fixed-width spaces advancing.
	static NSParagraphStyle *sourceStyle;
	static dispatch_once_t sourceStyleOnce;
	dispatch_once(&sourceStyleOnce, ^{
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		[style setLineBreakMode:NSLineBreakByCharWrapping];
		sourceStyle = [style copy];
		[style release];
	});
	[(NSMutableDictionary *)noteBodyAttributes setObject:sourceStyle forKey:NSParagraphStyleAttributeName];
	return noteBodyAttributes;
}
- (void)setForegroundTextColor:(NSColor*)aColor sender:(id)sender {
	if (aColor) {
		[noteBodyAttributes release];
		noteBodyAttributes = nil;
		
		[defaults setObject:[NSArchiver archivedDataWithRootObject:aColor] forKey:ForegroundTextColorKey];
		
		SEND_CALLBACKS();
	}	
}

- (NSColor*)foregroundTextColor {
	NSData *theData = [defaults dataForKey:ForegroundTextColorKey];
	if (theData) return (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
	return nil;
}

- (void)setBackgroundTextColor:(NSColor*)aColor sender:(id)sender {
	
	if (aColor) {
		[defaults setObject:[NSArchiver archivedDataWithRootObject:aColor] forKey:BackgroundTextColorKey];
	
		SEND_CALLBACKS();
	}
}

- (NSColor*)backgroundTextColor {
	//don't need to cache the unarchived color, as it's not used in a random-access pattern
	
	NSData *theData = [defaults dataForKey:BackgroundTextColorKey];
	if (theData) return (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];

	return nil;	
}

- (void)setDarkForegroundTextColor:(NSColor*)color sender:(id)sender {
    if (color) {
        [defaults setObject:[NSArchiver archivedDataWithRootObject:color] forKey:DarkForegroundTextColorKey];
        SEND_CALLBACKS();
    }
}

- (NSColor*)darkForegroundTextColor {
    NSData *data = [defaults dataForKey:DarkForegroundTextColorKey];
    return data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
}

- (void)setDarkBackgroundTextColor:(NSColor*)color sender:(id)sender {
    if (color) {
        [defaults setObject:[NSArchiver archivedDataWithRootObject:color] forKey:DarkBackgroundTextColorKey];
        SEND_CALLBACKS();
    }
}

- (NSColor*)darkBackgroundTextColor {
    NSData *data = [defaults dataForKey:DarkBackgroundTextColorKey];
    return data ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
}

- (BOOL)tableColumnsShowPreview {
	return [defaults boolForKey:TableColumnsHaveBodyPreviewKey];
}

- (void)setTableColumnsShowPreview:(BOOL)showPreview sender:(id)sender {
	[defaults setBool:showPreview forKey:TableColumnsHaveBodyPreviewKey];
	
	SEND_CALLBACKS();
}

- (BOOL)showTitleInTopSection {
	return [defaults boolForKey:ShowTitleInTopSectionKey];
}

- (void)setShowTitleInTopSection:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:ShowTitleInTopSectionKey];
	SEND_CALLBACKS();
}

- (BOOL)showTagsInTopSection {
	return [defaults boolForKey:ShowTagsInTopSectionKey];
}

- (void)setShowTagsInTopSection:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:ShowTagsInTopSectionKey];
	SEND_CALLBACKS();
}

- (BOOL)showBodyControlsInTopSection {
	return [defaults boolForKey:ShowBodyControlsInTopSectionKey];
}

- (void)setShowBodyControlsInTopSection:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:ShowBodyControlsInTopSectionKey];
	SEND_CALLBACKS();
}

- (BOOL)showNotesList {
	return [defaults boolForKey:ShowNotesListKey];
}

- (void)setShowNotesList:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:ShowNotesListKey];
	SEND_CALLBACKS();
}

- (float)tableFontSize {
	return [defaults floatForKey:TableFontSizeKey];
}

- (void)setTableFontSize:(float)fontSize sender:(id)sender {
	[defaults setFloat:fontSize forKey:TableFontSizeKey];
	
	SEND_CALLBACKS();
}

- (void)removeTableColumn:(NSString*)columnKey sender:(id)sender {
	[tableColumns removeObject:columnKey];
	tableColsBitmap = 0U;
	
	[defaults setObject:tableColumns forKey:NoteAttributesVisibleKey];
	
	SEND_CALLBACKS();
}
- (void)addTableColumn:(NSString*)columnKey sender:(id)sender {
	if (![tableColumns containsObject:columnKey]) {
		[tableColumns addObject:columnKey];
		tableColsBitmap = 0U;
		
		[defaults setObject:tableColumns forKey:NoteAttributesVisibleKey];
		
		SEND_CALLBACKS();
	}
}

- (NSArray*)visibleTableColumns {
	if (!tableColumns) {
		tableColumns = [[NSMutableArray arrayWithArray:[defaults arrayForKey:NoteAttributesVisibleKey]] retain];
		tableColsBitmap = 0U;
	}
	
	if (![tableColumns count])
		[self addTableColumn:NoteTitleColumnString sender:self];
		
	return tableColumns;
}


- (unsigned int)tableColumnsBitmap {
	if (tableColsBitmap == 0U) {
		if ([tableColumns containsObject:NoteTitleColumnString])
			tableColsBitmap = (tableColsBitmap | (1 << NoteTitleColumn));
		if ([tableColumns containsObject:NoteLabelsColumnString])
			tableColsBitmap = (tableColsBitmap | (1 << NoteLabelsColumn));
		if ([tableColumns containsObject:NoteDateModifiedColumnString])
			tableColsBitmap = (tableColsBitmap | (1 << NoteDateModifiedColumn));
		if ([tableColumns containsObject:NoteDateCreatedColumnString])
			tableColsBitmap = (tableColsBitmap | (1 << NoteDateCreatedColumn));		
	}
	return tableColsBitmap;
}

- (void)setSortedTableColumnKey:(NSString*)sortedKey reversed:(BOOL)reversed sender:(id)sender {
	[defaults setBool:reversed forKey:TableIsReverseSortedKey];
    [defaults setObject:sortedKey forKey:TableSortColumnKey];
    
    SEND_CALLBACKS();
}

- (NSString*)sortedTableColumnKey {
    return [defaults objectForKey:TableSortColumnKey];
}

- (BOOL)tableIsReverseSorted {
    return [defaults boolForKey:TableIsReverseSortedKey];
}

- (void)setHorizontalLayout:(BOOL)value sender:(id)sender {
	if ([self horizontalLayout] != value) {
		[defaults setBool:value forKey:HorizontalLayoutKey];
		
		SEND_CALLBACKS();
	}
}
- (BOOL)horizontalLayout {
	return NO; // Legacy orientation preferences cannot change the stacked browser layout.
}

- (NSString*)lastSelectedPreferencesPane {
	return [defaults stringForKey:LastSelectedPreferencesPaneKey];
}
- (void)setLastSelectedPreferencesPane:(NSString*)pane sender:(id)sender {
	[defaults setObject:pane forKey:LastSelectedPreferencesPaneKey];
	
	SEND_CALLBACKS();
}

- (void)setLastSearchString:(NSString*)string selectedNote:(id<LogNote>)aNote scrollOffsetForTableView:(NotesTableView*)tv sender:(id)sender {
	
	[defaults setObject:string ?: @"" forKey:LastSearchStringKey];
    NSString *mode = [sender respondsToSelector:@selector(searchMode)] ? [sender searchMode] : @"exact";
    [defaults setObject:[mode isEqualToString:@"fuzzy"] ? @"fuzzy" : @"exact" forKey:LastSearchModeKey];
	
	CFUUIDBytes *bytes = [aNote uniqueNoteIDBytes];
	NSString *uuidString = nil;
	if (bytes) uuidString = [NSString uuidStringWithBytes:*bytes];

	if (uuidString) [defaults setObject:uuidString forKey:LastSelectedNoteUUIDBytesKey];
    else [defaults removeObjectForKey:LastSelectedNoteUUIDBytesKey];

    NSString *rowKey = aNote && [sender respondsToSelector:@selector(selectedSearchResultRowKey)] ?
        [sender selectedSearchResultRowKey] : nil;
    if ([rowKey isKindOfClass:[NSString class]] && [rowKey length])
        [defaults setObject:rowKey forKey:LastSearchResultRowKey];
    else [defaults removeObjectForKey:LastSearchResultRowKey];
	
    NSInteger selectedRow = [tv selectedRow];
    NSUInteger row = !aNote ? NSNotFound : selectedRow >= 0 ? (NSUInteger)selectedRow :
        [(FastListDataSource*)[tv dataSource] indexOfObjectIdenticalTo:aNote];
	double offset = row != NSNotFound ? [tv distanceFromRow:row forVisibleArea:[tv visibleRect]] : 0.0;
	[defaults setDouble:offset forKey:LastScrollOffsetKey];
	
	SEND_CALLBACKS();
}

- (NSString*)lastSearchString {
	id value = [defaults objectForKey:LastSearchStringKey];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSString*)lastSearchMode {
    id value = [defaults objectForKey:LastSearchModeKey];
    return [value isKindOfClass:[NSString class]] && [value isEqualToString:@"fuzzy"] ? @"fuzzy" : @"exact";
}

- (NSString*)lastSearchResultRowKey {
    id value = [defaults objectForKey:LastSearchResultRowKey];
    return [value isKindOfClass:[NSString class]] && [value length] ? value : nil;
}

- (CFUUIDBytes)UUIDBytesOfLastSelectedNote {
	CFUUIDBytes bytes = {0};
	
	NSString *uuidString = [defaults objectForKey:LastSelectedNoteUUIDBytesKey];
	if ([uuidString isKindOfClass:[NSString class]]) bytes = [uuidString uuidBytes];

	return bytes;
}

- (double)scrollOffsetOfLastSelectedNote {
	return [defaults doubleForKey:LastScrollOffsetKey];
}

- (void)saveCurrentBookmarksFromSender:(id)sender {
	//run this during quit and when saved searches change?
	NSArray *bookmarks = [bookmarksController dictionaryReps];
	if (bookmarks) {
		[defaults setObject:bookmarks forKey:BookmarksKey];
		[defaults setBool:[bookmarksController isVisible] forKey:@"BookmarksVisible"];
	}
		
	SEND_CALLBACKS();
}

- (BookmarksController*)bookmarksController {
	if (!bookmarksController) {
		bookmarksController = [[BookmarksController alloc] initWithBookmarks:[defaults arrayForKey:BookmarksKey]];
	}
	return bookmarksController;
}

- (void)setAliasDataForDefaultDirectory:(NSData*)alias sender:(id)sender {
    [defaults setObject:alias forKey:DirectoryAliasKey];
	
    SEND_CALLBACKS();
}

- (NSData*)aliasDataForDefaultDirectory {
    return [defaults dataForKey:DirectoryAliasKey];
}

- (NSString*)displayNameForDefaultDirectoryWithFSRef:(FSRef*)fsRef {

    if (!fsRef)
	return nil;
    
    if (IsZeros(fsRef, sizeof(FSRef))) {
	if (![[self aliasDataForDefaultDirectory] fsRefAsAlias:fsRef])
	    return nil;
    }
    CFStringRef displayName = NULL;
    if (LSCopyDisplayNameForRef(fsRef, &displayName) == noErr) {
	return [(NSString*)displayName autorelease];
    }
    return nil;
}

- (NSString*)humanViewablePathForDefaultDirectory {
    //resolve alias to fsref
    FSRef targetRef;
    if ([[self aliasDataForDefaultDirectory] fsRefAsAlias:&targetRef]) {	    
	//follow the parent fsrefs up the tree, calling LSCopyDisplayNameForRef, hoping that the root is a drive name
	
	NSMutableArray *directoryNames = [NSMutableArray arrayWithCapacity:4];
	FSRef parentRef, *currentRef = &targetRef;
	
	OSStatus err = noErr;
	
	do {
	    
	    if ((err = FSGetCatalogInfo(currentRef, kFSCatInfoNone, NULL, NULL, NULL, &parentRef)) == noErr) {
		
		CFStringRef displayName = NULL;
		if ((err = LSCopyDisplayNameForRef(currentRef, &displayName)) == noErr) {
		    
		    if (displayName) {
			[directoryNames insertObject:(id)displayName atIndex:0];
			CFRelease(displayName);
		    }
		}
		
		currentRef = &parentRef;
	    }
	} while (err == noErr);
	
	//build new string delimited by triangles like pages in its recent items menu
	return [directoryNames componentsJoinedByString:@" : "];
	
    }
    
    return nil;
}

- (void)setBlorImportAttempted:(BOOL)value {
	[defaults setBool:value forKey:TriedToImportBlorKey];
}

- (BOOL)triedToImportBlor {
	return [defaults boolForKey:TriedToImportBlorKey];
}
- (void)synchronize {
    [defaults synchronize];
}



//elasticthreads' work

- (void)setManagesTextWidthInWindow:(BOOL)manageIt sender:(id)sender{
    [defaults setBool:manageIt forKey:KeepsMaxTextWidth];
	SEND_CALLBACKS();
}

- (BOOL)managesTextWidthInWindow{
	return [defaults boolForKey:KeepsMaxTextWidth];
}

- (CGFloat)maxNoteBodyWidth{	
    
	return [[defaults objectForKey:NoteBodyMaxWidth]floatValue];
}

- (void)setMaxNoteBodyWidth:(CGFloat)maxWidth sender:(id)sender{
	[defaults setObject:[NSNumber numberWithFloat:maxWidth] forKey:NoteBodyMaxWidth];
//	[defaults synchronize];
	SEND_CALLBACKS();
}



@end
