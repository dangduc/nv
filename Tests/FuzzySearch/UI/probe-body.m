    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library]; AppController *a = self;
        NVBrowserSession *sa = [a browserSession];
        [NSApp activateIgnoringOtherApps:YES]; [[a window] makeKeyAndOrderFront:self];
        Check(FuzzyAwait(^BOOL { return [NSApp isActive] && [[a window] isKeyWindow]; }, 3), @"fuzzy workflow owns active disposable browser");
        NoteObject *road = MakeNote(library, @"Road map", @"road planning committed source");
        NoteObject *body = MakeNote(library, @"Other", @"road and copper lantern");
        NoteObject *gaps = MakeNote(library, @"Rivet", @"r---o---a---d");
        [a searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10), @"actual browser publishes fuzzy result");
        Check([sa resultCount] == 4 && [sa distinctResultNoteCount] == 3, @"title-first fuzzy search retains four occurrences in three notes");
        Check([sa noteObjectAtFilteredIndex:0] == road && [[sa matchKindAtIndex:0] isEqual:@"title"], @"literal title match appears first");
        Check(FuzzyRow(sa, body, @"title") == NSNotFound && FuzzyRow(sa, gaps, @"title") == NSNotFound, @"body-only and gapped matches cannot enter title group");
        Check(FuzzyRow(sa, body, @"fuzzy") != NSNotFound && FuzzyRow(sa, gaps, @"fuzzy") != NSNotFound, @"complete source contributes native fuzzy matches");
        NSUInteger titleRow = FuzzyRow(sa, road, @"title"), fuzzyRow = FuzzyRow(sa, road, @"fuzzy");
        FuzzySelect(a, titleRow);
        LinkingEditor *editor = [a valueForKey:@"textView"];
        NVNoteEditingSession *editing = [a valueForKey:@"editingSession"];
        NSTextStorage *storage = [editor textStorage]; NSUndoManager *undo = [road undoManager];
        [[a window] makeFirstResponder:editor];
        [editor insertText:@"Undoable " replacementRange:NSMakeRange(0, 0)]; [a finishEditing];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10), @"source edit refresh completes");
        titleRow = FuzzyRow(sa, road, @"title"); fuzzyRow = FuzzyRow(sa, road, @"fuzzy");
        FuzzySelect(a, titleRow); NSRange caret = NSMakeRange(4, 2); [editor setSelectedRange:caret];
        BOOL canUndo = [undo canUndo]; NSString *undoName = [[[undo undoActionName] copy] autorelease];
        FuzzySelect(a, fuzzyRow);
        Check([a selectedNoteObject] == road && [a valueForKey:@"editingSession"] == editing && [editor textStorage] == storage, @"duplicate occurrence reuses one editing session and text storage");
        Check([road undoManager] == undo && [undo canUndo] == canUndo && [[undo undoActionName] isEqual:undoName] && NSEqualRanges([editor selectedRange], caret), @"duplicate occurrence preserves Undo and caret");
        NSMutableIndexSet *duplicates = [NSMutableIndexSet indexSetWithIndex:titleRow]; [duplicates addIndex:fuzzyRow];
        Check([[sa notesAtIndexes:duplicates] isEqual:@[road]], @"multiple selected occurrences resolve to one document");
        NSString *fuzzyKey = [[[sa rowKeyAtIndex:fuzzyRow] copy] autorelease];
        NSDictionary *saved = [[[a browserWindowState] copy] autorelease];
        Check([saved[@"searchMode"] isEqual:@"fuzzy"] && [saved[@"searchRowKey"] isEqual:fuzzyKey], @"saved state retains fuzzy mode and selected occurrence");
        [app newWindow:self]; AppController *b = [[[app browserControllers] lastObject] retain]; NVBrowserSession *sb = [b browserSession];
        [b restoreBrowserWindowState:saved];
        Check(FuzzyAwait(^BOOL { return [sb searchResultsAreCurrent] && [b selectedNoteObject] == road; }, 10), @"second browser restores note after fuzzy completion");
        Check([[b selectedSearchResultRowKey] isEqual:fuzzyKey] && [b valueForKey:@"editingSession"] == editing, @"restoration preserves duplicate occurrence over shared editing session");
        Check(NSEqualRanges([[b valueForKey:@"textView"] selectedRange], caret), @"restoration applies saved source caret to restored note");
        LinkingEditor *peerEditor = [b valueForKey:@"textView"];
        for (LinkingEditor *view in @[editor, peerEditor]) [[view layoutManager] addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(0, 1)];
        [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@"x"];
        Check([[editor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] == nil &&
            [[peerEditor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] == nil,
            @"shared character notification clears stale source highlights in both attached browsers immediately");
        [editing commitTextChanges];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [sb searchResultsAreCurrent]; }, 10), @"shared character edit reaches both current search results");
        NSMutableDictionary *legacy = [[saved mutableCopy] autorelease]; [legacy removeObjectForKey:@"searchMode"]; [legacy removeObjectForKey:@"searchRowKey"];
        [b restoreBrowserWindowState:legacy];
        Check([[b searchMode] isEqual:@"exact"] && [sb searchResultsAreCurrent] && [sb resultCount] == 2, @"legacy saved state retains exact substring semantics and one row per note");
        [a searchForString:@"copper" mode:@"exact"];
        Check([sa searchResultsAreCurrent] && [sa resultCount] == 1 && [sa noteObjectAtFilteredIndex:0] == body, @"Exact continues matching committed source substrings");

        // Hold only publication. The production service still parses and scores
        // the real snapshots; the actual AppController handles every intent.
        NSMutableArray *deliveries = [NSMutableArray array]; __block BOOL hold = YES;
        Method method = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
        IMP original = method_getImplementation(method);
        IMP controlled = imp_implementationWithBlock(^NSUInteger(NVSearchService *service, id owner, NSString *query, NVSearchCompletion completion) {
            return ((NSUInteger(*)(id, SEL, id, id, id))original)(service, @selector(requestForOwner:query:completion:), owner, query, ^(NVSearchResult *result, NSError *error) {
                if (hold) [deliveries addObject:[[^{ completion(result, error); } copy] autorelease]];
                else completion(result, error);
            });
        });
        method_setImplementation(method, controlled);
        void (^releaseDeliveries)(void) = ^{
            NSArray *pending = [[deliveries copy] autorelease]; [deliveries removeAllObjects];
            for (void (^delivery)(void) in pending) delivery();
        };
        [[a window] makeKeyAndOrderFront:self];
        [a searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10) && [sa searchPending], @"publication hold establishes pending browser request");
        NSUInteger notesBeforeReturn = [[library allNotes] count];
        [a fieldAction:self];
        Check([[library allNotes] count] == notesBeforeReturn && [sa searchPending], @"Return during pending search cannot infer permission to create");
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [a selectedNoteObject] == road; }, 10), @"pending Return opens completed title-first result");
        Check([[library allNotes] count] == notesBeforeReturn, @"completed nonempty Return creates no note");

        hold = YES; [a searchForString:@"\"never create this obsolete query\"" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"obsolete zero result is held before publication");
        [a fieldAction:self]; [a searchForString:@"copper" mode:@"fuzzy"];
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [[sa searchString] isEqual:@"copper"]; }, 10), @"new query supersedes deferred Return");
        Check([[library allNotes] count] == notesBeforeReturn, @"superseded zero result cannot create its old query");

        hold = YES; [a searchForString:@"\"future marker\"" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"pre-edit membership completion is held");
        NSUInteger beforeMutation = [sa searchGeneration];
        [body setContentString:[[[NSAttributedString alloc] initWithString:@"road copper lantern future marker"] autorelease]];
        Check(![sa searchResultsAreCurrent] && [sa searchGeneration] > beforeMutation, @"model mutation invalidates browser ownership synchronously");
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && FuzzyRow(sa, body, @"fuzzy") != NSNotFound; }, 10), @"post-edit corpus supersedes held membership without omission");

        hold = YES; [b searchForString:@"copper" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"Reveal starts with pending membership");
        [b revealNote:road options:0];
        Check([[sb searchString] isEqual:@"copper"], @"Reveal does not clear query based on pending rows");
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sb searchResultsAreCurrent] && [b selectedNoteObject] == road && ![[sb searchString] length]; }, 10), @"Reveal resolves exclusion after completion and selects target");

        hold = YES; [b searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"closure starts with held result");
        [[b window] close]; NSUInteger browserCount = [[app browserControllers] count];
        hold = NO; releaseDeliveries(); Pump();
        Check([[app browserControllers] count] == browserCount && ![[app browserControllers] containsObject:b], @"closed browser rejects held completion and stays closed");
        method_setImplementation(method, original); imp_removeBlock(controlled); [b release];
        [a searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10), @"remaining browser remains usable after peer closure");
        NSLog(@"FUZZY APP WORKFLOW PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: fuzzy workflow exception %@", exception); exit(1); }
}
@end
