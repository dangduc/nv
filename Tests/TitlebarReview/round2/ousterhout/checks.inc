- (void)nv_oWaitSearch {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent], @"query completion stays current after toolbar transitions");
}
- (void)nv_oAssertField:(DualField *)original container:(NSView *)container query:(NSString *)query {
    Check(field == original && [field superview] == container && [dualFieldItem view] == container,
        @"toolbar transitions reuse the same field, item container, and browser ownership");
    Check([field window] == window && [field delegate] == self && [toolbar delegate] == self,
        @"reattached search uses the original window and delegates");
    Check([[[toolbar items] valueForKey:@"itemIdentifier"] isEqual:@[@"Search"]],
        @"reinsertion leaves exactly one Search item");
    Check([[field stringValue] isEqual:query] && [[[self browserSession] searchString] isEqual:query],
        @"field and session preserve native text across detachment");
    [toolbar validateVisibleItems];
    Check([field isEnabled] && [field isEditable] && [field target] == nil && [field action] == NULL,
        @"native toolbar validation preserves the targetless editable search field");
    Check([field currentEditor] != nil && [window firstResponder] == [field currentEditor],
        @"Search restores its native field editor before returning");
    Check(NSWidth([field bounds]) >= 140 && fabs(NSWidth([field bounds]) - NSWidth([container bounds])) < .5,
        @"the pinned field fills the attached container after layout");
}
- (void)nv_oTransitionsWithNote:(NoteObject *)note {
    [self nv_activateBrowser];
    DualField *original = field;
    NSView *container = [dualFieldItem view];
    [self searchForString:@"anchor" mode:@"exact"];
    [self nv_oWaitSearch]; [self revealNote:note options:0];
    [self bringFocusToControlField:self];
    NSTextView *editor = (id)[field currentEditor];
    Check(editor != nil, @"removal fixture starts during native query editing");
    NSString *query = @"anchor café 🧭";
    [editor insertText:query replacementRange:NSMakeRange(0, [[editor string] length])];
    [editor setSelectedRange:NSMakeRange(7, 4)];
    [self nv_oWaitSearch];
    NoteObject *selectedBeforeRemoval = [self selectedNoteObject];
    Check([field currentEditor] == editor, @"the query editor remains active before item removal");
    [toolbar removeItemAtIndex:0];
    Check([[toolbar items] count] == 0, @"AppKit removes Search during active query editing");
    [self bringFocusToControlField:self];
    [self nv_oAssertField:original container:container query:query];
    [self nv_oWaitSearch];
    Check([self selectedNoteObject] == selectedBeforeRemoval, @"item reinsertion preserves the selection present before removal");

    editor = (id)[field currentEditor];
    [editor insertText:@"anchor" replacementRange:NSMakeRange(0, [[editor string] length])];
    [self nv_oWaitSearch];
    NoteObject *selectedBeforeDetach = [self selectedNoteObject];
    [window setToolbar:nil];
    Check([window toolbar] == nil, @"AppKit detaches the whole toolbar during query editing");
    [window setToolbar:toolbar];
    [self bringFocusToControlField:self];
    [self nv_oAssertField:original container:container query:@"anchor"];
    [window makeFirstResponder:textView];
    for (NSUInteger i = 0; i < 3; i++) Pump();
    Check([window firstResponder] == textView, @"reattachment leaves no deferred search focus after body navigation");
    Check([self selectedNoteObject] == selectedBeforeDetach, @"whole-toolbar reattachment preserves the selection present before detachment");

    [self searchForString:@"query with no matches" mode:@"exact"];
    [self nv_oWaitSearch];
    [self bringFocusToControlField:self];
    [toolbar validateVisibleItems];
    Check([self selectedNoteObject] == nil && [field isEnabled] && [field isEditable] && [field currentEditor] != nil,
        @"native validation keeps Search editable without any selected note");
    [self searchForString:@"anchor" mode:@"exact"];
    [self nv_oWaitSearch]; [self revealNote:note options:0];
    [self bringFocusToControlField:self];
    [toolbar validateVisibleItems];
    Check([self selectedNoteObject] == note && [field isEnabled] && [field isEditable] && [field currentEditor] != nil,
        @"native validation keeps Search editable with a selected note");
}
- (void)nv_runTests {
    @try {
        NVReviewDeaths = [[NSMutableDictionary alloc] init];
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *note = [MakeNote(library, @"Ownership fixture", @"anchor café 🧭 original body") retain];
        [self searchForString:@"anchor" mode:@"exact"];
        [self nv_oWaitSearch]; [self revealNote:note options:0];
        NVNoteEditingSession *session = [app editingSessionForNote:note];
        NSUInteger initialLayouts = [[[session textStorage] layoutManagers] count];
        Check(initialLayouts == 1, @"the surviving browser owns one layout manager before peer creation");
        for (NSUInteger cycle = 0; cycle < 4; cycle++) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            [app newWindow:self]; Pump();
            AppController *peer = [[app browserControllers] lastObject];
            Check(peer != self, @"closure fixture uses a disposable secondary browser");
            NVReviewObserve(peer, @"controller");
            NVReviewObserve([peer valueForKey:@"field"], @"field");
            NVReviewObserve([peer valueForKey:@"toolbar"], @"toolbar");
            NVReviewObserve([peer valueForKey:@"dualFieldItem"], @"item");
            NVReviewObserve([[peer valueForKey:@"dualFieldItem"] view], @"container");
            [peer nv_oTransitionsWithNote:note];
            Check([peer sharedNotationController] == library && [[[session textStorage] layoutManagers] count] == initialLayouts + 1,
                @"toolbar transitions keep the shared library and one layout manager per browser");
            Check([[[self browserSession] searchString] isEqual:@"anchor"] && [self selectedNoteObject] == note,
                @"peer query transitions preserve the surviving browser state");
            if (getenv("NV_OWNERSHIP_CYCLE_CONTROL")) {
                // Deliberate strong delegate-like edge. Production delegates are nonretaining.
                objc_setAssociatedObject([peer valueForKey:@"field"], &NVReviewCycleKey, peer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [[peer window] close];
            Check([[app browserControllers] count] == 1, @"native window close removes the secondary browser registration");
            Check([[[session textStorage] layoutManagers] count] == initialLayouts,
                @"window close detaches only the secondary layout manager");
            // No explicit toolbar removal, controller release, or field-editor abort.
            // Drain the local snapshots before observing normal delayed teardown.
            [pool drain];
            for (NSUInteger tick = 0; tick < 40; tick++) {
                NSAutoreleasePool *tickPool = [[NSAutoreleasePool alloc] init]; Pump(); [tickPool drain];
                BOOL complete = YES;
                for (NSString *name in @[@"controller", @"field", @"toolbar", @"item", @"container"])
                    if ([[NVReviewDeaths objectForKey:name] unsignedIntegerValue] < cycle + 1) complete = NO;
                if (complete) break;
            }
            NSLog(@"DEATHS cycle=%lu %@", (unsigned long)cycle, NVReviewDeaths);
            Check([[NVReviewDeaths objectForKey:@"controller"] unsignedIntegerValue] == cycle + 1,
                @"native close releases the secondary controller without manual toolbar detachment");
            for (NSString *name in @[@"field", @"toolbar", @"item", @"container"]) {
                Check([[NVReviewDeaths objectForKey:name] unsignedIntegerValue] == cycle + 1,
                    [NSString stringWithFormat:@"native close releases exactly one %@", name]);
            }
            Check([library totalNoteCount] == 1 && [titleOfNote(note) isEqual:@"Ownership fixture"] &&
                [[[note contentString] string] isEqual:@"anchor café 🧭 original body"],
                @"search transitions and window close preserve fixture note count, title, and body");
        }
        [note release]; [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"OUSTERHOUT_ROUND_2_PASS checks=%lu deaths=%@", (unsigned long)Checks, NVReviewDeaths);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
