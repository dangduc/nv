- (void)nv_activateBrowser {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ((![NSApp isActive] || ![window isKeyWindow] ||
        [[NVApplicationController sharedController] activeBrowser] != self) && [deadline timeIntervalSinceNow] > 0) Pump();
    BOOL intendedBrowserIsActive = [NSApp isActive] && [window isKeyWindow] &&
        [[NVApplicationController sharedController] activeBrowser] == self;
    if (!intendedBrowserIsActive) NSLog(@"Browser fixture state: applicationActive=%d key=%@ main=%@ activeBrowser=%@ expectedWindow=%@ expectedBrowser=%@",
        [NSApp isActive], [NSApp keyWindow], [NSApp mainWindow], [[NVApplicationController sharedController] activeBrowser], window, self);
    Check(intendedBrowserIsActive, @"native activation makes the intended browser key and active before commands");
}

- (void)nv_focusSearch {
    [self nv_activateBrowser];
    [self bringFocusToControlField:self];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    Check([field currentEditor] != nil && ![field isHiddenOrHasHiddenAncestor],
        @"Search command opens a visible field editor");
    Check(NSWidth([field bounds]) >= 140, @"focused Search has enough width for text editing");
}

- (void)nv_checkPeer:(AppController *)peer note:(NoteObject *)note {
    Check([peer selectedNoteObject] == note && [[[peer browserSession] searchString] isEqual:@"Beta"],
        @"native control commands preserve the peer query and selection");
    Check([[[peer valueForKey:@"noteTagsField"] stringValue] isEqual:labelsOfNote(note)],
        @"peer tag display continues to match its selected note");
}

