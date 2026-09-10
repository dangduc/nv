    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        Check([[NoteObject sourceSyntaxIdentifierForPathExtension:@"org"] isEqual:@"org"] &&
              [[NoteObject sourceSyntaxIdentifierForPathExtension:@"ORG"] isEqual:@"org"], @"Org extension recognition is case insensitive");
        Check([[NoteObject sourceSyntaxIdentifierForPathExtension:@"unknown"] isEqual:@"plain"], @"unknown extensions retain Plain Text syntax");
        Check([[NotationPrefs defaultPathExtensionsForFormat:PlainTextFormat] containsObject:@"org"], @"new file libraries recognize Org");

        for (NSArray *extensions in @[@[@"custom", @"md"], @[@"custom", @"ORG", @"md"]]) {
            NotationPrefs *legacy = [[[NotationPrefs alloc] init] autorelease];
            unsigned int selected = (unsigned int)[extensions count] - 1;
            OrgSetLegacyExtensions(legacy, extensions, selected);
            NotationPrefs *migrated = [NSKeyedUnarchiver unarchiveObjectWithData:OrgLegacyArchive(legacy)];
            BOOL hadOrg = [extensions containsObject:@"ORG"];
            NSArray *expected = hadOrg ? extensions : [extensions arrayByAddingObject:@"org"];
            Check([OrgExtensions(migrated) isEqual:expected], @"legacy migration appends only a missing Org extension and preserves customization order");
            Check([migrated indexOfChosenPathExtension] == selected && [[migrated chosenPathExtensionForFormat:PlainTextFormat] isEqual:@"md"], @"legacy migration preserves the selected output extension");
            Check([migrated pathExtensionAllowed:@"org" forFormat:PlainTextFormat] && [migrated pathExtensionAllowed:@"ORG" forFormat:PlainTextFormat], @"migrated library accepts either Org extension case");
            NotationPrefs *reopened = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:migrated]];
            Check([OrgExtensions(reopened) isEqual:expected] && [reopened indexOfChosenPathExtension] == selected, @"reopening does not repeat the migration or change the chosen index");
            NSUInteger orgIndex = [OrgExtensions(reopened) indexOfObject:hadOrg ? @"ORG" : @"org"];
            Check([reopened removeAllowedPathExtensionAtIndex:orgIndex], @"users can remove the new extension from their file-library filter");
            NSArray *removed = [[OrgExtensions(reopened) copy] autorelease];
            NotationPrefs *removedReopened = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:reopened]];
            Check([OrgExtensions(removedReopened) isEqual:removed] && ![removedReopened pathExtensionAllowed:@"org" forFormat:PlainTextFormat], @"a later user removal survives another archive reopen");
        }

        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NSString *source = @"#+TITLE: Source fixture\r\n* TODO café 😀 e\u0301 :tag:\r\n  - [ ] untouched\r\n\n";
        const unsigned char utf8[] = {0xEF, 0xBB, 0xBF}, utf16le[] = {0xFF, 0xFE}, utf16be[] = {0xFE, 0xFF}, utf32le[] = {0xFF, 0xFE, 0, 0}, utf32be[] = {0, 0, 0xFE, 0xFF};
        NSArray *encodings = @[@(NSUTF8StringEncoding), @(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding), @(NSUTF32LittleEndianStringEncoding), @(NSUTF32BigEndianStringEncoding)];
        NSArray *boms = @[[NSData dataWithBytes:utf8 length:3], [NSData dataWithBytes:utf16le length:2], [NSData dataWithBytes:utf16be length:2], [NSData dataWithBytes:utf32le length:4], [NSData dataWithBytes:utf32be length:4]];
        NoteObject *firstImported = nil;
        for (NSUInteger index = 0; index < [encodings count]; index++) {
            NSStringEncoding encoding = [encodings[index] unsignedIntegerValue];
            NSMutableData *bytes = [NSMutableData dataWithData:boms[index]];
            [bytes appendData:[source dataUsingEncoding:encoding]];
            NSString *path = [TestDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"org-source-%lu.%@", (unsigned long)index, index % 2 ? @"ORG" : @"org"]];
            Check([bytes writeToFile:path atomically:YES], @"write an Org fixture with an explicit BOM");
            NSArray *imported = [importer notesInFile:path];
            Check([imported count] == 1, @"Org import returns one source note");
            NoteObject *note = [imported firstObject];
            Check([[[note contentString] string] isEqual:source] && [[note sourceSyntaxIdentifier] isEqual:@"org"], @"Org import preserves all source characters and supplies Org syntax");
            Check(fileEncodingOfNote(note) == encoding && [[note sourceDataReturningError:NULL] isEqual:bytes], @"Org import preserves encoding, BOM, line endings and original bytes");
            [library addNewNote:note];
            if (!firstImported) firstImported = note;
            Check([[note sourceDataReturningError:NULL] isEqual:bytes] && [[note sourceSyntaxIdentifier] isEqual:@"org"], @"library attachment preserves Org metadata and bytes");
            NSString *edited = [source stringByAppendingString:@"* Done\r\n"];
            [note setContentString:[[[NSAttributedString alloc] initWithString:edited] autorelease]];
            NSMutableData *expected = [NSMutableData dataWithData:boms[index]];
            [expected appendData:[edited dataUsingEncoding:encoding]];
            Check([[note sourceDataReturningError:NULL] isEqual:expected], @"edited Org source retains its encoding and BOM");
        }
        NSString *legacySource = @"* TODO café £\r\n";
        NSData *legacyBytes = [legacySource dataUsingEncoding:NSMacOSRomanStringEncoding];
        NSString *legacyPath = [TestDirectory stringByAppendingPathComponent:@"unmarked.org"];
        Check([legacyBytes writeToFile:legacyPath atomically:YES], @"write an unmarked legacy Org fixture");
        NoteObject *legacyNote = [importer noteWithFile:legacyPath];
        Check([[[legacyNote contentString] string] isEqual:legacySource] && fileEncodingOfNote(legacyNote) == NSMacOSRomanStringEncoding && [[legacyNote sourceDataReturningError:NULL] isEqual:legacyBytes], @"Org import preserves the existing unmarked MacRoman fallback");
        [library addNewNote:legacyNote];

        NoteObject *note = MakeNote(library, @"Org syntax support", @"#+TITLE: Project notebook\n\n* TODO Ship Org syntax :notes:\n  SCHEDULED: <2026-09-10 Thu>\n\n** Source stays editable\n- [X] Headings and task markers\n- [ ] Links, tables and source blocks\n\n[[file:agenda.org][Project agenda]]\n\n| Feature | Status |\n|---------+--------|\n| Source  | Ready  |\n\n#+BEGIN_SRC json\n{\"format\": \"org\", \"editable\": true}\n#+END_SRC\n");
        [self revealNote:note options:0];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:note options:0]; Pump();
        NSPopUpButton *popup = [self valueForKey:@"sourceSyntaxControl"], *peerPopup = [peer valueForKey:@"sourceSyntaxControl"];
        Check([popup indexOfItemWithRepresentedObject:@"org"] >= 0 && [peerPopup indexOfItemWithRepresentedObject:@"org"] >= 0, @"both source popups expose Org");
        Check([[[popup itemAtIndex:[popup indexOfItemWithRepresentedObject:@"org"]] title] isEqual:@"Org"], @"Org uses the requested display label");
        NSMutableArray *menuItems = [NSMutableArray array];
        OrgCollectSyntaxItems([NSApp mainMenu], menuItems);
        Check([menuItems count] >= 2, @"View Syntax Type and Source Syntax menus both expose Org");
        LinkingEditor *editor = [self valueForKey:@"textView"], *peerEditor = [peer valueForKey:@"textView"];
        Check([editor textStorage] == [peerEditor textStorage], @"two source editors share the same note storage");
        NSString *before = [[[note contentString] string] copy];
        NSString *filename = [filenameOfNote(note) copy];
        CFAbsoluteTime modified = modifiedDateOfNote(note);
        BOOL couldUndo = [[note undoManager] canUndo];
        __block NSUInteger notifications = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NVNoteSyntaxDidChangeNotification object:note queue:nil usingBlock:^(NSNotification *notification) { notifications++; }];
        [popup selectItemAtIndex:[popup indexOfItemWithRepresentedObject:@"org"]];
        [self selectSourceSyntax:popup];
        [self selectSourceSyntax:popup];
        Check(notifications == 1 && [[note sourceSyntaxIdentifier] isEqual:@"org"], @"selecting Org records syntax once");
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        Check([[[peerPopup selectedItem] representedObject] isEqual:@"org"], @"syntax selection updates the peer popup");
        Check([[[note contentString] string] isEqual:before] && [[editor string] isEqual:before] && [[peerEditor string] isEqual:before], @"syntax selection preserves model and shared source characters");
        Check(modifiedDateOfNote(note) == modified && [[note undoManager] canUndo] == couldUndo && [filenameOfNote(note) isEqual:filename], @"syntax selection changes neither dates, Undo nor filename");
        Check(![self isViewingNote] && ![peer isViewingNote], @"Org syntax selection leaves both windows in Source mode");
        for (NSMenuItem *item in menuItems) {
            Check([self validateMenuItem:item] && [item state] == NSControlStateValueOn, @"Org menu choice validates as checked for the selected source note");
        }
        [before release]; [filename release];
        Check(OrgAwait(^BOOL { return NVSourceCapturesAreCurrent([editor layoutManager]) && NVSourceCapturesAreCurrent([peerEditor layoutManager]); }, 4.0), @"Org analysis reaches both attached editors");
        if (getenv("NV_UI_ARTIFACTS")) {
            NSString *directory = [NSString stringWithUTF8String:getenv("NV_UI_ARTIFACTS")];
            Check([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL], @"Org screenshot directory exists");
            [[GlobalPrefs defaultPrefs] setShowBodyControlsInTopSection:YES sender:nil];
            [[GlobalPrefs defaultPrefs] setShowTitleInTopSection:YES sender:nil];
            [[self window] setFrame:NSMakeRect(100, 100, 930, 820) display:YES];
            [self setNotesListHeight:150];
            [[self window] makeKeyAndOrderFront:self];
            [[self window] makeFirstResponder:editor];
            [editor setSelectedRange:NSMakeRange(0, 0)];
            Check(OrgCaptureWindow([self window], [directory stringByAppendingPathComponent:@"org-source.png"]), @"capture the disposable Org source window");
        }

        NSData *noteArchive = [NSKeyedArchiver archivedDataWithRootObject:note];
        NSData *prefsArchive = [NSKeyedArchiver archivedDataWithRootObject:[library notationPrefs]];
        NoteObject *restored = [NSKeyedUnarchiver unarchiveObjectWithData:noteArchive];
        NVOrgPrefsOwner *owner = [[[NVOrgPrefsOwner alloc] init] autorelease];
        owner->prefs = [NSKeyedUnarchiver unarchiveObjectWithData:prefsArchive];
        [restored setDelegate:owner];
        Check([[restored sourceSyntaxIdentifier] isEqual:@"org"], @"archive reopen restores Org syntax by note UUID");
        owner->prefs = [[[NotationPrefs alloc] init] autorelease];
        Check([[restored sourceSyntaxIdentifier] isEqual:@"plain"], @"another library does not inherit Org metadata");

        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        Check([library flushAllNoteChanges], @"file-library checkpoint writes the disposable Org notes");
        NSString *storedPath = [[note noteFilePath] copy];
        NSData *storedBytes = [NSData dataWithContentsOfFile:storedPath];
        [note setSourceSyntaxIdentifier:@"plain"];
        [note setSourceSyntaxIdentifier:@"org"];
        Check([library flushAllNoteChanges] && [[note noteFilePath] isEqual:storedPath] && [[NSData dataWithContentsOfFile:storedPath] isEqual:storedBytes], @"selecting Org in a file library preserves the existing filename and file bytes");
        [storedPath release];
        NSString *watchedPath = [TestDirectory stringByAppendingPathComponent:@"Notes/watched.ORG"];
        NSData *watchedBytes = [@"* Watched\r\n  source\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        Check([watchedBytes writeToFile:watchedPath atomically:YES], @"write a new Org source into the watched library");
        [library synchronizeNotesFromDirectory];
        NoteObject *watched = nil;
        for (NoteObject *candidate in [library allNotes]) if ([[[candidate noteFilePath] stringByResolvingSymlinksInPath] isEqual:[watchedPath stringByResolvingSymlinksInPath]]) watched = candidate;
        if (!watched) for (NoteObject *candidate in [library allNotes]) NSLog(@"Org watcher candidate: %@ (expected %@)", [candidate noteFilePath], watchedPath);
        Check(watched && [[watched sourceSyntaxIdentifier] isEqual:@"org"] && [[watched sourceDataReturningError:NULL] isEqual:watchedBytes], @"directory reconciliation recognizes Org and preserves its exact source bytes");
        FSRef exportDirectory;
        Check(FSPathMakeRef((const UInt8 *)[TestDirectory fileSystemRepresentation], &exportDirectory, NULL) == noErr, @"temporary source-export directory resolves");
        Check([firstImported exportToDirectoryRef:&exportDirectory withFilename:@"export.org" usingFormat:PlainTextFormat overwrite:NO] == noErr && [[NSData dataWithContentsOfFile:[TestDirectory stringByAppendingPathComponent:@"export.org"]] isEqual:[firstImported sourceDataReturningError:NULL]], @"actual Org source export retains the original encoding and BOM after edits");
        Check([library flushAllNoteChanges], @"final checkpoint succeeds");
        FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithContentsOfFile:[TestDirectory stringByAppendingPathComponent:@"Notes/Notes & Settings"]]];
        OSStatus error = noErr;
        NSArray *reopenedNotes = [frozen unpackedNotesReturningError:&error];
        owner->prefs = [frozen notationPrefs];
        BOOL matched = NO;
        for (NoteObject *candidate in reopenedNotes) {
            if (memcmp([candidate uniqueNoteIDBytes], [firstImported uniqueNoteIDBytes], sizeof(CFUUIDBytes)) == 0) {
                [candidate setDelegate:owner];
                matched = [[candidate sourceSyntaxIdentifier] isEqual:@"org"] && [[candidate sourceDataReturningError:NULL] isEqual:[firstImported sourceDataReturningError:NULL]];
            }
        }
        Check(error == noErr && matched, @"on-disk library archive preserves Org metadata and exact source bytes");
        NSLog(@"ORG INTEGRATION PASSED (%lu checks)", (unsigned long)Checks);
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: %@", exception);
        exit(1);
    }
}
@end
