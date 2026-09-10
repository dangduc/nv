#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
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
//ET NV4

//#import "NSTextFinder.h"
#import "AppController.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "AlienNoteImporter.h"
#import "AppController_Importing.h"
#import "NotationPrefs.h"
#import "PrefsWindowController.h"
#import "NoteAttributeColumn.h"
#import "NotationDirectoryManager.h"
#import "NotationFileManager.h"
#import "NSString_NV.h"
#import "NSString_CustomTruncation.h"
#import "NSFileManager_NV.h"
#import "EncodingsManager.h"
#import "ExporterManager.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "BufferUtils.h"
#import "LinkingEditor.h"
#import "EmptyView.h"
#import "DualField.h"
#import "BookmarksController.h"
#import "MultiplePageView.h"
#import "SecureTextEntryManager.h"
#import "TagEditingManager.h"
#import "NotesTableHeaderCell.h"
#import "ETContentView.h"
#import "PreviewController.h"
#import "ETClipView.h"
//#import "ETScrollView.h"
#import "NSFileManager+DirectoryLocations.h"
#import "nvaDevConfig.h"

#define NSApplicationPresentationAutoHideMenuBar (1 <<  2)
#define NSApplicationPresentationHideMenuBar (1 <<  3)
//#define NSApplicationPresentationAutoHideDock (1 <<  0)
#define NSApplicationPresentationHideDock (1 <<  1)
//#define NSApplicationActivationPolicyAccessory



//#define NSTextViewChangedNotification @"TextViewHasChangedContents"
//#define kDefaultMarkupPreviewMode @"markupPreviewMode"

#define k_FinderTaggingReset 0




@interface AppController ()
- (void)selectSearchField;
@end

@implementation AppController

@synthesize isEditing;

- (void)setWindow:(NSWindow *)aWindow { window = aWindow; [super setWindow:aWindow]; }
- (BOOL)horizontalLayout { return browserHorizontalLayout; }

//an instance of this class is designated in the nib as the delegate of the window, nstextfield and two nstextviews
/*
 + (void)initialize
 {
 NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:MultiMarkdownPreview] forKey:kDefaultMarkupPreviewMode];
 
 [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
 } // initialize*/


- (id)init {
    self = [super initWithWindow:nil];
    if (self) {

        if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_11) {
            [NSWindow setAllowsAutomaticWindowTabbing:NO];
        }
#if k_FinderTaggingReset
        [[NSUserDefaults standardUserDefaults]removeObjectForKey:@"UseFinderTags"];
#endif
        
        hasLaunched=NO;
        prefsController = [GlobalPrefs defaultPrefs];
        applicationOwner = [NVApplicationController sharedController] == nil;
        browserHorizontalLayout = NO;
        browserIdentifier = [[[NSUUID UUID] UUIDString] copy];
        noteSelections = [[NSMutableDictionary alloc] init];
        noteBodyStates = [[NSMutableDictionary alloc] init];
        selectedViewerIdentifier = [@"markdown" copy];
        emptyEditorStorage = [[NSTextStorage alloc] init];

        if (applicationOwner && ![[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDockIcon"]){
            if (IsLionOrLater) {
                ProcessSerialNumber psn = { 0, kCurrentProcess };
                OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToUIElementApplication);
                if( returnCode != 0) {
                    NSLog(@"Could not bring the application to front. Error %d", returnCode);
                }                
            }
            if (![[NSUserDefaults standardUserDefaults] boolForKey:@"StatusBarItem"]) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"StatusBarItem"];
            }
        }else{
            if (!IsLionOrLater) {
                enum {NSApplicationActivationPolicyRegular};
                [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];
            }
        
        }
        
        windowUndoManager = [[NSUndoManager alloc] init];
        

        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        
        NSString *folder = [fileManager applicationSupportDirectory];
        
        if ([fileManager fileExistsAtPath: folder] == NO)
        {
            [fileManager createFolderAtPath:folder];
            
//            [fileManager createDirectoryAtPath: folder attributes: nil];
            
        }
        
        NSNotificationCenter *nc=[NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(sourceSyntaxChanged:) name:NVNoteSyntaxDidChangeNotification object:nil];
        if (applicationOwner) {
        [nc addObserver:self selector:@selector(togDockIcon:) name:@"AppShouldToggleDockIcon" object:nil];
        [nc addObserver:self selector:@selector(toggleStatusItem:) name:@"AppShouldToggleStatusItem" object:nil];
        }
        
        [nc addObserver:self selector:@selector(resetModTimers:) name:@"ModTimersShouldReset" object:nil];
        [nc addObserver:self selector:@selector(releaseTagEditor:) name:@"TagEditorShouldRelease" object:nil];
        // Setup URL Handling
        if (applicationOwner) {
        NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
        [appleEventManager setEventHandler:self andSelector:@selector(handleGetURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
        }
        
        isCreatingANote = isFilteringFromTyping = typedStringIsCached = NO;
        typedString = @"";
        self.isEditing=NO;
    }
    return self;
}

- (void)awakeFromNib {
    
	if (applicationOwner) [NSApp setDelegate:[NVApplicationController controllerWithInitialBrowser:self]];
    [super setWindow:window];
	[window setDelegate:self];
    
    [self setupBrowserContent];

    id docView = [[textScrollView documentView] retain];
    ETClipView *newClipView = [[ETClipView alloc] initWithFrame:[[textScrollView contentView] frame]];
    [newClipView setDrawsBackground:NO];
    //    [newClipView setBackgroundColor:[self backgrndColor]];
    [textScrollView setContentView:(ETClipView *)newClipView];
    [newClipView release];
    [textScrollView setDocumentView:textView];
    [docView release];
    
	[notesScrollView setBorderType:NSNoBorder];
	[textScrollView setBorderType:NSNoBorder];
	prefsController = [GlobalPrefs defaultPrefs];
	[NSColor setIgnoresAlpha:NO];
	
	//For ElasticThreads' fullscreen implementation.
	[self setDualFieldInToolbar];
	[notesTableView setDelegate:self];
	[field setDelegate:self];
	[textView setDelegate:self];
    
	//set up temporary FastListDataSource containing false visible notes
    
	//this will not make a difference
	
    
	//[window makeKeyAndOrderFront:self];
	//[self setEmptyViewState:YES];
    if (!IsYosemiteOrLater) {
        [window useOptimizedDrawing:YES];
    }
   
    
	// Create elasticthreads' NSStatusItem.
	if (applicationOwner && [[NSUserDefaults standardUserDefaults] boolForKey:@"StatusBarItem"]) {
		[self setUpStatusBarItem];
	}
	

	
	outletObjectAwoke(self);
}

//really need make AppController a subclass of NSWindowController and stick this junk in windowDidLoad
- (void)setupViewsAfterAppAwakened {

	if (!awakenedViews) {
		[notesTableView restoreColumns];
		
		[field setNextKeyView:textView];
		[textView setNextKeyView:field];
		[window setAutorecalculatesKeyViewLoop:NO];
		
		[self setEmptyViewState:YES];
		ModFlagger = 0;
        popped = 0;
		userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		if (userScheme==0) {
			[self setBWColorScheme:self];
		}else if (userScheme==1) {
			[self setLCColorScheme:self];
		}else if (userScheme==2) {
			[self setUserColorScheme:self];
		}
		//this is necessary on 10.3; keep just in case
		[splitView display];
        
        
        //        if (![NSApp isActive]) {  probably a mistake to have put this in the begin with
        //            [NSApp activateIgnoringOtherApps:YES];
        //        }
		awakenedViews = YES;
        [self browserAppearanceChanged];
	}
}

//what a hack
void outletObjectAwoke(id sender) {
    if ([sender isKindOfClass:[AppController class]])
        [sender performSelector:@selector(setupViewsAfterAppAwakened) withObject:nil afterDelay:0.0];
}

- (void)runDelayedUIActionsAfterLaunch {
	[[prefsController bookmarksController] setAppController:self];
	[[prefsController bookmarksController] restoreWindowFromSave];
	[[prefsController bookmarksController] updateBookmarksUI];
    [self updateNoteMenus];
    [prefsController registerAppActivationKeystrokeWithTarget:self selector:@selector(toggleNVActivation:)];
    [notationController updateLabelConnectionsAfterDecoding];
    [notationController checkIfNotationIsTrashed];
    [[SecureTextEntryManager sharedInstance] checkForIncompatibleApps];

    // add elasticthreads' menuitems
    if(IsLeopardOrLater){
        [fsMenuItem setEnabled:YES];
        [fsMenuItem setHidden:NO];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
        if (IsLionOrLater) {
            //  [window setCollectionBehavior:NSWindowCollectionBehaviorTransient|NSWindowCollectionBehaviorMoveToActiveSpace];
            //
            [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
            //            [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary];
            //            [NSApp setPresentationOptions:[NSApp currentSystemPresentationOptions]|NSApplicationPresentationFullScreen];


        }else{
#endif
            [fsMenuItem setTarget:self];
            [fsMenuItem setAction:@selector(switchFullScreen:)];
            
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
        }
#endif

        NSMenuItem *theMenuItem = [fsMenuItem copy];
        [statBarMenu insertItem:theMenuItem atIndex:14];
        [theMenuItem release];
    }
    [wordCounter setHidden:[prefsController showWordCount]];

	//
	[NSApp setServicesProvider:self];
    if (!hasLaunched) {
        hasLaunched=YES;
        [self focusControlField:self activate:NO];

    }
    
//    self.isEditing=NO;
    
    
    //    [NSApp activateIgnoringOtherApps:NO];
    //    [window makeKeyAndOrderFront:self];
}

//
//- (void)applicationWillFinishLaunching:(NSNotification *)aNotification{
//  
//}


- (void)applicationDidFinishLaunching:(NSNotification*)aNote {
    [self setupViewsAfterAppAwakened];
	//on tiger dualfield is often not ready to add tracking tracks until this point:
	
    NSDate *before = [NSDate date];
	prefsWindowController = [[PrefsWindowController alloc] init];
	
	OSStatus err = noErr;
	NotationController *newNotation = nil;
	NSData *aliasData = [prefsController aliasDataForDefaultDirectory];
	
	NSString *subMessage = @"";
	
	//if the option key is depressed, go straight to picking a new notes folder location
	if (kCGEventFlagMaskAlternate == (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & NSDeviceIndependentModifierFlagsMask)) {
		goto showOpenPanel;
	}
	
	if (aliasData) {
	    newNotation = [[[NotationController alloc] initWithAliasData:aliasData error:&err] autorelease];
	    subMessage = NSLocalizedString(@"Please choose a different folder in which to store your notes.",nil);
	} else {
	    newNotation = [[[NotationController alloc] initWithDefaultDirectoryReturningError:&err] autorelease];
	    subMessage = NSLocalizedString(@"Please choose a folder in which your notes will be stored.",nil);
	}
	//no need to display an alert if the error wasn't real
	if (err == kPassCanceledErr)
		goto showOpenPanel;
	
	NSString *location = (aliasData ? [[NSFileManager defaultManager] pathCopiedFromAliasData:aliasData] : NSLocalizedString(@"your Application Support directory",nil));
	if (!location) { //fscopyaliasinfo sucks
		FSRef locationRef;
		if ([aliasData fsRefAsAlias:&locationRef] && LSCopyDisplayNameForRef(&locationRef, (CFStringRef*)&location) == noErr) {
			[location autorelease];
		} else {
			location = NSLocalizedString(@"its current location",nil);
		}
	}
	
	while (!newNotation) {
	    location = [location stringByAbbreviatingWithTildeInPath];
	    NSString *reason = [NSString reasonStringFromCarbonFSError:err];
		
	    if (NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.",nil), location, reason],
							subMessage, NSLocalizedString(@"Choose another folder",nil),NSLocalizedString(@"Quit",nil),NULL) == NSAlertDefaultReturn) {
			//show nsopenpanel, defaulting to current default notes dir
			FSRef notesDirectoryRef;
		showOpenPanel:
			if (![prefsWindowController getNewNotesRefFromOpenPanel:&notesDirectoryRef returnedPath:&location]) {
				//they cancelled the open panel, or it was unable to get the path/FSRef of the file
//                [newNotation release];
				goto terminateApp;
			} else if ((newNotation = [[[NotationController alloc] initWithDirectoryRef:&notesDirectoryRef error:&err] autorelease])) {
				//have to make sure alias data is saved from setNotationController
				[newNotation setAliasNeedsUpdating:YES];
				break;
			}
	    } else {
			goto terminateApp;
	    }
	}
	
	[self setNotationController:newNotation];
	
	NSLog(@"load time: %g, ",[[NSDate date] timeIntervalSinceDate:before]);
	//	NSLog(@"version: %s", PRODUCT_NAME);
	
	//import old database(s) here if necessary
	[AlienNoteImporter importBlorOrHelpFilesIfNecessaryIntoNotation:newNotation];
	
//	[newNotation release];
	if (pathsToOpenOnLaunch) {
		[notationController openFiles:[pathsToOpenOnLaunch autorelease]];//autorelease
		pathsToOpenOnLaunch = nil;
	}
	
	if (URLToInterpretOnLaunch) {
		[self interpretNVURL:[NSURL URLWithString:URLToInterpretOnLaunch]];
		URLToInterpretOnLaunch = nil;
	}
	
	//tell us..
	[prefsController registerWithTarget:self forChangesInSettings:
	 @selector(setAliasDataForDefaultDirectory:sender:),  //when someone wants to load a new database
	 @selector(setSortedTableColumnKey:reversed:sender:),  //when sorting prefs changed
	 @selector(setNoteBodyFont:sender:),  //when to tell notationcontroller to restyle its notes
	 @selector(setForegroundTextColor:sender:),  //ditto
	 @selector(setBackgroundTextColor:sender:),  //ditto
	 @selector(setDarkForegroundTextColor:sender:),
	 @selector(setDarkBackgroundTextColor:sender:),
	 @selector(setTableFontSize:sender:),  //when to tell notationcontroller to regenerate the (now potentially too-short) note-body previews
	 @selector(addTableColumn:sender:),  //ditto
	 @selector(removeTableColumn:sender:),  //ditto
	 @selector(setTableColumnsShowPreview:sender:),  //when to tell notationcontroller to generate or disable note-body previews
	 @selector(setConfirmNoteDeletion:sender:),  //whether "delete note" should have an ellipsis
     @selector(setUseFinderTags:),  //whether nvalt should use findertags
	 @selector(setAutoCompleteSearches:sender:),@selector(setUseETScrollbarsOnLion:sender:), nil];   //when to tell notationcontroller to build its title-prefix connections
	
	[self performSelector:@selector(runDelayedUIActionsAfterLaunch) withObject:nil afterDelay:0.0];
    
	
    
	return;
terminateApp:
	[NSApp terminate:self];
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
	
	NSURL *fullURL = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
	
	if (notationController) {
		if (![self interpretNVURL:fullURL])
			NSBeep();
	} else {
		URLToInterpretOnLaunch = [[fullURL path]retain];
	}
}