- (void)nv_checkSearchCommandWithQuery:(NSString *)query note:(NoteObject *)note {
    [self nv_activateBrowser];
    [self searchForString:query];
    if (note) [self revealNote:note options:0];
    Pump();
    [window makeFirstResponder:notesTableView];
    NSUInteger searchIndex = [[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
    Check(searchIndex != NSNotFound, @"toolbar initially contains Search");
    [toolbar removeItemAtIndex:searchIndex]; Pump();
    Check([toolbar isVisible] && ![[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"],
        @"customization removes Search while leaving the toolbar visible");

    NSMenuItem *searchItem = nil;
    NSMutableArray *menus = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
    for (NSUInteger i = 0; i < [menus count]; i++) {
        for (NSMenuItem *item in [[menus objectAtIndex:i] itemArray]) {
            if ([item action] == @selector(bringFocusToControlField:)) searchItem = item;
            if ([item submenu]) [menus addObject:[item submenu]];
        }
    }
    Check(searchItem != nil, @"Search has a menu command");
    [self nv_activateBrowser];
    Check([NSApp sendAction:[searchItem action] to:[searchItem target] from:searchItem],
        @"the menu dispatches its Search action");
    for (NSUInteger i = 0; i < 6; i++) Pump();
    BOOL restoredAndFocused = [[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"] &&
        [field window] == window && ![field isHiddenOrHasHiddenAncestor] && [field currentEditor] != nil;
    if (!restoredAndFocused) NSLog(@"Search command state: present=%d fieldWindow=%@ editor=%@ key=%d activeBrowser=%@ expectedBrowser=%@",
        [[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"], [field window], [field currentEditor],
        [window isKeyWindow], [[NVApplicationController sharedController] activeBrowser], self);
    Check(restoredAndFocused,
        @"Search menu restores and focuses an item removed by customization");
    Check([[field stringValue] isEqual:query] && [[[self browserSession] searchString] isEqual:query] &&
        [self selectedNoteObject] == note, @"restoring Search preserves its query and selection");
    NSUInteger itemCount = [[toolbar items] count];
    [self nv_focusSearch];
    Check([[toolbar items] count] == itemCount, @"repeated Search does not duplicate the toolbar item");
    [self setDualFieldIsVisible:NO];
    [self nv_focusSearch];
    Check([toolbar isVisible] && [[field stringValue] isEqual:query],
        @"Search also restores a hidden toolbar and preserves the query");
}

- (void)nv_checkTabWithQuery:(NSString *)query note:(NoteObject *)note {
    [self searchForString:query];
    if (note) [self revealNote:note options:0];
    else [notesTableView deselectAll:self];
    Pump();
    [self nv_focusSearch];
    Check([self selectedNoteObject] == note, @"Tab fixture has the expected selected note");
    NSTextView *editor = (id)[field currentEditor];
    [editor doCommandBySelector:@selector(insertTab:)]; Pump();
    Check(note ? [window firstResponder] == textView : [field currentEditor] == editor,
        note ? @"Tab moves from Search to the selected note body" : @"Tab leaves Search focused without a selected note");
    Check([[field stringValue] isEqual:query] && [[[self browserSession] searchString] isEqual:query] &&
        [self selectedNoteObject] == note, @"Tab preserves the query and note selection");
}

- (void)nv_checkSearchFocusTransitionsWithNote:(NoteObject *)note {
    [self nv_activateBrowser];
    [self searchForString:@"al"]; [self revealNote:note options:0]; Pump();
    [self searchForString:@"al"];
    [window makeFirstResponder:textView];
    for (NSUInteger i = 0; i < 8; i++) Pump();
    Check([window firstResponder] == textView,
        @"a query change does not queue Search focus after navigation to the body");
    [self bringFocusToControlField:self];
    [window makeFirstResponder:textView];
    for (NSUInteger i = 0; i < 8; i++) Pump();
    Check([window firstResponder] == textView,
        @"Search does not queue focus after a later body focus command");
}

- (void)nv_completeTags:(NSString *)input expected:(NSString *)expected {
    [self nv_activateBrowser];
    [self tagNote:self]; Pump();
    NSTextView *editor = (id)[noteTagsField currentEditor];
    Check(editor != nil, @"Tag Note opens the native tag field editor");
    [editor insertText:input replacementRange:NSMakeRange(0, [[editor string] length])];
    [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
    [editor complete:nil]; Pump();
    Check([[editor string] isEqual:expected], [NSString stringWithFormat:@"native tag completion maps %@ to %@", input, expected]);
    // Collapse the candidate selection before Return so AppKit finishes completion.
    [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
    [editor doCommandBySelector:@selector(insertNewline:)]; Pump();
    Check([labelsOfNote([self selectedNoteObject]) isEqual:expected], @"Return commits the completed tags to the selected note");
}

- (void)nv_checkTitleCompletion {
    // Compare with an ordinary NSTextField instead of assuming a dictionary language.
    NSTextField *reference = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 200, 24)] autorelease];
    [[window contentView] addSubview:reference];
    [reference selectText:self];
    NSTextView *editor = (id)[reference currentEditor];
    Check(editor != nil, @"dictionary completion reference uses a native field editor");
    [editor insertText:@"wor" replacementRange:NSMakeRange(0, [[editor string] length])];
    [editor complete:nil]; Pump();
    NSString *expected = [[editor string] copy];
    [window makeFirstResponder:notesTableView];
    [reference removeFromSuperview];
    [self renameNote:self]; Pump();
    editor = (id)[noteTitleField currentEditor];
    Check(editor != nil, @"Rename opens the native title field editor");
    [editor insertText:@"wor" replacementRange:NSMakeRange(0, [[editor string] length])];
    [editor complete:nil]; Pump();
    Check([[editor string] isEqual:expected], @"title completion retains AppKit dictionary behavior");
    [expected release];
    [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
    [editor doCommandBySelector:@selector(cancelOperation:)]; Pump();
}

- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha body") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"beta body") retain];
        [beta setLabelString:@"workflow"]; Pump();
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"completion and command checks have a peer browser");
        [peer searchForString:@"Beta"]; [peer revealNote:beta options:0]; Pump();
        [window makeKeyAndOrderFront:self]; Pump();
        NSString *probe = [NSString stringWithUTF8String:getenv("NV_NATIVE_CONTROLS_PROBE") ?: "all"];
        if ([probe isEqual:@"all"] || [probe isEqual:@"search"]) {
            [self nv_checkSearchCommandWithQuery:@"al" note:alpha];
            [self nv_checkSearchCommandWithQuery:@"No matching note" note:nil];
            [self nv_checkSearchFocusTransitionsWithNote:alpha];
            [self nv_checkPeer:peer note:beta];
        }
        if ([probe isEqual:@"all"] || [probe isEqual:@"tab"]) {
            [self nv_checkTabWithQuery:@"al" note:alpha];
            [self nv_checkTabWithQuery:@"" note:alpha];
            [self nv_checkTabWithQuery:@"" note:nil];
            [self nv_checkTabWithQuery:@"No matching note" note:nil];
            [self nv_checkPeer:peer note:beta];
        }
        if ([probe isEqual:@"all"] || [probe isEqual:@"tags"]) {
            [self searchForString:@"al"]; [self revealNote:alpha options:0]; Pump();
            [self nv_completeTags:@"wor" expected:@"workflow"];
            [self nv_completeTags:@"ideas, wor" expected:@"ideas, workflow"];
            [self nv_completeTags:@"ideas, workflow, wor" expected:@"ideas, workflow, wor"];
            Check([[[self browserSession] searchString] isEqual:@"al"], @"tag completion preserves the active query");
            [self nv_checkTitleCompletion];
            Check([titleOfNote(alpha) isEqual:@"Alpha"], @"cancelling title completion preserves the note title");
            [self nv_checkPeer:peer note:beta];
            // The peer can complete a tag that the other browser just committed.
            NSInteger completionIndex = 0;
            NSArray *libraryTags = [[library labelsListDataSource] labelTitlesPrefixedByString:@"ide"
                indexOfSelectedItem:&completionIndex minusWordSet:[NSSet set]];
            Check([libraryTags containsObject:@"ideas"], @"peer completion fixture has an existing ideas tag in the library");
            [[peer window] makeKeyAndOrderFront:self]; Pump();
            [peer nv_completeTags:@"ide" expected:@"ideas"];
            Check([self selectedNoteObject] == alpha && [[[self browserSession] searchString] isEqual:@"al"],
                @"peer completion preserves the origin query and selection");
            [window makeKeyAndOrderFront:self];
            [self searchForString:@""]; [notesTableView deselectAll:self]; Pump();
            NSUInteger count = [library totalNoteCount];
            [self tagNote:self]; Pump();
            Check(![noteTagsField isEnabled] && ![noteTagsField currentEditor] && [library totalNoteCount] == count,
                @"Tag Note without a selection does not begin metadata editing or create a note");
        }
        Check([library totalNoteCount] == 2, @"control commands do not create notes");
        Check(![splitView isVertical], @"native controls retain the list-above-editor stack");
        NSColor *listColor = [[notesTableView backgroundColor] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
        Check([listColor whiteComponent] > .99, @"native controls retain the white notes list");
        const char *artifacts = getenv("NV_UI_ARTIFACTS");
        if (artifacts) {
            [self searchForString:@"al"]; [self revealNote:alpha options:0];
            [self nv_focusSearch];
            CGImageRef capture = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
                (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
            Check(capture != NULL, @"the desktop captures the Search window");
            NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
            CGImageRelease(capture);
            NSString *path = [[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:@"restored-search.png"];
            Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
                @"restored Search screenshot is saved");
        }
        [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"NATIVE CONTROL TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
