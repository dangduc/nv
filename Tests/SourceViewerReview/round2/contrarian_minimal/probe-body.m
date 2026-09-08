    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        Check(ProviderInitializations == 0 && ProviderViewLoads == 0, @"startup never constructs a transient preview provider");
        NoteObject *note = MakeNote(library, @"Restoration costs", @"<p>restoration lazy marker</p>");
        [note setSourceSyntaxIdentifier:@"json"];
        [self revealNote:note options:0];
        NSMutableDictionary *sourceState = [[[self browserWindowState] mutableCopy] autorelease];
        [sourceState setObject:@NO forKey:@"viewingNote"];
        [sourceState setObject:@"html" forKey:@"viewerIdentifier"];
        [sourceState setObject:@{@"viewers": @{@"html": @{@"scrollY": @100}}} forKey:@"bodyState"];
        for (NSDictionary *overrides in @[@{}, @{@"presentationVersion": @2, @"viewingNote": @YES}, @{@"presentationVersion": @"1", @"viewingNote": @YES}, @{@"viewingNote": @"yes"}]) {
            NSMutableDictionary *state = [[sourceState mutableCopy] autorelease];
            [state addEntriesFromDictionary:overrides];
            [self restoreBrowserWindowState:state]; Pump();
            Check(![self isViewingNote] && ![self valueForKey:@"previewController"], @"source or unsupported restoration state leaves the provider absent");
            Check(ProviderInitializations == 0 && ProviderViewLoads == 0, @"restoration does not construct and discard a transient provider");
        }
        NSArray *actions = @[@"togglePreview:", @"toggleSourceView:", @"selectPreviewMode:", @"selectSourceSyntax:", @"savePreview:", @"printPreview:", @"performFindPanelAction:", @"printNote:"];
        for (NSUInteger iteration = 0; iteration < 100; iteration++) {
            for (NSString *name in actions) {
                NSMenuItem *item = SourceItem(@"html", NSSelectorFromString(name));
                [item setTag:NSFindPanelActionShowFindPanel];
                [self validateMenuItem:item];
            }
        }
        Check(ProviderInitializations == 0 && ProviderViewLoads == 0, @"800 menu validation calls allocate no viewer or web view in Source");
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self && ![peer isViewingNote], @"new window starts in Source independently of the selected viewer format");
        [peer restoreBrowserWindowState:sourceState]; Pump();
        Check([peer selectedNoteObject] == note && ![peer valueForKey:@"previewController"], @"second source restoration selects its note without a provider");
        Check(ProviderInitializations == 0 && ProviderViewLoads == 0, @"source-only windows share the library without any provider construction");
        NSMutableDictionary *previewState = [[sourceState mutableCopy] autorelease];
        [previewState setObject:@1 forKey:@"presentationVersion"];
        [previewState setObject:@YES forKey:@"viewingNote"];
        [peer restoreBrowserWindowState:previewState];
        Check(Await(^BOOL { return PreviewShows(peer, @"restoration lazy marker"); }, 15), @"supported Preview restoration renders its saved format");
        Check(ProviderInitializations == 1 && ProviderViewLoads == 1, @"restored Preview constructs exactly one provider and one web view");
        Check(![self valueForKey:@"previewController"], @"peer preview allocation does not allocate an original-window provider");
        Check([[note sourceSyntaxIdentifier] isEqual:@"json"], @"restoring HTML Preview keeps JSON source metadata");
        ChangeMode(peer, NO);
        for (NSUInteger iteration = 0; iteration < 10; iteration++) [peer restoreBrowserWindowState:sourceState];
        Pump();
        Check(![peer isViewingNote] && ![peer valueForKey:@"previewController"], @"restoring Source after Preview releases the browser provider reference");
        Check(ProviderInitializations == 1 && ProviderViewLoads == 1 && ProviderCloses >= 1, @"ten Source restorations close the prior provider and allocate no replacement");
        [[self window] makeKeyAndOrderFront:self];
        [[self valueForKey:@"notesTableView"] deselectAll:self]; Pump();
        Check([self selectedNoteObject] == nil, @"empty-selection menu probe has no selected note");
        [self selectPreviewMode:SourceItem(@"textile", @selector(selectPreviewMode:))];
        [self togglePreview:self];
        Check(![self isViewingNote] && ![self valueForKey:@"previewController"], @"direct Preview menu actions with no note allocate no provider");
        Check(ProviderInitializations == 1 && ProviderViewLoads == 1, @"provider construction stays at one after no-note actions");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND 2 MINIMAL CHECKS PASSED: %lu; providers=%lu views=%lu close calls=%lu", (unsigned long)Checks, (unsigned long)ProviderInitializations, (unsigned long)ProviderViewLoads, (unsigned long)ProviderCloses);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
@end
