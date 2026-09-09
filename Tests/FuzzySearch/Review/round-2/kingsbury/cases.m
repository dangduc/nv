// New round-two histories exercise current production methods. The support
// doubles are a local snapshot, so later round-one edits cannot change a run.
#import <objc/runtime.h>
static NSDictionary *RestoreState(NoteObject *note, NSString *query, NSString *kind, NSRange selection) {
    const unsigned char *bytes = (const unsigned char *)[note uniqueNoteIDBytes];
    NSMutableString *key = [NSMutableString stringWithFormat:@"%@:", kind];
    for (NSUInteger i = 0; i < 16; i++) [key appendFormat:@"%02x", bytes[i]];
    return @{@"search":query, @"searchMode":@"fuzzy", @"note":[NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]],
             @"searchRowKey":key, @"selection":NSStringFromRange(selection)};
}
static void Resign(StateController *controller) {
    controller->window->key = NO;
    [controller windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:controller->window]];
}
static void Reenter(StateController *controller) { controller->window->key = YES; [controller selectSearchField]; }
static void RepeatCompletion(StateController *controller, NSUInteger count) {
    for (NSUInteger i = 0; i < count; i++) [controller browserSessionSearchDidComplete:controller->notationController];
}

int main(void) {
    @autoreleasepool {
        Autocomplete = YES;
        NoteObject *road = Note(@"Road map", @"road planning"), *body = Note(@"Other", @"road copper lantern"), *gaps = Note(@"Rivet", @"r---o---a---d");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, body, gaps]] autorelease];
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;

        // A canceled pending Return stays canceled after any number of focus
        // round trips, including a repeated completion after focus returns.
        for (NSUInteger trips = 1; trips <= 3; trips++) {
            StateController *controller = Controller(library, service);
            Pending(controller, [NSString stringWithFormat:@"round-two-zero-%lu", (unsigned long)trips]);
            [controller performSearchReturn];
            Check(controller->pendingSearchReturnQuery != nil, "zero Return begins with an explicit pending intent");
            for (NSUInteger i = 0; i < trips; i++) { Resign(controller); Reenter(controller); }
            Check(!controller->pendingSearchReturnQuery && !controller->searchAutocompletePending, "key-window round trips cancel transient intents");
            Complete(controller); RepeatCompletion(controller, 3);
            Check(controller->creations == 0 && controller->bodyFocuses == 0, "focus reentry and repeated completions cannot revive canceled Return");
            [controller performSearchReturn];
            Check(controller->creations == 1, "a new explicit Return remains usable after the canceled request");
        }

        // A user query supersedes a saved restoration before publication.
        StateController *restored = Controller(library, service);
        [restored restoreBrowserWindowState:RestoreState(road, @"road", @"fuzzy", NSMakeRange(2, 2))];
        Check(restored->pendingSearchRestoration != nil, "saved restoration waits for its query");
        Pending(restored, @"copper"); Complete(restored); RepeatCompletion(restored, 3);
        Check(restored->pendingSearchRestoration == nil && restored->currentNote == body &&
              [[restored->notationController searchString] isEqual:@"copper"], "explicit new query supersedes delayed restoration");

        // A newer saved state also replaces the old saved state atomically.
        StateController *twiceRestored = Controller(library, service);
        [twiceRestored restoreBrowserWindowState:RestoreState(road, @"road", @"title", NSMakeRange(1, 1))];
        [twiceRestored restoreBrowserWindowState:RestoreState(body, @"copper", @"fuzzy", NSMakeRange(3, 2))];
        Resign(twiceRestored); Reenter(twiceRestored); Complete(twiceRestored); RepeatCompletion(twiceRestored, 3);
        Check(twiceRestored->currentNote == body && NSEqualRanges(twiceRestored->textView->selection, NSMakeRange(3, 2)),
              "newer saved state wins across focus loss and repeated completion");

        // A query edit supersedes both singular and plural Reveal. Neither can
        // later clear the new query just to find an obsolete target.
        for (NSUInteger plural = 0; plural < 2; plural++) {
            StateController *controller = Controller(library, service);
            Pending(controller, @"road");
            if (plural) [controller notation:(id)controller->notationController revealNotes:@[road, body]];
            else [controller revealNote:road options:0];
            Check(controller->pendingSearchReveal != nil, "Reveal waits before the explicit new query");
            Resign(controller); Reenter(controller); Pending(controller, @"copper");
            Complete(controller); RepeatCompletion(controller, 3);
            Check(controller->currentNote == body && !controller->pendingSearchReveal && [[controller->notationController searchString] isEqual:@"copper"],
                  "explicit new query supersedes delayed Reveal across focus reentry");
        }

        // Plural targets preserve all unique UUIDs through background completion.
        StateController *targets = Controller(library, service);
        Pending(targets, @"copper"); [targets notation:(id)targets->notationController revealNotes:@[road, body, road]];
        Check([[targets->pendingSearchReveal objectForKey:@"notes"] isEqual:@[road, body]], "plural pending targets deduplicate UUID occurrences");
        Resign(targets); Complete(targets); RepeatCompletion(targets, 3);
        NSArray *revealedTargets = [targets->notationController notesAtIndexes:[targets->notesTableView selectedRowIndexes]];
        Check([revealedTargets count] == 2 && [revealedTargets containsObject:road] && [revealedTargets containsObject:body] &&
              [[targets->notationController searchString] length] == 0 && !targets->pendingSearchReveal,
              "plural Reveal includes excluded targets after key loss and is consumed once");

        // Failed service callbacks are held at their original delivery boundary.
        // The service still allocates and computes the real request identity.
        __block NVSearchCompletion heldCompletion = nil;
        __block NVSearchResult *heldResult = nil;
        Method request = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
        IMP original = method_getImplementation(request);
        IMP controlled = imp_implementationWithBlock(^NSUInteger(NVSearchService *s, id owner, NSString *query, NVSearchCompletion completion) {
            return ((NSUInteger(*)(id, SEL, id, id, id))original)(s, @selector(requestForOwner:query:completion:), owner, query, ^(NVSearchResult *result, NSError *error) {
                [heldCompletion release]; heldCompletion = [completion copy];
                [heldResult release]; heldResult = [result retain];
            });
        });
        method_setImplementation(request, controlled);
        StateController *failed = Controller(library, service);
        Pending(failed, @"error-zero-history"); [failed performSearchReturn];
        Check(Spin(^BOOL { return heldCompletion != nil; }), "real current request reaches controlled completion boundary");
        NSError *error = [NSError errorWithDomain:@"ReviewInjectedFailure" code:1 userInfo:nil];
        heldCompletion(nil, error); heldCompletion(nil, error); RepeatCompletion(failed, 3);
        Check([failed->notationController searchError] != nil && ![failed->notationController searchResultsAreCurrent] && failed->creations == 0,
              "repeated error completions cannot authorize zero-result creation");
        NVSearchCompletion obsolete = [heldCompletion copy]; NVSearchResult *obsoleteResult = [heldResult retain];
        [heldCompletion release]; heldCompletion = nil; [heldResult release]; heldResult = nil;
        Pending(failed, @"copper");
        obsolete(obsoleteResult, nil); [obsolete release]; [obsoleteResult release];
        Check(failed->creations == 0 && ![failed->notationController searchResultsAreCurrent], "late success from failed obsolete request cannot satisfy a newer query");
        Check(Spin(^BOOL { return heldCompletion != nil; }), "new request reaches controlled publication boundary");
        method_setImplementation(request, original); imp_removeBlock(controlled);
        heldCompletion(heldResult, nil); RepeatCompletion(failed, 3);
        Check([failed->notationController searchResultsAreCurrent] && failed->currentNote == body && failed->creations == 0,
              "new query completes after repeated errors without reviving old Return");
        [heldCompletion release]; heldCompletion = nil; [heldResult release]; heldResult = nil;

        // Review witness: a later programmatic Reveal must not be hidden behind
        // an older saved restoration for the same pending result.
        StateController *restoreThenReveal = Controller(library, service);
        [restoreThenReveal restoreBrowserWindowState:RestoreState(road, @"road", @"fuzzy", NSMakeRange(1, 1))];
        [restoreThenReveal revealNote:body options:0];
        Check((NV_REVIEW_EXPECT_FIXED || restoreThenReveal->pendingSearchRestoration != nil) && restoreThenReveal->pendingSearchReveal != nil,
              "WITNESS precondition: older restoration and newer Reveal coexist");
        Complete(restoreThenReveal); PrintState(@"restore-then-reveal-first-completion", restoreThenReveal);
        Check(NV_REVIEW_EXPECT_FIXED ?
              (restoreThenReveal->currentNote == body && !restoreThenReveal->pendingSearchReveal && !restoreThenReveal->pendingSearchRestoration) :
              (restoreThenReveal->currentNote == road && restoreThenReveal->pendingSearchReveal != nil),
              NV_REVIEW_EXPECT_FIXED ? "newer Reveal wins on the first completion and consumes older restoration" :
              "WITNESS: first completion applies obsolete restoration and leaves newer Reveal pending");
        RepeatCompletion(restoreThenReveal, 1); PrintState(@"restore-then-reveal-repeated-completion", restoreThenReveal);
        Check(restoreThenReveal->currentNote == body && !restoreThenReveal->pendingSearchReveal,
              "WITNESS: otherwise identical repeated completion changes selection to the stranded Reveal");

        StateController *restoreThenPlural = Controller(library, service);
        [restoreThenPlural restoreBrowserWindowState:RestoreState(road, @"road", @"title", NSMakeRange(1, 1))];
        [restoreThenPlural notation:(id)restoreThenPlural->notationController revealNotes:@[body, gaps]];
        Resign(restoreThenPlural); Complete(restoreThenPlural);
        NSArray *firstSelection = [restoreThenPlural->notationController notesAtIndexes:[restoreThenPlural->notesTableView selectedRowIndexes]];
        Check(NV_REVIEW_EXPECT_FIXED ?
              ([firstSelection count] == 2 && [firstSelection containsObject:body] && [firstSelection containsObject:gaps] &&
               !restoreThenPlural->pendingSearchReveal && !restoreThenPlural->pendingSearchRestoration) :
              ([firstSelection isEqual:@[road]] && restoreThenPlural->pendingSearchReveal != nil),
              NV_REVIEW_EXPECT_FIXED ? "newer plural Reveal wins on the first background completion" :
              "WITNESS: older restoration also strands a newer plural Reveal in a background browser");
        RepeatCompletion(restoreThenPlural, 1);
        NSArray *secondSelection = [restoreThenPlural->notationController notesAtIndexes:[restoreThenPlural->notesTableView selectedRowIndexes]];
        Check([secondSelection count] == 2 && [secondSelection containsObject:body] && [secondSelection containsObject:gaps] &&
              !restoreThenPlural->pendingSearchReveal, "WITNESS: repeated completion finally selects all stranded plural Reveal targets");
        printf("RESTORE_THEN_PLURAL first_selected_count=%lu first_selected_restored=%d second_selected_count=%lu\n",
               (unsigned long)[firstSelection count], [firstSelection isEqual:@[road]], (unsigned long)[secondSelection count]);