- (void)setNotationController:(NotationController *)newNotation {
    if (newNotation) [[NVApplicationController sharedController] setLibrary:newNotation];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
    if ((![prefsController quitWhenClosingWindow])&&(hasLaunched)) {
        [self bringFocusToControlField:nil];
        return YES;
    }
    
    return NO;
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
	SEL selector = [menuItem action];
	NSInteger numberSelected = [[[self browserSession] notesAtIndexes:[notesTableView selectedRowIndexes]] count];
    if (selector == @selector(newNote:)) return [self sharedNotationController] != nil;
    if (selector == @selector(toggleTitleInTopSection:)) {
        [menuItem setTitle:[prefsController showTitleInTopSection] ? NSLocalizedString(@"Hide Title in Top Section", nil) : NSLocalizedString(@"Show Title in Top Section", nil)];
        return YES;
    }
    if (selector == @selector(toggleTagsInTopSection:)) {
        [menuItem setTitle:[prefsController showTagsInTopSection] ? NSLocalizedString(@"Hide Tag in Top Section", nil) : NSLocalizedString(@"Show Tag in Top Section", nil)];
        return YES;
    }
    if (selector == @selector(toggleBodyControlsInTopSection:)) {
        [menuItem setTitle:[prefsController showBodyControlsInTopSection] ? NSLocalizedString(@"Hide Source-Preview Toggle and Syntax Type in Top Section", nil) : NSLocalizedString(@"Show Source-Preview Toggle and Syntax Type in Top Section", nil)];
        return YES;
    }
    if (selector == @selector(toggleNotesList:)) {
        [menuItem setTitle:[prefsController showNotesList] ? NSLocalizedString(@"Hide Notes List", nil) : NSLocalizedString(@"Show Notes List", nil)];
        return YES;
    }
    if (selector == @selector(toggleWordCount:)) {
        [menuItem setState:[prefsController showWordCount] ? NSControlStateValueOff : NSControlStateValueOn];
        return YES;
    }
    if (selector == @selector(toggleSourcePreview:)) {
        [menuItem setTitle:viewingNote ? NSLocalizedString(@"Show Source", nil) : NSLocalizedString(@"Show Preview", nil)];
        return currentNote != nil;
    }
    if (selector == @selector(setSystemColorScheme:) || selector == @selector(setBWColorScheme:) ||
        selector == @selector(setLCColorScheme:) || selector == @selector(setUserColorScheme:)) {
        NSInteger scheme = selector == @selector(setSystemColorScheme:) ? 3 :
            (selector == @selector(setBWColorScheme:) ? 0 : (selector == @selector(setLCColorScheme:) ? 1 : 2));
        [menuItem setState:userScheme == scheme ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    }
    
    if (selector == @selector(printNote:) && viewingNote && numberSelected == 1) {
        NSMenuItem *item = [[menuItem copy] autorelease];
        [item setAction:@selector(printPreview:)];
        return [previewController validateMenuItem:item];
    }
    if (selector == @selector(printNote:) || selector == @selector(deleteNote:) ||
               selector == @selector(exportNote:) ||
               selector == @selector(tagNote:)) {
		
		return (numberSelected > 0);
		
	} else if (selector == @selector(renameNote:) ||
			   selector == @selector(copyNoteLink:)) {
		
		return (numberSelected == 1);
		
	} else if (selector == @selector(revealNote:)) {
        
		return (numberSelected == 1) && [notationController currentNoteStorageFormat] != SingleDatabaseFormat;
		
        //	} else if (selector == @selector(openFileInEditor:)) {
        //		NSString *defApp = [prefsController textEditor];
        //		if (![[self getTxtAppList] containsObject:defApp]) {
        //			defApp = @"Default";
        //			[prefsController setTextEditor:@"Default"];
        //		}
        //		if (([defApp isEqualToString:@"Default"])||(![[NSFileManager defaultManager] fileExistsAtPath:[[NSWorkspace sharedWorkspace] fullPathForApplication:defApp]])) {
        //
        //			if (![defApp isEqualToString:@"Default"]) {
        //				[prefsController setTextEditor:@"Default"];
        //			}
        //			CFStringRef cfFormat = (CFStringRef)noteFormat;
        //			defApp = [(NSString *)LSCopyDefaultRoleHandlerForContentType(cfFormat,kLSRolesEditor) autorelease];
        //			defApp = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: defApp];
        //			defApp = [[NSFileManager defaultManager] displayNameAtPath: defApp];
        //		}
        //		if ((!defApp)||([defApp isEqualToString:@"Safari"])) {
        //			defApp = @"TextEdit";
        //		}
        //		[menuItem setTitle:[@"Open Note in " stringByAppendingString:defApp]];
        //		return (numberSelected == 1) && [notationController currentNoteStorageFormat] != SingleDatabaseFormat;
	} else if (selector == @selector(toggleCollapse:)) {
        [menuItem setTitle:[self notesListHeight] > 90 ? NSLocalizedString(@"Compact Notes List", nil) : NSLocalizedString(@"Expand Notes List", nil)];
        return [prefsController showNotesList];
	} else if ((selector == @selector(toggleFullScreen:))||(selector == @selector(switchFullScreen:))) {
        
        if (IsLeopardOrLater) {
            
            if([NSApp presentationOptions]>0){
                [menuItem setTitle:NSLocalizedString(@"Exit Full Screen",@"menu item title for exiting fullscreen")];
            }else{
                
                [menuItem setTitle:NSLocalizedString(@"Enter Full Screen",@"menu item title for entering fullscreen")];
                
            }
            
        }
        
        
	} else if (selector == @selector(fixFileEncoding:)) {
		
		return (currentNote != nil && storageFormatOfNote(currentNote) == PlainTextFormat && ![currentNote contentsWere7Bit]);
    } else if (selector == @selector(editNoteExternally:)) {
        return (numberSelected > 0) && [[menuItem representedObject] canEditAllNotes:[notationController notesAtIndexes:[notesTableView selectedRowIndexes]]];
	}else if (selector == @selector(previewNoteWithMarked:)){
        BOOL gotMarked=[[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marky"] isFileURL] || [[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked2"] isFileURL]
            || [[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked2.beta"] isFileURL]
            || [[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked-setapp"] isFileURL];
        if ([menuItem isHidden]==gotMarked) {
            [menuItem setHidden:!gotMarked];
        }
        return gotMarked&&([[notesTableView selectedRowIndexes]count]>0);
    } else if (selector == @selector(togglePreview:) || selector == @selector(toggleSourceView:)) {
        [menuItem setState:(selector == @selector(togglePreview:) ? viewingNote : !viewingNote) ? NSControlStateValueOn : NSControlStateValueOff];
        return currentNote != nil;
    } else if (selector == @selector(selectPreviewMode:)) {
        [menuItem setState:[[menuItem representedObject] isEqual:selectedViewerIdentifier] ? NSControlStateValueOn : NSControlStateValueOff];
        return currentNote != nil;
    } else if (selector == @selector(selectSourceSyntax:)) {
        [menuItem setState:[[menuItem representedObject] isEqual:[currentNote sourceSyntaxIdentifier]] ? NSControlStateValueOn : NSControlStateValueOff];
        return currentNote != nil;
    } else if (selector == @selector(savePreview:) || selector == @selector(printPreview:)) {
        NSMenuItem *item = [[menuItem copy] autorelease];
        if (selector == @selector(savePreview:)) [item setAction:@selector(saveHTML:)];
        return currentNote != nil && viewingNote && [previewController validateMenuItem:item];
    } else if (selector == @selector(performFindPanelAction:)) {
        return currentNote != nil && (viewingNote ? [previewController validateMenuItem:menuItem] : [textView validateMenuItem:menuItem]);
    }
	return YES;
}

- (void)updateNoteMenus {
    if ([[NVApplicationController sharedController] activeBrowser] != self) return;
	NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
	
	NSInteger menuIndex = [notesMenu indexOfItemWithTarget:[NVApplicationController sharedController] andAction:@selector(deleteNote:)];
	NSMenuItem *deleteItem = nil;
	if (menuIndex > -1 && (deleteItem = [notesMenu itemAtIndex:menuIndex]))	{
		NSString *trailingQualifier = [prefsController confirmNoteDeletion] ? NSLocalizedString(@"...", @"ellipsis character") : @"";
		[deleteItem setTitle:[NSString stringWithFormat:@"%@%@",
							  NSLocalizedString(@"Delete", nil), trailingQualifier]];
	}
	
    [notesMenu setSubmenu:[[ExternalEditorListController sharedInstance] addEditNotesMenu] forItem:[notesMenu itemWithTag:88]];
	NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
	
	menuIndex = [viewMenu indexOfItemWithTarget:[NVApplicationController sharedController] andAction:@selector(toggleNoteBodyPreviews:)];
	NSMenuItem *bodyPreviewItem = nil;
	if (menuIndex > -1 && (bodyPreviewItem = [viewMenu itemAtIndex:menuIndex])) {
		[bodyPreviewItem setTitle: [prefsController tableColumnsShowPreview] ?
		 NSLocalizedString(@"Hide Note Previews in Title", @"menu item in the View menu to turn off note-body previews in the Title column") :
		 NSLocalizedString(@"Show Note Previews in Title", @"menu item in the View menu to turn on note-body previews in the Title column")];
	}

}

- (void)_forceRegeneratePreviewsForTitleColumn {
	[notationController regeneratePreviewsForColumn:[notesTableView noteAttributeColumnForIdentifier:NoteTitleColumnString]
								visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:YES];
    
}

// Kept as an action endpoint for old nibs and stored commands. Browser windows
// always use the stacked layout; restoring an old orientation cannot change it.
- (IBAction)switchViewLayout:(id)sender {
    browserHorizontalLayout = NO;
}

- (void)createFromSelection:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	if (!notationController || ![self addNotesFromPasteboard:pboard]) {
		*error = NSLocalizedString(@"Error: Couldn't create a note from the selection.", @"error message to set during a Service call when adding a note failed");
	}
}



- (IBAction)renameNote:(id)sender {
    if (currentNote) {
        if (![prefsController showTitleInTopSection]) [prefsController setShowTitleInTopSection:YES sender:nil];
        [noteTitleField selectText:sender];
    }
}

//
- (void)deleteAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(NSIndexSet *)contextInfo {
    if ((returnCode == NSAlertFirstButtonReturn)&&(contextInfo!=nil)&&([contextInfo count]>0)) {
//        NSLog(@"gonna delete:%@",contextInfo);
        
//        NSIndexSet *indexes=(NSIndexSet *)contextInfo;
        [notationController removeNotesAtIndexes:contextInfo];
    }
    [contextInfo release];
    [alert release];
}

//
//	id retainedDeleteObj = (id)contextInfo;
//	
//	if (returnCode == NSAlertDefaultReturn) {
//		//delete! nil-msgsnd-checking
//		
//		//ensure that there are no pending edits in the tableview,
//		//lest editing end with the same field editor and a different selected note
//		//resulting in the renaming of notes in adjacent rows
//		[notesTableView abortEditing];
//		
//		if ([retainedDeleteObj isKindOfClass:[NSArray class]]) {
//			[notationController removeNotes:retainedDeleteObj];
//		} else if ([retainedDeleteObj isKindOfClass:[NoteObject class]]) {
//			[notationController removeNote:retainedDeleteObj];
//		}
//		
//		if (IsLeopardOrLater && [[alert suppressionButton] state] == NSOnState) {
//			[prefsController setConfirmNoteDeletion:NO sender:self];
//		}
//	}
//	[retainedDeleteObj release];
//}


- (IBAction)deleteNote:(id)sender {
    NVBrowserSession *session = [self browserSession];
    if (![session searchResultsAreCurrent]) return;
    NSArray *notes = [session notesAtIndexes:[notesTableView selectedRowIndexes]];
    if (![notes count]) return;
    NotationController *targetLibrary = [self sharedNotationController];
    NSMutableArray *uuids = [NSMutableArray arrayWithCapacity:[notes count]];
    for (NoteObject *note in notes)
        [uuids addObject:[NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)]];
    void (^removeTargets)(void) = ^{
        if (targetLibrary != [self sharedNotationController]) return;
        NSMutableArray *targets = [NSMutableArray array];
        for (NSData *uuid in uuids) {
            CFUUIDBytes bytes; [uuid getBytes:&bytes length:sizeof(bytes)];
            NoteObject *note = [targetLibrary noteForUUIDBytes:&bytes];
            if (note) [targets addObject:note];
        }
        if ([targets count]) [targetLibrary removeNotes:targets];
    };
    if (![prefsController confirmNoteDeletion]) { removeTargets(); return; }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[notes count] == 1 ?
        [NSString stringWithFormat:NSLocalizedString(@"Delete the note titled quotemark%@quotemark?", nil), titleOfNote(notes[0])] :
        [NSString stringWithFormat:NSLocalizedString(@"Delete %lu notes?", nil), (unsigned long)[notes count]]];
    [alert setInformativeText:NSLocalizedString(@"Press Command-Z to undo this action later.", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Delete", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) removeTargets();
    }];
}

- (IBAction)copyNoteLink:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	if ([[notationController notesAtIndexes:indexes] count] == 1) {
		[[[[[notationController notesAtIndexes:indexes] lastObject]
		   uniqueNoteLink] absoluteString] copyItemToPasteboard:nil];
	}
}

- (IBAction)exportNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	NSArray *notes = [notationController notesAtIndexes:indexes];
	
	[notationController synchronizeNoteChanges:nil];
	[[ExporterManager sharedManager] exportNotes:notes forWindow:window];
}

