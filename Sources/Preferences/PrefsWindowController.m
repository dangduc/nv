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
#import "PrefsWindowController.h"
#import "PTKeyComboPanel.h"
#import "PTKeyCombo.h"
#import "NotationPrefsViewController.h"
#import "NVBackupPreferencesViewController.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NSBezierPath_NV.h"
#import "NotationPrefs.h"
#import "GlobalPrefs.h"
#import "BufferUtils.h"

#define SYSTEM_LIST_FONT_SIZE 12.0f

@interface PrefsWindowController ()
- (void)configureUserSchemeControls;
- (void)refreshUserSchemeControls;
@end

static NSTextField *NVLabelBesideColorWell(NSColorWell *well) {
    for (NSView *view in [[well superview] subviews]) {
        if ([view isKindOfClass:[NSTextField class]] &&
            NSMaxX([view frame]) <= NSMinX([well frame]) &&
            fabs(NSMidY([view frame]) - NSMidY([well frame])) < 8.0) return (NSTextField *)view;
    }
    return nil;
}

static NSTextField *NVSchemeLabel(NSString *title, NSRect frame) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [label setTextColor:[NSColor labelColor]];
    [label setStringValue:title];
    return label;
}

static void NVAddUserSchemeGroup(NSView *pane, NSString *title, NSRect frame, NSArray *labels, NSArray *wells) {
    NSBox *group = [[[NSBox alloc] initWithFrame:frame] autorelease];
    [group setTitle:title];
    [group setTitleFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
    [group setContentViewMargins:NSMakeSize(12.0, 8.0)];
    [pane addSubview:group];
    NSView *content = [group contentView];
    CGFloat wellX = NSWidth([content bounds]) - 60.0;
    for (NSUInteger index = 0; index < [wells count]; index++) {
        NSColorWell *well = [wells objectAtIndex:index];
        NSTextField *label = [labels objectAtIndex:index];
        CGFloat rowY = NSHeight([content bounds]) - 26.0 - 30.0 * index;
        // The arrays retain the nib controls while they move into the group.
        [content addSubview:label];
        [label setAutoresizingMask:NSViewNotSizable];
        [label setAlignment:NSRightTextAlignment];
        [label setFrame:NSMakeRect(0.0, rowY + 3.0, wellX - 8.0, 20.0)];
        [content addSubview:well];
        [well setAutoresizingMask:NSViewNotSizable];
        [well setFrame:NSMakeRect(wellX, rowY, 52.0, 24.0)];
    }
}

@implementation PrefsWindowController

- (id)init {
    if (self=[super init]) {
		prefsController = [GlobalPrefs defaultPrefs];
		fontPanelWasOpen = NO;
      // remove opacity slider from color pickers -bt
    [[NSColorPanel sharedColorPanel] setShowsAlpha:NO];
		[prefsController registerWithTarget:self forChangesInSettings:
		 @selector(resolveNoteBodyFontFromNotationPrefsFromSender:), 
		 @selector(setConfirmNoteDeletion:sender:),
         @selector(setForegroundTextColor:sender:), @selector(setBackgroundTextColor:sender:),
         @selector(setSearchTermHighlightColor:sender:),
         @selector(setDarkForegroundTextColor:sender:), @selector(setDarkBackgroundTextColor:sender:),
         @selector(setDarkSearchTermHighlightColor:sender:),
         @selector(setShouldHighlightSearchTerms:sender:), nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [prefsController unregisterTarget:self];
    [backupPreferencesViewController release];
    [centerStyle release];
    [items release];
    [super dealloc];
}

- (void)showWindow:(id)sender {
	if (!window) {
		if (![NSBundle loadNibNamed:@"Preferences" owner:self])  {
			NSLog(@"Failed to load Preferences.nib");
			return;
		}
	}
    [self refreshUserSchemeControls];
    [backupPreferencesViewController refreshControls];
	if (![window isVisible])
		[window center];
	
	[window makeKeyAndOrderFront:self];
    if (!NSApp.isActive) {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (BOOL)windowShouldClose:(id)sender {
    NSError *error = nil;
    if (backupPreferencesViewController && ![backupPreferencesViewController prepareForWindowCloseWithError:&error]) {
        if ([[backupPreferencesViewController view] window] != window) [self switchViews:[items objectForKey:@"Backups"]];
        [toolbar setSelectedItemIdentifier:@"Backups"];
        if (error) [NSApp presentError:error];
        [backupPreferencesViewController focusFieldForError:error];
        return NO;
    }
    return YES;
}

- (void)windowWillClose:(NSNotification *)aNotification {
	[prefsController performSelector:@selector(synchronize) withObject:nil afterDelay:0.0];
	
	[[NSFontPanel sharedFontPanel] close];
}
- (void)windowDidResignMain:(NSNotification *)aNotification {
	//hide the font panel--don't want to confuse people into thinking it will affect some other part of the program
	fontPanelWasOpen = [[NSFontPanel sharedFontPanel] isVisible];
	[[NSFontPanel sharedFontPanel] orderOut:nil];
}
- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	if (fontPanelWasOpen) {
		[self changeBodyFont:self];
	}
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	NSLog(@"I need an update: %@", [menu description]);
}

- (IBAction)setAppShortcut:(id)sender {
	[[PTKeyComboPanel sharedPanel] showSheetForHotkey:[prefsController appActivationHotKey] forWindow:window modalDelegate:self];
}

- (void)keyComboPanelEnded:(PTKeyComboPanel*)panel {
	PTKeyCombo *oldKeyCombo = [[prefsController appActivationKeyCombo] retain];
	[prefsController setAppActivationKeyCombo:[panel keyCombo] sender:self];
	
	[appShortcutField setStringValue:[[prefsController appActivationKeyCombo] description]];
		
	if (![prefsController registerAppActivationKeystrokeWithTarget:[NSApp delegate] selector:@selector(toggleNVActivation:)]) {
		[prefsController setAppActivationKeyCombo:oldKeyCombo sender:self];
		NSLog(@"reverting to old (hopefully working key combo");
	}
	
	[oldKeyCombo release];
}

- (IBAction)changeBodyFont:(id)sender {
	[[NSFontManager sharedFontManager] setSelectedFont:[prefsController noteBodyFont] isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (void)changeFont:(id)sender {
	NSFontManager *fontMan = [NSFontManager sharedFontManager];
	NSFont *panelFont = [fontMan convertFont:[fontMan selectedFont]];
	
	if (/*![fontMan fontNamed:[panelFont fontName] hasTraits:NSUnboldFontMask | NSUnitalicFontMask]*/
	([fontMan traitsOfFont:panelFont] & NSItalicFontMask) == NSItalicFontMask ||
	([fontMan traitsOfFont:panelFont] & NSBoldFontMask) == NSBoldFontMask) {
		//revert the font--using a bold or italic variant as the default could cause some notes to lose styles
	//	NSLog(@"traits: %u", [fontMan traitsOfFont:panelFont]); 
		
		[self performSelector:@selector(changeBodyFont:) withObject:sender afterDelay:0.0];
		NSBeep();
	} else {
		[prefsController setNoteBodyFont:panelFont sender:self];
	
		[self previewNoteBodyFont];
	}
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel {
	
	return NSFontPanelSizeModeMask | NSFontPanelCollectionModeMask;
}

- (void)previewNoteBodyFont {

	if (!centerStyle) {
		centerStyle = [[NSMutableParagraphStyle alloc] init];
		[centerStyle setAlignment:NSCenterTextAlignment];
	}

	NSFont *font = [prefsController noteBodyFont];
    CGFloat lh=[font pointSize];
    if (lh<27.0) {
        lh=floorf(27.0-((27.0-lh)/2));
    }
    [centerStyle setMaximumLineHeight:lh];
	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font ? font : [NSFont systemFontOfSize:12.0],
		NSFontAttributeName, [NSColor labelColor], NSForegroundColorAttributeName, centerStyle, NSParagraphStyleAttributeName, nil];

	NSString *fontNameAndSize = font ? [NSString stringWithFormat:@"%@ %g", [font fontName], [font pointSize]] : @"Unknown";
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:fontNameAndSize attributes:attributes];
	
	[[bodyTextFontField cell] setAttributedStringValue:attributedString];
    [bodyTextFontField updateCell:[bodyTextFontField cell]];
	
	[attributedString autorelease];
	
}

- (IBAction)changedUseETScrollbarsOnLion:(id)sender{
    [prefsController setUseETScrollbarsOnLion:[useETScrollbarsOnLionButton state] sender:self];
}

- (IBAction)changedBackgroundTextColorWell:(id)sender {
	[prefsController setBackgroundTextColor:[backgroundColorWell color] sender:self];
}
- (IBAction)changedForegroundTextColorWell:(id)sender {
	[prefsController setForegroundTextColor:[foregroundColorWell color] sender:self];
}
- (IBAction)changedSearchHighlightColorWell:(id)sender {
	[prefsController setSearchTermHighlightColor:[searchHighlightColorWell color] sender:self];
}
- (IBAction)changedDarkBackgroundTextColorWell:(id)sender {
    [prefsController setDarkBackgroundTextColor:[darkBackgroundColorWell color] sender:self];
}
- (IBAction)changedDarkForegroundTextColorWell:(id)sender {
    [prefsController setDarkForegroundTextColor:[darkForegroundColorWell color] sender:self];
}
- (IBAction)changedDarkSearchHighlightColorWell:(id)sender {
    [prefsController setDarkSearchTermHighlightColor:[darkSearchHighlightColorWell color] sender:self];
}
- (IBAction)changedHighlightSearchTerms:(id)sender {
	[prefsController setShouldHighlightSearchTerms:[highlightSearchTermsButton state] sender:self];
}
- (IBAction)changedMakeURLsClickable:(id)sender {
	[prefsController setMakeURLsClickable:[makeURLsClickable state] sender:self];
}

- (IBAction)changedNoteDeletion:(id)sender {
	[prefsController setConfirmNoteDeletion:[confirmDeletionButton state] sender:self];
}

- (IBAction)changedNotesFolderLocation:(id)sender {
    NSLog(@"Changed notes folder menu");
}

- (IBAction)changedQuitBehavior:(id)sender {
    [prefsController setQuitWhenClosingWindow:[quitWhenClosingButton state] sender:self];
}

- (IBAction)changedExternalEditorsMenu:(id)sender {
  //not currently called as an action in practice
  [self _selectDefaultExternalEditor];
}

- (void)_selectDefaultExternalEditor {
  ExternalEditor *ed = [[ExternalEditorListController sharedInstance] defaultExternalEditor];
  NSInteger idx = ed ? [externalEditorMenuButton indexOfItemWithRepresentedObject:ed] : 0;
  if (idx > -1) {
    [externalEditorMenuButton selectItemAtIndex:idx];
  }
}

- (IBAction)changedTableText:(id)sender {
	if (sender == tableTextMenuButton) {
		if ([tableTextSizeField selectedTag] != 3) [tableTextSizeField setFloatValue:[prefsController tableFontSize]];
		[self performSelector:@selector(changedTableText:) withObject:nil afterDelay:0.0];
	} else {
		[window makeFirstResponder:window];
		float newFontSize = 0.0;
		switch ([tableTextMenuButton selectedTag]) {
			case 1:
				newFontSize = [NSFont smallSystemFontSize];
				break;
			case 2:
				newFontSize = /*[NSFont systemFontSize]*/ SYSTEM_LIST_FONT_SIZE;
				break;
			case 3:
				newFontSize = [tableTextSizeField floatValue];
		}
		[tableTextSizeField setHidden:([tableTextMenuButton selectedTag] != 3)];
		if (![tableTextSizeField isHidden])
			[tableTextSizeField selectText:sender];
		
		[prefsController setTableFontSize:newFontSize sender:self];
	}	
}

- (IBAction)changedTitleCompletion:(id)sender {
    [prefsController setAutoCompleteSearches:[completeNoteTitlesButton state] sender:self];
}

- (void)settingChangedForSelectorString:(NSString*)selectorString {
    if ([selectorString isEqualToString:SEL_STR(resolveNoteBodyFontFromNotationPrefsFromSender:)]) {
		[self previewNoteBodyFont];
	} else if ([selectorString isEqualToString:SEL_STR(setConfirmNoteDeletion:sender:)]) {
		[confirmDeletionButton setState:[prefsController confirmNoteDeletion]];
	}
    [self refreshUserSchemeControls];
}

- (NSMenu*)directorySelectionMenu {
    NSMenu *theMenu = [[[NSMenu alloc] initWithTitle:@"Note Directory Menu"] autorelease];
    
    FSRef targetRef = {{0}};
    NSString *name = [prefsController displayNameForDefaultDirectoryWithFSRef:&targetRef];
    if (!name)
		name = NSLocalizedString(@"<Directory unknown>", nil);
	
	NSImage *iconImage = nil;
	if (!IsZeros(&targetRef, sizeof(FSRef)) || [[prefsController aliasDataForDefaultDirectory] fsRefAsAlias:&targetRef])
	    iconImage = [NSImage smallIconForFSRef:&targetRef];
	
    NSMenuItem *theMenuItem = [[[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""] autorelease];
    
    if (iconImage)
		[theMenuItem setImage:iconImage];
    
    [theMenu addItem:theMenuItem];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    theMenuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Other...", @"title of menu item for selecting a different notes folder")
											  action:@selector(changeDefaultDirectory) keyEquivalent:@""] autorelease];
    [theMenuItem setTarget:self];
    [theMenu addItem:theMenuItem];
    
    return theMenu;
}

- (void)changeDefaultDirectory {
	FSRef notesDirectoryRef;
	NSData *aliasData = nil;

	if ([self getNewNotesRefFromOpenPanel:&notesDirectoryRef returnedPath:NULL]) {
		
		//make sure we're not choosing the same folder as what we started with, because:
		//-[NotationController initWithAliasData:] might attempt to initialize journaling, which will already be in use
		FSRef currentNotesDirectoryRef;
		[[prefsController aliasDataForDefaultDirectory] fsRefAsAlias:&currentNotesDirectoryRef];
		if (FSCompareFSRefs(&notesDirectoryRef, &currentNotesDirectoryRef) != noErr) {
			
			if ((aliasData = [NSData aliasDataForFSRef:&notesDirectoryRef])) {
				[prefsController setAliasDataForDefaultDirectory:aliasData sender:self];
			}
		} else {
			NSLog(@"This folder is already chosen!");
		}
		
	}

	[folderLocationsMenuButton setMenu:[self directorySelectionMenu]];

	if ([folderLocationsMenuButton numberOfItems] > 0)
		[folderLocationsMenuButton selectItemAtIndex:0];
}

- (BOOL)getNewNotesRefFromOpenPanel:(FSRef*)notesDirectoryRef returnedPath:(NSString**)path {
    NSString *startingDirectory = nil;
	
    if (!notesDirectoryRef) {
		NSLog(@"notesDirectoryRef is NULL!");
		return NO;
    }
    
    FSRef currentNotesDirectoryRef;
    //resolve alias to fsref; get path from fsref
    if ([[prefsController aliasDataForDefaultDirectory] fsRefAsAlias:&currentNotesDirectoryRef]) {
		NSString *resolvedPath = [[NSFileManager defaultManager] pathWithFSRef:&currentNotesDirectoryRef];
		if (resolvedPath) startingDirectory = resolvedPath;
    }
    
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanCreateDirectories:YES];
    [openPanel setCanChooseFiles:NO];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setResolvesAliases:YES];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setTreatsFilePackagesAsDirectories:NO];
    [openPanel setTitle:NSLocalizedString(@"Select a folder",@"title of open panel for selecting a notes folder")];
    [openPanel setPrompt:NSLocalizedString(@"Select", @"title of open panel button to select a folder")];
    [openPanel setMessage:NSLocalizedString(@"Select the folder that Notational Velocity should use for reading and storing notes.",nil)];
    [openPanel setDirectoryURL:[NSURL fileURLWithPath:startingDirectory]];
    [openPanel setAllowedFileTypes:nil];
    if ([openPanel runModal]==NSFileHandlingPanelOKButton) {
        
		CFStringRef filename = (CFStringRef)[[openPanel URL]path];
		if (!filename)
			return NO;
		
		if (path)
			*path = [[[[openPanel URL]path] copy] autorelease];
		
		//yes, I know that navigation services uses uses FSRefs, but NSSavePanel saves us much more work
		CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, filename, kCFURLPOSIXPathStyle, true);
		[(id)url autorelease];
		if (!url || !CFURLGetFSRef(url, notesDirectoryRef))
			return NO;
		
		return YES;
    }
    
    return NO;
}

