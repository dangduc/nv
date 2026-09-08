    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        // Block network fetches, and keep the system clipboard intact.
        IMP originalStart = method_setImplementation(class_getInstanceMethod([SyncResponseFetcher class], @selector(start)),
            imp_implementationWithBlock(^BOOL(id object) { Check(NO, @"fixtures never start network requests"); return NO; }));
        NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
        method_setImplementation(class_getClassMethod([NSPasteboard class], @selector(generalPasteboard)),
            imp_implementationWithBlock(^id(id object) { return pboard; }));
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];

        // Exercise the production encoder and response readers without an account.
        SimplenoteSession *session = [[[SimplenoteSession alloc] initWithUsername:@"fixture@example.invalid" andPassword:@"quote\" café 😀"] autorelease];
        SyncResponseFetcher *login = [session loginFetcher];
        NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:[login valueForKey:@"dataToSend"] options:0 error:NULL];
        Check([payload[@"password"] isEqualToString:@"quote\" café 😀"], @"login JSON preserves escaped Unicode credentials");
        [session syncResponseFetcher:login receivedData:[@"{\"access_token\":\"fixture\"}" dataUsingEncoding:NSUTF8StringEncoding] returningError:nil];
        Check([[session valueForKey:@"simperiumToken"] isEqualToString:@"fixture"], @"login response reads the authorization token");
        NVSyncFixtureReceiver *receiver = [[[NVSyncFixtureReceiver alloc] init] autorelease];
        [session setDelegate:receiver];
        SyncResponseFetcher *index = [session listFetcher];
        [session syncResponseFetcher:index receivedData:[@"{\"index\":[{\"id\":\"a\",\"v\":3}],\"current\":\"cv1\"}" dataUsingEncoding:NSUTF8StringEncoding] returningError:nil];
        Check([receiver->fullList count] == 1 && [receiver->fullList[0][@"version"] integerValue] == 3, @"index JSON normalizes note versions");
        SyncResponseFetcher *changes = [session changesFetcher];
        [session syncResponseFetcher:changes receivedData:[@"[{\"id\":\"a\",\"cv\":\"cv2\",\"ev\":4,\"o\":\"+\"},{\"id\":\"b\",\"cv\":\"cv3\",\"ev\":2,\"o\":\"-\"}]" dataUsingEncoding:NSUTF8StringEncoding] returningError:nil];
        Check([receiver->partialList count] == 1 && [receiver->removedList count] == 1, @"array response separates changed and deleted notes");
        Check([[session valueForKey:@"lastCV"] isEqualToString:@"cv3"], @"changes advance the cursor");
        [session syncResponseFetcher:[session listFetcher] receivedData:[@"{\"index\":null}" dataUsingEncoding:NSUTF8StringEncoding] returningError:nil];
        Check([receiver->failure length] > 0, @"invalid index root reports a parsing error");

        SimplenoteEntryCollector *collector = [[[SimplenoteEntryCollector alloc] initWithEntriesToCollect:@[@{}] simperiumToken:@"fixture"] autorelease];
        SyncResponseFetcher *noteFetcher = [[[SyncResponseFetcher alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/Note/i/fixture"] POSTData:nil delegate:nil] autorelease];
        [noteFetcher setValue:@{@"X-Simperium-Version": @"7"} forKey:@"headers"];
        NSString *json = @"{\"content\":\"café 😀\\nquoted \\\"text\\\"\",\"deleted\":false,\"tags\":[\"日本語\"],\"creationDate\":1700000000.25,\"modificationDate\":1700000001,\"unused\":null}";
        NSDictionary *entry = [collector preparedDictionaryWithFetcher:noteFetcher receivedData:[json dataUsingEncoding:NSUTF8StringEncoding]];
        Check([entry[@"content"] isEqualToString:@"café 😀\nquoted \"text\""] && [entry[@"tags"] isEqual:@[@"日本語"]], @"note JSON preserves Unicode, escapes, and arrays");
        Check([entry[@"version"] integerValue] == 7 && ![entry[@"deleted"] boolValue] && [entry[@"create"] doubleValue] == 721692800.25, @"note JSON preserves booleans and fractional timestamps");
        for (NSString *invalid in @[@"{", @"[]", @"null", @"{\"content\":\"ok\"} trailing"]) {
            Check([collector preparedDictionaryWithFetcher:noteFetcher receivedData:[invalid dataUsingEncoding:NSUTF8StringEncoding]] == nil, @"invalid note JSON is rejected");
        }
        NoteObject *note = MakeNote(library, @"Native fixtures", @"café 😀 \"quoted\"\nsecond line");
        SimplenoteEntryModifier *modifier = [[[SimplenoteEntryModifier alloc] initWithEntries:@[note] operation:@selector(fetcherForCreatingNote:) simperiumToken:@"fixture"] autorelease];
        SyncResponseFetcher *creation = [modifier fetcherForCreatingNote:note];
        payload = [NSJSONSerialization JSONObjectWithData:[creation valueForKey:@"dataToSend"] options:0 error:NULL];
        Check([payload[@"content"] rangeOfString:@"café 😀 \"quoted\"\nsecond line"].location != NSNotFound && [payload[@"deleted"] intValue] == 0, @"outgoing note JSON preserves the body and deletion flag");
        [creation setValue:@{@"X-Simperium-Version": @"7"} forKey:@"headers"];
        NSDictionary *createdEntry = [modifier preparedDictionaryWithFetcher:creation receivedData:[json dataUsingEncoding:NSUTF8StringEncoding]];
        Check([createdEntry[@"key"] length] > 0 && [[note syncServicesMD][SimplenoteServiceName][@"version"] integerValue] == 7,
            @"creation response attaches parsed sync metadata to the note");
        SyncResponseFetcher *update = [modifier fetcherForUpdatingNote:note];
        payload = [NSJSONSerialization JSONObjectWithData:[update valueForKey:@"dataToSend"] options:0 error:NULL];
        Check([payload[@"content"] rangeOfString:@"café 😀"].location != NSNotFound && [[[update requestURL] path] hasSuffix:@"/v/7"],
            @"update JSON preserves content and uses the note version");
        DeletedNoteObject *deleted = [DeletedNoteObject deletedNoteWithNote:note];
        SyncResponseFetcher *deletion = [modifier fetcherForDeletingNote:deleted];
        payload = [NSJSONSerialization JSONObjectWithData:[deletion valueForKey:@"dataToSend"] options:0 error:NULL];
        Check([payload isEqual:@{@"deleted": @1}], @"deletion JSON sends the numeric deletion flag");
        NVSyncFixtureReceiver *encodingFailure = [[[NVSyncFixtureReceiver alloc] init] autorelease];
        SyncResponseFetcher *invalidWrite = [[[SyncResponseFetcher alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/"] POSTData:nil headers:nil contentType:@"application/json" delegate:encodingFailure] autorelease];
        Check(!((BOOL(*)(id, SEL))originalStart)(invalidWrite, @selector(start)) && [encodingFailure->failure length] > 0, @"failed encoding reports an error without issuing a GET");

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
        LinkingEditor *editor = [self valueForKey:@"textView"];
        Check(![[editor readablePasteboardTypes] containsObject:NSHTMLPboardType] && ![editor readSelectionFromPasteboard:pboard type:NSHTMLPboardType], @"editor paste excludes HTML readers");

        Check(NSClassFromString(@"SUUpdater") == Nil && NSClassFromString(@"AHHyperlinkScanner") == Nil && NSClassFromString(@"MAAttachedWindow") == Nil && NSClassFromString(@"URLGetter") == Nil, @"removed dependency classes are absent from the app");
        Check([[[NSBundle mainBundle] infoDictionary] objectForKey:@"SUCheckAtStartup"] == nil, @"Sparkle configuration is absent");
        NSMenu *statusMenu = [self valueForKey:@"statBarMenu"];
        BOOL hasQuit = NO;
        for (NSMenuItem *item in [statusMenu itemArray]) if ([item action] == @selector(terminate:)) hasQuit = YES;
        Check([statusMenu itemWithTag:902] == nil && hasQuit, @"status menu removes the updater and retains Quit");
        Check([[[[NSApp mainMenu] itemAtIndex:0] submenu] itemWithTag:88] == nil, @"application menu removes the updater");

        // Native popovers use the real nib, with no call to the sharing service.
        [self revealNote:note options:0]; Pump();
        PreviewController *preview = [self valueForKey:@"previewController"];
        [preview showWindow:self]; Pump();
        NSPopover *confirmation = [preview valueForKey:@"confirmationPopover"];
        NSPopover *result = [preview valueForKey:@"sharePopover"];
        Check([[confirmation contentViewController] view] == [preview valueForKey:@"shareConfirmation"] &&
            [[result contentViewController] view] == [preview valueForKey:@"shareNotification"], @"popover content uses the loaded nib views");
        Check([[preview valueForKey:@"shareConfirm"] superview] == [[confirmation contentViewController] view] &&
            [[preview valueForKey:@"viewOnWebButton"] superview] == [[result contentViewController] view], @"popover buttons belong to the visible content");
        [confirmation setAnimates:NO]; [result setAnimates:NO];
        [preview shareAsk:self]; Pump();
        Check([confirmation isShown], @"Share opens a native confirmation popover");
        [preview cancelShare:self]; Pump();
        Check(![confirmation isShown], @"Cancel dismisses the confirmation");
        [preview shareAsk:self]; Pump(); [confirmation close]; Pump();
        [preview shareAsk:self]; Pump();
        Check([confirmation isShown], @"Share reopens after native dismissal");
        [preview showShareURL:@"Error fixture" isError:YES]; Pump();
        Check(![confirmation isShown] && [result isShown] && [[preview valueForKey:@"viewOnWebButton"] isHidden], @"sharing errors replace the confirmation and hide the browser action");
        [preview showShareURL:@"https://example.invalid/shared" isError:NO]; Pump();
        Check(NSEqualSizes([result contentSize], NSMakeSize(360, 112)) &&
            [[[preview valueForKey:@"urlTextField"] stringValue] rangeOfString:@"example.invalid/shared"].location != NSNotFound,
            @"result popover retains its intended size and visible URL label");
        Check([result isShown] && ![[preview valueForKey:@"viewOnWebButton"] isHidden] && [[pboard stringForType:NSStringPboardType] isEqualToString:@"https://example.invalid/shared"], @"success restores the browser action and copies the URL");
        const char *screenshots = getenv("NV_DEPENDENCY_SCREENSHOTS");
        if (screenshots) {
            [NSApp activateIgnoringOtherApps:YES];
            [[preview window] makeKeyAndOrderFront:self];
            [preview showShareURL:@"https://example.invalid/shared" isError:NO];
            Pump();
            NSWindow *popoverWindow = [[[result contentViewController] view] window];
            CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
                (CGWindowID)[popoverWindow windowNumber], kCGWindowImageBoundsIgnoreFraming);
            if (image) {
                NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
                [[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:[NSString stringWithUTF8String:screenshots] atomically:YES];
                CGImageRelease(image);
            }
        }
        [preview togglePreview:self]; Pump();
        Check(![result isShown] && [preview valueForKey:@"shareURL"] == nil, @"hiding preview closes the result and releases its URL");
        [preview showWindow:self]; [preview shareAsk:self]; Pump();
        [preview close]; Pump();
        Check(![confirmation isShown] && ![result isShown], @"closing preview dismisses both popovers");
        [app newWindow:self]; Pump();
        AppController *browser = [[app browserControllers] lastObject];
        PreviewController *otherPreview = [[browser valueForKey:@"previewController"] retain];
        [[otherPreview valueForKey:@"confirmationPopover"] setAnimates:NO];
        [otherPreview showWindow:self]; [otherPreview shareAsk:self]; Pump();
        [[browser window] close]; Pump();
        Check(![[otherPreview valueForKey:@"confirmationPopover"] isShown], @"browser teardown dismisses its preview popover");
        [otherPreview release];
        [pboard releaseGlobally];
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"NATIVE DEPENDENCY CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
