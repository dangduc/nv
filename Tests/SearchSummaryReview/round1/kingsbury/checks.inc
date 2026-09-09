- (void)nv_sCheck:(SummaryState)state {
    Check([[field stringValue] isEqual:state.query] && [[[self browserSession] searchString] isEqual:state.query],
        @"visible and committed query follow the event model");
    Check([[self searchMode] isEqual:state.mode] && [[self browserSession] searchResultsAreCurrent] == state.current,
        @"mode and result currency follow the event model");
    Check([searchStatusField isHidden] == ![state.status length], @"status visibility follows the independent event model");
    Check([[searchStatusField stringValue] isEqual:state.status], @"status text follows the independent event model");
    Check([[field toolTip] isEqual:state.status] && [[searchStatusField toolTip] isEqual:state.status],
        @"search and status tooltips follow the event model");
    NSRect expected = [notesSubview bounds];
    if ([state.status length]) expected.size.height = MAX(0, expected.size.height - 24);
    Check(NSEqualRects([notesScrollView frame], expected), @"list allocation follows the model's transient-status visibility");
    Check([createNoteButton isHidden] != state.retryVisible, @"only the modeled Retry action is visible in these nonempty histories");
    if (state.retryVisible) Check([createNoteButton action] == @selector(retrySearch:), @"the visible error action dispatches Retry Search");
    if (state.title) Check([titleOfNote([self selectedNoteObject]) isEqual:state.title], @"document selection follows the independent event model");
}
- (SummaryDelivery *)nv_sAwait:(NSUInteger)index {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while ([SummaryDeliveries count] <= index && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([SummaryDeliveries count] > index, @"real fuzzy computation reaches the controlled completion boundary");
    return [SummaryDeliveries objectAtIndex:index];
}
- (void)nv_sAwaitProgress {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (![searchStatusField stringValue].length && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchPending] && searchStatusDelayElapsed, @"the production delayed-progress timer fires while search remains pending");
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *road = MakeNote(library, @"Road map", @"road source");
        NoteObject *copper = MakeNote(library, @"Copper", @"road copper source");
        NoteObject *empty = MakeNote(library, @"Empty", @"miscellaneous source");
        [self nv_activateBrowser]; [prefsController setAutoCompleteSearches:NO sender:self];
        [self searchForString:@"road" mode:@"exact"]; [self revealNote:road options:0];
        [self nv_sCheck:(SummaryState){@"road",@"exact",@"Road map",@"",YES,NO}];

        SummaryDeliveries = [NSMutableArray new];
        Method method = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
        IMP original = method_getImplementation(method);
        IMP gate = imp_implementationWithBlock(^NSUInteger(NVSearchService *service, id owner, NSString *query, NVSearchCompletion completion) {
            return ((NSUInteger(*)(id,SEL,id,id,id))original)(service, @selector(requestForOwner:query:completion:), owner, query,
                ^(NVSearchResult *result, NSError *error) {
                    SummaryDelivery *delivery = [[[SummaryDelivery alloc] init] autorelease];
                    delivery->completion=[completion copy]; delivery->result=[result retain]; delivery->error=[error retain];
                    [SummaryDeliveries addObject:delivery];
                });
        });
        method_setImplementation(method, gate);
        if (getenv("NV_SUMMARY_REINTRODUCE_COMPLETE")) {
            Method affordance=class_getInstanceMethod([AppController class], @selector(updateSearchAffordance));
            IMP normal=method_getImplementation(affordance);
            method_setImplementation(affordance, imp_implementationWithBlock(^(AppController *browser) {
                ((void(*)(id,SEL))normal)(browser,@selector(updateSearchAffordance));
                NVBrowserSession *session=[browser browserSession];
                if ([session searchResultsAreCurrent] && [[session searchMode] isEqual:@"fuzzy"] && [session hasSearchTerms]) {
                    NSTextField *label=[browser valueForKey:@"searchStatusField"];
                    [label setHidden:NO]; [label setStringValue:@"2 results in 2 notes — title matches first"];
                    NSRect frame=[[browser valueForKey:@"notesSubview"] bounds]; frame.size.height=MAX(0,frame.size.height-24);
                    [[browser valueForKey:@"notesScrollView"] setFrame:frame];
                }
            }));
        }

        NSLog(@"HISTORY A: immediate pending, delayed progress, complete, late progress callback");
        NSUInteger index=[SummaryDeliveries count]; [self searchForString:@"road" mode:@"fuzzy"];
        [self nv_sCheck:(SummaryState){@"road",@"fuzzy",@"Road map",@"",NO,NO}];
        [self revealNote:road options:0]; SummaryDelivery *first=[self nv_sAwait:index]; [self nv_sAwaitProgress];
        [self nv_sCheck:(SummaryState){@"road",@"fuzzy",@"Road map",NSLocalizedString(@"Searching…",nil),NO,NO}];
        [first deliver];
        [self nv_sCheck:(SummaryState){@"road",@"fuzzy",@"Road map",@"",YES,NO}];
        [self showSearchProgress]; Pump();
        [self nv_sCheck:(SummaryState){@"road",@"fuzzy",@"Road map",@"",YES,NO}];

        NSLog(@"HISTORY B: error, native Retry action, stale failure/success, current completion");
        index=[SummaryDeliveries count]; [self searchForString:@"copper" mode:@"fuzzy"];
        SummaryDelivery *failed=[self nv_sAwait:index]; [failed fail];
        [self nv_sCheck:(SummaryState){@"copper",@"fuzzy",@"Road map",@"Controlled search failure",NO,YES}];
        [self fieldAction:self]; Check([library totalNoteCount]==3, @"Return in the failed state cannot create a note");
        index=[SummaryDeliveries count]; [createNoteButton performClick:self];
        [self nv_sCheck:(SummaryState){@"copper",@"fuzzy",@"Road map",@"",NO,NO}];
        [self revealNote:copper options:0]; [failed fail]; [failed deliver];
        [self nv_sCheck:(SummaryState){@"copper",@"fuzzy",@"Road map",@"",NO,NO}];
        SummaryDelivery *retry=[self nv_sAwait:index]; [self nv_sAwaitProgress];
        [self nv_sCheck:(SummaryState){@"copper",@"fuzzy",@"Road map",NSLocalizedString(@"Searching…",nil),NO,NO}];
        [retry deliver];
        [self nv_sCheck:(SummaryState){@"copper",@"fuzzy",@"Copper",@"",YES,NO}];

        NSLog(@"HISTORY C: pending fuzzy progress, new Exact query, obsolete callbacks");
        index=[SummaryDeliveries count]; [self searchForString:@"road again" mode:@"fuzzy"];
        SummaryDelivery *obsolete=[self nv_sAwait:index]; [self nv_sAwaitProgress];
        [self searchForString:@"Empty" mode:@"exact"]; [self revealNote:empty options:0];
        [obsolete fail]; [obsolete deliver]; [self showSearchProgress]; Pump();
        [self nv_sCheck:(SummaryState){@"Empty",@"exact",@"Empty",@"",YES,NO}];
        Check([library totalNoteCount]==3, @"status and retry histories preserve exactly three fixture notes");
        method_setImplementation(method,original); imp_removeBlock(gate);
        [SummaryDeliveries removeAllObjects]; [SummaryDeliveries release]; SummaryDeliveries=nil;
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"SEARCH_SUMMARY_KINGSBURY_PASS checks=%lu",(unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@\n%@",exception,[exception callStackSymbols]); exit(1); }
}
