    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        NotesTableView *table = [browser valueForKey:@"notesTableView"];
        NVBrowserSession *session = [browser browserSession];
        [[GlobalPrefs defaultPrefs] setShowWordCount:NO];
        [[GlobalPrefs defaultPrefs] setTableColumnsShowPreview:YES sender:self];
        NSMutableArray *notes = [NSMutableArray array];
        for (NSUInteger i = 0; i < 20; i++)
            [notes addObject:MakeNote(library, [NSString stringWithFormat:@"Note %02lu", (unsigned long)i], @"short source")];
        NoteObject *alpha = notes[0], *beta = notes[1];
        [browser searchForString:@"" mode:@"fuzzy"];
        [session setSortColumn:[table noteAttributeColumnForIdentifier:NoteTitleColumnString] reversed:NO];
        [browser revealNote:alpha options:0]; Pump(); Pump(); Pump();
        [[browser window] makeKeyAndOrderFront:self]; [[browser window] makeFirstResponder:editor];
        Check([browser selectedNoteObject] == alpha && [[editor string] isEqual:@"short source"], @"short source fixture opens in the production editor");
        Swap([AppController class], @selector(notationListDidChange:), @selector(nv_countList:));
        Swap([AppController class], @selector(rowShouldUpdate:), @selector(nv_countRow:));
        Swap([AppController class], @selector(postTextUpdate), @selector(nv_countPost));
        Swap([AppController class], @selector(updateNoteHeader), @selector(nv_countHeader));
        Swap([NVSearchService class], @selector(requestLiteralRangesInSource:matchingSource:query:owner:completion:), @selector(nv_countLiteral:matchingSource:query:owner:completion:));
        TrackedBrowser = browser;
        id otherPreview = [[session previewForNote:beta inTable:table] retain];
        id oldPreview = [[session previewForNote:alpha inTable:table] retain];
        NSUInteger sourceLength = [[editor string] length];
        [editor setSelectedRange:NSMakeRange(sourceLength, 0)];
        for (NSUInteger i = 0; i < 50; i++) [editor insertText:@"k" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check([[[alpha contentString] string] length] == sourceLength + 50 && [[editor string] isEqual:[[alpha contentString] string]], @"all 50 edits commit synchronously before any refresh timer");
        Check([session searchResultsAreCurrent] && [[session notesAtIndexes:[NSIndexSet indexSetWithIndex:0]] count] == 1, @"empty-query body edits keep safe existing rows actionable");
        Check(FullRefreshes == 0 && Headers == 0 && OriginPosts == 50, @"body edits skip full-list and header refreshes and notify the origin once");
        Check([session previewForNote:beta inTable:table] == otherPreview && [session previewForNote:alpha inTable:table] != oldPreview, @"body edit invalidates only its own UUID preview cache");
        [oldPreview release]; [otherPreview release];
        Check(Await(^BOOL { return DirtyRows != 0; }, 1), @"final dirty row is delivered after typing stops");
        Check(FullRefreshes == 0 && LiteralRequests == 0 && !HasBackground(editor), @"empty query needs neither full refresh nor literal highlight analysis");
        NSUInteger beforeRows = DirtyRows;
        for (NSUInteger i = 0; i < 30; i++) {
            [editor insertText:@"k" replacementRange:NSMakeRange(NSNotFound, 0)];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        }
        Check(DirtyRows > beforeRows && DirtyRows - beforeRows < 15, @"continuous typing delivers bounded row updates before the final key");
        Check([[session notesListDataSource] count] == 20 && [browser selectedNoteObject] == alpha, @"row updates retain membership and current editor");

        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer searchForString:@"" mode:@"fuzzy"]; [peer revealNote:alpha options:0]; Pump(); Pump();
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        TrackedPeer = peer;
        Check([editor textStorage] == [peerEditor textStorage], @"peer uses the same live source storage");
        [[browser window] makeKeyAndOrderFront:self]; [[browser window] makeFirstResponder:editor];
        OriginPosts = PeerPosts = Headers = 0;
        [editor insertText:@"shared" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check(OriginPosts == 1 && PeerPosts == 1 && Headers == 0 && [[editor string] isEqual:[peerEditor string]], @"each source window gets one content notification without metadata redraw");
        [editor undo:self];
        Check([[editor string] isEqual:[peerEditor string]] && [[editor string] isEqual:[[alpha contentString] string]], @"Undo remains synchronous across the source windows");
        Pump(); Pump(); Pump();

        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        for (NSUInteger i = 0; i < [notes count]; i++) [(NoteObject *)notes[i] setDateModified:now - 1000 + i * 10];
        [session setSortColumn:[table noteAttributeColumnForIdentifier:NoteDateModifiedColumnString] reversed:YES];
        Check([session noteObjectAtFilteredIndex:0] != alpha, @"Date Modified fixture initially places the old note below newer notes");
        NSString *selectedKey = [[browser selectedSearchResultRowKey] copy];
        [editor insertText:@"recent" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check(Await(^BOOL { return [session noteObjectAtFilteredIndex:0] == alpha; }, 1), @"body refresh publishes the new Date Modified order");
        Check([browser selectedNoteObject] == alpha && [[browser selectedSearchResultRowKey] isEqual:selectedKey], @"Date Modified reordering preserves the selected result occurrence");
        [selectedKey release];
        [session setSortColumn:[table noteAttributeColumnForIdentifier:NoteTitleColumnString] reversed:NO];

        [browser searchForString:@"needle" mode:@"exact"]; Pump();
        [beta setContentString:[[[NSAttributedString alloc] initWithString:@"needle body"] autorelease]];
        Check(![session searchResultsAreCurrent] && ![[session notesAtIndexes:[NSIndexSet indexSetWithIndex:0]] count], @"Exact body change immediately prevents stale row actions");
        Check(Await(^BOOL { return [session searchResultsAreCurrent]; }, 2) && [session indexInFilteredListForNoteIdenticalTo:beta] != NSNotFound, @"Exact membership refilters the committed body without the typing delay");
        [beta setTitleString:@"needle target"];
        [browser searchForString:@"needle" mode:@"fuzzy"];
        Check(Await(^BOOL { return [session searchResultsAreCurrent] && [session resultCount] >= 2; }, 5), @"Fuzzy search publishes title and native occurrences of the same note");
        NSUInteger fuzzyRow = NSNotFound;
        for (NSUInteger row = 0; row < [[session notesListDataSource] count]; row++)
            if ([session noteObjectAtFilteredIndex:row] == beta && [[session matchKindAtIndex:row] isEqual:@"fuzzy"]) fuzzyRow = row;
        Check(fuzzyRow != NSNotFound, @"duplicate note has an identifiable native occurrence");
        [table selectRowAndScroll:fuzzyRow]; [browser displayContentsForNoteAtIndex:fuzzyRow];
        selectedKey = [[browser selectedSearchResultRowKey] copy];
        [[browser window] makeFirstResponder:editor]; [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
        [editor insertText:@" changed" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check(![session searchResultsAreCurrent], @"Fuzzy body change invalidates stale occurrences immediately");
        Check(Await(^BOOL { return [session searchResultsAreCurrent]; }, 5) && [[browser selectedSearchResultRowKey] isEqual:selectedKey], @"fresh Fuzzy publication preserves the selected duplicate occurrence");
        [selectedKey release];
        [editor setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, 6)]]];
        Check(HasBackground(editor), @"highlight fixture contains a real temporary background");
        [browser searchForString:@"" mode:@"fuzzy"];
        Check(Await(^BOOL { return !HasBackground(editor); }, 1), @"clearing the query removes old highlights once");
        [browser revealNote:alpha options:0]; Pump(); Pump();
        [[browser window] makeFirstResponder:editor];
        NSString *beforeComposition = [[[alpha contentString] string] copy];
        [editor setMarkedText:@"composed" selectedRange:NSMakeRange(8, 0) replacementRange:NSMakeRange([[editor string] length], 0)];
        Check([editor hasMarkedText] && [[[alpha contentString] string] isEqual:beforeComposition] && [[peerEditor string] isEqual:[editor string]], @"marked source text is shared immediately while its model commit stays deferred");
        [editor unmarkText]; [[app editingSessionForNote:alpha] commitPendingTextChanges];
        Check([[[alpha contentString] string] isEqual:[editor string]] && [[editor string] hasSuffix:@"composed"], @"ending composition commits the complete source synchronously");
        [beforeComposition release];
        NVBrowserSession *detached = [[NVBrowserSession alloc] initWithLibrary:library];
        [detached setDelegate:browser]; [detached notePreviewDidChange:alpha];
        Check([[detached valueForKey:@"bodyRefreshScheduled"] boolValue], @"detachment fixture has a scheduled body refresh");
        [detached setDelegate:nil];
        Check(![[detached valueForKey:@"bodyRefreshScheduled"] boolValue] && ![[detached valueForKey:@"dirtyBodyUUIDs"] count], @"detaching a browser cancels delayed row work before library replacement or close");
        [detached release];
        [editor insertText:@"pending" replacementRange:NSMakeRange(NSNotFound, 0)];
        [library removeNotes:@[beta]];
        Check(![session searchResultsAreCurrent], @"deletion blocks stale empty-query row actions before deferred publication");
        Check(Await(^BOOL { return [session searchResultsAreCurrent]; }, 2) && [[session notesListDataSource] count] == 19 && [session indexInFilteredListForNoteIdenticalTo:beta] == NSNotFound, @"deletion overtakes pending body refresh without resurrecting the removed note");
        Pump(); Pump(); Pump();
        Check([[session notesListDataSource] count] == 19, @"trailing body refresh retains the post-deletion membership");

        TrackedBrowser = TrackedPeer = nil;
        Check([library flushAllNoteChanges], @"disposable library checkpoint succeeds");
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"TYPING REFRESH PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"TYPING REFRESH EXCEPTION %@ %@", [exception name], [exception reason]); exit(1);
    }
}
@end
