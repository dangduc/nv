- (NSData *)nv_kingsburyFileUUID:(NoteObject *)note {
    return [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
}

- (NoteObject *)nv_kingsburyFileCreate:(NSString *)title body:(NSString *)body mode:(NSString *)mode {
    [self nv_activateBrowser];
    // The legacy helper's asynchronous Reveal is outside this storage control.
    // Exact mode makes its post-creation selection synchronous in both cases.
    if (getenv("NV_KINGSBURY_LEGACY_TITLE")) mode = @"exact";
    [self searchForString:@"Submitted query differs from the title" mode:mode];
    NSTextView *editor = (id)[field currentEditor];
    [editor setString:title];
    Check([self searchFieldHasFocus] && ![[[self browserSession] searchString] isEqual:title],
        @"focused live input differs from the submitted query in file storage");
    NSUInteger before = [[self sharedNotationController] totalNoteCount];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
    if (getenv("NV_KINGSBURY_LEGACY_TITLE")) {
        // Prior entry point retained unchanged by this PR. Reset selection so
        // duplicate titles exercise creation instead of reusing the open note.
        [notesTableView deselectAll:nil]; [self _setCurrentNote:nil];
        [self setEmptyViewState:YES]; [textView setString:@""];
        [field setStringValue:title];
        Check([self createNoteIfNecessary] != nil, @"legacy query-title creation succeeds in file storage");
        [self focusNoteBody];
    } else Check([[NSApp mainMenu] performKeyEquivalent:event], @"native Command-N dispatch succeeds in file storage");
    NoteObject *created = [self selectedNoteObject];
    Check(created && [[self sharedNotationController] totalNoteCount] == before + 1,
        @"Command-N adds exactly one note in file storage");
    Check([[titleOfNote(created) dataUsingEncoding:NSUTF8StringEncoding] isEqual:[title dataUsingEncoding:NSUTF8StringEncoding]],
        @"title preserves raw input bytes before filename conversion");
    Check([[created contentString] length] == 0 && [window firstResponder] == textView,
        @"new file-backed note starts with an empty focused source editor");
    [textView insertText:body replacementRange:NSMakeRange(0, 0)]; Pump();
    Check([[[created contentString] string] isEqual:body], @"native source typing commits to the created note");
    Check([[self sharedNotationController] flushAllNoteChanges], @"created source checkpoints to its backing file");
    NSString *path = [created noteFilePath];
    Check([[[path stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath]
        isEqual:[[[TestDirectory stringByAppendingPathComponent:@"Notes"] stringByResolvingSymlinksInPath] stringByStandardizingPath]],
        @"filename conversion keeps the backing file directly inside the disposable notes directory");
    Check([[NSData dataWithContentsOfFile:path] isEqual:[body dataUsingEncoding:NSUTF8StringEncoding]],
        @"backing file contains this note's exact source bytes");
    return created;
}

- (void)nv_runTests {
    @try {
        NotationController *library = [self sharedNotationController];
        NSString *recordPath = [TestDirectory stringByAppendingPathComponent:@"file-identities.plist"];
        if (atoi(getenv("NV_REVIEW_PHASE")) == 2) {
            NSArray *records = [NSArray arrayWithContentsOfFile:recordPath];
            Check([library currentNoteStorageFormat] == PlainTextFormat, @"second launch retains separate text-file storage");
            Check([records count] == 2 && [library totalNoteCount] == 2, @"second launch retains both duplicate-title notes");
            NSMutableSet *paths = [NSMutableSet set];
            for (NSDictionary *record in records) {
                NoteObject *found = nil;
                for (NoteObject *candidate in [library allNotes])
                    if ([[self nv_kingsburyFileUUID:candidate] isEqual:record[@"uuid"]]) found = candidate;
                Check(found != nil, @"reopened file-backed note keeps its original UUID");
                NSData *actualTitleBytes = [titleOfNote(found) dataUsingEncoding:NSUTF8StringEncoding];
                if (![actualTitleBytes isEqual:record[@"titleBytes"]])
                    NSLog(@"OBSERVATION: reopened title=%@ expectedUTF8=%@ actualUTF8=%@ legacyControl=%d",
                        titleOfNote(found), record[@"titleBytes"], actualTitleBytes, getenv("NV_KINGSBURY_LEGACY_TITLE") != NULL);
                Check([actualTitleBytes isEqual:record[@"titleBytes"]],
                    @"reopened note preserves the raw title without using its sanitized filename");
                Check([[[found contentString] string] isEqual:record[@"body"]],
                    @"reopened duplicate-title note retains its own source");
                Check([[found noteFilePath] lastPathComponent] &&
                    [[[found noteFilePath] lastPathComponent] isEqual:record[@"filename"]],
                    @"reopened note retains its distinct backing filename");
                Check([[NSData dataWithContentsOfFile:[found noteFilePath]] isEqual:[record[@"body"] dataUsingEncoding:NSUTF8StringEncoding]],
                    @"reopened backing file retains the exact source bytes");
                [paths addObject:[[found noteFilePath] stringByResolvingSymlinksInPath]];
            }
            Check([paths count] == 2, @"both reopened note identities still refer to different files");
            NSLog(@"KINGSBURY ROUND 2 PHASE 2 PASSED (%lu checks)", (unsigned long)Checks);
            exit(0);
        }

        [prefsController setShowTitleInTopSection:NO sender:nil];
        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        Check([library currentNoteStorageFormat] == PlainTextFormat && [library totalNoteCount] == 0,
            @"first launch uses an empty separate-file library");
        NSString *title = getenv("NV_KINGSBURY_DECOMPOSED_TITLE") ?
            @"  \"garden\" / notes: Cafe\u0301 📝  " : @"  \"garden\" / notes: Café 📝  ";
        NoteObject *first = [[self nv_kingsburyFileCreate:title body:@"First source: alpha\n" mode:@"exact"] retain];
        NoteObject *second = [[self nv_kingsburyFileCreate:title body:@"Second source: beta\n" mode:@"fuzzy"] retain];
        Check(first != second && ![[self nv_kingsburyFileUUID:first] isEqual:[self nv_kingsburyFileUUID:second]],
            @"duplicate raw titles produce distinct note objects and UUIDs");
        Check(![[first noteFilePath] isEqual:[second noteFilePath]],
            @"duplicate raw titles produce distinct backing filenames");
        Check([[NSData dataWithContentsOfFile:[first noteFilePath]] isEqual:[@"First source: alpha\n" dataUsingEncoding:NSUTF8StringEncoding]],
            @"creating the second same-title note does not overwrite the first file");
        Check([titleOfNote(first) isEqual:title] && [[[first contentString] string] isEqual:@"First source: alpha\n"],
            @"creating the second same-title note preserves the first model title and source");
        NSMutableArray *records = [NSMutableArray array];
        for (NoteObject *note in @[first, second]) [records addObject:@{
            @"uuid":[self nv_kingsburyFileUUID:note],
            @"titleBytes":[titleOfNote(note) dataUsingEncoding:NSUTF8StringEncoding],
            @"body":[[note contentString] string],
            @"filename":[[note noteFilePath] lastPathComponent]
        }];
        Check([records writeToFile:recordPath atomically:YES], @"record both file identities and raw values before reopening");
        Check([library flushAllNoteChanges], @"both duplicate-title notes checkpoint before reopening");
        [library flushEverything]; [library closeJournal];
        [first release]; [second release];
        NSLog(@"KINGSBURY ROUND 2 PHASE 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
