// Independent contract probe: the title oracle is literal input, never the query/result.
static NSString *ContrarianSubmittedTitle;

- (NoteObject *)nv_contrarianStaleTitle:(NSString *)title {
    return [self nv_contrarianStaleTitle:ContrarianSubmittedTitle];
}

- (NoteObject *)nv_contrarianCommandNExpect:(NSString *)expected original:(NoteObject *)original {
    NotationController *library = [self sharedNotationController];
    NSUInteger count = [library totalNoteCount];
    [ContrarianSubmittedTitle release];
    ContrarianSubmittedTitle = [[[self browserSession] searchString] copy];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
    Check([[NSApp mainMenu] performKeyEquivalent:event], @"Command-N resolves through the real application menu");
    Pump();
    NoteObject *created = [self selectedNoteObject];
    Check(created != nil && created != original && [library totalNoteCount] == count + 1,
        @"Command-N creates a distinct note even when the existing title matches");
    Check([[titleOfNote(created) dataUsingEncoding:NSUTF8StringEncoding]
        isEqual:[expected dataUsingEncoding:NSUTF8StringEncoding]],
        @"the title equals the literal expected UTF-8 input, including spaces and punctuation");
    Check([[created contentString] length] == 0 && [[[original contentString] string] isEqual:@"Existing body"],
        @"creation starts empty and preserves the previously selected body");
    Check([[field stringValue] length] == 0 && [[[self browserSession] searchString] length] == 0,
        @"creation clears the field and submitted query");
    return created;
}

- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        if (getenv("NV_CONTRARIAN_STALE_TITLE"))
            Swap([AppController class], @selector(createNoteIfNecessaryWithTitle:), @selector(nv_contrarianStaleTitle:));
        NotationController *library = [self sharedNotationController];
        NoteObject *original = MakeNote(library, @"Existing title", @"Existing body");
        [self searchForString:@"Existing title" mode:@"exact"];
        [self revealNote:original options:0];
        NSTextView *editor = (id)[field currentEditor];
        Check([self searchFieldHasFocus] && [self selectedNoteObject] == original,
            @"the original matching note is selected while Search owns keyboard focus");
        NSString *literal = @"  '📓 cafe\u0301' | !draft^$  ";
        [editor setString:literal];
        [editor setSelectedRange:NSMakeRange(3, 2)];
        Check(![[[self browserSession] searchString] isEqual:literal],
            @"live input differs from the submitted query used by the negative control");
        NoteObject *created = [self nv_contrarianCommandNExpect:literal original:original];
        [library removeNote:created]; Pump();

        [self searchForString:@"Existing title" mode:@"exact"];
        [self revealNote:original options:0];
        Check([self searchFieldHasFocus], @"the duplicate-title case begins in focused Search");
        created = [self nv_contrarianCommandNExpect:@"Existing title" original:original];
        Check([titleOfNote(original) isEqual:@"Existing title"], @"duplicate creation preserves the original title");
        [library removeNote:created]; Pump();

        [self searchForString:@"Existing title" mode:@"exact"];
        [self revealNote:original options:0];
        [window makeFirstResponder:textView];
        Check(![self searchFieldHasFocus] && [[field stringValue] length] > 0,
            @"the body owns focus while Search retains nonempty text");
        [self nv_contrarianCommandNExpect:NSLocalizedString(@"Untitled Note", @"Title of a nameless note") original:original];
        NSLog(@"PASS: %lu contrarian assertions", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) {
        NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1);
    }
}
