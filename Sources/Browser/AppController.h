/* AppController */

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

#import "NotationController.h"
#import "NotesTableView.h"
//#import "Spaces.h"

@class NVBrowserSession, NVNoteEditingSession;
@class LinkingEditor;
@class EmptyView;
@class NotesTableView;
@class GlobalPrefs;
@class PrefsWindowController;
@class DualField;




@class TagEditingManager;

@class PreviewController;
@class WordCountToken;
//@class AugmentedScrollView;
@class ETContentView;
@class ETScrollView;
@class ETNoteScrollView;

@interface AppController : NSWindowController
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
<NSToolbarDelegate, NSToolbarItemValidation, NSTableViewDelegate, NSWindowDelegate, NSSearchFieldDelegate, NSTextViewDelegate>
#endif
{
    BOOL applicationOwner, awakenedViews, browserHorizontalLayout, reloadingNotesList;
    NSInteger ModFlagger, popped;
    NSArray *windowObjects;
    NSMutableDictionary *noteSelections;
    NSMutableDictionary *noteBodyStates;
    NVNoteEditingSession *editingSession;
    NSTextStorage *emptyEditorStorage;
    NSString *browserIdentifier;
	IBOutlet NSMenuItem *fsMenuItem;
    BOOL isAutocompleting;
    BOOL wasDeleting;
    IBOutlet ETContentView *mainView;
    NSStatusItem *statusItem;
	IBOutlet NSMenu *statBarMenu;
	TagEditingManager *tagEditor;
	NSColor *backgrndColor;
	NSColor *foregrndColor;
	NSInteger userScheme;
	NSString *noteFormat;
	NSTimer *modifierTimer;
	IBOutlet WordCountToken *wordCounter;
    IBOutlet DualField *field;
    NSSplitViewController *browserSplitController;
    NSSplitView *splitView;
    NSView *notesSubview, *splitSubview;
    NSTextField *noteTitleField, *noteTagsField;
    NSButton *createNoteButton;
    NSSegmentedControl *bodyModeControl;
    NSPopUpButton *sourceSyntaxControl, *viewerTypeControl;
    NSString *selectedViewerIdentifier;
    BOOL viewingNote;
    NSUInteger viewerGeneration;
    NSUInteger presentationStateGeneration;
    NoteObject *metadataNote;
    NSTextField *metadataControl;
    NSString *metadataOriginalValue;
    NSToolbarItem *syncToolbarItem;
    BOOL committingMetadata, searchHasPendingComposition;
    CGFloat pendingListHeight;
    IBOutlet ETScrollView *notesScrollView;
    IBOutlet ETNoteScrollView *textScrollView;
    IBOutlet NotesTableView *notesTableView;
    IBOutlet LinkingEditor *textView;
	IBOutlet EmptyView *editorStatusView;
    IBOutlet NSWindow *window;
	IBOutlet NSPanel *syncWaitPanel;
	IBOutlet NSProgressIndicator *syncWaitSpinner;
	NSToolbar *toolbar;
	NSToolbarItem *dualFieldItem;
	
	BOOL waitedForUncommittedChanges;
	
	
	NSString *URLToInterpretOnLaunch;
	NSMutableArray *pathsToOpenOnLaunch;
	
    NSUndoManager *windowUndoManager;
    PrefsWindowController *prefsWindowController;
    GlobalPrefs *prefsController;
    NotationController *notationController;
	
//	SpaceSwitchingContext spaceSwitchCtx;
	ViewLocationContext listUpdateViewCtx;
	BOOL isFilteringFromTyping, typedStringIsCached;
	BOOL isCreatingANote;
	NSString *typedString;
    BOOL isEditing;
	
	NoteObject *currentNote;
	NSArray *savedSelectedNotes;
	BOOL hasLaunched;
    PreviewController *previewController;
}

@property(readwrite)BOOL isEditing;

void outletObjectAwoke(id sender);

- (void)application:(NSApplication *)sender openFiles:(NSArray *)files;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (BOOL)horizontalLayout;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)syncSessionsChangedVisibleStatus:(NSNotification *)notification;
- (void)titleUpdatedForNote:(NoteObject *)note;
- (void)notation:(NotationController *)notation revealNotes:(NSArray *)notes;
- (void)setNotationController:(NotationController*)newNotation;
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;

- (void)setupViewsAfterAppAwakened;
- (void)runDelayedUIActionsAfterLaunch;
- (void)updateNoteMenus;

- (IBAction)makeActiveAndShowWindow:(id)sender;
- (IBAction)renameNote:(id)sender;
- (IBAction)deleteNote:(id)sender;
- (IBAction)copyNoteLink:(id)sender;
- (IBAction)exportNote:(id)sender;
- (IBAction)revealNote:(id)sender;
- (IBAction)editNoteExternally:(id)sender;
- (IBAction)printNote:(id)sender;
- (IBAction)tagNote:(id)sender;
- (IBAction)importNotes:(id)sender;
- (IBAction)switchViewLayout:(id)sender;

- (IBAction)fieldAction:(id)sender;
- (NoteObject*)createNoteIfNecessary;
- (void)searchForString:(NSString*)string;
- (NSUInteger)revealNote:(NoteObject*)note options:(NSUInteger)opts;
- (BOOL)displayContentsForNoteAtIndex:(NSUInteger)noteIndex;
- (void)processChangedSelectionForTable:(NSTableView*)table;
- (void)setEmptyViewState:(BOOL)state;
- (void)cancelOperation:(id)sender;
- (void)_setCurrentNote:(NoteObject*)aNote;
//- (void)_expandToolbar;
//- (void)_collapseToolbar;
- (void)_forceRegeneratePreviewsForTitleColumn;
- (NoteObject*)selectedNoteObject;

