// Actual-app review probe. The runner isolates the app, preferences, and library.
- (void)nv_mutatingFinishEditing {
    [self nv_mutatingFinishEditing]; // Original implementation while exchanged.
    [(NSTextView *)[field currentEditor] setString:@"Changed after title capture"];
}

- (void)nv_runTests {
    [self nv_activateBrowser];
    NotationController *library = [self sharedNotationController];
    [prefsController setAutoCompleteSearches:NO sender:nil];
    [prefsController setShowTitleInTopSection:NO sender:nil];
    NSUInteger count = [library totalNoteCount];

    [self searchForString:@"Legacy wrapper title" mode:@"exact"];
    Check(![self selectedNoteObject], @"legacy creation starts without a selected note");
    NoteObject *legacy = [[self createNoteIfNecessary] retain];
    Check(legacy && [titleOfNote(legacy) isEqual:@"Legacy wrapper title"] &&
        [library totalNoteCount] == count + 1, @"legacy wrapper still creates from the field value");
    [field setStringValue:@"Do not rename existing note"];
    Check([self createNoteIfNecessary] == legacy &&
        [self createNoteIfNecessaryWithTitle:@"Ignored argument"] == legacy &&
        [library totalNoteCount] == count + 1 && [titleOfNote(legacy) isEqual:@"Legacy wrapper title"],
        @"both creation entry points reuse an existing note without renaming or duplicating it");

    [self searchForString:@"No existing note matches this title" mode:@"exact"];
    Check(![self selectedNoteObject], @"nil-title helper starts without a selected note");
    NoteObject *fallback = [[self createNoteIfNecessaryWithTitle:nil] retain];
    Check([titleOfNote(fallback) isEqual:NSLocalizedString(@"Untitled Note", @"Title of a nameless note")],
        @"nil title preserves the localized unnamed-note fallback");

    [self searchForString:@"Captured title 📝" mode:@"exact"];
    Check([self searchFieldHasFocus], @"snapshot test owns the live search field editor");
    // Deliberately mutate the field editor after the newNote: snapshot. This is
    // an ownership stressor, not a claim that finishEditing normally changes it.
    Swap([AppController class], @selector(finishEditing), @selector(nv_mutatingFinishEditing));
    [self newNote:self];
    Swap([AppController class], @selector(finishEditing), @selector(nv_mutatingFinishEditing));
    NoteObject *snapshot = [[self selectedNoteObject] retain];
    Check([titleOfNote(snapshot) isEqual:@"Captured title 📝"] &&
        [library totalNoteCount] == count + 3,
        @"copied title survives deliberate mutation of the original field editor");
    [field setStringValue:@"Later unrelated query"];
    Pump();
    Check([titleOfNote(snapshot) isEqual:@"Captured title 📝"] && [[snapshot contentString] length] == 0,
        @"the created note owns its title after the search field is reused");

    [library removeNote:snapshot]; [snapshot release];
    [library removeNote:fallback]; [fallback release];
    [library removeNote:legacy]; [legacy release];
    NSLog(@"Torvalds-inspired review: %lu checks passed", (unsigned long)Checks);
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
}