- (IBAction)revealNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSString *path = nil;
	
	if ([[notationController notesAtIndexes:indexes] count] != 1 || !(path = [[[notationController notesAtIndexes:indexes] lastObject] noteFilePath])) {
		NSBeep();
		return;
	}
	[[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (IBAction)editNoteExternally:(id)sender {
    ExternalEditor *ed = [sender representedObject];
    if ([ed isKindOfClass:[ExternalEditor class]]) {
        NSIndexSet *indexes = [notesTableView selectedRowIndexes];
        if (kCGEventFlagMaskAlternate == (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & NSDeviceIndependentModifierFlagsMask)) {
            //allow changing the default editor directly from Notes menu
            [[ExternalEditorListController sharedInstance] setDefaultEditor:ed];
        }
        //force-write any queued changes to disk in case notes are being stored as separate files which might be opened directly by the method below
        [notationController synchronizeNoteChanges:nil];
        [[notationController notesAtIndexes:indexes] makeObjectsPerformSelector:@selector(editExternallyUsingEditor:) withObject:ed];
    } else {
        NSBeep();
    }
}

- (IBAction)previewNoteWithMarked:(id)sender {
    if (![[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked2"] isFileURL] && ![[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marky"] isFileURL] && ![[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked-setapp"] isFileURL] && ![[[NSWorkspace sharedWorkspace]URLForApplicationWithBundleIdentifier:@"com.brettterpstra.marked2.beta"] isFileURL])
    {
        NSBeep();
        NSLog(@"Marked not found");
    } else {
        NSIndexSet *indexes = [notesTableView selectedRowIndexes];
        //force-write any queued changes to disk in case notes are being stored as separate files which might be opened directly by the method below
        [notationController synchronizeNoteChanges:nil];
        [[notationController notesAtIndexes:indexes] makeObjectsPerformSelector:@selector(previewUsingMarked)];
    }
}

- (IBAction)printNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
    if (viewingNote && currentNote && [[notationController notesAtIndexes:indexes] count] == 1) { [self printPreview:sender]; return; }
	[MultiplePageView printNotes:[notationController notesAtIndexes:indexes] forWindow:window];
}

- (IBAction)tagNote:(id)sender {
    if (![[self browserSession] searchResultsAreCurrent]) return;
    NSArray *notes = [notationController notesAtIndexes:[notesTableView selectedRowIndexes]];
    if (![notes count]) return;
    [self cancelMultiTagEditing];
    if ([notes count] == 1) {
        if (![prefsController showTagsInTopSection]) [prefsController setShowTagsInTopSection:YES sender:nil];
        [noteTagsField selectText:sender];
        return;
    }
    
	if ([notes count] > 1) {
        [self captureMultiTagNotes:notes];
        
        NSRect linkingFrame=[textScrollView convertRect:[textScrollView frame] toView:nil];
        
        if (IsLionOrLater) {
            linkingFrame=[window convertRectToScreen:linkingFrame];
        }else{
            linkingFrame.origin=[window convertBaseToScreen:linkingFrame.origin];
        }
        NSPoint cPoint=NSMakePoint(NSMidX(linkingFrame), NSMaxY(linkingFrame));
        
        //Multiple Notes selected, use ElasticThreads' multitagging implementation
        tagEditor = [[TagEditingManager alloc] initWithDelegate:self commonTags:[self commonLabelsForNotes:notes] atPoint:cPoint];
        if (![tagEditor isMultitagging]) [self cancelMultiTagEditing];
        
	}
}

- (void)noteImporter:(AlienNoteImporter*)importer importedNotes:(NSArray*)notes {
	
	[notationController addNotes:notes];
}
- (IBAction)importNotes:(id)sender {
	AlienNoteImporter *importer = [[AlienNoteImporter alloc] init];
	[importer importNotesFromDialogAroundWindow:window receptionDelegate:self];
	[importer autorelease];
}

- (void)settingChangedForSelectorString:(NSString*)selectorString {
    if ([selectorString isEqualToString:SEL_STR(setShowTitleInTopSection:sender:)] ||
        [selectorString isEqualToString:SEL_STR(setShowTagsInTopSection:sender:)] ||
        [selectorString isEqualToString:SEL_STR(setShowBodyControlsInTopSection:sender:)]) {
        [self layoutNoteHeader];
        return;
    }
    if ([selectorString isEqualToString:SEL_STR(setShowNotesList:sender:)]) {
        [self updateNotesListVisibility];
        return;
    }
    if ([selectorString isEqualToString:SEL_STR(setShowWordCount:)]) {
        [wordCounter setHidden:[prefsController showWordCount]];
        popped = ![prefsController showWordCount];
        [self updateWordCount:![prefsController showWordCount]];
        [self layoutNoteHeader];
        return;
    }
    if ([selectorString isEqualToString:SEL_STR(setAliasDataForDefaultDirectory:sender:)]) {
		//defaults changed for the database location -- load the new one!
		
		OSStatus err = noErr;
		NotationController *newNotation = nil;
		NSData *newData = [prefsController aliasDataForDefaultDirectory];
		if (newData) {
#if kUseCachesFolderForInterimNoteChanges
            if (notationController&&[notationController flushAllNoteChanges]) {
                [notationController closeJournal];
            }
#endif
			if ((newNotation = [[NotationController alloc] initWithAliasData:newData error:&err])) {
				[self setNotationController:newNotation];
				[newNotation release];
				
			} else {
				
				//set alias data back
				NSData *oldData = [notationController aliasDataForNoteDirectory];
				[prefsController setAliasDataForDefaultDirectory:oldData sender:self];
				
				//display alert with err--could not set notation directory
				NSString *location = [[[NSFileManager defaultManager] pathCopiedFromAliasData:newData] stringByAbbreviatingWithTildeInPath];
				NSString *oldLocation = [[[NSFileManager defaultManager] pathCopiedFromAliasData:oldData] stringByAbbreviatingWithTildeInPath];
				NSString *reason = [NSString reasonStringFromCarbonFSError:err];
				NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.",nil), location, reason],
								[NSString stringWithFormat:NSLocalizedString(@"Reverting to current location of %@.",nil), oldLocation],
								NSLocalizedString(@"OK",nil), NULL, NULL);
			}
		}
    } else if ([selectorString isEqualToString:SEL_STR(setSortedTableColumnKey:reversed:sender:)]) {
		NoteAttributeColumn *oldSortCol = [notationController sortColumn];
		NoteAttributeColumn *newSortCol = [notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]];
		BOOL changedColumns = oldSortCol != newSortCol;
		
		ViewLocationContext ctx;
		if (changedColumns) {
			ctx = [notesTableView viewingLocation];
			ctx.pivotRowWasEdge = NO;
		}
		
		[notationController setSortColumn:newSortCol];
		
		if (changedColumns) [notesTableView setViewingLocation:ctx];
		
	} else if ([selectorString isEqualToString:SEL_STR(setNoteBodyFont:sender:)]) {
		
		[notationController restyleAllNotes];
        [[NVApplicationController sharedController] reloadCachedEditingSessionsFromLibrary];
	} else if ([selectorString isEqualToString:SEL_STR(setForegroundTextColor:sender:)] ||
               [selectorString isEqualToString:SEL_STR(setBackgroundTextColor:sender:)] ||
               [selectorString isEqualToString:SEL_STR(setDarkForegroundTextColor:sender:)] ||
               [selectorString isEqualToString:SEL_STR(setDarkBackgroundTextColor:sender:)]) {
        [self setUserColorScheme:self];
		
	} else if ([selectorString isEqualToString:SEL_STR(setTableFontSize:sender:)] || [selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview:sender:)]) {
		
		ResetFontRelatedTableAttributes();
		[notesTableView updateTitleDereferencorState];
		[[notationController labelsListDataSource] invalidateCachedLabelImages];
		[self _forceRegeneratePreviewsForTitleColumn];
        
		if ([selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview:sender:)]) [self updateNoteMenus];
		
		[notesTableView performSelector:@selector(reloadData) withObject:nil afterDelay:0];
	} else if ([selectorString isEqualToString:SEL_STR(addTableColumn:sender:)] || [selectorString isEqualToString:SEL_STR(removeTableColumn:sender:)]) {
		
		[notesTableView synchronizeColumnVisibility];
		ResetFontRelatedTableAttributes();
		[self _forceRegeneratePreviewsForTitleColumn];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0];
		
	} else if ([selectorString isEqualToString:SEL_STR(setConfirmNoteDeletion:sender:)]) {
		[self updateNoteMenus];
	} else if ([selectorString isEqualToString:SEL_STR(setAutoCompleteSearches:sender:)]) {
		if ([prefsController autoCompleteSearches])
			[notationController updateTitlePrefixConnections];
		
	}else if ([selectorString isEqualToString:SEL_STR(setUseFinderTags:)]) {
        if(IsMavericksOrLater&&(([notationController currentNoteStorageFormat] != SingleDatabaseFormat))){
            [notationController mirrorAllOMToFinderTags];
        }
    }
	
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
    if (tableView == notesTableView) {
		//Sorting belongs to this browser session.
		[notesTableView setStatusForSortedColumn:tableColumn];
    }
}

- (BOOL)tableView:(NSTableView *)tableView shouldShowCellExpansionForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	return ![[tableColumn identifier] isEqualToString:NoteTitleColumnString];
}

