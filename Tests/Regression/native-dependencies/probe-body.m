    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        // Keep the system clipboard intact.
        NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
        method_setImplementation(class_getClassMethod([NSPasteboard class], @selector(generalPasteboard)),
            imp_implementationWithBlock(^id(id object) { return pboard; }));
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];

        NoteObject *note = MakeNote(library, @"Native fixtures", @"café 😀 \"quoted\"\nsecond line");

        for (NSString *name in @[@"SimplenoteSession", @"SimplenoteEntryCollector", @"SimplenoteEntryModifier", @"SyncSessionController", @"SyncResponseFetcher"])
            Check(NSClassFromString(name) == Nil, @"Simplenote service and network classes are absent from the app");
        Check(![app respondsToSelector:NSSelectorFromString(@"syncSessionController")] && ![self respondsToSelector:NSSelectorFromString(@"showSyncStatus:")], @"application and browser expose no sync actions");
        for (NSString *locale in @[@"de", @"en", @"fr", @"it", @"pt-PT", @"zh"]) {
            NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:[locale stringByAppendingString:@".lproj/NotationPrefsView.nib"]];
            NSNib *nib = [[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:[NSBundle mainBundle]] autorelease];
            NotationPrefsViewController *controller = [[NotationPrefsViewController alloc] init];
            NSArray *top = nil;
            Check([nib instantiateWithOwner:controller topLevelObjects:&top], [locale stringByAppendingString:@" preferences interface loads with actual controller"]);
            NSTabView *tabs = NVFindPreferencesTabs([controller view]);
            NSMutableArray *identifiers = [NSMutableArray array];
            for (NSTabViewItem *item in [tabs tabViewItems]) [identifiers addObject:[item identifier]];
            Check([identifiers isEqual:@[@"storage", @"security"]], [locale stringByAppendingString:@" preferences expose only storage and security"]);
            Check([[controller valueForKey:@"storageFormatPopupButton"] numberOfItems] == 2, [locale stringByAppendingString:@" storage popup keeps database and plain-text formats"]);
            for (NSString *key in @[@"enableEncryptionButton", @"changePasswordButton", @"allowedExtensionsTable", @"allowedTypesTable"]) {
                Check([controller valueForKey:key] != nil, [NSString stringWithFormat:@"%@ surviving %@ outlet connected", locale, key]);
            }
            // Controller subscribes to shared preferences; retain it for this process's lifetime.
        }
        // UTF-16 offsets, punctuation, mail links, and nvALT's separate wiki pass.
        NSString *text = @"😀 prefix https://example.com/a?q=1, person@example.com and [[Other note]]";
        NSMutableAttributedString *linked = [[[NSMutableAttributedString alloc] initWithString:text] autorelease];
        NSRange changed = NSMakeRange(10, [text length] - 10);
        [linked addLinkAttributesForRange:changed];
        NSUInteger urlStart = [text rangeOfString:@"https://"].location;
        NSRange effective;
        NSURL *url = [linked attribute:NSLinkAttributeName atIndex:urlStart effectiveRange:&effective];
        Check([[url absoluteString] isEqualToString:@"https://example.com/a?q=1"] && NSEqualRanges(effective, [text rangeOfString:@"https://example.com/a?q=1"]), @"link detection handles Unicode offsets and excludes trailing punctuation");
        url = [linked attribute:NSLinkAttributeName atIndex:[text rangeOfString:@"person@"].location effectiveRange:NULL];
        Check([[url scheme] isEqualToString:@"mailto"], @"email addresses become mail links");
        url = [linked attribute:NSLinkAttributeName atIndex:[text rangeOfString:@"Other note"].location effectiveRange:NULL];
        Check([[url scheme] isEqualToString:@"nvalt"], @"wiki links retain nvALT navigation");
        [linked removeAttribute:NSLinkAttributeName range:changed];
        [linked replaceCharactersInRange:[text rangeOfString:@"https://example.com/a?q=1"] withString:@"ordinary words"];
        [linked addLinkAttributesForRange:NSMakeRange(0, [linked length])];
        Check([linked attribute:NSLinkAttributeName atIndex:urlStart effectiveRange:NULL] == nil, @"editing a URL clears its old link");
        NSMutableAttributedString *files = [[[NSMutableAttributedString alloc] initWithString:@"file:///tmp/fixture.txt file:///.file/id=123"] autorelease];
        [files addLinkAttributesForRange:NSMakeRange(0, [files length])];
        Check([[files attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL] isFileURL], @"ordinary file URLs remain clickable");
        Check([files attribute:NSLinkAttributeName atIndex:[[files string] rangeOfString:@"file:///.file/"].location effectiveRange:NULL] == nil, @"file-reference URLs stay unlinked");
        [linked addLinkAttributesForRange:NSMakeRange(0, 0)];

        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        for (NSString *extension in @[@"html", @"htm", @"shtml", @"xhtml", @"webarchive"]) {
            NSString *path = [TestDirectory stringByAppendingPathComponent:[@"import." stringByAppendingString:extension]];
            [@"<html><body>HTML fixture</body></html>" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            Check([importer noteWithFile:path] == nil, @"HTML and webarchive files are excluded from import");
        }
        NSString *plainPath = [TestDirectory stringByAppendingPathComponent:@"plain.txt"];
        [@"Plain fixture" writeToFile:plainPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        Check([importer noteWithFile:plainPath] != nil, @"plain text files still import");
        [pboard declareTypes:@[NSHTMLPboardType] owner:nil];
        [pboard setString:@"<b>HTML only</b>" forType:NSHTMLPboardType];
        Check(![self addNotesFromPasteboard:pboard], @"HTML-only paste cannot create a note");
        [pboard addTypes:@[NSStringPboardType] owner:nil];
        [pboard setString:@"Plain fallback" forType:NSStringPboardType];
        Check([self addNotesFromPasteboard:pboard], @"browser paste uses its plain text representation");
        [pboard declareTypes:@[NSStringPboardType] owner:nil];
        [pboard setString:@"https://example.invalid/page" forType:NSStringPboardType];
        Check([self addNotesFromPasteboard:pboard], @"pasting a URL creates text without downloading a web page");
        Check(![self interpretNVURL:[NSURL URLWithString:@"nvalt://make?html=%3Cb%3EHTML%3C/b%3E"]], @"HTML URL-scheme import is disabled");
        Check(![self interpretNVURL:[NSURL URLWithString:@"nvalt://make?url=https%3A%2F%2Fexample.invalid"]], @"web-page URL-scheme import is disabled");
        Check([self interpretNVURL:[NSURL URLWithString:@"nvalt://make?title=Fixture&txt=Plain%20body&tags=test"]], @"plain text URL-scheme import remains available");
        NSURL *localLink = [note uniqueNoteLink];
        Check([[localLink query] hasPrefix:@"NV="] && [[localLink query] rangeOfString:@"&"].location == NSNotFound, @"new note links encode only the local UUID");
        NSURL *localLookup = [NSURL URLWithString:[@"nvalt://find/Unmatched%20fixture/?" stringByAppendingString:[localLink query]]];
        Check([self interpretNVURL:localLookup] && [self selectedNoteObject] == note, @"local UUID links find notes independently of the search title");
        for (NSString *query in @[@"NV=YQ%3D%3D", @"NV=", @"Simplenote=legacy-remote-note"])
            Check([self interpretNVURL:[NSURL URLWithString:[@"nvalt://find/Unmatched%20fixture/?" stringByAppendingString:query]]] && [self selectedNoteObject] == nil,
                  @"short UUIDs and removed remote identifiers safely fall back to title search");
        LinkingEditor *editor = [self valueForKey:@"textView"];
        Check(![[editor readablePasteboardTypes] containsObject:NSHTMLPboardType] && ![editor readSelectionFromPasteboard:pboard type:NSHTMLPboardType], @"editor paste excludes HTML readers");

        Check(NSClassFromString(@"SUUpdater") == Nil && NSClassFromString(@"AHHyperlinkScanner") == Nil && NSClassFromString(@"MAAttachedWindow") == Nil && NSClassFromString(@"URLGetter") == Nil, @"removed dependency classes are absent from the app");
        Check([[[NSBundle mainBundle] infoDictionary] objectForKey:@"SUCheckAtStartup"] == nil, @"Sparkle configuration is absent");
        NSMenu *statusMenu = [self valueForKey:@"statBarMenu"];
        BOOL hasQuit = NO;
        for (NSMenuItem *item in [statusMenu itemArray]) if ([item action] == @selector(terminate:)) hasQuit = YES;
        Check([statusMenu itemWithTag:902] == nil && hasQuit, @"status menu removes the updater and retains Quit");
        Check([[[[NSApp mainMenu] itemAtIndex:0] submenu] itemWithTag:88] == nil, @"application menu removes the updater");

        // Source windows allocate the read-only provider only on demand.
        [self revealNote:note options:0]; Pump();
        Check(![self isViewingNote] && [self valueForKey:@"previewController"] == nil, @"source windows leave the inline viewer unallocated");
        NSSet *removedActions = [NSSet setWithObjects:@"shareNote:", @"shareAsk:", @"makePreviewSticky:", @"makePreviewNotSticky:", @"switchTabs:", @"showShareURL:isError:", nil];
        for (NSString *action in removedActions)
            Check(![PreviewController instancesRespondToSelector:NSSelectorFromString(action)], @"detached preview, sharing, and generated-source actions are removed");
        NSMutableArray *menus = [NSMutableArray arrayWithObjects:[NSApp mainMenu], statusMenu, nil];
        BOOL hasRemovedCommand = NO;
        for (NSUInteger index = 0; index < [menus count]; index++) {
            for (NSMenuItem *item in [[menus objectAtIndex:index] itemArray]) {
                NSString *action = [item action] ? NSStringFromSelector([item action]) : @"";
                if ([removedActions containsObject:action]) hasRemovedCommand = YES;
                if ([item submenu]) [menus addObject:[item submenu]];
            }
        }
        Check(!hasRemovedCommand, @"menus contain no removed preview commands");
        for (NSString *resource in @[@"template.html", @"templateclean.html", @"custom.css", @"customclean.css", @"tp2md.rb"])
            Check([[NSBundle mainBundle] pathForResource:[resource stringByDeletingPathExtension] ofType:[resource pathExtension]] == nil, @"script-dependent preview resources are absent from the application");
        Check([[NSBundle mainBundle] pathForResource:@"MarkupPreview" ofType:@"nib"] == nil, @"detached preview interfaces are absent from the application");
        [app newWindow:self]; Pump();
        AppController *browser = [[app browserControllers] lastObject];
        [browser revealNote:note options:0]; Pump();
        Check([browser valueForKey:@"previewController"] == nil, @"additional source browser also leaves the viewer unallocated");
        NSString *sourceBeforePreview = [[[note contentString] string] copy];
        [browser setViewingNote:YES];
        PreviewController *preview = [[browser valueForKey:@"previewController"] retain];
        NSDate *previewDeadline = [NSDate dateWithTimeIntervalSinceNow:12];
        while ([preview loading] && [previewDeadline timeIntervalSinceNow] > 0) Pump();
        Check(![preview loading] && ![preview renderError] && [preview renderedHTML] != nil, @"explicit Preview prepares the native read-only provider");
        Check([[preview view] window] == [browser window] && [[preview webView] isKindOfClass:[WKWebView class]], @"the provider embeds modern WebKit in the owning browser");
        Check([self valueForKey:@"previewController"] == nil && ![self isViewingNote], @"a peer stays in Source when another browser opens Preview");
        [browser setViewingNote:NO]; Pump();
        Check([[preview view] isHidden] && ![preview loading] && [[[note contentString] string] isEqual:sourceBeforePreview], @"returning to Source hides rendering without rewriting the note");
        [sourceBeforePreview release];
        [[browser window] close]; Pump();
        Check([preview renderedHTML] == nil && [[preview webView] navigationDelegate] == nil && [[preview webView] UIDelegate] == nil, @"browser closure disposes its viewer output and WebKit delegates");
        [preview release];
        [pboard releaseGlobally];
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"NATIVE DEPENDENCY CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
