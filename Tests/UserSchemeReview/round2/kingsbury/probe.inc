- (void)nv_kAppearance:(BOOL)dark {
    if (@available(macOS 10.14, *))
        [NSApp setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
    else Check(NO, @"the composition probe requires macOS 10.14 appearance support");
    for (NSWindow *nativeWindow in [NSApp windows]) [nativeWindow display];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    Check([window appearance] == nil && [self usesDarkUserColorScheme] == dark,
        @"the browser inherits application appearance through the native callback");
}
- (void)nv_kColors:(BOOL)dark {
    NSColor *foreground = dark ? [prefsController darkForegroundTextColor] : [prefsController foregroundTextColor];
    NSColor *background = dark ? [prefsController darkBackgroundTextColor] : [prefsController backgroundTextColor];
    Check([self usesDarkUserColorScheme] == dark && KSameColor([self foregrndColor], foreground) &&
        KSameColor([textView backgroundColor], background), @"the editor selects the expected palette after lifecycle changes");
}
- (void)nv_kNoHighlights {
    BOOL noHighlights = YES;
    for (NSUInteger i = 0; i < [[textView string] length]; i++)
        if ([[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName
            atCharacterIndex:i effectiveRange:NULL]) noHighlights = NO;
    Check(noHighlights, @"uncommitted composition cannot acquire stale committed-source search backgrounds");
}
- (void)nv_runTests {
    @try {
        NotationController *library = [self sharedNotationController];
        NVApplicationController *app = [NVApplicationController sharedController];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *recordPath = [TestDirectory stringByAppendingPathComponent:@"scheme-commit-record.plist"];
        if (atoi(getenv("NV_REVIEW_PHASE")) == 2) {
            NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:recordPath];
            Check(record != nil && [library totalNoteCount] == 2,
                @"the second process opens exactly the two checkpointed notes");
            NSDictionary *domain = [defaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
            for (NSString *key in KPersistedKeys())
                Check([domain[key] isEqual:record[@"preferences"][key]],
                    [NSString stringWithFormat:@"the archived %@ value survives process restart byte for byte", key]);
            Check(domain[@"DarkForegroundTextColor"] == nil &&
                KSameColor([prefsController darkForegroundTextColor],
                    [NSUnarchiver unarchiveObjectWithData:record[@"registeredDarkForeground"]]),
                @"the unedited dark foreground stays registration-only and retains its default after restart");
            Check([defaults integerForKey:@"ColorScheme"] == 2,
                @"the persisted menu choice is still the existing User Scheme value");
            for (NoteObject *note in [library allNotes]) {
                NSDictionary *expected = record[@"notes"][titleOfNote(note)];
                Check(expected != nil && [expected[@"uuid"] isEqual:[NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)]],
                    @"the reopened note retains its exact UUID and title");
                Check([[[note contentString] string] isEqual:expected[@"source"]] &&
                    [[note sourceSyntaxIdentifier] isEqual:expected[@"syntax"]] &&
                    [labelsOfNote(note) isEqual:expected[@"tags"]],
                    @"committed source, syntax metadata, and tags survive the appearance/edit checkpoint");
                [self searchForString:@"" mode:@"exact"]; [self revealNote:note options:0];
                [self setUserColorScheme:self];
                [self nv_kAppearance:YES]; [self nv_kColors:YES];
                [self nv_kAppearance:NO]; [self nv_kColors:NO];
                Check([[textView string] isEqual:expected[@"source"]],
                    @"reopening and drawing both palettes retains the committed source");
            }
            NSLog(@"KINGSBURY USER SCHEME ROUND 2 RELAUNCH PASSED (%lu checks)", (unsigned long)Checks);
            exit(0);
        }
        [prefsController setForegroundTextColor:KColor(.1,.15,.2,1) sender:nil];
        [prefsController setBackgroundTextColor:KColor(.95,.9,.85,1) sender:nil];
        [prefsController setSearchTermHighlightColor:KColor(.8,.3,.2,.4) sender:nil];
        [prefsController setShouldHighlightSearchTerms:YES sender:nil];
        NSColor *registeredDarkForeground = [[prefsController darkForegroundTextColor] retain];
        [self setUserColorScheme:self];
        NoteObject *a = MakeNote(library, @"draft A", @"# draft\nOriginal **Markdown** source.");
        NoteObject *b = MakeNote(library, @"draft B", @"{\"draft\": \"Original JSON source\"}");
        [a setSourceSyntaxIdentifier:@"markdown"]; [b setSourceSyntaxIdentifier:@"json"];
        [a setLabelString:@"work"]; [b setLabelString:@"reference"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self && [peer sharedNotationController] == library,
            @"two native browser windows share the disposable library");
        for (AppController *browser in @[self, peer]) {
            [browser setUserColorScheme:browser];
            [browser searchForString:@"draft" mode:@"exact"];
            [browser revealNote:a options:0];
        }
        [self nv_kAppearance:NO];
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        Check([textView textStorage] == [peerEditor textStorage], @"both editors initially share the Markdown source storage");
        NSUInteger draftIndex = [[textView string] rangeOfString:@"draft"].location;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (![[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:draftIndex effectiveRange:NULL] &&
            [deadline timeIntervalSinceNow] > 0) Pump();
        Check([[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:draftIndex effectiveRange:NULL] != nil,
            @"the initial real Exact search supplies a source decoration before composition");
        [[a undoManager] removeAllActions]; [[b undoManager] removeAllActions];
        [self nv_activateBrowser]; [window makeFirstResponder:textView];
        NSString *original = [[[a contentString] string] copy];
        NSString *otherOriginal = [[[b contentString] string] copy];
        NSString *marked = @"日本語 📝 ";
        [textView setMarkedText:marked selectedRange:NSMakeRange([marked length],0) replacementRange:NSMakeRange(0,0)];
        Check([textView hasMarkedText] && [[[a contentString] string] isEqual:original],
            @"native source composition changes live storage while the model retains committed text");
        NSRange markedRange = [textView markedRange], selection = [textView selectedRange];
        NSAttributedString *liveBefore = [[[textView textStorage] copy] autorelease];
        NVNoteEditingSession *editing = [app editingSessionForNote:a];
        uint64_t generation = [editing sourceGeneration];
        for (NSUInteger step = 0; step < 6; step++) {
            BOOL transitions = getenv("NV_SCHEME_NO_TRANSITIONS") == NULL;
            BOOL dark = transitions && (step % 2) == 0;
            if (transitions && step == 1) [prefsController setDarkBackgroundTextColor:KColor(.03,.06,.09,1) sender:nil];
            if (transitions && step == 2) [prefsController setDarkSearchTermHighlightColor:KColor(.9,.7,.2,.5) sender:nil];
            if (transitions && step == 3) [prefsController setForegroundTextColor:KColor(.2,.1,.3,1) sender:nil];
            if (step == 2) [peer revealNote:b options:0];
            if (transitions) [self nv_kAppearance:dark];
            else for (NSUInteger i = 0; i < 4; i++) Pump();
            [self nv_kColors:dark]; [peer nv_kColors:dark];
            Check([textView hasMarkedText] && NSEqualRanges([textView markedRange], markedRange) &&
                NSEqualRanges([textView selectedRange], selection) && [window firstResponder] == textView,
                @"appearance, palette edits, and peer navigation retain the active marked range, selection, and focus");
            Check([[textView textStorage] isEqualToAttributedString:liveBefore] && [editing sourceGeneration] == generation,
                @"presentation changes do not alter live composition attributes or its source generation");
            Check([[[a contentString] string] isEqual:original] && [[[b contentString] string] isEqual:otherOriginal] &&
                ![[a undoManager] canUndo] && ![[b undoManager] canUndo],
                @"presentation changes neither commit the composition nor add source Undo entries");
            [self nv_kNoHighlights];
        }
        Check([peer selectedNoteObject] == b && [textView textStorage] != [peerEditor textStorage] &&
            [[peerEditor string] isEqual:otherOriginal], @"the peer's different note keeps independent source storage during composition");
        if (getenv("NV_SCHEME_USE_UNMARK")) [textView unmarkText];
        else [textView insertText:marked replacementRange:[textView markedRange]];
        [self finishEditing]; Pump();
        NSString *expectedCommitted = [marked stringByAppendingString:original];
        Check(![textView hasMarkedText] && [[[a contentString] string] isEqual:expectedCommitted] && [[a undoManager] canUndo],
            @"explicitly ending composition commits the complete source and adds an Undo action");
        Check([[[b contentString] string] isEqual:otherOriginal] && ![[b undoManager] canUndo],
            @"committing the composing note leaves the peer note and its history unchanged");
        NSDictionary *domain = [defaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        NSMutableDictionary *palette = [NSMutableDictionary dictionary];
        for (NSString *key in KPersistedKeys()) {
            Check(domain[key] != nil, [NSString stringWithFormat:@"the explicit %@ edit has a persistent preference value", key]);
            palette[key] = domain[key];
        }
        Check(domain[@"DarkForegroundTextColor"] == nil && KSameColor([prefsController darkForegroundTextColor], registeredDarkForeground),
            @"editing other palette channels does not materialize or mutate the untouched dark foreground default");
        NSMutableDictionary *notes = [NSMutableDictionary dictionary];
        for (NoteObject *note in @[a,b]) notes[titleOfNote(note)] = @{
            @"uuid":[NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)],
            @"source":[[note contentString] string], @"syntax":[note sourceSyntaxIdentifier], @"tags":labelsOfNote(note)};
        NSDictionary *record = @{@"notes":notes, @"preferences":palette,
            @"registeredDarkForeground":[NSArchiver archivedDataWithRootObject:registeredDarkForeground]};
        Check([record writeToFile:recordPath atomically:YES], @"the independent restart oracle records both note identities and palette bytes");
        Check([library flushAllNoteChanges], @"both notes checkpoint successfully before restart");
        [library flushEverything];
        Check([defaults synchronize], @"the preference checkpoint completes before process exit");
        [registeredDarkForeground release]; [original release]; [otherOriginal release];
        NSLog(@"KINGSBURY USER SCHEME ROUND 2 FIRST LAUNCH PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