#if NV_REVIEW_EXPECT_FIXED
        // The same replacement rule applies in reverse order. A later saved
        // state keeps its exact occurrence and caret after just one completion.
        for (NSUInteger plural = 0; plural < 2; plural++) {
            StateController *controller = Controller(library, service);
            Pending(controller, @"road");
            if (plural) [controller notation:(id)controller->notationController revealNotes:@[body, gaps]];
            else [controller revealNote:body options:0];
            NSDictionary *state = RestoreState(road, @"road", @"fuzzy", NSMakeRange(2, 3));
            [controller restoreBrowserWindowState:state];
            Check(controller->pendingSearchRestoration && !controller->pendingSearchReveal,
                  "newer window restoration exclusively replaces earlier singular or plural Reveal");
            Complete(controller);
            Check(controller->currentNote == road && [[controller selectedSearchResultRowKey] isEqual:state[@"searchRowKey"]] &&
                  NSEqualRanges(controller->textView->selection, NSMakeRange(2, 3)) &&
                  !controller->pendingSearchRestoration && !controller->pendingSearchReveal,
                  "newer restoration applies its occurrence and caret on the first completion");
            RepeatCompletion(controller, 2);
            Check(controller->currentNote == road && NSEqualRanges(controller->textView->selection, NSMakeRange(2, 3)),
                  "repeated completion cannot revive the superseded Reveal");
        }

        // Multiple Reveal requests replace each other in arrival order, including
        // across singular/plural forms and an earlier pending saved state.
        for (NSUInteger plural = 0; plural < 2; plural++) {
            StateController *controller = Controller(library, service);
            [controller restoreBrowserWindowState:RestoreState(road, @"road", @"fuzzy", NSMakeRange(1, 1))];
            [controller performSearchReturn];
            controller->searchAutocompletePending = YES;
            [controller revealNote:body options:0];
            Check(!controller->pendingSearchReturnQuery && !controller->searchAutocompletePending &&
                  !controller->pendingSearchRestoration && controller->pendingSearchReveal,
                  "valid Reveal supersedes all older transient and programmatic intents");
            [controller notation:(id)controller->notationController revealNotes:@[road, body]];
            if (plural) [controller notation:(id)controller->notationController revealNotes:@[body, gaps, body]];
            else [controller revealNote:gaps options:0];
            Resign(controller); Complete(controller);
            NSArray *selected = [controller->notationController notesAtIndexes:[controller->notesTableView selectedRowIndexes]];
            Check(plural ? ([selected count] == 2 && [selected containsObject:body] && [selected containsObject:gaps]) : [selected isEqual:@[gaps]],
                  "latest singular or plural Reveal wins on one background completion");
            Check(!controller->pendingSearchRestoration && !controller->pendingSearchReveal && !controller->window->key,
                  "latest Reveal consumes all programmatic work without activating its browser");
            RepeatCompletion(controller, 2);
            Check([[controller->notationController notesAtIndexes:[controller->notesTableView selectedRowIndexes]] isEqual:selected],
                  "multiple Reveal history leaves no stranded selection for later completions");
        }

        // Rejected foreign targets do not supersede a valid intent from this
        // library, but a valid immediate Reveal does replace deferred work.
        StateController *invalid = Controller(library, service);
        [invalid restoreBrowserWindowState:RestoreState(road, @"road", @"fuzzy", NSMakeRange(1, 2))];
        NSDictionary *validRestoration = [[invalid->pendingSearchRestoration retain] autorelease];
        NoteObject *foreign = Note(@"Foreign", @"road");
        Check([invalid revealNote:foreign options:0] == NSNotFound && invalid->pendingSearchRestoration == validRestoration,
              "foreign singular Reveal leaves the valid pending restoration intact");
        [invalid notation:(id)invalid->notationController revealNotes:@[foreign]];
        Check(invalid->pendingSearchRestoration == validRestoration && !invalid->pendingSearchReveal,
              "foreign plural Reveal leaves the valid pending restoration intact");
        invalid->searchApplyingResult = YES;
        Complete(invalid);
        invalid->searchApplyingResult = NO;
        Check(invalid->pendingSearchRestoration == validRestoration, "held completion retains the earlier selection intent");
        [invalid revealNote:body options:0];
        Check(invalid->currentNote == body && !invalid->pendingSearchRestoration && !invalid->pendingSearchReveal,
              "immediately applicable Reveal also replaces older deferred selection work");
        RepeatCompletion(invalid, 2);
        Check(invalid->currentNote == body, "later completion cannot overwrite an immediate newer Reveal");
#endif

        [service invalidate];
        printf("ROUND TWO STATE REVIEW: %lu checks passed\n", (unsigned long)Checks);
    }
    return 0;
}