- (IBAction)showHelpDocument:(id)sender {
	NSString *path = nil;
	
	switch ([sender tag]) {
		case 1:		//shortcuts
			path = [[NSBundle mainBundle] pathForResource:NSLocalizedString(@"Excruciatingly Useful Shortcuts", nil) ofType:@"nvhelp" inDirectory:nil];
		case 2:		//acknowledgments
			if (!path) path = [[NSBundle mainBundle] pathForResource:@"Acknowledgments" ofType:@"txt" inDirectory:nil];
			[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:path]] withAppBundleIdentifier:@"com.apple.TextEdit"
											options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifiers:NULL];
			break;
		case 3:		//product site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:NSLocalizedString(@"SiteURL", nil)]];
			break;
		case 4:		//development site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/ttscoff/nv/wiki"]];
			break;
        case 5:     //nvALT home
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brettterpstra.com/project/nvalt/"]];
            break;
        case 6:     //ElasticThreads
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://elasticthreads.tumblr.com/nv"]];
            break;
        case 7:     //Brett Terpstra
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brettterpstra.com"]];
            break;
		default:
			NSBeep();
	}
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
	
	if (notationController)
		[notationController openFiles:filenames];
	else
		pathsToOpenOnLaunch = [filenames mutableCopyWithZone:nil];
	
	[NSApp replyToOpenOrPrint:[filenames count] ? NSApplicationDelegateReplySuccess : NSApplicationDelegateReplyFailure];
}

//- (void)applicationWillBecomeActive:(NSNotification *)aNotification {
//	
//	if (IsLeopardOrLater) {
//		SpaceSwitchingContext thisSpaceSwitchCtx;
//        if ([window windowNumber]!=-1) {
//            CurrentContextForWindowNumber([window windowNumber], &thisSpaceSwitchCtx);
//            
//        }
//		//what if the app is switched-to in another way? then the last-stored spaceSwitchCtx will cause us to return to the wrong app
//		//unfortunately this notification occurs only after NV has become the front process, but we can still verify the space number
//		
//		if ((thisSpaceSwitchCtx.userSpace != spaceSwitchCtx.userSpace) ||
//			(thisSpaceSwitchCtx.windowSpace != spaceSwitchCtx.windowSpace)) {
//			//forget the last space-switch info if it's effectively different from how we're switching into the app now
//			bzero(&spaceSwitchCtx, sizeof(SpaceSwitchingContext));
//		}
//	}
//}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
	[notationController checkJournalExistence];
	
    if ([notationController currentNoteStorageFormat] != SingleDatabaseFormat)
		[notationController performSelector:@selector(synchronizeNotesFromDirectory) withObject:nil afterDelay:0.0];
	[notationController updateDateStringsIfNecessary];
}

- (void)applicationWillResignActive:(NSNotification *)aNotification {
	//sync note files when switching apps so user doesn't have to guess when they'll be updated
	[notationController synchronizeNoteChanges:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
	static NSMenu *dockMenu = nil;
	if (!dockMenu) {
		dockMenu = [[NSMenu alloc] initWithTitle:@"NV Dock Menu"];
		[[dockMenu addItemWithTitle:NSLocalizedString(@"Add New Note from Clipboard", @"menu item title in dock menu")
							 action:@selector(paste:) keyEquivalent:@""] setTarget:notesTableView];
	}
	return dockMenu;
}

- (void)cancel:(id)sender {
	//fallback for when other views are hidden/removed during toolbar collapse
	[self cancelOperation:sender];
}

- (void)cancelOperation:(id)sender {
    [self cancelSearchIntents];
	//simulate a search for nothing
	if ([window isKeyWindow]) {
		if (IsLionOrLater&&([textView textFinderIsVisible])) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:self];
            return;
        }
		[field setStringValue:@""];
		typedStringIsCached = NO;
		
		[notesTableView deselectAll:sender];//thiss
		[notationController filterNotesFromString:@""];
		//was here
        [self setDualFieldIsVisible:YES];
        //		[self _expandToolbar];
		
		[field selectText:sender];
	}
}



- (BOOL)control:(NSControl *)control textView:(NSTextView *)aTextView doCommandBySelector:(SEL)command {
    if (control == noteTitleField || control == noteTagsField) {
        if (command == @selector(cancelOperation:)) {
            [self cancelNoteMetadataEditing];
            [self focusNoteBody];
            return YES;
        }
        if (command == @selector(insertNewline:)) {
            [self applyNoteMetadata:control];
            return YES;
        }
        return NO;
    }
	if (control == (NSControl*)field) {
        if (command == @selector(insertNewline:)) { [self fieldAction:control]; return YES; }
        if (![[self browserSession] searchResultsAreCurrent] &&
            (command == @selector(moveDown:) || command == @selector(moveUp:) ||
             command == @selector(moveDownAndModifySelection:) || command == @selector(moveUpAndModifySelection:) ||
             command == @selector(moveToBeginningOfDocument:) || command == @selector(moveToEndOfDocument:) ||
             command == @selector(moveToBeginningOfDocumentAndModifySelection:) || command == @selector(moveToEndOfDocumentAndModifySelection:) ||
             command == @selector(insertTab:) || command == @selector(insertTabIgnoringFieldEditor:))) return YES;
		
        self.isEditing=NO;
		//backwards-searching is slow enough as it is, so why not just check this first?
		if (command == @selector(deleteBackward:))
			return NO;
		
		if (command == @selector(moveDown:) || command == @selector(moveUp:) ||
			//catch shift-up/down selection behavior
			command == @selector(moveDownAndModifySelection:) ||
			command == @selector(moveUpAndModifySelection:) ||
			command == @selector(moveToBeginningOfDocumentAndModifySelection:) ||
			command == @selector(moveToEndOfDocumentAndModifySelection:)) {
			
			BOOL singleSelection = ([notesTableView numberOfRows] == 1 && [notesTableView numberOfSelectedRows] == 1);
			[notesTableView keyDown:[window currentEvent]];
			
			NSUInteger strLen = [[aTextView string] length];
			if (!singleSelection && [aTextView selectedRange].length != strLen) {
				[aTextView setSelectedRange:NSMakeRange(0, strLen)];
			}
			
			return YES;
		}
		
		if ((command == @selector(insertTab:) || command == @selector(insertTabIgnoringFieldEditor:))) {
			//[self setEmptyViewState:NO];
			if (!currentNote && ![[aTextView string] length]) {
				return YES;
			}
			if (!currentNote && [notationController preferredSelectedNoteIndex] != NSNotFound && [prefsController autoCompleteSearches]) {
				//if the current note is deselected and re-searching would auto-complete this search, then allow tab to trigger it
				[self searchForString:[self fieldSearchString] mode:[self searchMode]];
				return YES;
			} else if ([textView isHidden]) {
				return YES;
			}
			
			[self focusNoteBody];
			
			//don't eat the tab!
			return NO;
		}
		if (command == @selector(moveToBeginningOfDocument:)) {
		    [notesTableView selectRowAndScroll:0];
		    return YES;
		}
		if (command == @selector(moveToEndOfDocument:)) {
		    [notesTableView selectRowAndScroll:[notesTableView numberOfRows]-1];
		    return YES;
		}
		
		if (command == @selector(moveToBeginningOfLine:) || command == @selector(moveToLeftEndOfLine:)) {
			[aTextView moveToBeginningOfDocument:nil];
			return YES;
		}
		if (command == @selector(moveToEndOfLine:) || command == @selector(moveToRightEndOfLine:)) {
			[aTextView moveToEndOfDocument:nil];
			return YES;
		}
		
		if (command == @selector(moveToBeginningOfLineAndModifySelection:) || command == @selector(moveToLeftEndOfLineAndModifySelection:)) {
			
			if ([aTextView respondsToSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)]) {
				[(id)aTextView performSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)];
				return YES;
			}
		}
		if (command == @selector(moveToEndOfLineAndModifySelection:) || command == @selector(moveToRightEndOfLineAndModifySelection:)) {
			if ([aTextView respondsToSelector:@selector(moveToEndOfDocumentAndModifySelection:)]) {
				[(id)aTextView performSelector:@selector(moveToEndOfDocumentAndModifySelection:)];
				return YES;
			}
		}
		
		//we should make these two commands work for linking editor as well
		if (command == @selector(deleteToMark:)) {
			[aTextView deleteWordBackward:nil];
			return YES;
		}
		if (command == @selector(noop:)) {
			//control-U is not set to anything by default, so we have to check the event itself for noops
			NSEvent *event = [window currentEvent];
			if ([event modifierFlags] & NSControlKeyMask) {
				if ([event firstCharacterIgnoringModifiers] == 'u') {
					//in 1.1.1 this deleted the entire line, like tcsh. this is more in-line with bash
					[aTextView deleteToBeginningOfLine:nil];
					return YES;
				}
			}
		}
		
	} else if (control == (NSControl*)notesTableView) {
		
		if (command == @selector(insertNewline:)) {
			//hit return in cell
            self.isEditing=NO;
			[self focusNoteBody];
			return YES;
		}
	} else if (control == [tagEditor tagField]) {
		if ((command == @selector(insertNewline:))||(command == @selector(insertTab:))) {
            if ([aTextView selectedRange].length>0) {
                NSString *fieldStr=[aTextView string];
                NSInteger len=fieldStr.length;
                if ((![fieldStr hasSuffix:@","])&&![fieldStr hasSuffix:@" "]) {
                    [aTextView insertText:@"," replacementRange:NSMakeRange(len, 0)];
                    len++;
                }
                [aTextView setSelectedRange:NSMakeRange(len, 0)];
                return YES;
            }
		}else {
            if ((command == @selector(deleteBackward:))||(command == @selector(deleteForward:))) {
                wasDeleting = YES;
            }
            return NO;
		}
	} else{
        
		NSLog(@"%@/%@ got %@", [control description], [aTextView description], NSStringFromSelector(command));
        self.isEditing=NO;
    }
	
	return NO;
}

- (void)_setCurrentNote:(NoteObject *)aNote {
    [self _setCurrentNote:aNote finishingEditing:YES];
}
- (void)_setCurrentNote:(NoteObject *)aNote finishingEditing:(BOOL)finishOldEditing {
    if (currentNote == aNote) return;
    if (finishOldEditing) [self finishEditing];
    [self captureBodyPresentation];
    if (currentNote) {
        NSString *key = [NSString uuidStringWithBytes:*[currentNote uniqueNoteIDBytes]];
        [noteSelections setObject:NSStringFromRange([textView selectedRange]) forKey:key];
    }
    [currentNote release];
    currentNote = [aNote retain];
    NVNoteEditingSession *previousSession = [editingSession autorelease];
    editingSession = [[[NVApplicationController sharedController] editingSessionForNote:aNote] retain];
    NSTextStorage *storage = editingSession ? [editingSession textStorage] : emptyEditorStorage;
    NSLayoutManager *layout = [[textView layoutManager] retain];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageWillProcessEditingNotification object:[layout textStorage]];
    // Cancel the old note's deferred cleanup before this editor changes storage.
    [textView removeHighlightedTerms];
    // replaceTextStorage: moves every layout manager from the old storage.
    // Detach only this window's layout manager when switching notes.
    [[layout textStorage] removeLayoutManager:layout];
    [previousSession sourceLayoutDidDetach];
    [storage addLayoutManager:layout];
    if (editingSession) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(searchSourceStorageWillProcessEditing:) name:NSTextStorageWillProcessEditingNotification object:storage];
    [editingSession sourceLayoutDidAttach];
    [layout release];
    [textView setAllowsUndo:NO];
    [self updateNoteHeader];
    [self updateBodyPresentation];
    if (!aNote) [self discardViewer];
    else if (viewingNote) [self updateViewerSnapshot];
}

- (NoteObject*)selectedNoteObject {
	return currentNote;
}

- (NSString*)fieldSearchString {
    return [[self browserSession] searchString] ?: [field stringValue];
}

- (NSString*)typedString {
	if (typedStringIsCached)
		return typedString;
	
	return nil;
}

- (void)cacheTypedStringIfNecessary:(NSString*)aString {
	if (!typedStringIsCached) {
		[typedString release];
		typedString = [(aString ? aString : [field stringValue]) copy];
		typedStringIsCached = YES;
	}
}

