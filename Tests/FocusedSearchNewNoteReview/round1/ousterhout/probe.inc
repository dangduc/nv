// Review the title API boundary in the actual copied app, with disposable notes.
- (void)nv_r1PrepareEmptyQuery:(NSString *)query {
    [self searchForString:query mode:@"exact"];
    Check(![self selectedNoteObject] && [[self browserSession] searchResultsAreCurrent],
        @"a unique exact query supplies an empty creation context");
    [textView setString:@""]; // Isolate direct helper cases from the preceding source fixture.
}

- (void)nv_r1PerturbFinishEditing {
    // Only the first boundary call is perturbed; later calls remain production code.
    Swap([AppController class], @selector(finishEditing), @selector(nv_r1PerturbFinishEditing));
    [self finishEditing];
    [field setStringValue:@"Changed synchronously while finishing edits"];
}

- (void)nv_runTests {
    NotationController *library = [[NVApplicationController sharedController] library];
    [prefsController setAutoCompleteSearches:NO sender:nil];
    [prefsController setShowTitleInTopSection:NO sender:nil];
    [self nv_activateBrowser];
    NoteObject *original = MakeNote(library, @"Original note", @"Original body");
    [self revealNote:original options:0];
    NSUInteger count = [library totalNoteCount];
    Check([self createNoteIfNecessaryWithTitle:@"Must not rename"] == original &&
        [library totalNoteCount] == count && [titleOfNote(original) isEqual:@"Original note"],
        @"explicit creation preserves an existing selected note and its title");

    [self nv_r1PrepareEmptyQuery:@"Unmatched field value one"];
    NSMutableString *explicitTitle = [NSMutableString stringWithString:@"Explicit title 日本語 📝"];
    NoteObject *explicit = [self createNoteIfNecessaryWithTitle:explicitTitle];
    [explicitTitle setString:@"Caller changed its mutable title"];
    Check(explicit && [titleOfNote(explicit) isEqual:@"Explicit title 日本語 📝"] &&
        [library totalNoteCount] == ++count, @"explicit title wins over the unrelated field and is owned by the note");
    Check([[explicit contentString] length] == 0 && [titleOfNote(original) isEqual:@"Original note"] &&
        [[[original contentString] string] isEqual:@"Original body"], @"explicit creation leaves the original note unchanged");

    [self nv_r1PrepareEmptyQuery:@"Legacy query title"];
    [textView setString:@"Source entered before implicit creation"];
    NoteObject *legacy = [self createNoteIfNecessary];
    Check([titleOfNote(legacy) isEqual:@"Legacy query title"] &&
        [library totalNoteCount] == ++count, @"legacy creation still takes the query as its title");
    Check([[[legacy contentString] string] isEqual:@"Source entered before implicit creation"],
        @"legacy body-driven creation keeps source already in the editor");
    Check([self createNoteIfNecessary] == legacy && [library totalNoteCount] == count,
        @"legacy creation also returns an existing current note without duplicating it");

    for (id title in @[[NSNull null], @""]) {
        [self nv_r1PrepareEmptyQuery:@"Unmatched field value two"];
        NoteObject *untitled = [self createNoteIfNecessaryWithTitle:title == [NSNull null] ? nil : title];
        Check([titleOfNote(untitled) isEqual:NSLocalizedString(@"Untitled Note", @"Title of a nameless note")] &&
            [library totalNoteCount] == ++count, @"nil or empty explicit title uses the fallback, independently of the query");
    }

    NSString *live = @"Captured before finishing edits e\u0301 📝";
    [self nv_r1PrepareEmptyQuery:@"A submitted query"];
    NSTextView *editor = (id)[field currentEditor];
    [editor setString:live];
    Check([self searchFieldHasFocus] && ![[[self browserSession] searchString] isEqual:live],
        @"the focused live title differs from the browser session query");
    Swap([AppController class], @selector(finishEditing), @selector(nv_r1PerturbFinishEditing));
    [self newNote:self];
    NoteObject *captured = [self selectedNoteObject];
    Check(captured && [titleOfNote(captured) isEqual:live] && [library totalNoteCount] == ++count,
        @"New Note retains the captured live string across a synchronous field mutation during finishEditing");
    Check([[captured contentString] length] == 0 && [[field stringValue] length] == 0 &&
        [[[self browserSession] searchString] length] == 0,
        @"the captured title is separate from the cleared query and new empty body");
    for (NSUInteger i = 0; i < 8; ++i) Pump();
    Check([self selectedNoteObject] == captured && [library totalNoteCount] == count,
        @"deferred callbacks preserve the one created note");
    NSLog(@"PASS: %lu Ousterhout boundary checks", (unsigned long)Checks);
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
}
