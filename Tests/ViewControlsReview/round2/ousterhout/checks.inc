// Included in the disposable AppController category by run-probe.py.
- (NSMenuItem *)nv_r2Item:(SEL)selector inMenu:(NSMenu *)menu {
    for (NSMenuItem *item in [menu itemArray]) if ([item action] == selector) return item;
    return nil;
}
- (void)nv_r2Dispatch:(NSMenuItem *)item {
    [[item menu] update];
    Check(item && [item isEnabled], @"the actual View menu command is enabled");
    Check([NSApp sendAction:[item action] to:[item target] from:item], @"the native responder chain dispatches the View command");
}
- (void)nv_r2Syntax:(NSMenu *)menu expected:(NSString *)identifier {
    [menu update];
    NSUInteger checked = 0;
    for (NSMenuItem *item in [menu itemArray]) {
        Check([item isEnabled] && [item state] == ([[item representedObject] isEqual:identifier] ? NSControlStateValueOn : NSControlStateValueOff),
            @"Syntax Type follows the active browser note after callbacks");
        checked += [item state] == NSControlStateValueOn;
    }
    Check(checked == 1, @"exactly one source syntax is checked");
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"base") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"peer") retain];
        [app newWindow:self]; Pump();
        AppController *peer = [[[app browserControllers] lastObject] retain];
        LinkingEditor *peerSource = [peer valueForKey:@"textView"];
        [self searchForString:@""]; [peer searchForString:@""];
        [self revealNote:alpha options:0]; [peer revealNote:alpha options:0];
        [self setViewingNote:NO]; [peer setViewingNote:NO];
        [prefsController setShowTitleInTopSection:YES sender:nil];
        [prefsController setShowTagsInTopSection:YES sender:nil];
        [prefsController setShowBodyControlsInTopSection:YES sender:nil];
        [prefsController setShowNotesList:YES sender:nil];
        [peer nv_activateBrowser]; [peer focusNoteBody]; Pump();
        [[alpha undoManager] removeAllActions];
        [peerSource setMarkedText:@" local" selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(4,0)];
        Check([peerSource hasMarkedText] && [[[alpha contentString] string] isEqual:@"base"], @"source composition remains live and uncommitted");
        NSRange marked = [peerSource markedRange], selection = [peerSource selectedRange];
        // Layout-only shared callbacks must leave an unrelated composing editor alone.
        for (NSUInteger pass = 0; pass < 2; pass++) {
            [self toggleTitleInTopSection:self]; [self toggleTagsInTopSection:self];
            [self toggleBodyControlsInTopSection:self]; [self toggleNotesList:self];
            [self toggleWordCount:self];
            for (NSUInteger i=0;i<4;i++) Pump();
            Check([peerSource hasMarkedText] && NSEqualRanges([peerSource markedRange], marked) && NSEqualRanges([peerSource selectedRange], selection),
                @"shared visibility and word-count callbacks preserve marked source and its selection");
            Check([[peer window] firstResponder] == peerSource && [[[alpha contentString] string] isEqual:@"base"] && ![[alpha undoManager] canUndo],
                @"layout callbacks retain source focus and do not prematurely commit or create Undo");
        }
        // Extend the metadata boundary with simultaneous native source and title composition.
        [self nv_activateBrowser]; [self renameNote:self];
        NSTextView *titleEditor = (id)[noteTitleField currentEditor];
        [titleEditor setMarkedText:@"Marked title" selectedRange:NSMakeRange(12,0) replacementRange:NSMakeRange(0,[[titleEditor string] length])];
        Check([titleEditor hasMarkedText] && [peerSource hasMarkedText], @"two windows retain native source and metadata compositions");
        [peer toggleTitleInTopSection:self]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Marked title"] && [[[alpha contentString] string] isEqual:@"base local"],
            @"hiding a marked title commits both compositions to their shared original note");
        Check(![peerSource hasMarkedText] && ![noteTitleField currentEditor] && metadataNote == nil && metadataControl == nil,
            @"metadata callback completes marked input and releases its original editing target");
        Check([window firstResponder] == textView && [[peer window] firstResponder] == peerSource,
            @"both source responders remain owned by their original windows after the callback");
        [self nv_activateBrowser]; [self focusNoteBody];
        Check([NSApp sendAction:@selector(undo:) to:nil from:self], @"Undo dispatches through the focused source responder"); Pump();
        Check([titleOfNote(alpha) isEqual:@"Alpha"] && [[[alpha contentString] string] isEqual:@"base local"],
            @"Undo removes the hidden title commit before the preceding source composition");
        Check([NSApp sendAction:@selector(undo:) to:nil from:self], @"the second Undo dispatches through the source responder"); Pump();
        Check([[[alpha contentString] string] isEqual:@"base"] && [[peerSource string] isEqual:@"base"],
            @"the next Undo removes source composition once in both attached editors");
        [NSApp sendAction:@selector(redo:) to:nil from:self]; Pump(); [NSApp sendAction:@selector(redo:) to:nil from:self]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Marked title"] && [[[alpha contentString] string] isEqual:@"base local"],
            @"Redo restores composition and hidden metadata in their original order");

        // Real menu routing across windows with hidden controls and pending viewer work.
        [peer revealNote:beta options:0]; [peer setViewingNote:NO];
        [prefsController setShowBodyControlsInTopSection:NO sender:nil];
        NSMenu *view = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
        NSMenuItem *mode = [self nv_r2Item:@selector(toggleSourcePreview:) inMenu:view];
        NSMenu *syntax = nil;
        for (NSMenuItem *item in [view itemArray]) if ([[item title] isEqual:@"Syntax Type"]) syntax = [item submenu];
        Check(syntax && mode && [mode target] == app, @"new View menu commands route through the application coordinator");
        [self nv_activateBrowser];
        NSMenuItem *json = [syntax itemAtIndex:4], *markdown = [syntax itemAtIndex:1];
        [self nv_r2Dispatch:json];
        Check([[alpha sourceSyntaxIdentifier] isEqual:@"json"] && [[beta sourceSyntaxIdentifier] isEqual:@"plain"],
            @"hidden syntax action changes only the active note");
        [self nv_r2Dispatch:mode];
        Check([self isViewingNote] && ![peer isViewingNote], @"Show Preview changes only its originating browser");
        [peer nv_activateBrowser]; [self nv_r2Dispatch:markdown];
        Check([[beta sourceSyntaxIdentifier] isEqual:@"markdown"] && [[alpha sourceSyntaxIdentifier] isEqual:@"json"],
            @"a peer menu command does not inherit the previous active note");
        [self nv_r2Syntax:syntax expected:@"markdown"]; [view update];
        Check([[mode title] isEqual:@"Show Preview"], @"a source peer advertises Show Preview while another viewer loads");
        for (NSUInteger i=0;i<35;i++) Pump();
        [self nv_r2Syntax:syntax expected:@"markdown"]; [view update];
        Check([[mode title] isEqual:@"Show Preview"] && [[peer window] firstResponder] == peerSource,
            @"delayed viewer callbacks do not replace the peer menu state or focus");
        [self nv_activateBrowser]; [self nv_r2Syntax:syntax expected:@"json"]; [view update];
        Check([[mode title] isEqual:@"Show Source"] && [bodyModeControl isHidden] && [sourceSyntaxControl isHidden] && [viewerTypeControl isHidden],
            @"returning to Preview validates Show Source while all body controls stay hidden");
        [self nv_r2Dispatch:mode]; Pump();
        Check(![self isViewingNote] && [window firstResponder] == textView && [[[alpha contentString] string] isEqual:@"base local"],
            @"Show Source restores the owning editor and exact shared source");
        [peer revealNote:alpha options:0]; [peer nv_activateBrowser];
        [self nv_r2Dispatch:markdown];
        Check([[alpha sourceSyntaxIdentifier] isEqual:@"markdown"] && [[[sourceSyntaxControl selectedItem] representedObject] isEqual:@"markdown"],
            @"same-note syntax notifications update the hidden peer control without changing presentation");
        Check(![self isViewingNote] && ![peer isViewingNote] && [bodyModeControl isHidden] && [[peer valueForKey:@"bodyModeControl"] isHidden],
            @"same-note syntax callbacks preserve independent presentation and global visibility");
        Check([library totalNoteCount] == 2 && [[[beta contentString] string] isEqual:@"peer"] && [titleOfNote(beta) isEqual:@"Beta"],
            @"interleaved callback and command routing creates no note or unrelated metadata edit");
        NSLog(@"OUSTERHOUT ROUND 2 PASSED: %lu checks", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal]; [peer release]; [alpha release]; [beta release]; exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
