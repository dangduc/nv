- (void)nv_k2Check:(TitlebarModel)model {
    Check([[field stringValue] isEqual:model.visibleQuery], @"visible query equals the independent event model");
    Check([[[self browserSession] searchString] isEqual:model.committedQuery], @"committed query equals the independent event model");
    Check([[self searchMode] isEqual:model.mode], @"mode equals the independent event model");
    Check([[self browserSession] searchResultsAreCurrent] == model.current, @"result currency equals the independent event model");
    Check([toolbar isVisible] == model.toolbarVisible, @"toolbar visibility equals the independent event model");
    Check([[[toolbar items] valueForKey:@"itemIdentifier"] containsObject:@"Search"] == model.itemPresent,
        @"toolbar membership equals the independent event model");
    Check([self searchFieldHasFocus] == model.searchFocused, @"search focus equals the independent event model");
    if (model.selectedTitle) Check([titleOfNote([self selectedNoteObject]) isEqual:model.selectedTitle],
        @"selected document equals the independent event model");
    Check([window titleVisibility] == NSWindowTitleHidden, @"title remains hidden during asynchronous histories");
}
- (TitlebarDelivery *)nv_k2Await:(NSUInteger)index {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while ([TitlebarDeliveries count] <= index && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([TitlebarDeliveries count] > index, @"real fuzzy work finishes at the deterministic publication gate");
    return [TitlebarDeliveries objectAtIndex:index];
}
- (TitlebarDelivery *)nv_k2Pending:(NSString *)query {
    NSUInteger index = [TitlebarDeliveries count];
    [self nv_activateBrowser]; [self searchForString:query mode:@"fuzzy"];
    TitlebarDelivery *delivery = [self nv_k2Await:index];
    Check([[self browserSession] searchPending] && ![[self browserSession] searchResultsAreCurrent], @"publication gate leaves the real browser pending");
    return delivery;
}
- (void)nv_k2Remove {
    NSUInteger index = [[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
    Check(index != NSNotFound, @"Search exists before explicit toolbar removal");
    [toolbar removeItemAtIndex:index]; Pump();
}
- (void)nv_k2Focus {
    [self nv_activateBrowser]; [self bringFocusToControlField:self];
    Check([toolbar isVisible] && [field window] == window && [self searchFieldHasFocus], @"Search restores and focuses its native toolbar field synchronously");
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        [prefsController setAutoCompleteSearches:YES sender:self];
        NoteObject *road = MakeNote(library, @"Road map", @"road source");
        NoteObject *copper = MakeNote(library, @"Copper", @"road copper source");
        NoteObject *empty = MakeNote(library, @"Empty", @"miscellaneous source");
        [self searchForString:@"road" mode:@"exact"]; [self revealNote:road options:0];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer searchForString:@"Empty" mode:@"exact"]; [peer revealNote:empty options:0];
        [peer nv_k2Check:(TitlebarModel){@"Empty",@"Empty",@"exact",@"Empty",YES,YES,YES,YES}];

        TitlebarDeliveries = [NSMutableArray new];
        Method request = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
        IMP originalRequest = method_getImplementation(request);
        IMP gatedRequest = imp_implementationWithBlock(^NSUInteger(NVSearchService *service, id owner, NSString *query, NVSearchCompletion completion) {
            return ((NSUInteger(*)(id,SEL,id,id,id))originalRequest)(service, @selector(requestForOwner:query:completion:), owner, query,
                ^(NVSearchResult *result, NSError *error) {
                    TitlebarDelivery *delivery = [[[TitlebarDelivery alloc] init] autorelease];
                    delivery->completion = [completion copy]; delivery->result = [result retain]; delivery->error = [error retain];
                    [TitlebarDeliveries addObject:delivery];
                });
        });
        method_setImplementation(request, gatedRequest);

        NSLog(@"HISTORY A: pending Return, native toolbar detachment, focus reentry, completion");
        TitlebarDelivery *first = [self nv_k2Pending:@"road"];
        [self fieldAction:self];
        Check(pendingSearchReturnQuery != nil, @"pending Return records an explicit transient intent");
        if (getenv("NV_TITLEBAR_RETAIN_TRANSIENT")) {
            Method cancel = class_getInstanceMethod([AppController class], @selector(cancelTransientSearchIntents));
            method_setImplementation(cancel, imp_implementationWithBlock(^(AppController *browser) {}));
        }
        [self setDualFieldIsVisible:NO]; [self nv_k2Remove];
        [self nv_k2Check:(TitlebarModel){@"road",@"road",@"fuzzy",@"Road map",NO,NO,NO,NO}];
        [self nv_k2Focus];
        Check(pendingSearchReturnQuery == nil && !searchAutocompletePending, @"native toolbar detachment cancels transient search intents");
        [first deliver]; Pump();
        [self nv_k2Check:(TitlebarModel){@"road",@"road",@"fuzzy",@"Road map",YES,YES,YES,YES}];
        [window makeFirstResponder:textView]; for (NSUInteger i=0;i<4;i++) Pump();
        Check([window firstResponder] == textView, @"completed async work never steals later body focus");

        NSLog(@"HISTORY B: pending zero Return, hidden toolbar, Exact replacement, late fuzzy completion");
        first = [self nv_k2Pending:@"\"obsolete absent phrase\""]; [self fieldAction:self];
        [self setDualFieldIsVisible:NO];
        [self searchForString:@"copper" mode:@"exact"]; [self revealNote:copper options:0];
        [self nv_k2Remove]; [self nv_k2Focus];
        [first deliver]; Pump();
        [self nv_k2Check:(TitlebarModel){@"copper",@"copper",@"exact",@"Copper",YES,YES,YES,YES}];
        Check([library totalNoteCount] == 3, @"obsolete zero completion cannot create a note after toolbar and mode transitions");

        NSLog(@"HISTORY C: accepted Reveal completes in a hidden background toolbar");
        first = [self nv_k2Pending:@"road"];
        [self revealNote:copper options:0]; [self setDualFieldIsVisible:NO];
        [peer nv_k2Focus]; [first deliver]; Pump();
        [self nv_k2Check:(TitlebarModel){@"road",@"road",@"fuzzy",@"Copper",YES,NO,YES,NO}];
        [peer nv_k2Check:(TitlebarModel){@"Empty",@"Empty",@"exact",@"Empty",YES,YES,YES,YES}];
        [self nv_k2Focus];
        [self nv_k2Check:(TitlebarModel){@"road",@"road",@"fuzzy",@"Copper",YES,YES,YES,YES}];

        NSLog(@"HISTORY D: native marked text, obsolete completion, committed query, toolbar restoration");
        first = [self nv_k2Pending:@"road pending"];
        NSTextView *editor = (id)[field currentEditor];
        [editor setMarkedText:@"copper" selectedRange:NSMakeRange(6,0) replacementRange:NSMakeRange(0,[[editor string] length])];
        [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field userInfo:@{@"NSFieldEditor":editor}]];
        Check([editor hasMarkedText] && searchHasPendingComposition, @"actual field editor and production controller track marked composition");
        [first deliver]; [self fieldAction:self];
        Check(![[self browserSession] searchResultsAreCurrent] && [library totalNoteCount] == 3, @"old result and Return cannot authorize work during composition");
        NSUInteger next = [TitlebarDeliveries count];
        [editor unmarkText]; [editor insertText:@"copper" replacementRange:NSMakeRange(0,[[editor string] length])];
        TitlebarDelivery *current = [self nv_k2Await:next];
        [self setDualFieldIsVisible:NO]; [self nv_k2Remove]; [self nv_k2Focus];
        [self revealNote:copper options:0]; [current deliver]; Pump();
        [self nv_k2Check:(TitlebarModel){@"copper",@"copper",@"fuzzy",@"Copper",YES,YES,YES,YES}];
        Check([library totalNoteCount] == 3 && !searchHasPendingComposition, @"committed native composition keeps the three-note fixture intact");

        method_setImplementation(request, originalRequest); imp_removeBlock(gatedRequest);
        [TitlebarDeliveries removeAllObjects]; [TitlebarDeliveries release]; TitlebarDeliveries = nil;
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"TITLEBAR_ROUND2_KINGSBURY_PASS checks=%lu", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