//from fieldeditor
- (void)controlTextDidChange:(NSNotification *)aNotification {
    
    if ([aNotification object] == field) {
        NSTextView *editor = [[aNotification userInfo] objectForKey:@"NSFieldEditor"];
        NSString *query = [editor string] ?: [field stringValue];
        // Input-method composition is local until committed.
        if ([editor hasMarkedText]) {
            searchHasPendingComposition = YES;
            [self cancelSearchIntents];
            [[self browserSession] suspendSearchForComposition:YES];
            return;
        }
        [self cancelSearchIntents];
        [[self browserSession] suspendSearchForComposition:NO];
        searchHasPendingComposition = NO;
        [typedString release]; typedString = [query copy]; typedStringIsCached = YES;
        isFilteringFromTyping = YES;
        searchSubmitting = YES;
        [notationController filterNotesFromString:query];
        searchSubmitting = NO;
        if ([[self searchMode] isEqual:@"fuzzy"] && [[self browserSession] hasSearchTerms]) {
            searchAutocompletePending = YES;
            searchIntentGeneration = [[self browserSession] searchGeneration];
            isFilteringFromTyping = NO;
            [self updateSearchAffordance];
            if ([[self browserSession] searchResultsAreCurrent]) [self browserSessionSearchDidComplete:[self browserSession]];
            return;
        }
        NSUInteger preferred = [notationController preferredSelectedNoteIndex];
        if ([query length] && [prefsController autoCompleteSearches] && preferred != NSNotFound) {
            [notesTableView selectRowAndScroll:preferred];
            [self displayContentsForNoteAtIndex:preferred];
        } else {
            [notesTableView deselectAll:nil];
            [self _setCurrentNote:nil];
            [self setEmptyViewState:YES];
        }
        isFilteringFromTyping = NO;
        [self updateSearchAffordance];
	} else if ([aNotification object] == [tagEditor tagField] && [tagEditor isMultitagging]) { //<--for elasticthreads multitagging
        if (!isAutocompleting&&!wasDeleting) {
            isAutocompleting = YES;
            NSTextView *editor = [tagEditor tagFieldEditor];
            NSRange selRange = [editor selectedRange];
            NSString *tagString = [NSString stringWithString:tagEditor.tagFieldString];
            NSString *searchString = tagString;
            if (selRange.length>0) {
                searchString = [searchString substringWithRange:selRange];
            }
            searchString = [[searchString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]] lastObject];
            selRange = [tagString rangeOfString:searchString options:NSBackwardsSearch];
            NSArray *theTags = [notesTableView labelCompletionsForString:searchString index:0];
            if ((theTags)&&([theTags count]>0)&&(![[theTags objectAtIndex:0] isEqualToString:@""])){
                NSString *useStr;
                for (useStr in theTags) {
                    if ([tagString rangeOfString:useStr].location==NSNotFound) {
                        break;
                    }
                }
                if (useStr) {
                    tagString = [tagString substringToIndex:selRange.location];
                    tagString = [tagString stringByAppendingString:useStr];
                    selRange = NSMakeRange(selRange.location + selRange.length, useStr.length - searchString.length );
                    [tagEditor setTF:tagString];
                    [editor setSelectedRange:selRange];
                }
            }
            isAutocompleting = NO;
            //            [tagString release];
        }
        wasDeleting = NO;
    }
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification {
    if (reloadingNotesList) return;
	
    if (IsLionOrLater) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldReset" object:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    
	BOOL allowMultipleSelection = NO;
	NSEvent *event = [window currentEvent];
    
	NSEventType type = [event type];
	//do not allow drag-selections unless a modifier is pressed
	if (type == NSLeftMouseDragged || type == NSLeftMouseDown) {
		NSUInteger flags = [event modifierFlags];
		if ((flags & NSShiftKeyMask) || (flags & NSCommandKeyMask)) {
			allowMultipleSelection = YES;
		}
	}
	
	if (allowMultipleSelection != [notesTableView allowsMultipleSelection]) {
		//we may need to hack some hidden NSTableView instance variables to improve mid-drag flags-changing
		//NSLog(@"set allows mult: %d", allowMultipleSelection);
		
		[notesTableView setAllowsMultipleSelection:allowMultipleSelection];
		
		//we need this because dragging a selection back to the same note will nto trigger a selectionDidChange notification
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}
    
	if ([window firstResponder] != notesTableView) {
		//occasionally changing multiple selection ability in-between selecting multiple items causes total deselection
		[window makeFirstResponder:notesTableView];
	}
	
	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)setTableAllowsMultipleSelection {
	[notesTableView setAllowsMultipleSelection:YES];
	//NSLog(@"allow mult: %d", [notesTableView allowsMultipleSelection]);
	//[textView setNeedsDisplay:YES];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    if (reloadingNotesList) return;
    if (![[self browserSession] searchResultsAreCurrent]) return;
    if (!searchApplyingResult) [self cancelSearchIntents];
    if (IsLionOrLater) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldUpdate" object:self];
    }
    self.isEditing = NO;
	NSEventType type = [[window currentEvent] type];
	if (type != NSKeyDown && type != NSKeyUp) {
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}
	
	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)processChangedSelectionForTable:(NSTableView*)table {
    if (reloadingNotesList) return;
    if (table == notesTableView && ![[self browserSession] searchResultsAreCurrent]) return;
    if (table == notesTableView && [[[self browserSession] notesAtIndexes:[table selectedRowIndexes]] count] == 1 && [notesTableView primarySelectedRow] >= 0) {
        [self cacheTypedStringIfNecessary:[[self browserSession] searchString]];
        [field setSnapbackString:[[self browserSession] searchString]];
        [self displayContentsForNoteAtIndex:(NSUInteger)[notesTableView primarySelectedRow]];
    } else if (!isFilteringFromTyping) {
        [self _setCurrentNote:nil];
        [self setEmptyViewState:YES];
        [savedSelectedNotes release]; savedSelectedNotes = nil;
    }
    [self updateNoteHeader];
    [self updateSearchAffordance];
}

- (BOOL)setNoteIfNecessary{
    if (currentNote==nil) {
        [notesTableView selectRowAndScroll:0];
        return (currentNote!=nil);
    }
    return YES;
}

- (void)setEmptyViewState:(BOOL)state {
    [self updateNoteHeader];
    [self updateSearchAffordance];
    //return;
	
	//int numberSelected = [notesTableView numberOfSelectedRows];
	//BOOL enable = /*numberSelected != 1;*/ state;
    
	[self postTextUpdate];
    [self updateWordCount:![prefsController showWordCount]];
	[textView setHidden:state];
	[editorStatusView setHidden:!state];
    [self updateBodyPresentation];
	
	if (state) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:self];
		[editorStatusView setLabelStatus:[notesTableView numberOfSelectedRows]];
	}
}

- (BOOL)displayContentsForNoteAtIndex:(NSUInteger)noteIndex {
    if (![[self browserSession] searchResultsAreCurrent]) return NO;
	NoteObject *note = [notationController noteObjectAtFilteredIndex:noteIndex];
    if (!note) return NO;
    [notesTableView setPrimarySelectedRow:(NSInteger)noteIndex];
    [selectedSearchRowKey release]; selectedSearchRowKey = [[[self browserSession] rowKeyAtIndex:noteIndex] copy];
	if (note != currentNote) {
		[self setEmptyViewState:NO];
		
		//actually load the new note
		[self _setCurrentNote:note];
		
		NSRange firstFoundTermRange = NSMakeRange(NSNotFound,0);
		NSString *selection = [noteSelections objectForKey:[NSString uuidStringWithBytes:*[currentNote uniqueNoteIDBytes]]];
        NSRange noteSelectionRange = selection ? NSRangeFromString(selection) : [currentNote lastSelectedRange];
		
		if (noteSelectionRange.location == NSNotFound ||
			NSMaxRange(noteSelectionRange) > [[note contentString] length]) {
			//revert to the top; selection is invalid
			noteSelectionRange = NSMakeRange(0,0);
		}
		
		//[textView beginInhibitingUpdates];
		//scroll to the top first in the old note body if necessary, because the text will (or really ought to) have already been laid-out
		//if ([textView visibleRect].origin.y > 0)
		//	[textView scrollRangeToVisible:NSMakeRange(0,0)];
		
		if (![textView didRenderFully]) {
			//NSLog(@"redisplay because last note was too long to finish before we switched");
			[textView setNeedsDisplayInRect:[textView visibleRect] avoidAdditionalLayout:YES];
		}
		
		//restore string
		// The note session supplies the shared text storage; this view keeps its layout manager.
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
		//[textView setAutomaticallySelectedRange:NSMakeRange(0,0)];
		
		//highlight terms--delay this, too
		if ([[self searchMode] isEqual:@"exact"] && (unsigned)noteIndex != [notationController preferredSelectedNoteIndex])
			firstFoundTermRange = [textView highlightTermsTemporarilyReturningFirstRange:typedString avoidHighlight:
								   ![prefsController highlightSearchTerms]];
		
		//if there was nothing selected, select the first found range
		if (!noteSelectionRange.length && firstFoundTermRange.location != NSNotFound)
			noteSelectionRange = firstFoundTermRange;
		
		//select and scroll
		[textView setAutomaticallySelectedRange:noteSelectionRange];
		[textView scrollRangeToVisible:noteSelectionRange];
        [self restoreSourceScroll];
		
		//NSString *words = noteIndex != [notationController preferredSelectedNoteIndex] ? typedString : nil;
		//[textView setFutureSelectionRange:noteSelectionRange highlightingWords:words];
		
        [self refreshSearchHighlights];
        
		return YES;
	}
	
	[self refreshSearchHighlights];
	return NO;
}

//from linkingeditor
- (void)textDidChange:(NSNotification *)aNotification {
	id textObject = [aNotification object];
    //[self resetModTimers];
    if (textObject == textView) {
        searchHighlightGeneration++;
        [textView removeHighlightedTerms];
        processingSourceEdit = YES;
        @try { [editingSession commitTextChanges]; }
        @finally { processingSourceEdit = NO; }
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
        if (IsLionOrLater) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextShouldUpdate" object:self];
        }
	}
    
    
}

- (void)textDidBeginEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		[textView removeHighlightedTerms];
	    [self createNoteIfNecessary];
	}/*else if ([aNotification object] == notesTableView) {
      NSLog(@"ntv tdbe2");
      }*/
}

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    id control = [notification object];
    if (control == noteTitleField || control == noteTagsField) [self beginNoteMetadataEditing:control];
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if ([notification object] == field) [self cancelTransientSearchIntents];
    if ([notification object] == metadataControl) [self commitNoteMetadata];
    if ([notification object] == field && searchHasPendingComposition) {
        searchHasPendingComposition = NO;
        [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
    }
}
- (void)textDidEndEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		//save last selection range for currentNote?
		//[currentNote setSelectedRange:[textView selectedRange]];
		
		//we need to set this here as we could return to searching before changing notes
		//and the next time the note would change would be when searching had triggered it
		//which would be too late
		[currentNote updateContentCacheCStringIfNecessary];
	}
}

- (NSMenu *)textView:(NSTextView *)view menu:(NSMenu *)menu forEvent:(NSEvent *)event atIndex:(NSUInteger)charIndex {
    //    NSLog(@"textview menu for event");
	NSInteger idx;
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(_removeLinkFromMenu:)]) > -1)
		[menu removeItemAtIndex:idx];
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(orderFrontLinkPanel:)]) > -1)
		[menu removeItemAtIndex:idx];
	return menu;
}

- (NSArray *)control:(NSControl *)control textView:(NSTextView *)aTextView completions:(NSArray *)words
  forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)anIndex {
    if (control == noteTagsField) {
        return [(id<NSTextViewDelegate>)notesTableView textView:aTextView completions:words
            forPartialWordRange:charRange indexOfSelectedItem:anIndex];
    }
    return words;
}


- (IBAction)fieldAction:(id)sender {
    [self performSearchReturn];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)sender {
	
	if ([sender firstResponder] == textView) {
		NSUndoManager *undoMan = [self undoManagerForTextView:textView];
		if (undoMan)
			return undoMan;
	}
	return notationController ? [[self sharedNotationController] undoManager] : windowUndoManager;
}

- (NSUndoManager *)undoManagerForTextView:(NSTextView *)aTextView {
    if (aTextView == textView && currentNote)
		return [currentNote undoManager];
    
    return nil;
}

- (NoteObject*)createNoteIfNecessary {
    return [self createNoteIfNecessaryWithTitle:[field stringValue]];
}

- (NoteObject*)createNoteIfNecessaryWithTitle:(NSString *)title {
    
    if (!currentNote) {
        [self setViewingNote:NO];
		//this assertion not yet valid until labels list changes notes list
		NSAssert([notesTableView numberOfSelectedRows] != 1, @"cannot create a note when one is already selected");
		
		[textView setTypingAttributes:[prefsController noteBodyAttributes]];
		[textView setFont:[prefsController noteBodyFont]];
		
		isCreatingANote = YES;
		if (![title length]) title = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		NSAttributedString *attributedContents = [textView textStorage] ? [textView textStorage] : [[[NSAttributedString alloc] initWithString:@"" attributes:
																									 [prefsController noteBodyAttributes]] autorelease];
		NoteObject *note = [[[NoteObject alloc] initWithNoteBody:attributedContents title:title delegate:[self sharedNotationController]
														  format:[notationController currentNoteStorageFormat] labels:nil] autorelease];
		[notationController addNewNote:note];
		
		isCreatingANote = NO;
		return note;
    }
    
    return currentNote;
}


