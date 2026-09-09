- (NVSchemeDelivery *)nv_waitHighlightAfter:(NSUInteger)start {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    NVSchemeDelivery *found = nil;
    do {
        Pump();
        for (NSUInteger i = start; i < [Deliveries count]; i++) {
            NVSchemeDelivery *candidate = Deliveries[i];
            if (candidate->owner == [self browserSession]) found = candidate;
        }
    } while (!found && [deadline timeIntervalSinceNow] > 0);
    Check(found && !found->error && [found->ranges count] > 0,
        @"the actual worker completes nonempty source ranges at the controlled publication boundary");
    return found;
}
- (void)nv_checkHighlight:(NSColor *)highlight background:(NSColor *)background {
    NSString *word = [[self searchMode] isEqual:@"fuzzy"] ? @"source" : @"needle";
    NSUInteger index = [[textView string] rangeOfString:word].location;
    Check(index != NSNotFound && Same([textView backgroundColor], background),
        @"the owning editor retains its source and expected background");
    Check(Same([[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName
        atCharacterIndex:index effectiveRange:NULL], Blend(highlight, background)),
        @"published search highlight uses the current owning palette and an independent alpha-composite oracle");
}
- (void)nv_selectFixture:(NoteObject *)note mode:(NSString *)mode {
    [self searchForString:[mode isEqual:@"fuzzy"] ? @"source" : @"needle" mode:mode];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent], @"the real search completes before source-row selection");
    NSUInteger target = NSNotFound;
    for (NSUInteger i = 0; i < [[self browserSession] resultCount]; i++)
        if ([[self browserSession] noteObjectAtFilteredIndex:i] == note &&
            (![mode isEqual:@"fuzzy"] || [[[self browserSession] matchKindAtIndex:i] isEqual:@"fuzzy"])) { target = i; break; }
    Check(target != NSNotFound, @"the fixture selects the requested Exact or native Fuzzy result row");
    [notesTableView selectRowAndScroll:target];
    [self displayContentsForNoteAtIndex:target];
    Check([self selectedNoteObject] == note, @"the selected result belongs to the shared fixture note");
}
- (void)nv_appearance:(BOOL)dark {
    if (@available(macOS 10.14, *))
        [window setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
    else Check(NO, @"the scheduling probe requires appearance support on macOS 10.14 or later");
    [window display];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    Check([self usesDarkUserColorScheme] == dark, @"AppKit propagates the requested effective appearance without a manual browser callback");
}
- (void)nv_runTests {
    @try {
        NotationController *library = [self sharedNotationController];
        NVApplicationController *app = [NVApplicationController sharedController];
        NSColor *lightBG = C(.9,.8,.7,1), *darkBG = C(.1,.2,.3,1);
        NSColor *lightHL = C(.2,.7,.4,.25), *darkHL = C(.8,.3,.1,.6);
        [prefsController setForegroundTextColor:C(.05,.06,.07,1) sender:nil];
        [prefsController setBackgroundTextColor:lightBG sender:nil];
        [prefsController setSearchTermHighlightColor:lightHL sender:nil];
        [prefsController setDarkForegroundTextColor:C(.95,.94,.93,1) sender:nil];
        [prefsController setDarkBackgroundTextColor:darkBG sender:nil];
        [prefsController setDarkSearchTermHighlightColor:darkHL sender:nil];
        [prefsController setShouldHighlightSearchTerms:YES sender:nil];
        NoteObject *note = MakeNote(library, @"needle schedule", @"needle source\nordinary shared text\nneedle again");
        [note setSourceSyntaxIdentifier:@"plain"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self && [peer sharedNotationController] == library, @"two independent browsers use one disposable library");
        [self setUserColorScheme:self]; [peer setUserColorScheme:peer];
        InstallSchemeGate();
        NSAttributedString *before = [[[note contentString] copy] autorelease];
        for (NSString *mode in @[@"exact", @"fuzzy"]) {
            NSLog(@"SCHEDULE: %@ palette inversion and reversed final deliveries", mode);
            [self nv_appearance:NO]; [peer nv_appearance:YES];
            for (AppController *browser in @[self, peer]) {
                NSUInteger start = [Deliveries count];
                [browser nv_selectFixture:note mode:mode];
                [[browser nv_waitHighlightAfter:start] deliver];
            }
            [self nv_checkHighlight:lightHL background:lightBG];
            [peer nv_checkHighlight:darkHL background:darkBG];
            Check([textView textStorage] == [[peer valueForKey:@"textView"] textStorage],
                @"opposite palettes are rendered through separate layout managers on shared source storage");
            NSUInteger start = [Deliveries count];
            [self refreshSearchHighlights]; [peer refreshSearchHighlights];
            [self nv_waitHighlightAfter:start]; [peer nv_waitHighlightAfter:start];
            NSArray *obsolete = [[Deliveries copy] autorelease];
            start = [Deliveries count];
            [self nv_appearance:YES]; [peer nv_appearance:NO];
            NVSchemeDelivery *newSelf = [self nv_waitHighlightAfter:start];
            NVSchemeDelivery *newPeer = [peer nv_waitHighlightAfter:start];
            [newPeer deliver]; [newSelf deliver];
            [self nv_checkHighlight:darkHL background:darkBG];
            [peer nv_checkHighlight:lightHL background:lightBG];
            NSUInteger selfApplied = [[Applied objectForKey:textView] unsignedIntegerValue];
            NSUInteger peerApplied = [[Applied objectForKey:[peer valueForKey:@"textView"]] unsignedIntegerValue];
            // Service callbacks normally have one delivery. Duplicate delivery is adversarial instrumentation.
            for (NVSchemeDelivery *old in [obsolete reverseObjectEnumerator]) { [old deliver]; [old deliver]; }
            Check([[Applied objectForKey:textView] unsignedIntegerValue] == selfApplied &&
                [[Applied objectForKey:[peer valueForKey:@"textView"]] unsignedIntegerValue] == peerApplied,
                @"obsolete reversed and duplicate results do not cross either browser's highlight-generation fence");
            [self nv_checkHighlight:darkHL background:darkBG];
            [peer nv_checkHighlight:lightHL background:lightBG];
        }
        NSLog(@"SCHEDULE: change two dark preferences while Fuzzy delivery is held");
        NSUInteger start = [Deliveries count];
        [self refreshSearchHighlights];
        NVSchemeDelivery *beforeEdits = [self nv_waitHighlightAfter:start];
        darkBG = C(.04,.08,.12,1); darkHL = C(.9,.6,.2,.4);
        start = [Deliveries count];
        [prefsController setDarkBackgroundTextColor:darkBG sender:nil];
        [prefsController setDarkSearchTermHighlightColor:darkHL sender:nil];
        [[self nv_waitHighlightAfter:start] deliver];
        [self nv_checkHighlight:darkHL background:darkBG];
        NSUInteger applied = [[Applied objectForKey:textView] unsignedIntegerValue];
        [beforeEdits deliver];
        Check([[Applied objectForKey:textView] unsignedIntegerValue] == applied,
            @"a result captured before consecutive background and highlight edits cannot publish afterward");
        NSLog(@"SCHEDULE: close a browser, create its replacement, then deliver the old result");
        start = [Deliveries count]; [peer refreshSearchHighlights];
        NVSchemeDelivery *closedDelivery = [[peer nv_waitHighlightAfter:start] retain];
        LinkingEditor *closedEditor = [[peer valueForKey:@"textView"] retain];
        NSUInteger closedApplied = [[Applied objectForKey:closedEditor] unsignedIntegerValue];
        [[peer window] close]; Pump();
        Check(![[app browserControllers] containsObject:peer], @"closing the peer unregisters it from application ownership");
        [app newWindow:self]; Pump();
        AppController *replacement = [[app browserControllers] lastObject];
        Check(replacement != peer && [replacement sharedNotationController] == library,
            @"a newly opened browser gets independent ownership and the existing library");
        [replacement setUserColorScheme:replacement]; [replacement nv_appearance:YES];
        start = [Deliveries count]; [replacement nv_selectFixture:note mode:@"fuzzy"];
        [[replacement nv_waitHighlightAfter:start] deliver];
        [replacement nv_checkHighlight:darkHL background:darkBG];
        NSUInteger replacementApplied = [[Applied objectForKey:[replacement valueForKey:@"textView"]] unsignedIntegerValue];
        [closedDelivery deliver]; [closedDelivery deliver];
        Check([[Applied objectForKey:closedEditor] unsignedIntegerValue] == closedApplied &&
            [[Applied objectForKey:[replacement valueForKey:@"textView"]] unsignedIntegerValue] == replacementApplied,
            @"late closed-window callbacks publish to neither the detached editor nor its replacement");
        Check([[note contentString] isEqualToAttributedString:before] && [library totalNoteCount] == 1,
            @"all schedules preserve the single note's attributed source");
        [closedDelivery release]; [closedEditor release];
        NSLog(@"KINGSBURY USER SCHEME ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
