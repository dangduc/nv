    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        Check([self valueForKey:@"previewController"] == nil, @"an empty Source window allocates no preview provider");
        for (NSString *action in @[@"selectPreviewMode:", @"selectSourceSyntax:", @"togglePreview:", @"savePreview:", @"printPreview:"]) {
            NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:action action:NSSelectorFromString(action) keyEquivalent:@""] autorelease];
            [item setRepresentedObject:@"org"];
            Check(![self validateMenuItem:item], @"note-dependent source and viewer commands disable without a selected note");
        }
        [self selectPreviewMode:ViewerItem(@"org")];
        Check(![self isViewingNote] && [self valueForKey:@"previewController"] == nil, @"a direct viewer API call without a note allocates no provider");
        [self selectPreviewMode:ViewerItem(@"future-viewer")];
        Check([[self selectedViewerIdentifier] isEqual:@"org"] && [self valueForKey:@"previewController"] == nil, @"an unknown viewer API input retains the previous valid choice without allocation");

        NSMutableString *source = [NSMutableString stringWithString:@"* First heading\n:PROPERTIES:\n:CUSTOM_ID: first\n:END:\n\n[[#second][Second heading]]\n\n"];
        for (NSUInteger i = 0; i < 35; i++) [source appendFormat:@"Paragraph %lu with ordinary *Org text*.\n\n", (unsigned long)i];
        [source appendString:@"* Second heading\n:PROPERTIES:\n:CUSTOM_ID: second\n:END:\n\n[[#first][First heading]]\n\n"];
        for (NSUInteger i = 0; i < 35; i++) [source appendFormat:@"Final paragraph %lu.\n\n", (unsigned long)i];
        NoteObject *note = MakeNote(library, @"Round 2 viewer boundaries", source);
        [self revealNote:note options:0]; Pump();
        Check(![self isViewingNote] && [self valueForKey:@"previewController"] == nil, @"selecting a note keeps source-only allocation despite a saved Org choice");
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:note options:0]; Pump();
        Check([peer valueForKey:@"previewController"] == nil && ![peer isViewingNote], @"a new peer window starts without a viewer allocation");
        LinkingEditor *editor = [self valueForKey:@"textView"], *peerEditor = [peer valueForKey:@"textView"];
        NSTextStorage *storage = [editor textStorage];
        Check(storage == [peerEditor textStorage], @"both windows attach the same note storage before preview allocation");
        CFAbsoluteTime modified = modifiedDateOfNote(note);
        [[note undoManager] removeAllActions];
        uint64_t generation = [[app editingSessionForNote:note] sourceGeneration];
        [self selectPreviewMode:ViewerItem(@"html")];
        Check(Await(^BOOL { return Ready([self valueForKey:@"previewController"], @"html"); }, 20), @"HTML supplies the valid choice before malformed state restoration");
        NSMutableDictionary *saved = [[[self browserWindowState] mutableCopy] autorelease];
        for (id invalid in @[@"future-viewer", @42, [NSNull null]]) {
            NSMutableDictionary *state = [[saved mutableCopy] autorelease];
            if (invalid == [NSNull null]) [state removeObjectForKey:@"viewerIdentifier"];
            else [state setObject:invalid forKey:@"viewerIdentifier"];
            [state setObject:@{@"viewers": @{@"org": @42, @"future-viewer": @{@"find": @"unrecognized"}}} forKey:@"bodyState"];
            [self restoreBrowserWindowState:state];
            Check(Await(^BOOL { return Ready([self valueForKey:@"previewController"], @"html"); }, 20), @"unknown, numeric or missing saved viewer values retain a supported viewer");
            Check(![peer isViewingNote] && [peer valueForKey:@"previewController"] == nil && [peerEditor textStorage] == storage, @"restoring one window does not allocate or reattach its peer provider");
            Check([[note sourceSyntaxIdentifier] isEqual:@"plain"] && [[storage string] isEqual:source], @"malformed viewer state cannot change note syntax or source");
        }
        [self selectPreviewMode:ViewerItem(@"org")];
        [peer selectPreviewMode:ViewerItem(@"org")];
        PreviewController *first = [self valueForKey:@"previewController"], *second = [peer valueForKey:@"previewController"];
        Check(Await(^BOOL { return Ready(first, @"org") && Ready(second, @"org"); }, 20), @"both independent providers render the same Plain Text note as Org");
        Check(first != second && [first webView] != [second webView] && [editor textStorage] == [peerEditor textStorage], @"per-window viewers remain separate while source ownership stays shared");

        // Suppress periodic cache updates. Each public capture must obtain its
        // offsets from its own real WebKit document after a fragment change.
        [[first valueForKey:@"stateTimer"] invalidate];
        [[second valueForKey:@"stateTimer"] invalidate];
        [first restoreViewerState:@{@"find": @"first-window-query", @"scrollY": @0}];
        [second restoreViewerState:@{@"find": @"second-window-query", @"scrollY": @0}];
        NSArray *firstDOM = DOM([first webView], @"window.location.hash='first';window.scrollTo(0,170);[document.baseURI,window.scrollY]");
        NSArray *secondDOM = DOM([second webView], @"window.location.hash='second';window.scrollTo(0,410);[document.baseURI,window.scrollY]");
        Check([firstDOM count] == 2 && [secondDOM count] == 2 && [firstDOM[0] hasSuffix:@"#first"] && [secondDOM[0] hasSuffix:@"#second"], @"real WebKit documents carry distinct heading fragments");
        Check([firstDOM[1] doubleValue] > 100 && [secondDOM[1] doubleValue] > 300, @"both documents have fresh offsets outside their cached state");
        __block NSUInteger firstReplies = 0, secondReplies = 0;
        __block NSDictionary *firstState = nil, *secondState = nil;
        [first captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
            Check(snapshot == [first snapshot] && [identifier isEqual:@"org"], @"first capture retains the original snapshot and viewer identity");
            firstState = [state copy]; firstReplies++;
        }];
        [second captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) {
            Check(snapshot == [second snapshot] && [identifier isEqual:@"org"], @"peer capture retains its own snapshot and viewer identity");
            secondState = [state copy]; secondReplies++;
        }];
        Check(Await(^BOOL { return firstReplies && secondReplies; }, 3), @"both public capture callbacks complete");
        Check(fabs([firstState[@"scrollY"] doubleValue] - [firstDOM[1] doubleValue]) <= 2 && [firstState[@"find"] isEqual:@"first-window-query"], @"fragment fix captures the first window offset and keeps its query");
        Check(fabs([secondState[@"scrollY"] doubleValue] - [secondDOM[1] doubleValue]) <= 2 && [secondState[@"find"] isEqual:@"second-window-query"], @"fragment fix captures the peer offset and keeps its independent query");
        Check(![firstState[@"scrollY"] isEqual:secondState[@"scrollY"]], @"simultaneous captures do not merge the two windows' presentation state");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.6]];
        Check(firstReplies == 1 && secondReplies == 1, @"capture fallback deadlines cannot issue duplicate callbacks");
        [firstState release]; [secondState release];

        [first retain];
        NSMutableDictionary *empty = [[[self browserWindowState] mutableCopy] autorelease];
        [empty setObject:@"review-missing-note" forKey:@"note"];
        [empty setObject:@"org" forKey:@"viewerIdentifier"];
        [self restoreBrowserWindowState:empty];
        Check(Await(^BOOL { return [self selectedNoteObject] == nil; }, 3), @"saved state with a missing note restores an empty browser");
        Check(![self isViewingNote] && [self valueForKey:@"previewController"] == nil, @"empty restoration closes the old provider and keeps allocation lazy");
        Check([first renderedHTML] == nil && [[first valueForKey:@"closed"] boolValue], @"the discarded provider clears its result and marks itself closed");
        Check(Ready(second, @"org") && [peerEditor textStorage] == storage, @"closing one restored provider leaves the peer viewer and shared source intact");
        __block NSUInteger closedReplies = 0;
        [first captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *state) { closedReplies++; }];
        Check(closedReplies == 1, @"capture after closure terminates once without a WebKit request");
        [first release];
        Check([[note sourceSyntaxIdentifier] isEqual:@"plain"] && [[[note contentString] string] isEqual:source] && [storage.string isEqual:source] && [[app editingSessionForNote:note] sourceGeneration] == generation, @"all restoration and capture paths preserve source metadata, characters and generation");
        Check(modifiedDateOfNote(note) == modified && ![[note undoManager] canUndo], @"viewer ownership transitions leave note dates and Undo unchanged");
        NSLog(@"ORG PREVIEW OUSTERHOUT ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