- (void)restoreListStateUsingPreferences {
	//to be invoked after loading a notationcontroller
	[self cancelSearchIntents];
	
	NSString *searchString = [prefsController lastSearchString];
    if (searchString || [[NSUserDefaults standardUserDefaults] objectForKey:@"LastSearchMode"])
        [[self browserSession] setSearchMode:[prefsController lastSearchMode]];
	if ([searchString length])
		[self searchForString:searchString mode:[prefsController lastSearchMode]];
	else
		[notationController refilterNotes];
    [self setupSearchControls];
    
	CFUUIDBytes bytes = [prefsController UUIDBytesOfLastSelectedNote];
    NoteObject *savedNote = [notationController noteForUUIDBytes:&bytes];
    if (![[self browserSession] searchResultsAreCurrent] && savedNote) {
        searchAutocompletePending = NO;
        [pendingSearchReveal release];
        NSMutableDictionary *intent = [NSMutableDictionary dictionaryWithObjectsAndKeys:savedNote, @"note",
            @(NVDoNotChangeScrollPosition), @"options", @([prefsController scrollOffsetOfLastSelectedNote]), @"scrollOffset", nil];
        if ([prefsController lastSearchResultRowKey]) [intent setObject:[prefsController lastSearchResultRowKey] forKey:@"rowKey"];
        pendingSearchReveal = [intent copy];
        return;
    }
	NSUInteger idx = [self revealNote:[notationController noteForUUIDBytes:&bytes] options:NVDoNotChangeScrollPosition];
    NSString *savedKey = [prefsController lastSearchResultRowKey];
    NSUInteger savedRow = savedKey ? [[self browserSession] indexForRowKey:savedKey] : NSNotFound;
    if (savedRow != NSNotFound && [[self browserSession] noteObjectAtFilteredIndex:savedRow] == savedNote) {
        idx = savedRow;
        [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
    }
	//scroll using saved scrollbar position
	[notesTableView scrollRowToVisible:NSNotFound == idx ? 0 : idx withVerticalOffset:[prefsController scrollOffsetOfLastSelectedNote]];
}

- (NSUInteger)revealNote:(NoteObject*)note options:(NSUInteger)opts {
	if (note && ![[[self sharedNotationController] allNotes] containsObject:note]) return NSNotFound;
    // An accepted selection command replaces older restoration or Reveal work,
    // whether it can select immediately or must wait for current results.
    [self cancelSearchIntents];
	if (note) {
        NVBrowserSession *session = [self browserSession];
        // Reveal can arrive between model invalidation and the delayed list
        // refresh. Exact and empty-query lists can refresh synchronously;
        // libraryDidChange also respects composition and active inline edits.
        if (![session searchResultsAreCurrent] &&
            (![[session searchMode] isEqual:@"fuzzy"] || ![session hasSearchTerms]))
            [session libraryDidChange];
        if (![[self browserSession] searchResultsAreCurrent]) {
            [pendingSearchReveal release];
            pendingSearchReveal = [@{@"note":note, @"options":@(opts)} copy];
            return NSNotFound;
        }
		NSUInteger selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
        if ([notesTableView primarySelectedRow] >= 0 && [[self browserSession] noteObjectAtFilteredIndex:[notesTableView primarySelectedRow]] == note)
            selectedNoteIndex = [notesTableView primarySelectedRow];
		
		if (selectedNoteIndex == NSNotFound) {
            // Library refreshes are deferred. A newly added note can be absent
            // from this browser's cached list even when its query matches.
            if ([[self searchMode] isEqual:@"exact"]) [[self browserSession] refilterNotes];
            if (![[self browserSession] searchResultsAreCurrent]) {
                [pendingSearchReveal release];
                pendingSearchReveal = [@{@"note":note, @"options":@(opts)} copy];
                return NSNotFound;
            }
			selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
            if (selectedNoteIndex == NSNotFound && [[[self sharedNotationController] allNotes] containsObject:note]) {
                // Reveal also serves background browsers; cancelOperation:
                // intentionally ignores windows that are not key.
                [field setStringValue:@""];
                [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
                selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
            }
		}
		
		if (selectedNoteIndex != NSNotFound) {
			if (opts & NVDoNotChangeScrollPosition) { //select the note only
				[notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedNoteIndex] byExtendingSelection:NO];
			} else {
				[notesTableView selectRowAndScroll:selectedNoteIndex];
			}
		}
		
		if (opts & NVEditNoteToReveal) {
			[self setViewingNote:NO];
			[self focusNoteBody];
		}
		if (opts & NVOrderFrontWindow) {
			//for external url-handling, often the app will already have been brought to the foreground
			if (![NSApp isActive]) {
				if (IsLeopardOrLater)
//                CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
				[NSApp activateIgnoringOtherApps:YES];
			}
			if (![window isKeyWindow])
				[window makeKeyAndOrderFront:nil];
		}
		return selectedNoteIndex;
	} else {
		[notesTableView deselectAll:self];
		return NSNotFound;
	}
}

- (void)notation:(NotationController*)notation revealNote:(NoteObject*)note options:(NSUInteger)opts {
	[self revealNote:note options:opts];
}

- (void)notation:(NotationController*)notation revealNotes:(NSArray*)notes {
    NVBrowserSession *session = [self browserSession];
    NSHashTable *members = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NoteObject *note in [[self sharedNotationController] allNotes]) [members addObject:note];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *targets = [NSMutableArray array];
    for (NoteObject *note in notes) {
        if (![members containsObject:note]) continue;
        NSData *uuid = [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
        if (![seen containsObject:uuid]) { [seen addObject:uuid]; [targets addObject:note]; }
    }
    if (![targets count]) return;
    [self cancelSearchIntents];
    if (![session searchResultsAreCurrent]) {
        [pendingSearchReveal release]; pendingSearchReveal = [@{@"notes":[[targets copy] autorelease]} copy];
        return;
    }
	NSIndexSet *indexes = [session indexesOfNotes:targets];
	if ([targets count] != [indexes count]) {
        // Reveal can finish in a background browser. Clear only its query;
        // cancelOperation: is a foreground keyboard command that also changes focus.
        [field setStringValue:@""];
        [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
		indexes = [session indexesOfNotes:targets];
	}
	if ([indexes count]) {
		[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];
		[notesTableView scrollRowToVisible:[indexes firstIndex]];
	}
}

- (void)searchForString:(NSString*)string {
    [self searchForString:string mode:@"exact"];
}

- (void)bookmarksController:(BookmarksController*)controller restoreNoteBookmark:(NoteBookmark*)aBookmark inBackground:(BOOL)inBG {
	if (aBookmark) {
        [self searchForString:[aBookmark searchString] mode:[aBookmark searchMode]];
        searchAutocompletePending = NO;
        NoteObject *note = [aBookmark noteObject];
        if (note) {
            NSMutableDictionary *intent = [NSMutableDictionary dictionaryWithObjectsAndKeys:note, @"note", @(!inBG ? NVOrderFrontWindow : 0), @"options", nil];
            if ([aBookmark resultRowKey]) [intent setObject:[aBookmark resultRowKey] forKey:@"rowKey"];
            [pendingSearchReveal release]; pendingSearchReveal = [intent copy];
            if ([[self browserSession] searchResultsAreCurrent]) [self browserSessionSearchDidComplete:[self browserSession]];
        }
	}
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize {
	if ([self horizontalLayout]) {
		[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	}
	return proposedFrameSize;
}


- (void)tableViewColumnDidResize:(NSNotification *)aNotification {
	NoteAttributeColumn *col = [[aNotification userInfo] objectForKey:@"NSTableColumn"];
	if ([[col identifier] isEqualToString:NoteTitleColumnString]) {
		[notationController regeneratePreviewsForColumn:col visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:NO];
		
	 	[NSObject cancelPreviousPerformRequestsWithTarget:notesTableView selector:@selector(reloadDataIfNotEditing) object:nil];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0.0];
	}
}


//the notationcontroller must call notationListShouldChange: first
//if it's going to do something that could mess up the tableview's field eidtor
- (BOOL)notationListShouldChange:(NotationController*)someNotation {
	
	if (someNotation == notationController) {
		if ([notesTableView currentEditor])
			return NO;
	}
	
	return YES;
}

- (void)notationListMightChange:(NotationController*)someNotation {
	
	if (!isFilteringFromTyping) {
		if (someNotation == notationController) {
			//deal with one notation at a time
			
			if ([notesTableView numberOfSelectedRows] > 0) {
				NSIndexSet *indexSet = [notesTableView selectedRowIndexes];
                
				[savedSelectedNotes release];
				savedSelectedNotes = [[someNotation notesAtIndexes:indexSet] retain];
                [savedSelectedRowKeys release];
                savedSelectedRowKeys = [[[self browserSession] rowKeysAtIndexes:indexSet] copy];
			}
			
			listUpdateViewCtx = [notesTableView viewingLocation];
		}
	}
}

- (void)notationListDidChange:(NotationController*)someNotation {
	
	if (someNotation == notationController) {
		//deal with one notation at a time
        
		reloadingNotesList = YES;
        [notesTableView reloadData];
		//[notesTableView noteNumberOfRowsChanged];
		
		if (!isFilteringFromTyping) {
			if (savedSelectedNotes) {
				NSIndexSet *indexes = savedSelectedRowKeys ? [[self browserSession] indexesForRowKeys:savedSelectedRowKeys] : [someNotation indexesOfNotes:savedSelectedNotes];
				[savedSelectedNotes release];
				savedSelectedNotes = nil;
                [savedSelectedRowKeys release]; savedSelectedRowKeys = nil;
				
				[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];

                NSUInteger primary = [[self browserSession] indexForRowKey:selectedSearchRowKey];
                if (primary != NSNotFound && [indexes containsIndex:primary])
                    [notesTableView setPrimarySelectedRow:(NSInteger)primary];
			}
			
			[notesTableView setViewingLocation:listUpdateViewCtx];
		}
        reloadingNotesList = NO;
        if (!isFilteringFromTyping) [self processChangedSelectionForTable:notesTableView];
	}
}

- (void)titleUpdatedForNote:(NoteObject*)aNoteObject {
    if (aNoteObject == currentNote) { [self updateNoteHeader]; [self postTextUpdate]; }
    [[prefsController bookmarksController] updateBookmarksUI];
}

- (void)contentsUpdatedForNote:(NoteObject *)note {
    if (note == currentNote) [editingSession reloadFromNote];
    [self refreshEditorForNote:note];
}

- (void)rowShouldUpdate:(NSInteger)affectedRow {
	NSRect rowRect = [notesTableView rectOfRow:affectedRow];
	NSRect visibleRect = [notesTableView visibleRect];
	
	if (NSContainsRect(visibleRect, rowRect) || NSIntersectsRect(visibleRect, rowRect)) {
		[notesTableView setNeedsDisplayInRect:rowRect];
	}
}

- (IBAction)fixFileEncoding:(id)sender {
	if (currentNote) {
		[notationController synchronizeNoteChanges:nil];
		
		[[EncodingsManager sharedManager] showPanelForNote:currentNote];
	}
}


- (void)windowDidResignKey:(NSNotification *)notification{
    [self cancelTransientSearchIntents];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];    
}

- (void)windowDidBecomeMain:(NSNotification *)notification {
    [[NVApplicationController sharedController] browserBecameActive:self];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self cancelMultiTagEditing];
    [self cancelSearchIntents];
    [[self browserSession] invalidateSearch];
    [self finishEditing];
    [self discardViewer];
    [notesTableView deselectAll:self];
    [self _setCurrentNote:nil];
    if (!applicationOwner) [self unregisterBrowserObservers];
    [[NVApplicationController sharedController] browserWillClose:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (notationController) {
		//only save the state if the notation instance has actually loaded; i.e., don't save last-selected-note if we quit from a PW dialog
		BOOL wasAutomatic = NO;
		NSRange currentRange = [textView selectedRangeWasAutomatic:&wasAutomatic];
		if (!wasAutomatic) [currentNote setSelectedRange:currentRange];
		
		[currentNote updateContentCacheCStringIfNecessary];
		
		[prefsController setLastSearchString:[self fieldSearchString] selectedNote:currentNote
					scrollOffsetForTableView:notesTableView sender:self];
		
		[prefsController saveCurrentBookmarksFromSender:self];
	}
	
	[[NSApp windows] makeObjectsPerformSelector:@selector(close)];
	[notationController stopFileNotifications];
	
    if ([notationController flushAllNoteChanges])
		[notationController closeJournal];
	else
		NSLog(@"Could not flush database, so not removing journal");
	
    [prefsController synchronize];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelMultiTagEditing];
    [window setDelegate:nil];
    [textView setDelegate:nil];
    [notesTableView setDelegate:nil];
    [field setDelegate:nil];
    [(NVBrowserSession *)notationController setDelegate:nil];
    [notationController release];
    [editingSession release];
    [emptyEditorStorage release];
    [currentNote release];
    [savedSelectedNotes release];
    [savedSelectedRowKeys release];
    [selectedSearchRowKey release];
    [pendingSearchReturnQuery release];
    [pendingSearchRestoration release];
    [pendingSearchReveal release];
    [searchStatusField release];
    [typedString release];
    [noteSelections release];
    [noteBodyStates release];
    [selectedViewerIdentifier release];
    [browserIdentifier release];
    [self discardViewer];
    [windowUndoManager release];
    [noteTitleField setDelegate:nil];
    [noteTagsField setDelegate:nil];
    [metadataNote release]; [metadataOriginalValue release];
    [noteTitleField release]; [noteTagsField release]; [createNoteButton release];
    [bodyModeControl release]; [sourceSyntaxControl release]; [viewerTypeControl release];
    [[browserSplitController view] removeFromSuperview];
    [browserSplitController setSplitViewItems:@[]];
    [browserSplitController release];
    [toolbar setDelegate:nil];
    [toolbar release]; [dualFieldItem release];
    [backgrndColor release];
    [foregrndColor release];
    [windowObjects release];
    [super dealloc];
}

- (IBAction)showPreferencesWindow:(id)sender {
	[prefsWindowController showWindow:sender];
}


- (IBAction)makeActiveAndShowWindow:(id)sender{
    [self makeActiveAndShowWindowByFocusingControlField:NO andForcingActivation:YES];
}

- (IBAction)bringFocusToControlField:(id)sender {
    //For ElasticThreads' fullscreen mode use this if/else otherwise uncomment the expand toolbar

    [self focusControlField:sender activate:YES];
}

- (void)focusControlField:(id)sender activate:(BOOL)shouldActivate{
    [self makeActiveAndShowWindowByFocusingControlField:YES andForcingActivation:shouldActivate];
}

- (IBAction)toggleNVActivation:(id)sender {

    if ([NSApp isActive] && [window isMainWindow]&&[window isVisible]) {
        [NSApp hide:sender];
        return;
    }
    [self focusControlField:sender activate:YES];
}

- (void)makeActiveAndShowWindowByFocusingControlField:(BOOL)focus andForcingActivation:(BOOL)activate{
    [[NVApplicationController sharedController] browserBecameActive:self];

    if (focus) [self setDualFieldIsVisible:YES];
    if (activate && ![NSApp isActive]) [NSApp activateIgnoringOtherApps:YES];
    [self setEmptyViewState:currentNote == nil];
    self.isEditing = NO;
    if (![window isKeyWindow] || ![window isVisible]) [window makeKeyAndOrderFront:nil];
    if (focus) [self selectSearchField];
}

- (void)selectSearchField {
    // Attach and size the toolbar field before focusing its native editor.
    [[[window contentView] superview] layoutSubtreeIfNeeded];
    [window makeFirstResponder:field];
    [field selectText:self];
}

- (NSWindow*)window {
	return window;
}



#pragma mark nvALT methods

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (aTableView == notesTableView && [cell respondsToSelector:@selector(setTextColor:)]) {
        BOOL active = [window isKeyWindow] && ([window firstResponder] == notesTableView || [notesTableView editedRow] == row);
        [cell setTextColor:[cell isHighlighted] && active ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor]];
    }
}