- (void)restoreListStateUsingPreferences;

- (void)_finishSyncWait;
- (IBAction)syncWaitQuit:(id)sender;

- (void)setTableAllowsMultipleSelection;

- (NSString*)fieldSearchString;
- (void)cacheTypedStringIfNecessary:(NSString*)aString;
- (NSString*)typedString;

- (IBAction)showHelpDocument:(id)sender;
- (IBAction)showPreferencesWindow:(id)sender;
- (IBAction)toggleNVActivation:(id)sender;
- (IBAction)bringFocusToControlField:(id)sender;
- (NSWindow*)window;

//elasticwork
//- (void)setIsEditing:(BOOL)inBool inCell:(NSCell *)theCell;
//- (void)focusOnCtrlFld:(id)sender;
- (NSMenu *)statBarMenu;
- (NSArray *)commonLabelsForNotesAtIndexes:(NSIndexSet *)selDexes;
- (IBAction)multiTag:(id)sender;
- (void)releaseTagEditor:(NSNotification *)note;
- (void)setDualFieldInToolbar;
- (void)setDualFieldIsVisible:(BOOL)isVis;
//- (void)hideDualFieldView;
//- (void)showDualFieldView;
- (BOOL)dualFieldIsVisible;
- (IBAction)toggleCollapse:(id)sender;
- (IBAction)switchFullScreen:(id)sender;
- (BOOL)isInFullScreen;
//- (IBAction)openFileInEditor:(id)sender;
//- (NSArray *)getTxtAppList;
//- (void)updateTextApp:(id)sender;
- (IBAction)setBWColorScheme:(id)sender;
- (IBAction)setLCColorScheme:(id)sender;
- (IBAction)setUserColorScheme:(id)sender;
- (void)updateColorScheme;
- (void)setBackgrndColor:(NSColor *)inColor;
- (void)setForegrndColor:(NSColor *)inColor;
- (NSColor *)backgrndColor;
- (NSColor *)foregrndColor;
- (void)updateWordCount:(BOOL)doIt;
- (void)resetModTimers:(NSNotification *)notification;
- (IBAction)toggleWordCount:(id)sender;
- (void)popWordCount:(BOOL)showIt;
- (IBAction)previewNoteWithMarked:(id)sender;
- (BOOL)setNoteIfNecessary;
- (void)updateRTL;
- (void)refreshNotesList;
- (void)focusControlField:(id)sender activate:(BOOL)shouldActivate;
- (void)updateModifier:(NSTimer*)theTimer;
#pragma mark toggling dock icon
- (void)togDockIcon:(NSNotification *)notification;
- (void)hideDockIconAfterDelay;
- (void)hideDockIcon;
- (void)showDockIcon;
- (void)reActivate:(id)sender;
- (void)toggleStatusItem:(NSNotification *)notification;
- (void)setUpStatusBarItem;
- (NSArray *)referenceLinksInString:(NSString *)contentString;
//- (IBAction)testThing:(id)sender;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
- (void)postToggleToolbar:(NSNumber *)boolNum;
#endif

@end

@interface AppController (Preview)
- (void)ensurePreviewIsVisible;
- (IBAction)togglePreview:(id)sender;
- (IBAction)toggleSourceView:(id)sender;
- (IBAction)savePreview:(id)sender;
- (IBAction)printPreview:(id)sender;
- (void)postTextUpdate;
- (IBAction)selectPreviewMode:(id)sender;
- (BOOL)isViewingNote;
- (NSString *)selectedViewerIdentifier;
- (void)setViewingNote:(BOOL)viewing;
- (void)setupBodyPresentation;
- (void)updateBodyPresentation;
- (void)updateViewerSnapshot;
- (void)captureBodyPresentation;
- (void)restoreSourceScroll;
- (void)discardViewer;
- (void)focusNoteBody;
- (void)sourceSyntaxChanged:(NSNotification *)notification;
- (IBAction)selectBodyMode:(id)sender;
- (IBAction)selectSourceSyntax:(id)sender;
- (IBAction)performFindPanelAction:(id)sender;
@end

@interface AppController (MultipleWindows)
- (NVBrowserSession *)browserSession;
- (NotationController *)sharedNotationController;
- (void)attachLibrary:(NotationController *)library;
- (void)retainWindowObjects:(NSArray *)objects;
- (void)prepareAdditionalWindow;
- (void)finishEditing;
- (void)refreshEditorForNote:(NoteObject *)note;
- (NSDictionary *)browserWindowState;
- (void)restoreBrowserWindowState:(NSDictionary *)state;
- (NSString *)browserIdentifier;
- (id)tablePreviewForNote:(NoteObject *)note;
- (void)unregisterBrowserObservers;
@end

@interface AppController (BrowserUI)
- (void)setupBrowserContent;
- (void)updateNoteHeader;
- (void)commitNoteMetadata;
- (void)beginNoteMetadataEditing:(NSTextField *)control;
- (void)cancelNoteMetadataEditing;
- (void)updateSearchAffordance;
- (void)updateSyncToolbarItem;
- (CGFloat)notesListHeight;
- (void)setNotesListHeight:(CGFloat)height;
- (void)restoreNotesListHeight;
- (IBAction)newNote:(id)sender;
- (IBAction)createNoteFromSearch:(id)sender;
- (IBAction)showNoteActions:(id)sender;
- (IBAction)showSyncStatus:(id)sender;
- (IBAction)applyNoteMetadata:(id)sender;
- (IBAction)setSystemColorScheme:(id)sender;
- (void)browserAppearanceChanged;
@end
