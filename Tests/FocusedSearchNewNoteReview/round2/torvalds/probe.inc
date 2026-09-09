// Preserve the old note's edited content and independent metadata history.
- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        NotationController *library = [self sharedNotationController];
        [prefsController setAutoCompleteSearches:NO sender:nil];
        NoteObject *original = [MakeNote(library, @"Original title", @"Initial body") retain];
        [self searchForString:@"" mode:@"exact"];
        [self revealNote:original options:0]; [self focusNoteBody];
        [textView insertText:@" plus saved source" replacementRange:NSMakeRange([[textView string] length], 0)];
        [self finishEditing]; Pump();
        Check([[[original contentString] string] isEqual:@"Initial body plus saved source"],
            @"native source insertion commits to the original note");

        // Isolate metadata history from the known broad-suite body Undo failure.
        [[original undoManager] removeAllActions];
        [self renameNote:self];
        NSTextView *metadataEditor = (id)[noteTitleField currentEditor];
        Check(metadataEditor != nil, @"native Rename opens the title field editor");
        [metadataEditor insertText:@"Saved original title" replacementRange:NSMakeRange(0, [[metadataEditor string] length])];
        [self control:noteTitleField textView:metadataEditor doCommandBySelector:@selector(insertNewline:)]; Pump();
        [self tagNote:self];
        metadataEditor = (id)[noteTagsField currentEditor];
        Check(metadataEditor != nil, @"native Tag opens the tags field editor");
        [metadataEditor insertText:@"review-tag" replacementRange:NSMakeRange(0, [[metadataEditor string] length])];
        [self control:noteTagsField textView:metadataEditor doCommandBySelector:@selector(insertNewline:)]; Pump();
        Check([titleOfNote(original) isEqual:@"Saved original title"] && [labelsOfNote(original) isEqual:@"review-tag"],
            @"native metadata edits commit to the original note before creation");

        [prefsController setShowTitleInTopSection:NO sender:nil];
        [self searchForString:@"Saved original title" mode:@"exact"];
        [self revealNote:original options:0]; Pump();
        [(NSTextView *)[field currentEditor] setString:@"Independent new title"];
        Check([self searchFieldHasFocus] && [self selectedNoteObject] == original,
            @"focused live Search and the edited original note coexist before Command-N");
        NSString *undoName = [[[original undoManager] undoActionName] copy];
        CFAbsoluteTime modified = modifiedDateOfNote(original);
        NSUInteger count = [library totalNoteCount];
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
            modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
            context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
        Check([[NSApp mainMenu] performKeyEquivalent:event], @"the application menu dispatches Command-N"); Pump();
        NoteObject *created = [[self selectedNoteObject] retain];
        Check(created != original && [library totalNoteCount] == count + 1 &&
            [titleOfNote(created) isEqual:@"Independent new title"] && [[created contentString] length] == 0,
            @"Command-N creates one independent empty note with the live search title");
        Check([titleOfNote(original) isEqual:@"Saved original title"] && [labelsOfNote(original) isEqual:@"review-tag"] &&
            [[[original contentString] string] isEqual:@"Initial body plus saved source"] && modifiedDateOfNote(original) == modified,
            @"creation leaves the old title, tags, saved source, and modification timestamp unchanged");
        Check([[original undoManager] canUndo] && [[[original undoManager] undoActionName] isEqual:undoName] &&
            ![[created undoManager] canUndo], @"creation preserves the old history and adds no new-note edit action");

        [[original undoManager] undo]; Pump();
        Check([labelsOfNote(original) length] == 0 && [titleOfNote(original) isEqual:@"Saved original title"],
            @"the first original-note Undo remains the tag edit");
        [[original undoManager] undo]; Pump();
        Check([titleOfNote(original) isEqual:@"Original title"] &&
            [[[original contentString] string] isEqual:@"Initial body plus saved source"],
            @"the second original-note Undo remains the rename and preserves saved source");
        [[original undoManager] redo]; Pump();
        [[original undoManager] redo]; Pump();
        Check([titleOfNote(original) isEqual:@"Saved original title"] && [labelsOfNote(original) isEqual:@"review-tag"] &&
            [self selectedNoteObject] == created && [titleOfNote(created) isEqual:@"Independent new title"] &&
            [[created contentString] length] == 0 && [library totalNoteCount] == count + 1,
            @"metadata Undo and Redo stay with the original note while the new note remains selected");
        Check([library flushAllNoteChanges], @"the edited old note and empty new note checkpoint successfully");
        [undoName release]; [created release]; [original release];
        NSLog(@"TORVALDS ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
