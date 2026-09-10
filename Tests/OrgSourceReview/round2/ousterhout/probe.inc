    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSString *source = @"* TODO Boundary\n[[https://example.com][Web label]]\n[[Internal note]]\n";
        NoteObject *note = MakeNote(library, @"Round 2 boundary", source);
        [self revealNote:note options:0]; Pump();
        NSPopUpButton *popup = [self valueForKey:@"sourceSyntaxControl"];
        NSMutableArray *menus = [NSMutableArray array];
        CollectSourceMenus([NSApp mainMenu], menus);
        NSArray *identifiers = @[@"plain", @"markdown", @"textile", @"html", @"json", @"org"];
        NSMutableSet *popupValues = [NSMutableSet set];
        for (NSMenuItem *item in [popup itemArray]) [popupValues addObject:[item representedObject]];
        Check([popupValues isEqual:[NSSet setWithArray:identifiers]], @"popup exposes exactly the model syntax choices");
        Check([menus count] >= 2, @"both source menu surfaces exist");
        for (NSMenu *menu in menus) {
            NSMutableSet *values = [NSMutableSet set];
            for (NSMenuItem *item in [menu itemArray]) if ([item action] == @selector(selectSourceSyntax:)) [values addObject:[item representedObject]];
            Check([values isEqual:popupValues], @"menu choices match the popup and model contract");
        }
        CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, *[note uniqueNoteIDBytes]);
        NSString *key = [(NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease]; CFRelease(uuid);
        [[library notationPrefs] setSourceMetadata:@{@"syntax": @"plain", @"reviewExtra": @[@1, @"opaque"]} forNoteUUID:key];
        NSString *viewerBefore = [[self valueForKey:@"selectedViewerIdentifier"] copy];
        CFAbsoluteTime modified = modifiedDateOfNote(note);
        NSString *filename = [filenameOfNote(note) copy];
        [[note undoManager] removeAllActions];
        __block NSUInteger notifications = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NVNoteSyntaxDidChangeNotification object:note queue:nil usingBlock:^(NSNotification *notification) { notifications++; }];
        for (NSString *identifier in identifiers) {
            NSMenuItem *action = [[[NSMenuItem alloc] initWithTitle:identifier action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
            [action setRepresentedObject:identifier];
            [note setSourceSyntaxIdentifier:@"org"];
            NSUInteger before = notifications;
            [self selectSourceSyntax:action];
            Check([[note sourceSyntaxIdentifier] isEqual:identifier] && [[[popup selectedItem] representedObject] isEqual:identifier], @"menu action and popup agree with the note's effective syntax");
            Check(notifications == before + ![identifier isEqual:@"org"], @"the effective syntax transition sends exactly one notification");
            [self selectSourceSyntax:action];
            Check(notifications == before + ![identifier isEqual:@"org"], @"repeating the selection sends no duplicate notification");
            for (NSMenu *menu in menus) {
                NSUInteger checked = 0;
                for (NSMenuItem *item in [menu itemArray]) if ([item action] == @selector(selectSourceSyntax:)) {
                    Check([app validateMenuItem:item], @"application forwarding enables the source choice for the current note");
                    if ([item state] == NSControlStateValueOn) {
                        checked++;
                        Check([[item representedObject] isEqual:identifier], @"the checked menu item is the current model choice");
                    }
                }
                Check(checked == 1, @"each source menu has exactly one checked choice");
            }
        }
        for (id invalid in @[@"ORG", @"future-format", @42, [NSNull null]]) {
            [note setSourceSyntaxIdentifier:@"org"];
            NSUInteger before = notifications;
            [note setSourceSyntaxIdentifier:invalid == [NSNull null] ? nil : invalid];
            Check([[note sourceSyntaxIdentifier] isEqual:@"plain"] && notifications == before + 1, @"invalid public API input changes Org to Plain Text once");
            [note setSourceSyntaxIdentifier:invalid == [NSNull null] ? nil : invalid];
            Check(notifications == before + 1, @"repeated invalid input is a notification no-op");
            Check([[[popup selectedItem] representedObject] isEqual:@"plain"], @"the UI receives the sanitized model choice");
        }
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        Check([[[[library notationPrefs] sourceMetadataForNoteUUID:key] objectForKey:@"reviewExtra"] isEqual:@[@1, @"opaque"]], @"syntax changes preserve unrelated local metadata");
        Check([[[note contentString] string] isEqual:source] && modifiedDateOfNote(note) == modified && [filenameOfNote(note) isEqual:filename] && ![[note undoManager] canUndo], @"the API matrix preserves source, modification date, filename and Undo history");
        Check(![self isViewingNote] && [[self valueForKey:@"selectedViewerIdentifier"] isEqual:viewerBefore], @"source syntax never changes the independent preview choice or source mode");
        [viewerBefore release]; [filename release];

        // This note never attaches an editor. Exercise lazy session setup from
        // archived local metadata, without relying on a prior syntax observer.
        NoteObject *unopened = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:source] autorelease] title:@"Unopened Org" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
        [unopened setSourceSyntaxIdentifier:@"org"];
        NSData *noteBytes = [NSKeyedArchiver archivedDataWithRootObject:unopened];
        NotationPrefs *restoredPrefs = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[library notationPrefs]]];
        NoteObject *restored = [NSKeyedUnarchiver unarchiveObjectWithData:noteBytes];
        ReviewPrefsOwner *owner = [[[ReviewPrefsOwner alloc] init] autorelease]; owner->prefs = restoredPrefs;
        [restored setDelegate:owner];
        Check([[restored sourceSyntaxIdentifier] isEqual:@"org"], @"an unopened archived note restores Org through library UUID metadata");
        NVNoteEditingSession *session = [[NVNoteEditingSession alloc] initWithNote:restored];
        NSTextStorage *storage = [[session textStorage] retain];
        Check([[storage layoutManagers] count] == 0 && [[storage string] isEqual:source], @"the lazy session owns exact source before any editor attaches");
        NSRange web = [source rangeOfString:@"Web label"], internal = [source rangeOfString:@"Internal note"];
        Check([[[storage attribute:NSLinkAttributeName atIndex:web.location effectiveRange:NULL] absoluteString] isEqual:@"https://example.com"] && ![storage attribute:NSLinkAttributeName atIndex:internal.location effectiveRange:NULL], @"initial session construction uses the restored Org semantics");
        uint64_t generation = [session sourceGeneration];
        [restored setSourceSyntaxIdentifier:@"plain"];
        Check(![storage attribute:NSLinkAttributeName atIndex:web.location effectiveRange:NULL] && [[[storage attribute:NSLinkAttributeName atIndex:internal.location effectiveRange:NULL] scheme] isEqual:@"nvalt"], @"a session without layouts refreshes links after a syntax change");
        Check([session sourceGeneration] == generation, @"link-only changes leave the source generation unchanged");
        [restored setSourceSyntaxIdentifier:@"org"];
        [session closeWithoutCommitting];
        [restored setSourceSyntaxIdentifier:@"plain"];
        Check([[[storage attribute:NSLinkAttributeName atIndex:web.location effectiveRange:NULL] absoluteString] isEqual:@"https://example.com"], @"closing the session removes its syntax observer");
        [session release]; [storage release];
        owner->prefs = [[[NotationPrefs alloc] init] autorelease];
        Check([[restored sourceSyntaxIdentifier] isEqual:@"plain"], @"the same note UUID in a different metadata store retains library isolation");
        NSLog(@"ORG OUSTERHOUT ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
