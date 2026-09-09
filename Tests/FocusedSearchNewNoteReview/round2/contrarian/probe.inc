// Negative control weakens only the key-window requirement, inside the copied app.
- (BOOL)nv_r2FocusWithoutKeyWindow {
    return [field currentEditor] && [window firstResponder] == [field currentEditor];
}

- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        [prefsController setShowTitleInTopSection:YES sender:nil];
        NotationController *library = [self sharedNotationController];
        NoteObject *original = MakeNote(library, @"Original anchor", @"Keep this body");
        [self searchForString:@"Original anchor" mode:@"exact"];
        [self revealNote:original options:0];
        Check([self searchFieldHasFocus], @"first browser begins with focused populated Search");
        NVApplicationController *app = [NVApplicationController sharedController];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"the fixture has two distinct browsers");
        [peer nv_activateBrowser];
        [peer searchForString:@"Original anchor" mode:@"exact"];
        [peer revealNote:original options:0];
        [peer renameNote:self];
        NSTextView *metadata = (id)[[peer valueForKey:@"noteTitleField"] currentEditor];
        [metadata insertText:@"Original anchor renamed" replacementRange:NSMakeRange(0, [[metadata string] length])];
        Check([[peer window] firstResponder] == metadata && ![peer searchFieldHasFocus],
            @"the key browser's title field owns its shared field editor");
        Check(![window isKeyWindow] && [field currentEditor] && [window firstResponder] == [field currentEditor] &&
            ![self searchFieldHasFocus], @"a background browser retains a Search editor without keyboard focus");
        NSUInteger before = [library totalNoteCount];
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
            modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[[peer window] windowNumber]
            context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
        Check([[NSApp mainMenu] performKeyEquivalent:event], @"native Command-N routes to the key browser");
        NoteObject *peerCreated = [peer selectedNoteObject];
        Check(peerCreated && peerCreated != original && [library totalNoteCount] == before + 1 &&
            [titleOfNote(peerCreated) isEqual:NSLocalizedString(@"Untitled Note", @"Title of a nameless note")],
            @"metadata focus creates the default title, ignoring both windows' populated Search fields");
        Check([titleOfNote(original) isEqual:@"Original anchor renamed"] &&
            [[[original contentString] string] isEqual:@"Keep this body"],
            @"native Command-N commits only the original metadata and preserves its body");
        Check([self selectedNoteObject] == original && [[field stringValue] isEqual:@"Original anchor"],
            @"the inactive browser keeps its original selection and query");

        // Explicitly target the inactive browser to test the action's defensive
        // focus boundary independently of menu routing. This is a synthetic call.
        Check(![window isKeyWindow] && [field currentEditor] && [window firstResponder] == [field currentEditor],
            @"the inactive Search editor is still present at the direct-action boundary");
        BOOL mutate = getenv("NV_CONTRARIAN_NO_KEY_CHECK") != NULL;
        if (mutate) Swap([AppController class], @selector(searchFieldHasFocus), @selector(nv_r2FocusWithoutKeyWindow));
        [self newNote:self];
        if (mutate) Swap([AppController class], @selector(searchFieldHasFocus), @selector(nv_r2FocusWithoutKeyWindow));
        NoteObject *backgroundCreated = [self selectedNoteObject];
        Check(backgroundCreated && backgroundCreated != original && backgroundCreated != peerCreated &&
            [library totalNoteCount] == before + 2, @"the direct action creates a separate note in its owning browser");
        Check([titleOfNote(backgroundCreated) isEqual:NSLocalizedString(@"Untitled Note", @"Title of a nameless note")],
            @"an inactive Search editor cannot supply a title without keyboard focus");
        Check([peer selectedNoteObject] == peerCreated && [[backgroundCreated contentString] length] == 0,
            @"the inactive-browser action preserves the peer selection and starts empty source");
        NSLog(@"PASS: %lu round 2 contrarian assertions", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
