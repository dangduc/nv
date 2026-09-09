- (NVHeldNewNoteDelivery *)nv_kingsburyQueueReturn:(NSString *)query {
    [self nv_activateBrowser];
    NSUInteger before = [HeldNewNoteDeliveries count];
    [self searchForString:query mode:@"fuzzy"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while ([HeldNewNoteDeliveries count] == before && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([HeldNewNoteDeliveries count] > before, @"real fuzzy result reaches the controlled delivery boundary");
    NVHeldNewNoteDelivery *held = [HeldNewNoteDeliveries objectAtIndex:before];
    Check(held->result && !held->error && [[self browserSession] searchPending] &&
        ![[self browserSession] searchResultsAreCurrent], @"successful fuzzy work remains pending before browser publication");
    [self performSearchReturn];
    Check([[self valueForKey:@"pendingSearchReturnQuery"] isEqual:query], @"Return records an intent before Command-N");
    return held;
}

- (NoteObject *)nv_kingsburyCreate:(NSString *)title {
    [self nv_activateBrowser];
    [self bringFocusToControlField:self];
    NSTextView *editor = (id)[field currentEditor];
    [editor setString:title];
    Check([self searchFieldHasFocus] && ![[[self browserSession] searchString] isEqual:title],
        @"key browser has live search input newer than its held query");
    NSUInteger before = [[self sharedNotationController] totalNoteCount];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
    Check([[NSApp mainMenu] performKeyEquivalent:event], @"native application menu dispatches Command-N");
    NoteObject *created = [self selectedNoteObject];
    Check(created && [titleOfNote(created) isEqual:title] &&
        [[self sharedNotationController] totalNoteCount] == before + 1,
        @"Command-N creates one note from this browser's captured live input");
    Check(![self valueForKey:@"pendingSearchReturnQuery"] && [[field stringValue] length] == 0 &&
        [[[self browserSession] searchString] length] == 0 && [[self browserSession] searchResultsAreCurrent],
        @"Command-N consumes the old Return intent and clears search synchronously");
    Check([window firstResponder] == textView, @"new source receives keyboard focus");
    return created;
}

- (void)nv_runTests {
    @try {
        NotationController *library = [self sharedNotationController];
        NSString *recordPath = [TestDirectory stringByAppendingPathComponent:@"created-identities.plist"];
        if (atoi(getenv("NV_REVIEW_PHASE")) == 2) {
            NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:recordPath];
            Check([record count] == 2 && [library totalNoteCount] == 2, @"second launch opens exactly the two checkpointed notes");
            for (NoteObject *note in [library allNotes]) {
                NSData *uuid = [NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)];
                Check([[record objectForKey:titleOfNote(note)] isEqual:uuid], @"reopened title retains its original note UUID");
                Check([[note contentString] length] == 0, @"reopened new note remains empty source");
            }
            NSLog(@"KINGSBURY ROUND 1 PHASE 2 PASSED (%lu checks)", (unsigned long)Checks);
            exit(0);
        }
        [prefsController setShowTitleInTopSection:NO sender:nil];
        Check([library totalNoteCount] == 0, @"schedule starts with an empty disposable library");
        InstallNewNoteDeliveryGate();
        NVApplicationController *app = [NVApplicationController sharedController];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self && [peer sharedNotationController] == library, @"two browsers share the same disposable library");
        NVHeldNewNoteDelivery *first = [[self nv_kingsburyQueueReturn:@"held-A"] retain];
        NVHeldNewNoteDelivery *second = [[peer nv_kingsburyQueueReturn:@"held-B"] retain];
        NoteObject *b = [[peer nv_kingsburyCreate:@"Captured B 📝"] retain];
        Check([self selectedNoteObject] != b && [[[self browserSession] searchString] isEqual:@"held-A"],
            @"peer creation preserves the other browser's query and ownership");
        NoteObject *a = [[self nv_kingsburyCreate:@"Captured A 日本語"] retain];
        Check(a != b && memcmp([a uniqueNoteIDBytes], [b uniqueNoteIDBytes], sizeof(CFUUIDBytes)) != 0,
            @"the two creations have different objects and UUIDs");
        // Deliver actual pre-creation results in reverse order, then repeat them.
        // Duplicate delivery exceeds the service contract and tests the browser fence.
        for (NSUInteger repeat = 0; repeat < 2; repeat++) {
            [peer nv_activateBrowser];
            [second deliver]; [first deliver]; Pump();
            Check([library totalNoteCount] == 2 && [self selectedNoteObject] == a && [peer selectedNoteObject] == b,
                @"late pre-creation results cannot select another note or create a duplicate");
            Check([titleOfNote(a) isEqual:@"Captured A 日本語"] && [titleOfNote(b) isEqual:@"Captured B 📝"],
                @"late deliveries preserve both captured titles");
            Check([[[self browserSession] searchString] length] == 0 && [[[peer browserSession] searchString] length] == 0 &&
                [[self browserSession] searchResultsAreCurrent] && [[peer browserSession] searchResultsAreCurrent],
                @"late deliveries cannot restore either obsolete query or pending state");
            Check([[peer window] firstResponder] == [peer valueForKey:@"textView"],
                @"late deliveries preserve the active peer's source focus");
        }
        [first release]; [second release]; RemoveNewNoteDeliveryGate();
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        for (NoteObject *note in @[a, b]) [record setObject:[NSData dataWithBytes:[note uniqueNoteIDBytes]
            length:sizeof(CFUUIDBytes)] forKey:titleOfNote(note)];
        Check([record writeToFile:recordPath atomically:YES], @"record exact created identities for second launch");
        Check([library flushAllNoteChanges], @"both notes checkpoint successfully before the second launch");
        [library flushEverything];
        [a release]; [b release];
        NSLog(@"KINGSBURY ROUND 1 PHASE 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