- (NSMenu *)statBarMenu{
	return statBarMenu;
}



#pragma mark multitagging

- (void)captureMultiTagNotes:(NSArray *)notes {
    [self cancelMultiTagEditing];
    multiTagLibrary = [[self sharedNotationController] retain];
    NSMutableArray *uuids = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NoteObject *note in notes) {
        NSData *uuid = [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
        if (![seen containsObject:uuid]) { [uuids addObject:uuid]; [seen addObject:uuid]; }
    }
    multiTagNoteUUIDs = [uuids copy];
}
- (NSArray *)pendingMultiTagNotes {
    if (!multiTagLibrary || multiTagLibrary != [self sharedNotationController]) return @[];
    NSMutableArray *notes = [NSMutableArray array];
    for (NSData *uuid in multiTagNoteUUIDs) {
        CFUUIDBytes bytes; [uuid getBytes:&bytes length:sizeof(bytes)];
        NoteObject *note = [multiTagLibrary noteForUUIDBytes:&bytes];
        if (note) [notes addObject:note];
    }
    return notes;
}
- (void)cancelMultiTagEditing {
    TagEditingManager *editor = tagEditor; tagEditor = nil;
    [multiTagNoteUUIDs release]; multiTagNoteUUIDs = nil;
    [multiTagLibrary release]; multiTagLibrary = nil;
    [editor closeTP:self];
    [editor release];
}

- (NSArray *)commonLabelsForNotesAtIndexes:(NSIndexSet *)selDexes{
    return [self commonLabelsForNotes:[notationController notesAtIndexes:selDexes]];
}
- (NSArray *)commonLabelsForNotes:(NSArray *)notes {
	if (![notes count]) return @[];
	NSArray *retArray =[NSArray array];
    
	NSEnumerator *noteEnum = [[notes objectEnumerator] retain];
	NoteObject *aNote;
	aNote = [noteEnum nextObject];
	NSString *existTags = labelsOfNote(aNote);
	if (existTags&&(existTags.length>0)) {
        NSMutableSet *commonTags = [NSMutableSet new];
        
        [commonTags addObjectsFromArray:[existTags labelCompatibleWords]];
		while (((aNote = [noteEnum nextObject]))&&([commonTags count]>0)) {
			existTags = labelsOfNote(aNote);
			if (!existTags||(existTags.length==0)) {
				[commonTags removeAllObjects];
				break;
            }else{
				NSArray *tagArray = [existTags labelCompatibleWords];
                if (tagArray&&([tagArray count]>0)) {
                    NSSet *tagsForNote =[NSSet setWithArray:tagArray];
                    if ([commonTags intersectsSet:tagsForNote]) {
                        [commonTags intersectSet:tagsForNote];
                    }else {
                        [commonTags removeAllObjects];
                        break;
                    }
                }else {
                    [commonTags removeAllObjects];
                    break;
                }
			}
		}
		if (commonTags&&([commonTags count]>0)) {
			retArray = [NSArray arrayWithArray:[commonTags allObjects]];
		}
        [commonTags release];
	}
	[noteEnum release];
	return retArray;
}

- (IBAction)multiTag:(id)sender {
    NSArray *selNotes = [self pendingMultiTagNotes];
    if (!tagEditor || ![selNotes count]) { [self cancelMultiTagEditing]; return; }
	NSString *tagString = [tagEditor.tagFieldString stringByTrimmingCharactersInSet:[NSCharacterSet labelSeparatorCharacterSet]];
	NSArray *newTags;
    if (tagString&&(tagString.length>0)) {
        newTags=[tagString labelCompatibleWords];
    }else{
        newTags=[NSArray array];
    }
    NSArray *commonLabs=tagEditor.commonTags;
    if (![newTags isEqualToArray:commonLabs]) {
        
        tagString=nil;
        
        BOOL gotNewLabels=(newTags&&([newTags count]>0));
        BOOL gotCommonLabels=(commonLabs&&([commonLabs count]>0));
        NSPredicate *pred;
        if (gotCommonLabels&&gotNewLabels) {
            pred=[NSPredicate predicateWithFormat:@"NOT %@ CONTAINS[cd] SELF",newTags];
            commonLabs=[commonLabs filteredArrayUsingPredicate:pred];
        }
        NSMutableArray *finalTags = [NSMutableArray new];
        for (NoteObject *aNote in selNotes) {
            NSString *separator=@" ";
            tagString=labelsOfNote(aNote);
            NSArray *filteredTags;
            
            if (tagString&&(tagString.length>0)) {
                if (([tagString rangeOfString:@","].location!=NSNotFound)) {
                    separator=@",";
                }
                filteredTags=[tagString labelCompatibleWords];
                if (gotCommonLabels) {
                    pred=[NSPredicate predicateWithFormat:@"NOT %@ CONTAINS[cd] SELF",commonLabs];
                    filteredTags=[filteredTags filteredArrayUsingPredicate:pred];
                }
                if (filteredTags&&([filteredTags count]>0)) {
                    [finalTags addObjectsFromArray:filteredTags];
                }
            }
            if (gotNewLabels) {
                if (finalTags&&([finalTags count]>0)) {
                    pred=[NSPredicate predicateWithFormat:@"NOT %@ CONTAINS[cd] SELF",finalTags];
                    filteredTags=[newTags filteredArrayUsingPredicate:pred];
                    if (filteredTags&&([filteredTags count]>0)) {
                        [finalTags addObjectsFromArray:filteredTags];
                    }
                }else{
                    [finalTags addObjectsFromArray:newTags];
                }
            }
            if (finalTags&&([finalTags count]>0)) {
                tagString = [finalTags componentsJoinedByString:separator];
            }else{
                tagString=@"";
            }
        
            [aNote setLabelString:tagString];
            [finalTags removeAllObjects];
        }
        
        if ([[self browserSession] searchResultsAreCurrent] && [notesTableView primarySelectedRow] >= 0)
            [notesTableView scrollRowToVisible:[notesTableView primarySelectedRow]];
        [finalTags release];
    }
	[self cancelMultiTagEditing];
}

- (void)releaseTagEditor:(NSNotification *)note{
    if ([note object] == tagEditor) [self cancelMultiTagEditing];
}

#pragma mark Browser layout

- (void)setDualFieldIsVisible:(BOOL)visible {
    [toolbar setVisible:visible];
    if (visible) {
        BOOL searchPresent = NO;
        for (NSToolbarItem *item in [toolbar items]) if ([[item itemIdentifier] isEqual:@"Search"]) searchPresent = YES;
        if (!searchPresent) [toolbar insertItemWithItemIdentifier:@"Search" atIndex:[[toolbar items] count]];
    }
}
- (BOOL)dualFieldIsVisible { return [toolbar isVisible]; }
- (IBAction)toggleCollapse:(id)sender {
    [self setNotesListHeight:[self notesListHeight] > 90 ? 84 : NSHeight([splitView bounds]) / 3.0];
}
- (BOOL)isInFullScreen { return ([window styleMask] & NSWindowStyleMaskFullScreen) != 0; }
- (IBAction)switchFullScreen:(id)sender { [window toggleFullScreen:sender]; }
- (void)windowDidEnterFullScreen:(NSNotification *)notification { [textView updateInsetAndForceLayout:YES]; }
- (void)windowDidExitFullScreen:(NSNotification *)notification { [textView updateInsetAndForceLayout:YES]; }
- (void)postToggleToolbar:(NSNumber *)visible { [self setDualFieldIsVisible:[visible boolValue]]; }

