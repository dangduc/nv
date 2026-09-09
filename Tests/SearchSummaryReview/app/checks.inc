- (void)nv_summaryAwaitResults {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent], @"actual search completes");
    Check([searchStatusField isHidden] && ![[searchStatusField stringValue] length], @"completed search has no summary label");
    Check(![[field toolTip] length] && ![[searchStatusField toolTip] length], @"completed search has no summary tooltip");
    Check(NSEqualRects([notesScrollView frame], [notesSubview bounds]), @"completed search uses the full notes-list area");
}

- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *road = MakeNote(library, @"Road map", @"Road planning\n\nKeep the source text directly editable.\nSwitch to Preview to read a formatted note.");
        MakeNote(library, @"Project journal", @"The road ahead includes smaller, clearer search controls.");
        MakeNote(library, @"Ideas", @"r---o---a---d");
        [self nv_activateBrowser];
        [prefsController setAutoCompleteSearches:NO sender:self];
        [self searchForString:@"road" mode:@"fuzzy"];
        [self nv_summaryAwaitResults];
        NVBrowserSession *session = [self browserSession];
        Check([session resultCount] == 4 && [session distinctResultNoteCount] == 3, @"search preserves four occurrences across three notes");
        Check([session noteObjectAtFilteredIndex:0] == road && [[session matchKindAtIndex:0] isEqual:@"title"], @"literal title result remains first");
        [self revealNote:road options:0];
        [window setFrame:NSMakeRect(100, 100, 800, 600) display:YES];
        [self bringFocusToControlField:self];
        Pump();
        Check([field currentEditor] != nil && [[field stringValue] isEqual:@"road"], @"active query remains editable");
        if (getenv("NV_SUMMARY_SCREENSHOT")) {
            NSView *frame = [[window contentView] superview];
            [frame layoutSubtreeIfNeeded];
            NSBitmapImageRep *bitmap = [frame bitmapImageRepForCachingDisplayInRect:[frame bounds]];
            [frame cacheDisplayInRect:[frame bounds] toBitmapImageRep:bitmap];
            NSString *path = [NSString stringWithUTF8String:getenv("NV_SUMMARY_SCREENSHOT")];
            Check([[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES], @"actual window render is saved");
        }
        [self searchForString:@"road" mode:@"exact"];
        [self nv_summaryAwaitResults];
        Check([session resultCount] == 2, @"Exact results retain their existing matching behavior");
        [self searchForString:@"summary-removal-empty-fixture" mode:@"fuzzy"];
        [self nv_summaryAwaitResults];
        Check([session resultCount] == 0 && ![createNoteButton isHidden] &&
            [createNoteButton action] == @selector(createNoteFromSearch:), @"zero results keep explicit note creation");
        [self searchForString:@"" mode:@"fuzzy"];
        [self nv_summaryAwaitResults];
        Check([session resultCount] == 3 && [createNoteButton isHidden], @"clearing search restores all notes without a creation prompt");
        NSLog(@"SEARCH_SUMMARY_APP_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
