// Command policy across metadata commits and read-only presentation transitions.
- (NoteObject *)nv_r2CommandN:(NSString *)expectedTitle {
    NSUInteger before = [[self sharedNotationController] totalNoteCount];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
    Check([[NSApp mainMenu] performKeyEquivalent:event], @"the native menu dispatches Command-N across the transition");
    NoteObject *created = [self selectedNoteObject];
    Check(created && [titleOfNote(created) isEqual:expectedTitle] &&
        [[self sharedNotationController] totalNoteCount] == before + 1,
        @"the focused control determines the title of exactly one new note");
    Check(![self isViewingNote] && [[created contentString] length] == 0,
        @"New Note leaves Preview and opens empty editable source");
    Check([prefsController showTitleInTopSection] ? [noteTitleField currentEditor] != nil : [window firstResponder] == textView,
        @"New Note follows the current header preference for editing focus");
    return created;
}

- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        [prefsController setShowTitleInTopSection:YES sender:nil];
        [prefsController setShowTagsInTopSection:YES sender:nil];
        NotationController *library = [self sharedNotationController];
        NoteObject *original = MakeNote(library, @"Anchor note", @"# Preserved source");
        NSString *fallback = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");

        [self searchForString:@"Anchor" mode:@"exact"]; [self revealNote:original options:0];
        [self renameNote:self];
        NSTextView *editor = (id)[noteTitleField currentEditor];
        [editor insertText:@"Renamed Anchor" replacementRange:NSMakeRange(0, [[editor string] length])];
        Check([noteTitleField currentEditor] && ![self searchFieldHasFocus] &&
            [titleOfNote(original) isEqual:@"Anchor note"] && [[field stringValue] isEqual:@"Anchor"],
            @"a pending title edit owns focus while the old search and model title remain");
        NoteObject *created = [self nv_r2CommandN:fallback];
        Check([titleOfNote(original) isEqual:@"Renamed Anchor"],
            @"Command-N commits the pending title to its original note");
        [library removeNote:created]; Pump();

        [self searchForString:@"Anchor" mode:@"exact"]; [self revealNote:original options:0];
        [self tagNote:self];
        editor = (id)[noteTagsField currentEditor];
        [editor insertText:@"reviewtag" replacementRange:NSMakeRange(0, [[editor string] length])];
        Check([noteTagsField currentEditor] && ![self searchFieldHasFocus] &&
            [labelsOfNote(original) length] == 0, @"a pending tag edit is distinct from focused search input");
        created = [self nv_r2CommandN:fallback];
        Check([labelsOfNote(original) isEqual:@"reviewtag"] && [labelsOfNote(created) length] == 0,
            @"Command-N commits the old note's tags without copying them into the new note");
        [library removeNote:created]; Pump();

        [prefsController setShowTitleInTopSection:NO sender:nil];
        [prefsController setShowTagsInTopSection:NO sender:nil];
        for (NSNumber *searchFocus in @[@NO, @YES]) {
            [self searchForString:@"Renamed Anchor" mode:@"exact"]; [self revealNote:original options:0];
            [self setViewingNote:YES];
            if ([searchFocus boolValue]) [self bringFocusToControlField:self];
            else [self focusNoteBody];
            Check([self isViewingNote] && [self searchFieldHasFocus] == [searchFocus boolValue] &&
                [[field stringValue] isEqual:@"Renamed Anchor"],
                @"Preview starts with nonempty Search and the requested focus owner");
            created = [self nv_r2CommandN:[searchFocus boolValue] ? @"Renamed Anchor" : fallback];
            Check([titleOfNote(original) isEqual:@"Renamed Anchor"] &&
                [[[original contentString] string] isEqual:@"# Preserved source"] &&
                [labelsOfNote(original) isEqual:@"reviewtag"],
                @"leaving Preview preserves the old note's title, tags, and source");
            [library removeNote:created]; Pump();
        }
        NSLog(@"PASS: %lu round 2 Ousterhout transition checks", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