#pragma mark color scheme methods
    
    - (IBAction)setBWColorScheme:(id)sender{
        userScheme=0;
        [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
        
        [self setForegrndColor:[[NSColor colorWithCalibratedWhite:0.02f alpha:1.0f]colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
        [self setBackgrndColor:[[NSColor colorWithCalibratedWhite:0.98f alpha:1.0f]colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
        NSMenu *mainM = [NSApp mainMenu];
        NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
        mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
        viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
        [[mainM itemAtIndex:0] setState:1];
        [[mainM itemAtIndex:1] setState:0];
        [[mainM itemAtIndex:2] setState:0];
        
        [[viewM  itemAtIndex:0] setState:1];
        [[viewM  itemAtIndex:1] setState:0];
        [[viewM  itemAtIndex:2] setState:0];
        [self updateColorScheme];
    }
    
    - (IBAction)setLCColorScheme:(id)sender{
        userScheme=1;
        [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];

        [self setForegrndColor:[NSColor colorWithCalibratedRed:0.2430 green:0.2430 blue:0.2430 alpha:1.0]];
        
        [self setBackgrndColor:[NSColor colorWithCalibratedRed:0.902 green:0.902 blue:0.902 alpha:1.0]];
        NSMenu *mainM = [NSApp mainMenu];
        NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
        mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
        viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
        [[mainM itemAtIndex:0] setState:0];
        [[mainM itemAtIndex:1] setState:1];
        [[mainM itemAtIndex:2] setState:0];
        
        [[viewM  itemAtIndex:0] setState:0];
        [[viewM  itemAtIndex:1] setState:1];
        [[viewM  itemAtIndex:2] setState:0];
        [self updateColorScheme];
    }
    
    - (IBAction)setUserColorScheme:(id)sender{
        userScheme=2;
        [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
        NSMenu *mainM = [NSApp mainMenu];
        NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
        mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
        viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
        [[mainM itemAtIndex:0] setState:0];
        [[mainM itemAtIndex:1] setState:0];
        [[mainM itemAtIndex:2] setState:1];
        
        [[viewM  itemAtIndex:0] setState:0];
        [[viewM  itemAtIndex:1] setState:0];
        [[viewM  itemAtIndex:2] setState:1];
        [self browserAppearanceChanged];
    }
    
- (void)updateColorScheme{
    [mainView setBackgroundColor:[NSColor windowBackgroundColor]];
    [notesTableView setGridColor:[NSColor gridColor]];
    [notesTableView setBackgroundColor:[NSColor textBackgroundColor]];
    [textView setBackgroundColor:backgrndColor];
    [textView updateTextColors];
    if (currentNote) [self refreshSearchHighlights];
    [splitView setNeedsDisplay:YES];
    
}

    - (void)setBackgrndColor:(NSColor *)inColor{
        if (backgrndColor) {
            [backgrndColor release];
        }
        backgrndColor = [inColor retain];
    }
    
    - (void)setForegrndColor:(NSColor *)inColor{
        if (foregrndColor) {
            [foregrndColor release];
        }
        foregrndColor = [inColor retain];
    }
    
    - (NSColor *)backgrndColor{
        if (!backgrndColor) {
            NSColor *theColor;
            if (!userScheme) {
                userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
            }
            if (userScheme==0) {
                theColor = [NSColor colorWithCalibratedRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
            }else if (userScheme==1) {
                theColor = [NSColor colorWithCalibratedRed:0.874f green:0.874f blue:0.874f alpha:1.0f];
            }else if (userScheme==2) {
                theColor = [self usesDarkUserColorScheme] ? [prefsController darkBackgroundTextColor] : [prefsController backgroundTextColor];
            }else{
                theColor =  [NSColor whiteColor];
            }
            [self setBackgrndColor:theColor];
            
            return theColor;
        }else {
            return backgrndColor;
        }
        
    }
    
    - (NSColor *)foregrndColor{
        if (!foregrndColor) {
            NSColor *theColor = [NSColor blackColor];
            if (!userScheme) {
                userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
            }            
            if (userScheme==0) {
                theColor = [NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:1.0f];
            }else if (userScheme==1) {
                theColor = [NSColor colorWithCalibratedRed:0.142f green:0.142f blue:0.142f alpha:1.0f];
            }else if (userScheme==2) {
                theColor = [self usesDarkUserColorScheme] ? [prefsController darkForegroundTextColor] : [prefsController foregroundTextColor];
            }
            [self setForegrndColor:theColor];
            return theColor;
        }else {
            return foregrndColor;
        }
        
    }
    
#pragma mark control/opt key hold down to pop word count/preview window
    
    - (void)updateWordCount:(BOOL)doIt{
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NVNoteWordCountDidChangeNotification object:nil];
        [editingSession setWordCountRequested:doIt forTextView:textView];
        if (!doIt) return;
        if (editingSession) [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(sourceWordCountDidChange:) name:NVNoteWordCountDidChangeNotification object:editingSession];
        NSUInteger theCount = 0;
        // A shared session computes this once for all interested windows. Do
        // not leave the previous note's count visible while its replacement is pending.
        BOOL current = [editingSession getWordCount:&theCount];
        NSString *label = current && theCount ? [NSString stringWithFormat:@"%lu words", (unsigned long)theCount] : @"";
        if (![[wordCounter stringValue] isEqualToString:label]) [wordCounter setStringValue:label];
    }

    - (void)sourceWordCountDidChange:(NSNotification *)notification {
        if ([notification object] == editingSession) [self updateWordCount:![wordCounter isHidden]];
    }
    
    - (void)popWordCount:(BOOL)showIt{
        NSUInteger curEv=[[NSApp currentEvent] type];
        if ((curEv==NSFlagsChanged)||(curEv==NSMouseMoved)||(curEv==NSMouseEntered)||(curEv==NSMouseExited)||(curEv==NSScrollWheel)){
            if (showIt) {
                if (([wordCounter isHidden])&&([prefsController showWordCount])) {
                    [self updateWordCount:YES];
                    [wordCounter setHidden:NO];
                    popped=1;
                    [self layoutNoteHeader];
                }
            }else {
                if ((![wordCounter isHidden])&&([prefsController showWordCount])) {
                    [wordCounter setHidden:YES];
                    [wordCounter setStringValue:@""];
                    [self updateWordCount:NO];
                    popped=0;
                    [self layoutNoteHeader];
                }
            }
        }
    }
    
    - (IBAction)toggleWordCount:(id)sender {
        [prefsController setShowWordCount:![prefsController showWordCount]];
    }

    - (void)flagsChanged:(NSEvent *)theEvent{
        if ((ModFlagger==0)&&(popped==0)) {            
            NSUInteger flags=[theEvent modifierFlags];
            if (((flags&NSDeviceIndependentModifierFlagsMask)==(flags&NSAlternateKeyMask))&&((flags&NSDeviceIndependentModifierFlagsMask)>0)) { //only option key down
                ModFlagger = 1;
                modifierTimer = [[NSTimer scheduledTimerWithTimeInterval:1.2
                                                                  target:self
                                                                selector:@selector(updateModifier:)
                                                                userInfo:@"option"
                                                                 repeats:NO] retain];
                return;

            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    }
    
    - (void)updateModifier:(NSTimer*)theTimer{
        if ([theTimer isValid]) {
            if((ModFlagger>0)&&(popped==0)){
                if ([[theTimer userInfo] isEqualToString:@"option"]) {
                    [self popWordCount:YES];
                    popped=1;

                }
            }
            [theTimer invalidate];
        }
    }
    
    - (void)resetModTimers:(NSNotification *)notification{
        
        
        if ((ModFlagger>0)||(popped>0)) {
            ModFlagger = 0;
            if (modifierTimer){
                if ([modifierTimer isValid]) {
                    [modifierTimer invalidate];
                }
                modifierTimer = nil;
                [modifierTimer release];
            }
            if (popped==1) {
                [self performSelector:@selector(popWordCount:) withObject:NO afterDelay:0.1];

            }
            popped=0;
        }
    }
    
    
    - (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
        return nil; // AppKit supplies and configures the native field editor.
    }

    - (void)refreshNotesList
    {
        [notesTableView setNeedsDisplay:YES];
    }
    
    
    
#pragma mark toggleDock
    - (void)togDockIcon:(NSNotification *)notification{
        
        [NSApp hide:self];
        BOOL showIt=[[notification object]boolValue];
        if (showIt) {
            [self performSelectorOnMainThread:@selector(showDockIcon) withObject:nil waitUntilDone:NO];
        }else {
            [self performSelectorOnMainThread:@selector(hideDockIconAfterDelay) withObject:nil waitUntilDone:NO];
            
        }
    }
    
    - (void)showDockIcon{
        if (IsLionOrLater) {
            ProcessSerialNumber psn = { 0, kCurrentProcess };
            OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToForegroundApplication);
            if( returnCode != 0) {
                NSLog(@"Could not bring the application to front. Error %d", returnCode);
            }

        }else{
            enum {NSApplicationActivationPolicyRegular};
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
              [self performSelector:@selector(reActivate:) withObject:self afterDelay:0.16];
    }

    - (void)hideDockIcon{
        //    id fullPath = [[NSBundle mainBundle] executablePath];
        //    NSArray *arg = [NSArray arrayWithObjects:nil];
        //    [NSTask launchedTaskWithLaunchPath:fullPath arguments:arg];
        //    [NSApp terminate:sender];
        if (IsLionOrLater) {
            ProcessSerialNumber psn = { 0, kCurrentProcess };
            OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToUIElementApplication);
            if( returnCode != 0) {
                NSLog(@"Could not bring the application to front. Error %d", returnCode);
            }
            if (!statusItem) {
                [self setUpStatusBarItem];
            }
            
            [self performSelector:@selector(reActivate:) withObject:self afterDelay:0.36];
        }else{
//            NSLog(@"hiding dock incon in snow leopard");
            id fullPath = [[NSBundle mainBundle] executablePath];
//            NSArray *arg = [NSArray arrayWithObjects:nil];
            [NSTask launchedTaskWithLaunchPath:fullPath arguments:@[]];
            [NSApp terminate:self];
        }
        
    }
    
    - (void)reActivate:(id)sender{
        [NSApp activateIgnoringOtherApps:YES];
    }
    
    - (void)hideDockIconAfterDelay{
        
        [self performSelector:@selector(hideDockIcon) withObject:nil afterDelay:0.22];
    }



- (IBAction)statusItemAction:(id)sender{

    NSEvent *curEv=[NSApp currentEvent];
    if ((curEv.type==NSEventTypeRightMouseUp)||((NSEventModifierFlagControl&curEv.modifierFlags)!=0)) {
        [statusItem popUpStatusItemMenu:statBarMenu];
        //        NSPoint og=NSMakePoint(statusItem.button.frame.origin.x, 27.f);//NSMaxY(statusItem.button.frame));
        //        [self.statusMenu popUpMenuPositioningItem:nil atLocation:og inView:statusItem.button];
    }else{
        [self toggleNVActivation:sender];
    }
}


- (void)setUpStatusBarItem{

    NSImage *statusIcon=[NSImage imageNamed:@"nvMenuDark"];
    [statusIcon setSize:NSMakeSize(16.0, 16.0)];
    [statusIcon setTemplate:YES];
    statusItem =[[NSStatusBar systemStatusBar] statusItemWithLength:24.f];
    if (IsYosemiteOrLater) {
        statusItem.button.image=statusIcon;
        statusItem.button.target=self;
        statusItem.button.action=@selector(statusItemAction:);
        [statusItem.button sendActionOn:NSEventMaskLeftMouseUp|NSEventMaskRightMouseUp];
    }else{
        statusItem.image=statusIcon;
        statusItem.target=self;
        statusItem.action=@selector(statusItemAction:);
         [statusItem sendActionOn:NSEventMaskLeftMouseUp|NSEventMaskRightMouseUp];
        statusItem.highlightMode=YES;
    }
    [statusItem retain];

}

    - (void)toggleStatusItem:(NSNotification *)notification{
        if (!statusItem) {
            [self setUpStatusBarItem];
        }else{
            [[NSStatusBar systemStatusBar]removeStatusItem:statusItem];
            statusItem=nil;
        }
    }
    
    
#pragma mark NSPREDICATE TO FIND MARKDOWN REFERENCE LINKS
//    - (IBAction)testThing:(id)sender{
        //    NSString *testString=@"not []http://sdfas as\n\not [][]\n not [](http://)\n     a   [a ref]: http://nytimes.com \n squirels [another ref]: http://google.com    \n http://squarshit \n how's tthat http his lorem ipsum";
        //    
        //    NSArray *foundLinks=[self referenceLinksInString:testString];
        //    if (foundLinks&&([foundLinks count]>0)) {
        //        NSLog(@"found'em:%@",[foundLinks description]);
        //    }else{
        //        NSLog(@"didn't find shit");
        //    }
//    }
    
    - (NSArray *)referenceLinksInString:(NSString *)contentString{    
        NSString *wildString = @"*[*]:*http*"; //This is where you define your match string.    
        NSPredicate *matchPred = [NSPredicate predicateWithFormat:@"SELF LIKE[cd] %@", wildString]; 
        /*
         Breaking it down:
         SELF is the string your testing
         [cd] makes the test case insensitive
         LIKE is one of the predicate search possiblities. It's NOT regex, but lets you use wildcards '?' for one character and '*' for any number of characters
         MATCH (not used) is what you would use for Regex. And you'd set it up similiar to LIKE. I don't really know regex, and I can't quite get it to work. But that might be because I don't know regex. 
         %@ you need to pass in the search string like this, rather than just embedding it in the format string. so DON'T USE something like [NSPredicate predicateWithFormat:@"SELF LIKE[cd] *[*]:*http*"]
         */
        
        NSMutableArray *referenceLinks=[NSMutableArray new];
        
        //enumerateLinesUsing block seems like a good way to go line by line thru the note and test each line for the regex match of a reference link. Downside is that it uses blocks so requires 10.6+. Let's get it to work and then we can figure out a Leopard friendly way of doing this; which I don't think will be a problem (famous last words).
        [contentString enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) { 
            if([matchPred evaluateWithObject:line]){
                //            NSLog(@"%@ matched",line);
                NSString *theRef=line;
                //theRef=[line substring...]  here you want to parse out and get just the name of the reference link we'd want to offer up to the user in the autocomplete
                //and maybe trim out whitespace
                theRef = [theRef stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                //check to make sure its not empty
                if(![theRef isEqualToString:@""]){
                    [referenceLinks addObject:theRef];
                } 		
            }	
        }];
        //create an immutable array safe for returning
        NSArray *returnArray=[NSArray array];
        //see if we found anything
        if(referenceLinks&&([referenceLinks count]>0))
        {
            returnArray=[NSArray arrayWithArray:referenceLinks];
        }
        [referenceLinks release];
        return returnArray;
    }
    
    @end
