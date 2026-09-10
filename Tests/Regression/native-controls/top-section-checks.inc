- (NSMenuItem *)nv_itemInMenu:(NSMenu *)menu action:(SEL)action {
    for (NSMenuItem *item in [menu itemArray]) if ([item action] == action) return item;
    return nil;
}

- (void)nv_sendMenuItem:(NSMenuItem *)item {
    Check(item != nil && [item action] != NULL, @"the requested command exists in the application menu");
    [[item menu] update];
    Check([item isEnabled], [NSString stringWithFormat:@"%@ is enabled before native dispatch", [item title]]);
    Check([NSApp sendAction:[item action] to:[item target] from:item],
        [NSString stringWithFormat:@"the application dispatches %@", [item title]]);
    Pump();
    [[window contentView] layoutSubtreeIfNeeded];
}

- (CGFloat)nv_headerHeight {
    [[window contentView] layoutSubtreeIfNeeded];
    return NSHeight([splitSubview bounds]) - NSMaxY([textScrollView frame]);
}

- (void)nv_captureViewControls:(NSString *)name {
    const char *artifacts = getenv("NV_UI_ARTIFACTS");
    if (!artifacts) return;
    [[window contentView] layoutSubtreeIfNeeded]; [window displayIfNeeded]; Pump();
    CGImageRef capture = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
    Check(capture != NULL, @"the desktop captures the View controls window");
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
    CGImageRelease(capture);
    NSString *path = [[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:name];
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
        @"the native view controls screenshot is saved");
}

- (void)nv_checkSyntaxMenu:(NSMenu *)menu selected:(NSString *)identifier enabled:(BOOL)enabled {
    [menu update];
    NSUInteger checked = 0;
    for (NSMenuItem *item in [menu itemArray]) {
        Check([item isEnabled] == enabled, @"syntax choices follow the active note's availability");
        BOOL selected = identifier && [[item representedObject] isEqual:identifier];
        Check([item state] == (selected ? NSControlStateValueOn : NSControlStateValueOff),
            @"each syntax choice reflects the selected note's source syntax");
        if ([item state] == NSControlStateValueOn) checked++;
    }
    Check(checked == (identifier ? 1 : 0), @"Syntax Type has one checked choice only when a note is selected");
}

