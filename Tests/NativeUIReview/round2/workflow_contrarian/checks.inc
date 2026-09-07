- (void)nv_activate {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ((![NSApp isActive] || [NSApp keyWindow] != window || [NSApp mainWindow] != window) &&
        [deadline timeIntervalSinceNow] > 0) Pump();
    NSLog(@"ACTIVATION active=%d keyMatches=%d mainMatches=%d browserMatches=%d",
        [NSApp isActive], [NSApp keyWindow] == window, [NSApp mainWindow] == window,
        [[NVApplicationController sharedController] activeBrowser] == self);
    Check([NSApp isActive] && [NSApp keyWindow] == window && [NSApp mainWindow] == window &&
        [[NVApplicationController sharedController] activeBrowser] == self,
        @"native activation supplies the intended key window, main window, and command target");
}

- (void)nv_bulk:(NoteObject *)alpha beta:(NoteObject *)beta gamma:(NoteObject *)gamma {
    [self nv_activate];
    [alpha setLabelString:@"common,alpha-only"];
    [beta setLabelString:@"common,beta-only"];
    [gamma setLabelString:@"untouched"];
    [self searchForString:@""]; Pump();
    NSIndexSet *selection = [[self browserSession] indexesOfNotes:@[alpha, beta]];
    [notesTableView selectRowIndexes:selection byExtendingSelection:NO];
    [window makeFirstResponder:notesTableView]; Pump();
    Check([notesTableView numberOfSelectedRows] == 2, @"two fixture notes are selected for bulk tagging");
    [self tagNote:self]; Pump();
    NSTextField *control = [tagEditor tagField];
    NSWindow *panel = [control window];
    Check([NSApp isActive] && [NSApp keyWindow] == panel && [NSApp mainWindow] == window,
        @"native bulk-tag panel is key and its originating browser remains main");
    NSTextView *editor = (id)[control currentEditor];
    Check(editor != nil && [[editor string] isEqual:@"common"], @"bulk-tag editor starts with only the common tag");
    [editor insertText:@"replacement" replacementRange:NSMakeRange(0, [[editor string] length])]; Pump();
    [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
    Check([[tagEditor tagFieldString] isEqual:@"replacement"], @"native field binding receives the replacement tag");
    [editor doCommandBySelector:@selector(insertNewline:)]; Pump();
    NSLog(@"BULK expected=alpha-only+replacement,beta-only+replacement,untouched actual=%@ | %@ | %@ panelVisible=%d",
        labelsOfNote(alpha), labelsOfNote(beta), labelsOfNote(gamma), [panel isVisible]);
    Check([[NSSet setWithArray:[labelsOfNote(alpha) labelCompatibleWords]] isEqualToSet:[NSSet setWithArray:@[@"alpha-only", @"replacement"]]] &&
        [[NSSet setWithArray:[labelsOfNote(beta) labelCompatibleWords]] isEqualToSet:[NSSet setWithArray:@[@"beta-only", @"replacement"]]],
        @"Return replaces the common tag and preserves both notes' unique tags");
    Check([labelsOfNote(gamma) isEqual:@"untouched"] && ![panel isVisible],
        @"Return closes the bulk-tag panel and leaves the unselected note unchanged");
}

- (void)nv_search:(NoteObject *)alpha beta:(NoteObject *)beta {
    NVApplicationController *app = [NVApplicationController sharedController];
    [app newWindow:self]; Pump();
    AppController *peer = [[app browserControllers] lastObject];
    [peer nv_activate];
    [peer searchForString:@"Beta"]; [peer revealNote:beta options:0]; Pump();
    for (NSString *action in @[@"escape", @"native-clear"]) {
        [self nv_activate];
        [self searchForString:@"al"]; [self revealNote:alpha options:0];
        [self bringFocusToControlField:self]; Pump();
        NSTextView *editor = (id)[field currentEditor];
        Check(editor != nil && [[[self browserSession] searchString] isEqual:@"al"], @"search fixture has an active editor and the intended query");
        if ([action isEqual:@"escape"]) {
            [editor doCommandBySelector:@selector(cancelOperation:)];
        } else {
            if (![[field cell] isKindOfClass:[NSSearchFieldCell class]]) {
                NSLog(@"SKIP native-clear: baseline uses a custom search cell");
                continue;
            }
            NSSearchFieldCell *cell = (id)[field cell];
            NSButtonCell *cancel = [cell cancelButtonCell];
            Check(cancel != nil, @"native search field supplies a cancel button cell");
            [cancel performClick:field];
        }
        for (NSUInteger i=0; i<5; i++) Pump();
        NSLog(@"SEARCH_CLEAR action=%@ expected=empty-query,3-rows,3-notes,peer-Beta actual=query(%@),field(%@),rows%ld,notes%lu,peer(%@),peerQuery(%@)",
            action, [[self browserSession] searchString], [field stringValue], (long)[notesTableView numberOfRows],
            (unsigned long)[[app library] totalNoteCount], titleOfNote([peer selectedNoteObject]), [[peer browserSession] searchString]);
        Check([[[self browserSession] searchString] length] == 0 && [[field stringValue] length] == 0 && [notesTableView numberOfRows] == 3,
            @"clear command clears both the visible query and the browser filter");
        Check([[app library] totalNoteCount] == 3, @"clear command creates no note");
        Check([peer selectedNoteObject] == beta && [[[[peer browserSession] searchString] lowercaseString] isEqual:@"beta"],
            @"clear command preserves the other browser's query and selected note");
        [peer nv_activate]; [self nv_activate];
        Check([[[self browserSession] searchString] length] == 0 && [[field stringValue] length] == 0,
            @"empty query persists through a browser activation round trip");
    }
}

#ifndef NV_WORKFLOW_NO_METADATA
- (void)nv_metadata:(NoteObject *)alpha beta:(NoteObject *)beta {
    [self nv_activate];
    [self searchForString:@""]; [self revealNote:alpha options:0]; Pump();
    Check(noteTitleField != nil && noteTagsField != nil, @"current build exposes separate metadata fields");
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    NSArray *values = @[@"  Pasted title\nSecond line  ", @"  first,second\nthird  "];
    NSUInteger i = 0;
    for (NSTextField *control in @[noteTitleField, noteTagsField]) {
        [self nv_activate];
        [control selectText:self];
        NSTextView *editor = (id)[control currentEditor];
        Check(editor != nil, @"metadata paste uses the native field editor");
        [pasteboard declareTypes:@[NSStringPboardType] owner:nil];
        [pasteboard setString:[values objectAtIndex:i] forType:NSStringPboardType];
        Check([editor readSelectionFromPasteboard:pasteboard type:NSStringPboardType], @"native field editor accepts text from the isolated pasteboard");
        NSString *expected = [[[values objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
        [editor doCommandBySelector:@selector(insertNewline:)]; Pump();
        NSString *actual = i == 0 ? titleOfNote(alpha) : labelsOfNote(alpha);
        NSLog(@"METADATA_PASTE field=%@ expected=%@ actual=%@", i == 0 ? @"title" : @"tags", expected, actual);
        Check([actual isEqualToString:expected], @"metadata commit preserves the field editor's pasted text after outer whitespace trim");
        [self revealNote:beta options:0]; [self revealNote:alpha options:0]; Pump();
        Check([[control stringValue] isEqualToString:expected], @"pasted metadata survives selection away and back");
        [expected release]; i++;
    }
    Check([[[alpha contentString] string] isEqual:@"Alpha body"] && [[[beta contentString] string] isEqual:@"Beta body"],
        @"metadata paste leaves both note bodies unchanged");
    [pasteboard releaseGlobally];
}
#endif

- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"Alpha body") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"Beta body") retain];
        NoteObject *gamma = [MakeNote(library, @"Gamma", @"Gamma body") retain];
        NSString *probe = [NSString stringWithUTF8String:getenv("NV_WORKFLOW_PROBE")];
        if ([probe isEqual:@"bulk"]) [self nv_bulk:alpha beta:beta gamma:gamma];
        else if ([probe isEqual:@"search"]) [self nv_search:alpha beta:beta];
#ifndef NV_WORKFLOW_NO_METADATA
        else if ([probe isEqual:@"metadata"]) [self nv_metadata:alpha beta:beta];
#endif
        [alpha release]; [beta release]; [gamma release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"WORKFLOW PROBES PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
