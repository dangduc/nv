#import "AppController.h"
#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "DualField.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"
#import "ETContentView.h"
#import "ETScrollView.h"
#import "ETNoteScrollView.h"
#import "EmptyView.h"
#import "NSString_NV.h"
#import "WordCountToken.h"
#import "PreviewController.h"

// Receive appearance changes on the view whose window supplies the appearance.
@interface NVBrowserContentView : NSView
@end
@implementation NVBrowserContentView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [[[self window] windowController] browserAppearanceChanged];
}
@end

static NSImage *BrowserSymbol(NSString *name, NSString *fallback, NSString *label) {
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:label];
        if (image) return image;
    }
    return [NSImage imageNamed:fallback];
}

@implementation AppController (BrowserUI)
- (void)setupBrowserContent {
    browserHorizontalLayout = NO;
    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    browserSplitController = [[NSSplitViewController alloc] init];
    splitView = [browserSplitController splitView];
    [splitView setVertical:NO];
    [splitView setDividerStyle:NSSplitViewDividerStyleThin];
    [splitView setFrame:[mainView bounds]];
    [splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    NSViewController *listController = [[[NSViewController alloc] init] autorelease];
    NSViewController *editorController = [[[NSViewController alloc] init] autorelease];
    notesSubview = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([mainView bounds]), 180)] autorelease];
    splitSubview = [[[NVBrowserContentView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([mainView bounds]), 400)] autorelease];
    [notesSubview setTranslatesAutoresizingMaskIntoConstraints:NO];
    [splitSubview setTranslatesAutoresizingMaskIntoConstraints:NO];
    [listController setView:notesSubview];
    [editorController setView:splitSubview];
    NSSplitViewItem *listItem = [NSSplitViewItem splitViewItemWithViewController:listController];
    [listItem setMinimumThickness:84];
    [listItem setCanCollapse:NO];
    [listItem setCollapseBehavior:NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView];
    [listItem setHoldingPriority:251];
    NSSplitViewItem *editorItem = [NSSplitViewItem splitViewItemWithViewController:editorController];
    [editorItem setMinimumThickness:212];
    [editorItem setCanCollapse:NO];
    [browserSplitController addSplitViewItem:listItem];
    [browserSplitController addSplitViewItem:editorItem];
    // NSSplitViewController's root view can wrap its split view. Constrain the
    // controller's root, leaving AppKit in charge of the internal hierarchy.
    NSView *content = [browserSplitController view];
    [content setTranslatesAutoresizingMaskIntoConstraints:NO];
    [mainView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [[content leadingAnchor] constraintEqualToAnchor:[mainView leadingAnchor]],
        [[content trailingAnchor] constraintEqualToAnchor:[mainView trailingAnchor]],
        [[content topAnchor] constraintEqualToAnchor:[mainView topAnchor]],
        [[content bottomAnchor] constraintEqualToAnchor:[mainView bottomAnchor]],
        [[mainView widthAnchor] constraintGreaterThanOrEqualToConstant:480],
        [[mainView heightAnchor] constraintGreaterThanOrEqualToConstant:320]
    ]];
    [window setContentMinSize:NSMakeSize(480, 320)];

    [notesScrollView setFrame:[notesSubview bounds]];
    [notesScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [notesScrollView setBackgroundColor:[NSColor textBackgroundColor]];
    [[notesScrollView contentView] setBackgroundColor:[NSColor textBackgroundColor]];
    [notesSubview addSubview:notesScrollView];
    createNoteButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 60, NSWidth([notesSubview bounds]) - 24, 32)];
    [createNoteButton setBezelStyle:NSBezelStyleRounded];
    [createNoteButton setTarget:self];
    [createNoteButton setAction:@selector(createNoteFromSearch:)];
    [createNoteButton setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
    [createNoteButton setHidden:YES];
    [notesSubview addSubview:createNoteButton];

    const CGFloat headerHeight = 96;
    NSRect bounds = [splitSubview bounds];
    [textScrollView setFrame:NSMakeRect(0, 0, NSWidth(bounds), NSHeight(bounds) - headerHeight)];
    [textScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [splitSubview addSubview:textScrollView];
    [editorStatusView setFrame:[textScrollView frame]];
    [editorStatusView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [splitSubview addSubview:editorStatusView];

    noteTitleField = [[NSTextField alloc] initWithFrame:NSMakeRect(14, NSHeight(bounds) - 32, NSWidth(bounds) - 150, 24)];
    noteTagsField = [[NSTextField alloc] initWithFrame:NSMakeRect(14, NSHeight(bounds) - 57, NSWidth(bounds) - 28, 20)];
    for (NSTextField *control in @[noteTitleField, noteTagsField]) {
        [control setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [control setBezeled:NO];
        [control setDrawsBackground:NO];
        [control setTextColor:[NSColor labelColor]];
        [control setDelegate:self];
        [control setTarget:self];
        [control setAction:@selector(applyNoteMetadata:)];
        [[control cell] setScrollable:YES];
        [splitSubview addSubview:control];
    }
    [noteTitleField setFont:[NSFont boldSystemFontOfSize:15]];
    [noteTitleField setPlaceholderString:NSLocalizedString(@"Note title", nil)];
    [noteTitleField setAccessibilityLabel:NSLocalizedString(@"Note title", nil)];
    [noteTagsField setFont:[NSFont systemFontOfSize:12]];
    [noteTagsField setTextColor:[NSColor secondaryLabelColor]];
    [noteTagsField setPlaceholderString:NSLocalizedString(@"Add tags, separated by commas", nil)];
    [noteTagsField setAccessibilityLabel:NSLocalizedString(@"Note tags", nil)];
    [wordCounter retain];
    [wordCounter removeFromSuperview];
    [wordCounter setFrame:NSMakeRect(NSWidth(bounds) - 130, NSHeight(bounds) - 32, 116, 24)];
    [wordCounter setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [wordCounter setEditable:NO];
    [wordCounter setSelectable:NO];
    [wordCounter setBezeled:NO];
    [wordCounter setDrawsBackground:NO];
    [wordCounter setFont:[NSFont systemFontOfSize:12]];
    [wordCounter setTextColor:[NSColor secondaryLabelColor]];
    [wordCounter setAccessibilityLabel:NSLocalizedString(@"Word count", nil)];
    [wordCounter setHidden:[prefsController showWordCount]];
    [splitSubview addSubview:wordCounter];
    [wordCounter release];
    [self setupBodyPresentation];
    [prefsController registerWithTarget:self forChangesInSettings:
        @selector(setShowTitleInTopSection:sender:), @selector(setShowTagsInTopSection:sender:),
        @selector(setShowBodyControlsInTopSection:sender:), @selector(setShowNotesList:sender:),
        @selector(setShowWordCount:), nil];
    pendingListHeight = NSHeight([mainView bounds]) / 3.0;
    [self updateNotesListVisibility];
    [self performSelector:@selector(restoreNotesListHeight) withObject:nil afterDelay:0];
}

- (CGFloat)notesListHeight {
    return [[[browserSplitController splitViewItems] firstObject] isCollapsed] ? pendingListHeight : NSHeight([notesSubview frame]);
}
- (void)restoreNotesListHeight { [self setNotesListHeight:pendingListHeight]; }
- (void)setNotesListHeight:(CGFloat)height {
    if (!isfinite(height)) return;
    [mainView layoutSubtreeIfNeeded];
    CGFloat maximum = MAX(84, NSHeight([splitView bounds]) - 212 - [splitView dividerThickness]);
    pendingListHeight = MIN(maximum, MAX(84, height));
    if ([[[browserSplitController splitViewItems] firstObject] isCollapsed]) return;
    [splitView setPosition:pendingListHeight ofDividerAtIndex:0];
    [mainView layoutSubtreeIfNeeded];
}

- (void)updateNotesListVisibility {
    NSSplitViewItem *item = [[browserSplitController splitViewItems] firstObject];
    BOOL show = [prefsController showNotesList];
    if (!item || [item isCollapsed] == !show) return;
    if (!show) {
        pendingListHeight = [self notesListHeight];
        NSResponder *responder = [window firstResponder];
        if ([responder isKindOfClass:[NSView class]] && [(NSView *)responder isDescendantOf:notesSubview]) {
            if (currentNote) [self focusNoteBody];
            else [window makeFirstResponder:field];
        }
    }
    [item setCollapsed:!show];
    [mainView layoutSubtreeIfNeeded];
    if (show) [self restoreNotesListHeight];
}
- (IBAction)toggleNotesList:(id)sender {
    [prefsController setShowNotesList:![prefsController showNotesList] sender:nil];
}

- (void)updateNoteHeader {
    if (metadataControl != noteTitleField) [noteTitleField setStringValue:currentNote ? titleOfNote(currentNote) : @""];
    if (metadataControl != noteTagsField) [noteTagsField setStringValue:currentNote ? labelsOfNote(currentNote) ?: @"" : @""];
    [noteTitleField setEnabled:currentNote != nil];
    [noteTagsField setEnabled:currentNote != nil];
    [window setTitle:currentNote ? titleOfNote(currentNote) : @"nvALT"];
    [toolbar validateVisibleItems];
}

- (void)layoutNoteHeader {
    if (!noteTitleField || !bodyModeControl) return;
    BOOL showTitle = [prefsController showTitleInTopSection];
    BOOL showTags = [prefsController showTagsInTopSection];
    BOOL showControls = [prefsController showBodyControlsInTopSection];
    BOOL hidingMetadata = (metadataControl == noteTitleField && !showTitle) ||
        (metadataControl == noteTagsField && !showTags);
    NSResponder *responder = [window firstResponder];
    BOOL hidingFocusedControl = (!showTitle && (responder == noteTitleField || [noteTitleField currentEditor])) ||
        (!showTags && (responder == noteTagsField || [noteTagsField currentEditor])) ||
        (!showControls && (responder == bodyModeControl || responder == sourceSyntaxControl || responder == viewerTypeControl));
    // Finish the field editor before its control disappears, including edits in
    // another browser that receives this shared preference change.
    if (hidingMetadata) [self commitNoteMetadata];
    if (hidingMetadata || hidingFocusedControl) [self focusNoteBody];

    [noteTitleField setHidden:!showTitle];
    [noteTagsField setHidden:!showTags];
    [bodyModeControl setHidden:!showControls];
    [sourceSyntaxControl setHidden:!showControls || viewingNote];
    [viewerTypeControl setHidden:!showControls || !viewingNote];

    NSRect bounds = [splitSubview bounds];
    CGFloat width = NSWidth(bounds), height = NSHeight(bounds), used = 8;
    BOOL hasRow = showTitle || ![wordCounter isHidden];
    if (hasRow) {
        used += 24;
        [noteTitleField setFrame:NSMakeRect(14, height - used, width - ([wordCounter isHidden] ? 28 : 150), 24)];
        [wordCounter setFrame:NSMakeRect(width - 130, height - used, 116, 24)];
    }
    if (showTags) {
        used += (hasRow ? 5 : 0) + 20;
        [noteTagsField setFrame:NSMakeRect(14, height - used, width - 28, 20)];
        hasRow = YES;
    }
    if (showControls) {
        used += (hasRow ? 7 : 0) + 24;
        [bodyModeControl setFrameOrigin:NSMakePoint(14, height - used)];
        [sourceSyntaxControl setFrameOrigin:NSMakePoint(178, height - used)];
        [viewerTypeControl setFrame:[sourceSyntaxControl frame]];
        hasRow = YES;
    }
    CGFloat headerHeight = hasRow ? used + 8 : 0;
    NSRect bodyFrame = NSMakeRect(0, 0, width, MAX(0, height - headerHeight));
    [textScrollView setFrame:bodyFrame];
    [editorStatusView setFrame:bodyFrame];
    [[previewController view] setFrame:bodyFrame];
    NSView *body = viewingNote && currentNote ? [previewController webView] : (NSView *)textView;
    [noteTitleField setNextKeyView:showTags ? noteTagsField : body];
    [noteTagsField setNextKeyView:body];
    [bodyModeControl setNextKeyView:viewingNote ? viewerTypeControl : sourceSyntaxControl];
    [sourceSyntaxControl setNextKeyView:body];
    [viewerTypeControl setNextKeyView:body];
    [splitSubview setNeedsDisplay:YES];
}

- (IBAction)toggleTitleInTopSection:(id)sender {
    [prefsController setShowTitleInTopSection:![prefsController showTitleInTopSection] sender:nil];
}
- (IBAction)toggleTagsInTopSection:(id)sender {
    [prefsController setShowTagsInTopSection:![prefsController showTagsInTopSection] sender:nil];
}
- (IBAction)toggleBodyControlsInTopSection:(id)sender {
    [prefsController setShowBodyControlsInTopSection:![prefsController showBodyControlsInTopSection] sender:nil];
}

- (void)beginNoteMetadataEditing:(NSTextField *)control {
    [self commitNoteMetadata];
    if (!currentNote) return;
    metadataNote = [currentNote retain];
    metadataControl = control;
    metadataOriginalValue = [(control == noteTitleField ? titleOfNote(currentNote) : labelsOfNote(currentNote)) copy];
}
- (void)commitNoteMetadata {
    if (!metadataNote || committingMetadata) return;
    committingMetadata = YES;
    NSTextView *editor = (id)[metadataControl currentEditor];
    if ([editor hasMarkedText]) [editor unmarkText];
    [metadataControl validateEditing];
    NoteObject *note = [metadataNote autorelease];
    NSString *value = [[metadataControl stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *oldValue = [metadataOriginalValue autorelease];
    BOOL title = metadataControl == noteTitleField;
    metadataNote = nil; metadataControl = nil; metadataOriginalValue = nil;
    if ([[[self sharedNotationController] allNotes] containsObject:note] && ![value isEqualToString:oldValue ?: @""] && (!title || [value length])) {
        [[NVApplicationController sharedController] setNote:note metadataValue:value isTitle:title];
    }
    committingMetadata = NO;
    [self updateNoteHeader];
}
- (void)cancelNoteMetadataEditing {
    [metadataControl abortEditing];
    [metadataNote release]; metadataNote = nil;
    [metadataOriginalValue release]; metadataOriginalValue = nil;
    metadataControl = nil;
    [self updateNoteHeader];
}
- (IBAction)applyNoteMetadata:(id)sender {
    [self commitNoteMetadata];
    [self focusNoteBody];
}
- (void)updateSearchAffordance {
    NSString *query = [[self browserSession] searchString] ?: @"";
    BOOL canCreate = [query length] && [notesTableView numberOfRows] == 0;
    [createNoteButton setHidden:!canCreate];
    if (canCreate) {
        NSString *label = [NSString stringWithFormat:NSLocalizedString(@"Create “%@” — Return", nil), query];
        [createNoteButton setTitle:label];
        [createNoteButton setToolTip:label];
    }
}
- (IBAction)newNote:(id)sender {
    [self finishEditing];
    [self setViewingNote:NO];
    [notesTableView deselectAll:self];
    [field setStringValue:@""];
    [typedString release]; typedString = [@"" copy]; typedStringIsCached = YES;
    [[self browserSession] filterNotesFromString:@""];
    [self createNoteIfNecessary];
    [self updateNoteHeader];
    if ([prefsController showTitleInTopSection]) [noteTitleField selectText:self];
    else [self focusNoteBody];
}
- (IBAction)createNoteFromSearch:(id)sender {
    [self fieldAction:sender];
}

- (void)setDualFieldInToolbar {
    // Keep the nib outlet alive while moving it out of its legacy wrapper.
    [field retain];
    NSView *wrapper = [field superview];
    [field removeFromSuperview];
    [wrapper removeFromSuperview];
    [field setFrame:NSMakeRect(0, 0, 260, 24)];
    if (@available(macOS 11.0, *)) {
        NSSearchToolbarItem *item = [[NSSearchToolbarItem alloc] initWithItemIdentifier:@"Search"];
        [item setSearchField:field];
        [item setPreferredWidthForSearchField:280];
        dualFieldItem = item;
        [window setToolbarStyle:NSWindowToolbarStyleUnifiedCompact];
    } else {
        dualFieldItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"Search"];
        [dualFieldItem setView:field];
        [dualFieldItem setMinSize:NSMakeSize(140, 24)];
        [dualFieldItem setMaxSize:NSMakeSize(400, 24)];
    }
    [field release];
    [dualFieldItem setLabel:NSLocalizedString(@"Search or Create", nil)];
    [dualFieldItem setPaletteLabel:[dualFieldItem label]];
    [field setDelegate:self];
    // NSSearchField sends actions while typing and when clearing; Return is handled
    // by the field delegate so those actions cannot accidentally create a note.
    [field setTarget:nil];
    [field setAction:NULL];
    toolbar = [[NSToolbar alloc] initWithIdentifier:@"NVBrowserToolbar"];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:YES];
    [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [toolbar setDelegate:self];
    [window setToolbar:toolbar];
    [window setInitialFirstResponder:field];
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)aToolbar {
    return @[@"NewNote", @"Preview", @"More", NSToolbarFlexibleSpaceItemIdentifier, @"Search"];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)aToolbar {
    return @[@"NewNote", @"Preview", @"More", @"Search", NSToolbarSpaceItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)aToolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)inserted {
    if ([identifier isEqual:@"Search"]) return dualFieldItem;
    NSDictionary *spec = @{
        @"NewNote": @[@"New Note", @"square.and.pencil", NSImageNameAddTemplate, @"newNote:"],
        @"Preview": @[@"Preview", @"doc.richtext", NSImageNameQuickLookTemplate, @"togglePreview:"],
        @"More": @[@"Note Actions", @"ellipsis.circle", NSImageNameActionTemplate, @"showNoteActions:"]
    };
    NSArray *values = [spec objectForKey:identifier];
    if (!values) return nil;
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    NSString *label = NSLocalizedString([values objectAtIndex:0], nil);
    [item setLabel:label]; [item setPaletteLabel:label]; [item setToolTip:label];
    [item setImage:BrowserSymbol([values objectAtIndex:1], [values objectAtIndex:2], label)];
    [item setTarget:self]; [item setAction:NSSelectorFromString([values objectAtIndex:3])];
    return item;
}
- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    SEL action = [item action];
    if (action == @selector(togglePreview:)) return currentNote != nil;
    if (action == @selector(showNoteActions:)) return [notesTableView numberOfSelectedRows] > 0;
    return [self sharedNotationController] != nil;
}
- (IBAction)showNoteActions:(id)sender {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:NSLocalizedString(@"Note Actions", nil)] autorelease];
    for (NSArray *spec in @[@[@"Rename", @"renameNote:"], @[@"Tags…", @"tagNote:"], @[@"Copy Note Link", @"copyNoteLink:"], @[@"Export…", @"exportNote:"], @[@"Delete…", @"deleteNote:"]]) {
        NSMenuItem *item = [menu addItemWithTitle:NSLocalizedString(spec[0], nil) action:NSSelectorFromString(spec[1]) keyEquivalent:@""];
        [item setTarget:self];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(14, NSHeight([mainView bounds])) inView:mainView];
}
- (IBAction)setSystemColorScheme:(id)sender {
    userScheme = 3;
    [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
    [self browserAppearanceChanged];
}
- (void)browserAppearanceChanged {
    if (!awakenedViews) return;
    if (userScheme == 3) {
        void (^update)(void) = ^{
            [self setForegrndColor:[[NSColor textColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
            [self setBackgrndColor:[[NSColor textBackgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
            [self updateColorScheme];
        };
        if (@available(macOS 10.14, *)) [[window effectiveAppearance] performAsCurrentDrawingAppearance:update];
        else update();
    }
    [notesTableView setNeedsDisplay:YES];
}
@end