- (NotationPrefsViewController*)notationPrefsViewController {
	if (!notationPrefsViewController) {
		notationPrefsViewController = [[NotationPrefsViewController alloc] init];
	}
	return notationPrefsViewController;
}

- (NSView*)databaseView {
    if (![notationPrefsView subviews] || ![[notationPrefsView subviews] count])
		[notationPrefsView addSubview:[[self notationPrefsViewController] view]];
	
    return databaseView;
}

- (void)addToolbarItemWithName:(NSString*)name {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:name];
	
	NSString *localizedTitle = [[NSBundle mainBundle] localizedStringForKey:name value:@"" table:nil];
    [item setPaletteLabel:localizedTitle];
    [item setLabel:localizedTitle];
    //[item setToolTip:@"General settings: appearance and behavior"];
    [item setImage:[[[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:name ofType:@"tiff"]] autorelease]];
    if ([name isEqualToString:@"Backups"]) [item setImage:[NSImage imageNamed:NSImageNameFolderSmart]];
    [item setTarget:self];
    [item setAction:@selector(switchViews:)];
    [items setObject:item forKey:name];
    [item release];
}

- (void)configureUserSchemeControls {
    if (darkForegroundColorWell) return;

    // Reuse the localized nib controls. All preference panes use the same two groups.
    NSArray *originalViews = [[fontsColorsView subviews] copy];
    NSTextField *foregroundLabel = NVLabelBesideColorWell(foregroundColorWell);
    NSTextField *backgroundLabel = NVLabelBesideColorWell(backgroundColorWell);
    NSString *foregroundTitle = foregroundLabel ? [foregroundLabel stringValue] : NSLocalizedString(@"Foreground Text:", nil);
    NSString *backgroundTitle = backgroundLabel ? [backgroundLabel stringValue] : NSLocalizedString(@"Background:", nil);
    NSString *searchTitle = [[[highlightSearchTermsButton title] copy] autorelease];
    [highlightSearchTermsButton setTitle:NSLocalizedString(@"Highlight Search Terms", nil)];
    if (!foregroundLabel) foregroundLabel = NVSchemeLabel(foregroundTitle, NSZeroRect);
    if (!backgroundLabel) backgroundLabel = NVSchemeLabel(backgroundTitle, NSZeroRect);

    CGFloat lowerControlsTop = NSMaxY([showGridButton frame]);
    NSTextField *appearanceLabel = nil;
    for (NSView *view in originalViews) {
        if ([view isKindOfClass:[NSTextField class]] &&
            NSMinY([view frame]) >= lowerControlsTop &&
            NSMaxY([view frame]) <= NSMinY([backgroundColorWell frame])) {
            appearanceLabel = (NSTextField *)view;
            break;
        }
    }
    if (!appearanceLabel) {
        appearanceLabel = NVSchemeLabel(@"", NSZeroRect);
        [fontsColorsView addSubview:appearanceLabel];
    }

    CGFloat groupHeight = 132.0;
    CGFloat darkGroupY = lowerControlsTop + 40.0;
    CGFloat lightGroupY = darkGroupY + groupHeight + 12.0;
    CGFloat checkboxY = lightGroupY + groupHeight + 12.0;
    CGFloat fontOffset = checkboxY + 32.0 - NSMinY([bodyTextFontField frame]);
    CGFloat oldSearchTop = NSMaxY([searchHighlightColorWell frame]);
    NSSize paneSize = [fontsColorsView frame].size;
    paneSize.height += fontOffset;
    [fontsColorsView setAutoresizesSubviews:NO];
    [fontsColorsView setFrameSize:paneSize];
    for (NSView *view in originalViews) {
        if (NSMinY([view frame]) > oldSearchTop) {
            NSRect frame = [view frame];
            frame.origin.y += fontOffset;
            [view setFrame:frame];
        }
    }
    [fontsColorsView setAutoresizesSubviews:YES];
    [highlightSearchTermsButton setFrame:NSMakeRect(24.0, checkboxY, paneSize.width - 48.0, 18.0)];

    [appearanceLabel setStringValue:NSLocalizedString(@"User Scheme follows the macOS appearance.\nEdit its light and dark colors independently.", nil)];
    [appearanceLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [appearanceLabel setTextColor:[NSColor secondaryLabelColor]];
    [[appearanceLabel cell] setWraps:YES];
    [[appearanceLabel cell] setScrollable:NO];
    [appearanceLabel setFrame:NSMakeRect(24.0, lowerControlsTop + 6.0, paneSize.width - 48.0, 28.0)];

    darkSearchHighlightColorWell = [[[NSColorWell alloc] initWithFrame:NSZeroRect] autorelease];
    darkForegroundColorWell = [[[NSColorWell alloc] initWithFrame:NSZeroRect] autorelease];
    darkBackgroundColorWell = [[[NSColorWell alloc] initWithFrame:NSZeroRect] autorelease];
    NSArray *lightWells = [NSArray arrayWithObjects:searchHighlightColorWell, foregroundColorWell, backgroundColorWell, nil];
    NSArray *darkWells = [NSArray arrayWithObjects:darkSearchHighlightColorWell, darkForegroundColorWell, darkBackgroundColorWell, nil];
    NSArray *lightLabels = [NSArray arrayWithObjects:NVSchemeLabel(searchTitle, NSZeroRect), foregroundLabel, backgroundLabel, nil];
    NSArray *darkLabels = [NSArray arrayWithObjects:NVSchemeLabel(searchTitle, NSZeroRect),
                          NVSchemeLabel(foregroundTitle, NSZeroRect), NVSchemeLabel(backgroundTitle, NSZeroRect), nil];
    for (NSColorWell *well in darkWells) [well setTarget:self];
    [darkSearchHighlightColorWell setAction:@selector(changedDarkSearchHighlightColorWell:)];
    [darkForegroundColorWell setAction:@selector(changedDarkForegroundTextColorWell:)];
    [darkBackgroundColorWell setAction:@selector(changedDarkBackgroundTextColorWell:)];

    [searchHighlightColorWell setAccessibilityLabel:NSLocalizedString(@"User Scheme Light Search Highlight", nil)];
    [foregroundColorWell setAccessibilityLabel:NSLocalizedString(@"User Scheme Light Foreground Text", nil)];
    [backgroundColorWell setAccessibilityLabel:NSLocalizedString(@"User Scheme Light Background", nil)];
    [darkSearchHighlightColorWell setAccessibilityLabel:NSLocalizedString(@"User Scheme Dark Search Highlight", nil)];
    [darkForegroundColorWell setAccessibilityLabel:NSLocalizedString(@"User Scheme Dark Foreground Text", nil)];
    [darkBackgroundColorWell setAccessibilityLabel:NSLocalizedString(@"User Scheme Dark Background", nil)];
    NVAddUserSchemeGroup(fontsColorsView, NSLocalizedString(@"User Scheme — Light", nil),
                         NSMakeRect(20.0, lightGroupY, paneSize.width - 40.0, groupHeight), lightLabels, lightWells);
    NVAddUserSchemeGroup(fontsColorsView, NSLocalizedString(@"User Scheme — Dark", nil),
                         NSMakeRect(20.0, darkGroupY, paneSize.width - 40.0, groupHeight), darkLabels, darkWells);
    [originalViews release];
}

- (void)refreshUserSchemeControls {
    [searchHighlightColorWell setColor:[prefsController searchTermHighlightColorRaw:YES]];
    [foregroundColorWell setColor:[prefsController foregroundTextColor]];
    [backgroundColorWell setColor:[prefsController backgroundTextColor]];
    [darkSearchHighlightColorWell setColor:[prefsController darkSearchTermHighlightColor]];
    [darkForegroundColorWell setColor:[prefsController darkForegroundTextColor]];
    [darkBackgroundColorWell setColor:[prefsController darkBackgroundTextColor]];
    [highlightSearchTermsButton setState:[prefsController highlightSearchTerms]];
}

- (void)awakeFromNib {
	
	[window setDelegate:self];
	
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changedTableText:)
												 name:NSControlTextDidEndEditingNotification object:tableTextSizeField];
    
    float fontSize = [prefsController tableFontSize];
    int fontButtonIndex = 3;
    if (fontSize == [NSFont smallSystemFontSize]) fontButtonIndex = 0;
    else if (fontSize == /*[NSFont systemFontSize]*/ SYSTEM_LIST_FONT_SIZE) fontButtonIndex = 1;
    [tableTextMenuButton selectItemAtIndex:fontButtonIndex];
    [tableTextSizeField setFloatValue:fontSize];
    [tableTextSizeField setHidden:(fontButtonIndex != 3)];
    
    [externalEditorMenuButton setMenu:[[ExternalEditorListController sharedInstance] addEditorPrefsMenu]];
    [self _selectDefaultExternalEditor];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changedExternalEditorsMenu:) 
                           name:ExternalEditorsChangedNotification object:nil];
    
    [completeNoteTitlesButton setState:[prefsController autoCompleteSearches]];
    [confirmDeletionButton setState:[prefsController confirmNoteDeletion]];
    [quitWhenClosingButton setState:[prefsController quitWhenClosingWindow]];
	[makeURLsClickable setState:[prefsController URLsAreClickable]];
    [self previewNoteBodyFont];
	[appShortcutField setStringValue:[[prefsController appActivationKeyCombo] description]];
    [self configureUserSchemeControls];
    [self refreshUserSchemeControls];
    [maxWidthSlider setDoubleValue:[[NSUserDefaults standardUserDefaults] doubleForKey:@"NoteBodyMaxWidth"]];
	//for elasticthreads' hide dock icon option, check if OS compatible
	if (IsSnowLeopardOrLater) {
		[togDockButton setEnabled:YES];
		
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDockIcon"]) {
            [togDockButton setTitle:@"Hide Dock Icon"];
//			[togDockLabel setStringValue:@"This will immediately restart NV"];		
		}else {
            [togDockButton setTitle:@"Show Dock Icon"];
//			[togDockLabel setStringValue:@""];
		}

	}else {	
		[togDockButton setEnabled:NO];
		[togDockButton setHidden:YES];
//		[togDockLabel setHidden:YES];
	}
	
    [altRowsButton setState:[prefsController alternatingRows]];
    [showGridButton setState:[prefsController showGrid]];
    items = [[NSMutableDictionary alloc] init];
    
    [self addToolbarItemWithName:@"General"];
    [self addToolbarItemWithName:@"Notes"];	
    [self addToolbarItemWithName:@"Backups"];
    [self addToolbarItemWithName:@"Editing"];
	[self addToolbarItemWithName:@"Fonts & Colors"];
		
    toolbar = [[NSToolbar alloc] initWithIdentifier:@"preferencePanes"];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO]; 
    [window setToolbar:toolbar];
    [toolbar release];  //setToolbar retains the toolbar we pass, so release the one we used.
	
	[window setShowsToolbarButton:NO];
    [useETScrollbarsOnLionButton setState:[prefsController useETScrollbarsOnLion]];
    [useETScrollbarsOnLionButton setHidden:!IsLionOrLater];
    [self switchViews:nil];  //select last selected pane by default
    
}


- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    return [items objectForKey:itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)theToolbar {
    return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)theToolbar {
    return [NSArray arrayWithObjects:@"General", @"Notes", @"Backups", @"Editing", @"Fonts & Colors", nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar {
    //make all of them selectable. This puts that little grey outline thing around an item when you select it.
    return [items allKeys];
}

- (void)switchViews:(NSToolbarItem *)item {
    NSString *sender = nil;
	
    if (item == nil) {
        sender = [prefsController lastSelectedPreferencesPane];
        [toolbar setSelectedItemIdentifier:sender];
    } else {
        sender = [item itemIdentifier];
		[prefsController setLastSelectedPreferencesPane:sender sender:self];
    }
	
    NSView *prefsView = nil;
	
    [window setTitle:[[NSBundle mainBundle] localizedStringForKey:sender value:@"" table:nil]];
	
    if ([sender isEqualToString:@"General"]){
         prefsView = generalView;
    } else if([sender isEqualToString:@"Notes"]) {
        prefsView = [self databaseView];
    } else if([sender isEqualToString:@"Backups"]) {
        if (!backupPreferencesViewController) backupPreferencesViewController = [[NVBackupPreferencesViewController alloc] init];
        prefsView = [backupPreferencesViewController view];
        [backupPreferencesViewController refreshControls];
    } else if([sender isEqualToString:@"Editing"]) {
        prefsView = editingView;
    } else if([sender isEqualToString:@"Fonts & Colors"]) {
        prefsView = fontsColorsView;
	} else {
		NSLog(@"unknown sender: %@", sender);
	}
    
    if (prefsView == databaseView)
		[folderLocationsMenuButton setMenu:[self directorySelectionMenu]];
	
	NSAssert(prefsView != nil, @"switching to a nil prefs view!");
    
	[[NSFontPanel sharedFontPanel] close];
	
	//fix this math to convert between window and view coordinates for resolution independence
	
	float userSpaceScaleFactor = [window userSpaceScaleFactor];
	
    //to stop flicker, we make a temp blank view.
	
	NSRect windowContentFrame = ScaleRectWithFactor([[window contentView] frame], userSpaceScaleFactor);
    NSView *tempView = [[NSView alloc] initWithFrame:[[window contentView] frame]];
    [window setContentView:tempView];
    [tempView release];
    
    NSRect newFrame = [window frame];
	NSRect viewFrameForWindow = ScaleRectWithFactor([prefsView frame], userSpaceScaleFactor);
    newFrame.size.height = viewFrameForWindow.size.height + ([window frame].size.height - windowContentFrame.size.height);
    newFrame.size.width = viewFrameForWindow.size.width;
    newFrame.origin.y += (windowContentFrame.size.height - viewFrameForWindow.size.height);
    	
    [window setShowsResizeIndicator:YES];
    [window setFrame:newFrame display:YES animate:YES];

    [window setContentView:prefsView];
}

NSRect ScaleRectWithFactor(NSRect rect, float factor) {
	NSRect newRect = rect;
	newRect.size.width *= factor;
	newRect.size.height *= factor;
	newRect.origin.x *= factor;
	newRect.origin.y *= factor;
	
	//these may still need to be rounded up
	
	return newRect;
}

//elasticwork

- (IBAction)toggleHideDockIcon:(id)sender{
    NSUserDefaults *stdDefaults=[NSUserDefaults standardUserDefaults];
    BOOL showIt=![stdDefaults boolForKey:@"ShowDockIcon"];
    if (showIt) {
        [stdDefaults setBool:YES forKey:@"ShowDockIcon"];
        [togDockButton setTitle:@"Hide Dock Icon"];        
//        [togDockLabel setStringValue:@"This will immediately restart NV"];	
    }else{
        [stdDefaults setBool:YES forKey:@"StatusBarItem"];
        [stdDefaults setBool:NO forKey:@"ShowDockIcon"];
        [togDockButton setTitle:@"Show Dock Icon"];
    }
    [stdDefaults synchronize];
	[[NSNotificationCenter defaultCenter]postNotificationName:@"AppShouldToggleDockIcon" object:[NSNumber numberWithBool:showIt]];
}

- (IBAction)toggleStatusItem:(id)sender{
//    NSUserDefaults *stdDefaults=[NSUserDefaults standardUserDefaults];
//    BOOL showIt=[stdDefaults boolForKey:@"StatusBarItem"];
//    if (showIt) {
//        [stdDefaults setBool:NO forKey:@"StatusBarItem"];
//        //        [togDockLabel setStringValue:@"This will immediately restart NV"];
//    }else{
//        [stdDefaults setBool:YES forKey:@"StatusBarItem"];
//    }
//    [stdDefaults synchronize];
	[[NSNotificationCenter defaultCenter]postNotificationName:@"AppShouldToggleStatusItem" object:nil];
}


- (IBAction)toggleKeepsTextWidthInWindow:(id)sender{
   
    [prefsController setManagesTextWidthInWindow:[sender state] sender:self];
//		[[NSApp delegate] setMaxNoteBodyWidth];
}

- (IBAction)setMaxWidth:(id)sender{
	CGFloat dbWidth = [maxWidthSlider floatValue];	
	dbWidth = dbWidth - fmod(dbWidth,2.0);
	[prefsController setMaxNoteBodyWidth:dbWidth sender:self];
//	[[NSApp delegate] setMaxNoteBodyWidth];
}

- (IBAction)changedAltRows:(id)sender {
	[prefsController setAlternatingRows:[altRowsButton state] sender:self];
    [[NSApp delegate] refreshNotesList];
}

- (IBAction)changedShowGrid:(id)sender {
	[prefsController setShowGrid:[showGridButton state] sender:self];
    [[NSApp delegate] refreshNotesList];
}

@end
