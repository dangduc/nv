- (void)nv_createControlAwait {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent], @"creation control publishes current results");
}
- (void)nv_runTests {
    @try {
        BOOL oldMethod = getenv("NV_SUMMARY_OLD_AFFORDANCE") != NULL;
        if (oldMethod) Swap([AppController class], @selector(updateSearchAffordance), @selector(nv_oldSummaryAffordance));
        [self nv_activateBrowser];
        NotationController *library = [[NVApplicationController sharedController] library];
        MakeNote(library, @"Road map", @"road planning source");
        [prefsController setAutoCompleteSearches:NO sender:self];
        NSString *query = @"absent summary creation control";
        [self searchForString:query mode:@"fuzzy"]; [self nv_createControlAwait];
        Check([searchStatusField isHidden] == !oldMethod &&
            NSHeight([notesSubview bounds]) - NSHeight([notesScrollView frame]) == (oldMethod ? 24 : 0),
            @"control visibly installs the intended old or new summary method");
        Check([[self browserSession] resultCount] == 0 && ![createNoteButton isHidden],
            @"control has zero results and a visible Create button");
        [createNoteButton performClick:self]; [self nv_createControlAwait];
        NSUInteger matches = 0;
        for (NoteObject *note in [library allNotes]) if ([titleOfNote(note) isEqual:query]) matches++;
        Check([library totalNoteCount] == 2 && matches == 1, @"Create adds exactly one note with the query title");
        NSLog(@"CREATE_CONTROL oldMethod=%d count=%lu selected=%d pending=%d results=%lu", oldMethod,
            (unsigned long)[library totalNoteCount], [self selectedNoteObject] != nil,
            [[self browserSession] searchPending], (unsigned long)[[self browserSession] resultCount]);
        NSLog(@"CREATE_CONTROL_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) { NSLog(@"CREATE_CONTROL_EXCEPTION %@", exception); exit(2); }
}
