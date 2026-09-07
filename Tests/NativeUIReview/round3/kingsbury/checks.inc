- (void)nv_activate {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ((![NSApp isActive] || [NSApp keyWindow] != window || [NSApp mainWindow] != window) &&
        [deadline timeIntervalSinceNow] > 0) Pump();
    Check([NSApp isActive] && [NSApp keyWindow] == window && [NSApp mainWindow] == window &&
        [[NVApplicationController sharedController] activeBrowser] == self,
        @"native key window and main window identify the intended browser");
}
- (NSString *)nv_noteID:(NoteObject *)note {
    return [NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]];
}
- (void)nv_checkLayout:(CGFloat)height {
    for (NSUInteger i = 0; i < 4; i++) Pump();
    NSView *content = [window contentView];
    NSRect listFrame = [notesSubview convertRect:[notesSubview bounds] toView:content];
    NSRect bodyFrame = [textScrollView convertRect:[textScrollView bounds] toView:content];
    NSColor *color = [[notesTableView backgroundColor] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
    NSLog(@"LAYOUT query=%@ height=%.2f expected=%.2f list=%@ body=%@ white=%.3f appearance=%@ scrollBackground=%@", [[self browserSession] searchString],
        [self notesListHeight], height, NSStringFromRect(listFrame), NSStringFromRect(bodyFrame), [color whiteComponent],
        [[notesSubview appearance] name], [notesScrollView backgroundColor]);
    Check(![splitView isVertical] && NSMinY(listFrame) >= NSMaxY(bodyFrame) && NSHeight(bodyFrame) >= 100,
        @"restored native list remains above a usable body editor");
    Check(fabs(NSWidth(listFrame) - NSWidth(bodyFrame)) < 2 && fabs([self notesListHeight] - height) < 2,
        @"restored panes retain full width and their browser-specific divider height");
    Check([color whiteComponent] > .99 && [[[notesSubview appearance] name] isEqual:NSAppearanceNameAqua],
        @"restored notes list retains its white background and Aqua appearance");
}
- (NSDictionary *)nv_saveBrowserForNote:(NoteObject *)note query:(NSString *)query height:(CGFloat)height {
    [self nv_activate];
    [window setContentSize:NSMakeSize(760, 700)];
    [self searchForString:query]; [self revealNote:note options:0];
    [window makeFirstResponder:textView];
    [self setNotesListHeight:height];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    [textView setSelectedRange:NSMakeRange(2, 3)];
    Check([self selectedNoteObject] == note && [[[self browserSession] searchString] isEqual:query],
        @"reopened browser selects its intended note under its own query");
    [self nv_checkLayout:height];
    return @{@"query":query, @"noteID":[self nv_noteID:note], @"divider":@([self notesListHeight])};
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSString *phase = [NSString stringWithUTF8String:getenv("NV_REVIEW_PHASE") ?: ""];
        NSString *expectedPath = [TestDirectory stringByAppendingPathComponent:@"expected.plist"];
        if ([phase isEqual:@"1"]) {
            Check([library totalNoteCount] == 0 && [[app browserControllers] count] == 1,
                @"first process starts with one browser and an empty isolated library");
            NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha anchor body") retain];
            NoteObject *beta = [MakeNote(library, @"Beta", @"beta shared body") retain];
            [app newWindow:self]; Pump();
            AppController *peer = [[[app browserControllers] lastObject] retain];
            [self nv_activate]; [self revealNote:alpha options:0];
            [window makeFirstResponder:textView];
            [textView insertText:@" local edit" replacementRange:NSMakeRange([[textView string] length], 0)]; Pump();
            [self renameNote:self];
            NSTextView *titleEditor = (id)[noteTitleField currentEditor];
            Check(titleEditor != nil && [window firstResponder] == titleEditor, @"title edit owns the actual field editor before closure");
            [titleEditor insertText:@"Closed Alpha" replacementRange:NSMakeRange(0, [[titleEditor string] length])];
            Check([titleOfNote(alpha) isEqual:@"Alpha"] && [[titleEditor string] isEqual:@"Closed Alpha"],
                @"native title is still pending immediately before window closure");
            [window performClose:self]; Pump();
            Check([[app browserControllers] count] == 1 && [titleOfNote(alpha) isEqual:@"Closed Alpha"] &&
                [[[alpha contentString] string] isEqual:@"alpha anchor body local edit"],
                @"closing the origin commits its pending title and retains its earlier body edit");

            [peer nv_activate]; [peer revealNote:beta options:0];
            [peer tagNote:self];
            NSTextField *tags = [peer valueForKey:@"noteTagsField"];
            NSTextView *tagsEditor = (id)[tags currentEditor];
            Check(tagsEditor != nil && [[peer window] firstResponder] == tagsEditor,
                @"tags edit owns the actual field editor before closure");
            [tagsEditor setMarkedText:@"closed, durable" selectedRange:NSMakeRange(15, 0)
                replacementRange:NSMakeRange(0, [[tagsEditor string] length])];
            [beta setContentString:[[[NSAttributedString alloc] initWithString:@"beta shared external text"] autorelease]]; Pump();
            Check([tagsEditor hasMarkedText] && [labelsOfNote(beta) length] == 0 &&
                [[[peer valueForKey:@"textView"] string] isEqual:@"beta shared external text"],
                @"external body snapshot preserves the pending tags composition");
            [[peer window] performClose:self]; Pump();
            Check([[app browserControllers] count] == 0 && [labelsOfNote(beta) isEqual:@"closed, durable"] &&
                [[[beta contentString] string] isEqual:@"beta shared external text"],
                @"closing the last browser commits composed tags and retains the external body snapshot");

            [app applicationShouldHandleReopen:NSApp hasVisibleWindows:NO]; Pump();
            Check([[app browserControllers] count] == 1 && [app library] == library,
                @"native application reopen retains the original in-memory library");
            AppController *reopened = [[app browserControllers] lastObject];
            NSDictionary *first = [reopened nv_saveBrowserForNote:alpha query:@"anchor" height:160];
            [app newWindow:self]; Pump();
            AppController *second = [[app browserControllers] lastObject];
            NSDictionary *last = [second nv_saveBrowserForNote:beta query:@"shared" height:238];
            NSDictionary *expected = @{@"alphaID":[self nv_noteID:alpha], @"betaID":[self nv_noteID:beta], @"browsers":@[first, last]};
            Check([expected writeToFile:expectedPath atomically:YES], @"expected stable note identities and browser geometry save outside application state");
            Check([[app browserControllers] count] == 2 && [library totalNoteCount] == 2,
                @"normal termination starts with exactly two reopened browsers and two notes");
            [alpha release]; [beta release]; [peer release];
            NSLog(@"ROUND 3 KINGSBURY PHASE 1 PASSED (%lu checks), requesting normal application termination", (unsigned long)Checks);
            [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
        } else {
            Check([phase isEqual:@"2"], @"fresh process runs the durable read phase");
            NSDictionary *expected = [NSDictionary dictionaryWithContentsOfFile:expectedPath];
            Check(expected != nil && [[app browserControllers] count] == 2 && [library totalNoteCount] == 2,
                @"fresh process loads exactly two saved notes and two reopened browsers");
            NoteObject *alpha = nil, *beta = nil;
            for (NoteObject *note in [library allNotes]) {
                if ([[self nv_noteID:note] isEqual:expected[@"alphaID"]]) alpha = note;
                if ([[self nv_noteID:note] isEqual:expected[@"betaID"]]) beta = note;
            }
            Check(alpha != nil && beta != nil && alpha != beta, @"both durable notes preserve their original UUIDs without duplication");
            Check([titleOfNote(alpha) isEqual:@"Closed Alpha"] && [labelsOfNote(alpha) length] == 0 &&
                [[[alpha contentString] string] isEqual:@"alpha anchor body local edit"],
                @"fresh model restores the title committed on closure and the exact local body edit");
            Check([titleOfNote(beta) isEqual:@"Beta"] && [labelsOfNote(beta) isEqual:@"closed, durable"] &&
                [[[beta contentString] string] isEqual:@"beta shared external text"],
                @"fresh model restores tags committed on closure and the exact external body snapshot");
            NSArray *browsers = [app browserControllers];
            for (NSUInteger i = 0; i < [browsers count]; i++) {
                AppController *browser = browsers[i];
                NSDictionary *state = expected[@"browsers"][i];
                [browser nv_activate];
                Check([[[browser browserSession] searchString] isEqual:state[@"query"]] &&
                    [[[browser valueForKey:@"field"] stringValue] isEqual:state[@"query"]],
                    @"fresh process restores the browser query in both session and visible field");
                NoteObject *selected = [browser selectedNoteObject];
                Check(selected != nil && [[self nv_noteID:selected] isEqual:state[@"noteID"]],
                    @"fresh process selects the saved note identity for this browser");
                LinkingEditor *body = [browser valueForKey:@"textView"];
                Check([[body string] isEqual:[[selected contentString] string]] &&
                    [[[browser valueForKey:@"noteTitleField"] stringValue] isEqual:titleOfNote(selected)] &&
                    [[[browser valueForKey:@"noteTagsField"] stringValue] isEqual:labelsOfNote(selected) ?: @""],
                    @"restored body and metadata controls agree with the durable note model");
                Check(NSEqualRanges([body selectedRange], NSMakeRange(2, 3)), @"fresh process restores the saved body selection range");
                [browser nv_checkLayout:[state[@"divider"] doubleValue]];
                NSLog(@"DURABLE browser=%lu query=%@ title=%@ tags=%@ body=%@ divider=%.2f", (unsigned long)i,
                    [[browser browserSession] searchString], titleOfNote(selected), labelsOfNote(selected), [body string], [browser notesListHeight]);
            }
            Check([library flushAllNoteChanges], @"durable read phase flushes its isolated library");
            [library closeJournal];
            NSLog(@"ROUND 3 KINGSBURY PHASE 2 PASSED (%lu checks)", (unsigned long)Checks);
            exit(0);
        }
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