- (void)nv_checkViewMenuWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    NVApplicationController *app = [NVApplicationController sharedController];
    NotationController *library = [app library];
    [self nv_activateBrowser];
    NSRect fixtureFrame = [window frame]; fixtureFrame.size.width = MAX(780, fixtureFrame.size.width);
    [window setFrame:fixtureFrame display:YES];
    [self searchForString:@""]; [self revealNote:alpha options:0];
    [peer searchForString:@"Beta"]; [peer revealNote:beta options:0];
    [self setViewingNote:NO]; [peer setViewingNote:NO];
    [self nv_focusSearch];
    [self focusNoteBody];
    for (NSUInteger attempt = 0; attempt < 8; attempt++) Pump();
    Check([window firstResponder] == textView, @"the View fixture finishes native Search expansion before header commands");
    [prefsController setShowWordCount:YES]; Pump();
    NSString *originalTitle = [titleOfNote(alpha) copy];
    NSString *originalTags = [labelsOfNote(alpha) copy];
    NSString *originalSource = [[[alpha contentString] string] copy];
    NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
    NSMenuItem *anchor = [self nv_itemInMenu:viewMenu action:@selector(toggleNoteBodyPreviews:)];
    NSMenuItem *title = [self nv_itemInMenu:viewMenu action:@selector(toggleTitleInTopSection:)];
    NSMenuItem *tags = [self nv_itemInMenu:viewMenu action:@selector(toggleTagsInTopSection:)];
    NSMenuItem *controls = [self nv_itemInMenu:viewMenu action:@selector(toggleBodyControlsInTopSection:)];
    NSMenuItem *list = [self nv_itemInMenu:viewMenu action:@selector(toggleNotesList:)];
    NSMenuItem *mode = [self nv_itemInMenu:viewMenu action:@selector(toggleSourcePreview:)];
    Check(anchor && title && tags && controls && list && mode, @"View contains the existing preview command and all new commands");
    NSInteger index = [viewMenu indexOfItem:anchor];
    Check(index + 6 < [viewMenu numberOfItems], @"the six requested commands fit after Note Previews in Title");
    Check([viewMenu itemAtIndex:index + 1] == title && [viewMenu itemAtIndex:index + 2] == tags &&
        [viewMenu itemAtIndex:index + 3] == controls && [viewMenu itemAtIndex:index + 4] == list &&
        [viewMenu itemAtIndex:index + 5] == mode,
        @"the new view toggles immediately follow Note Previews in Title in the requested order");
    NSMenuItem *syntaxParent = [viewMenu itemAtIndex:index + 6];
    NSMenu *syntax = [syntaxParent submenu];
    Check([[syntaxParent title] isEqual:NSLocalizedString(@"Syntax Type", nil)] && syntax != nil,
        @"Syntax Type follows Show Source/Preview as a submenu");
    Check([[[syntax itemArray] valueForKey:@"representedObject"] isEqual:@[@"plain", @"markdown", @"textile", @"html", @"json"]],
        @"Syntax Type contains Plain Text, Markdown, Textile, HTML, and JSON in order");
    for (NSMenuItem *item in [syntax itemArray])
        Check([item action] == @selector(selectSourceSyntax:) && [item target] == app,
            @"syntax choices route through the application coordinator");
    for (NSMenuItem *item in @[title, tags, controls, list, mode])
        Check([item target] == app, @"new View commands route through the application coordinator");
    [viewMenu update];
    Check(![prefsController showTitleInTopSection] && ![prefsController showTagsInTopSection] &&
        ![prefsController showBodyControlsInTopSection], @"new application preferences hide all three header rows by default");
    Check([noteTitleField isHidden] && [noteTagsField isHidden] && [bodyModeControl isHidden] &&
        [sourceSyntaxControl isHidden] && [viewerTypeControl isHidden], @"Source initially hides all header controls");
    Check([[title title] isEqual:NSLocalizedString(@"Show Title in Top Section", nil)] &&
        [[tags title] isEqual:NSLocalizedString(@"Show Tag in Top Section", nil)] &&
        [[controls title] isEqual:NSLocalizedString(@"Show Source-Preview Toggle and Syntax Type in Top Section", nil)],
        @"visibility commands initially offer Show with the requested titles");
    Check([[mode title] isEqual:NSLocalizedString(@"Show Preview", nil)], @"Source offers the Show Preview command");
    [self nv_checkSyntaxMenu:syntax selected:@"plain" enabled:YES];

    // Show the rows explicitly before testing native edits and Hide commands.
    for (NSMenuItem *item in @[title, tags, controls]) [self nv_sendMenuItem:item];
    [viewMenu update];
    Check(![noteTitleField isHidden] && ![noteTagsField isHidden] && ![bodyModeControl isHidden] &&
        ![sourceSyntaxControl isHidden] && [viewerTypeControl isHidden], @"Show commands expose all applicable Source header controls");
    Check([[title title] isEqual:NSLocalizedString(@"Hide Title in Top Section", nil)] &&
        [[tags title] isEqual:NSLocalizedString(@"Hide Tag in Top Section", nil)] &&
        [[controls title] isEqual:NSLocalizedString(@"Hide Source-Preview Toggle and Syntax Type in Top Section", nil)],
        @"visible row commands offer Hide with the requested titles");
    [self nv_captureViewControls:@"view-controls-expanded.png"];

    // Keep native metadata edits open while the actual View commands hide them.
    CGFloat fullHeight = [self nv_headerHeight];
    [self renameNote:self]; Pump();
    NSTextView *metadataEditor = (id)[noteTitleField currentEditor];
    Check(metadataEditor != nil, @"the title hide fixture has a native field editor");
    [metadataEditor insertText:@"Alpha renamed from View" replacementRange:NSMakeRange(0, [[metadataEditor string] length])];
    [self nv_sendMenuItem:title];
    Check([titleOfNote(alpha) isEqual:@"Alpha renamed from View"] && [noteTitleField isHidden] &&
        ![noteTitleField currentEditor] && metadataControl == nil,
        @"hiding an active title field commits its edit and ends native metadata editing");
    Check([[peer valueForKey:@"noteTitleField"] isHidden] && [self nv_headerHeight] < fullHeight,
        @"Hide Title reaches the peer and returns the unused title row to the source area");
    Check([self selectedNoteObject] == alpha && [peer selectedNoteObject] == beta && [titleOfNote(beta) isEqual:@"Beta"],
        @"a shared visibility change preserves each browser's selected note and metadata target");
    CGFloat titleHiddenHeight = [self nv_headerHeight];
    [self tagNote:self]; Pump();
    metadataEditor = (id)[noteTagsField currentEditor];
    Check(metadataEditor != nil, @"the tag hide fixture has a native field editor");
    [metadataEditor insertText:@"view-menu, retained" replacementRange:NSMakeRange(0, [[metadataEditor string] length])];
    [self nv_sendMenuItem:tags];
    Check([labelsOfNote(alpha) isEqual:@"view-menu, retained"] && [noteTagsField isHidden] &&
        ![noteTagsField currentEditor] && metadataControl == nil,
        @"hiding an active tag field commits its edit and ends native metadata editing");
    Check([[peer valueForKey:@"noteTagsField"] isHidden] && [self nv_headerHeight] < titleHiddenHeight,
        @"Hide Tag reaches the peer and returns its row to the source area");
    [self nv_sendMenuItem:controls];
    Check([bodyModeControl isHidden] && [sourceSyntaxControl isHidden] && [viewerTypeControl isHidden] &&
        [[peer valueForKey:@"bodyModeControl"] isHidden], @"the third toggle hides the mode and both syntax or viewer controls in all browsers");
    Check(fabs([self nv_headerHeight]) < 0.5 && fabs([peer nv_headerHeight]) < 0.5,
        @"hiding all rows and the word count returns the full header to the source area");
    NSArray *ownLayouts = [[[[[app editingSessionForNote:alpha] textStorage] layoutManagers] copy] autorelease];
    NSArray *peerLayouts = [[[[[app editingSessionForNote:beta] textStorage] layoutManagers] copy] autorelease];
    [prefsController setShowWordCount:NO];
    NSDate *countDeadline = [NSDate dateWithTimeIntervalSinceNow:4];
    while (![[[self valueForKey:@"wordCounter"] stringValue] isEqual:@"2 words"] && [countDeadline timeIntervalSinceNow] > 0) Pump();
    Check([[[[app editingSessionForNote:alpha] textStorage] layoutManagers] isEqualToArray:ownLayouts] &&
        [[[[app editingSessionForNote:beta] textStorage] layoutManagers] isEqualToArray:peerLayouts],
        @"asynchronous word counting preserves both shared layout arrays");
    Check([[[self valueForKey:@"wordCounter"] stringValue] isEqual:@"2 words"], @"word count retains the existing count for the source");
    Pump();
    Check([noteTitleField isHidden] && [self nv_headerHeight] > 0 && [peer nv_headerHeight] > 0,
        @"an independently visible word count retains its row while the title stays hidden");
    [self nv_sendMenuItem:[self nv_itemInMenu:viewMenu action:@selector(toggleWordCount:)]];
    Check([prefsController showWordCount], @"the Word Count menu changes its preference once without a duplicate nib binding");
    Check(fabs([self nv_headerHeight]) < 0.5 && fabs([peer nv_headerHeight]) < 0.5,
        @"hiding the word count returns its otherwise hidden row in every browser");
    [self setNotesListHeight:120]; [peer setNotesListHeight:160]; Pump();
    CGFloat ownListHeight = [self notesListHeight], peerListHeight = [peer notesListHeight];
    NSRect ownWindowFrame = [window frame], peerWindowFrame = [[peer window] frame];
    CGFloat ownBodyHeight = NSHeight([splitSubview frame]);
    Check([prefsController showNotesList] && [[list title] isEqual:NSLocalizedString(@"Hide Notes List", nil)],
        @"the notes list starts visible and its menu offers Hide Notes List");
    [window makeFirstResponder:notesTableView];
    [self nv_sendMenuItem:list];
    Check([[browserSplitController splitViewItems][0] isCollapsed] &&
        [[[[peer valueForKey:@"browserSplitController"] splitViewItems] objectAtIndex:0] isCollapsed] &&
        [notesSubview isHiddenOrHasHiddenAncestor] && [[peer valueForKey:@"notesSubview"] isHiddenOrHasHiddenAncestor],
        @"Hide Notes List collapses the actual list area in both browser windows");
    Check(NSEqualRects([window frame], ownWindowFrame) && NSEqualRects([[peer window] frame], peerWindowFrame) &&
        NSHeight([splitSubview frame]) >= ownBodyHeight + ownListHeight - 1,
        @"the collapsed list returns space to the body without resizing either browser window");
    Check(fabs([[[self browserWindowState] objectForKey:@"divider"] doubleValue] - ownListHeight) < 1 &&
        fabs([[[peer browserWindowState] objectForKey:@"divider"] doubleValue] - peerListHeight) < 1,
        @"collapsed browsers still serialize their separate expanded list heights");
    Check([window firstResponder] == textView && [self selectedNoteObject] == alpha && [peer selectedNoteObject] == beta,
        @"hiding a focused notes list keeps each selection and focuses the active note source");
    [self nv_captureViewControls:@"view-controls-collapsed.png"];
    [viewMenu update];
    Check([[title title] isEqual:NSLocalizedString(@"Show Title in Top Section", nil)] &&
        [[tags title] isEqual:NSLocalizedString(@"Show Tag in Top Section", nil)] &&
        [[controls title] isEqual:NSLocalizedString(@"Show Source-Preview Toggle and Syntax Type in Top Section", nil)],
        @"hidden row commands offer Show with the requested titles");
    Check([[list title] isEqual:NSLocalizedString(@"Show Notes List", nil)], @"the hidden notes list offers Show Notes List");
    [prefsController synchronize];
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    for (NSString *key in @[@"ShowTitleInTopSection", @"ShowTagsInTopSection", @"ShowBodyControlsInTopSection", @"ShowNotesList"])
        Check([stored objectForKey:key] != nil && ![[stored objectForKey:key] boolValue],
            @"each hidden-row preference is stored in the application preferences domain");

    [app newWindow:self]; Pump();
    AppController *newBrowser = [[[app browserControllers] lastObject] retain];
    Check(newBrowser != self && newBrowser != peer, @"the visibility fixture creates an additional browser");
    [newBrowser searchForString:@""]; [newBrowser revealNote:alpha options:0]; Pump();
    Check([[newBrowser valueForKey:@"noteTitleField"] isHidden] && [[newBrowser valueForKey:@"noteTagsField"] isHidden] &&
        [[newBrowser valueForKey:@"bodyModeControl"] isHidden] && fabs([newBrowser nv_headerHeight]) < 0.5,
        @"a new browser inherits all hidden rows and reclaims their height");
    Check([[newBrowser valueForKey:@"notesSubview"] isHiddenOrHasHiddenAncestor] &&
        [[[[newBrowser valueForKey:@"browserSplitController"] splitViewItems] objectAtIndex:0] isCollapsed],
        @"a new browser also inherits the collapsed notes list");
    [[newBrowser window] performClose:self]; [newBrowser release]; Pump();
    [self nv_activateBrowser];

    // These commands must remain usable after their toolbar equivalents disappear.
    [self nv_sendMenuItem:mode];
    Check([self isViewingNote] && ![peer isViewingNote], @"Show Preview changes only the active browser with the header hidden");
    Check([bodyModeControl isHidden] && [sourceSyntaxControl isHidden] && [viewerTypeControl isHidden],
        @"entering Preview does not reveal the hidden mode row");
    Check(NSEqualRects([[previewController view] frame], [textScrollView frame]),
        @"the preview occupies the same reclaimed body area as Source");
    [viewMenu update];
    Check([[mode title] isEqual:NSLocalizedString(@"Show Source", nil)], @"Preview offers the Show Source command");
    NSString *viewerBeforeSyntaxChange = [[self selectedViewerIdentifier] copy];
    for (NSMenuItem *choice in [syntax itemArray]) {
        [self nv_sendMenuItem:choice];
        [self nv_checkSyntaxMenu:syntax selected:[choice representedObject] enabled:YES];
        Check([[alpha sourceSyntaxIdentifier] isEqual:[choice representedObject]] && [self isViewingNote] &&
            [[self selectedViewerIdentifier] isEqual:viewerBeforeSyntaxChange],
            @"Syntax Type changes source syntax in Preview without changing its viewer or presentation mode");
        Check([sourceSyntaxControl isHidden] && [viewerTypeControl isHidden],
            @"a syntax update preserves the hidden controls row");
    }
    [viewerBeforeSyntaxChange release];
    [self nv_sendMenuItem:mode];
    Check(![self isViewingNote] && [window firstResponder] == textView,
        @"Show Source restores the editable source and keyboard focus with the header hidden");

    [peer nv_activateBrowser];
    [self nv_checkSyntaxMenu:syntax selected:@"plain" enabled:YES];
    [peer nv_sendMenuItem:[syntax itemAtIndex:1]];
    Check([[beta sourceSyntaxIdentifier] isEqual:@"markdown"] && [[alpha sourceSyntaxIdentifier] isEqual:@"json"],
        @"the shared Syntax Type menu changes only the active browser's selected note");
    [peer nv_sendMenuItem:mode];
    Check([peer isViewingNote] && ![self isViewingNote], @"the shared mode menu routes to the newly active peer");
    [peer nv_sendMenuItem:mode];
    [self nv_activateBrowser];
    [self nv_sendMenuItem:list];
    Check(![[browserSplitController splitViewItems][0] isCollapsed] &&
        ![[[[peer valueForKey:@"browserSplitController"] splitViewItems] objectAtIndex:0] isCollapsed] &&
        fabs([self notesListHeight] - ownListHeight) < 1 && fabs([peer notesListHeight] - peerListHeight) < 1,
        @"Show Notes List restores each browser's separate divider height");

    [self renameNote:self]; Pump();
    Check(![noteTitleField isHidden] && [noteTitleField currentEditor] &&
        ![[peer valueForKey:@"noteTitleField"] isHidden] && [prefsController showTitleInTopSection],
        @"Rename reveals a hidden title row in all browsers and focuses its field");
    [(id)[noteTitleField currentEditor] doCommandBySelector:@selector(cancelOperation:)]; Pump();
    [self renameNote:self]; Pump();
    Check([noteTitleField currentEditor] != nil, @"the untouched title hide fixture has keyboard focus without a text edit");
    [self nv_sendMenuItem:title];
    Check(![noteTitleField currentEditor] && [window firstResponder] == textView,
        @"hiding an untouched title field ends its field editor and focuses Source");
    [self tagNote:self]; Pump();
    Check(![noteTagsField isHidden] && [noteTagsField currentEditor] &&
        ![[peer valueForKey:@"noteTagsField"] isHidden] && [prefsController showTagsInTopSection],
        @"Tag Note reveals a hidden tag row in all browsers and focuses its field");
    [(id)[noteTagsField currentEditor] doCommandBySelector:@selector(cancelOperation:)]; Pump();
    [self tagNote:self]; Pump();
    Check([noteTagsField currentEditor] != nil, @"the untouched tag hide fixture has keyboard focus without a text edit");
    [self nv_sendMenuItem:tags];
    Check(![noteTagsField currentEditor] && [window firstResponder] == textView,
        @"hiding an untouched tag field ends its field editor and focuses Source");
    NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
    [self nv_sendMenuItem:[self nv_itemInMenu:notesMenu action:@selector(newNote:)]];
    NoteObject *created = [[self selectedNoteObject] retain];
    Check(created && created != alpha && created != beta && [library totalNoteCount] == 3 &&
        [[created contentString] length] == 0 && [[created sourceSyntaxIdentifier] isEqual:@"plain"],
        @"New Note creates one blank note with Plain Text syntax while the title row is hidden");
    Check([noteTitleField isHidden] && ![self isViewingNote] && [window firstResponder] == textView,
        @"New Note preserves the hidden title preference and focuses the editable source");
    [library removeNote:created]; [created release]; Pump();

    [self searchForString:@""]; [notesTableView deselectAll:self]; Pump();
    [viewMenu update];
    Check([self selectedNoteObject] == nil && ![mode isEnabled], @"Show Source/Preview is disabled without a selected note");
    [self nv_checkSyntaxMenu:syntax selected:nil enabled:NO];
    Check([title isEnabled] && [tags isEnabled] && [controls isEnabled] && [list isEnabled],
        @"all visibility toggles remain available without a selected note");
    for (NSMenuItem *item in @[title, tags, controls]) [self nv_sendMenuItem:item];
    Check(![noteTitleField isHidden] && ![noteTagsField isHidden] && ![bodyModeControl isHidden] &&
        ![noteTitleField isEnabled] && ![noteTagsField isEnabled] && ![bodyModeControl isEnabled],
        @"Show commands restore the header without enabling note controls or creating a note");
    Check([prefsController showTitleInTopSection] && [prefsController showTagsInTopSection] &&
        [prefsController showBodyControlsInTopSection] && [prefsController showNotesList],
        @"the fixture restores all header and list visibility preferences");
    Check([[[alpha contentString] string] isEqual:originalSource], @"view commands and syntax changes preserve the exact note source");
    [app setNote:alpha metadataValue:originalTitle isTitle:YES];
    [app setNote:alpha metadataValue:originalTags ?: @"" isTitle:NO];
    [alpha setSourceSyntaxIdentifier:@"plain"]; [beta setSourceSyntaxIdentifier:@"plain"];
    [originalTitle release]; [originalTags release]; [originalSource release];
    [self searchForString:@""]; [self revealNote:alpha options:0]; Pump();
}
