    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        Swap([EncodingsManager class], @selector(offerUTF8ConversionForNote:), @selector(nv_cancelConversionForNote:));
        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NSString *source = @"  \t# Heading\r\n\t café 😀 e\u0301\rFinal\n\n";
        NSArray *encodings = @[@(NSUTF8StringEncoding), @(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding), @(NSUTF32LittleEndianStringEncoding), @(NSUTF32BigEndianStringEncoding)];
        const unsigned char utf8[] = {0xEF, 0xBB, 0xBF}, utf16le[] = {0xFF, 0xFE}, utf16be[] = {0xFE, 0xFF}, utf32le[] = {0xFF, 0xFE, 0, 0}, utf32be[] = {0, 0, 0xFE, 0xFF};
        NSArray *boms = @[[NSData dataWithBytes:utf8 length:3], [NSData dataWithBytes:utf16le length:2], [NSData dataWithBytes:utf16be length:2], [NSData dataWithBytes:utf32le length:4], [NSData dataWithBytes:utf32be length:4]];
        NoteObject *firstImported = nil;
        for (NSUInteger index = 0; index < [encodings count]; index++) {
            NSStringEncoding encoding = [encodings[index] unsignedIntegerValue];
            NSMutableData *bytes = [NSMutableData dataWithData:boms[index]];
            [bytes appendData:[source dataUsingEncoding:encoding]];
            NSString *path = [TestDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"source-%lu.md", (unsigned long)index]];
            Check([bytes writeToFile:path atomically:YES], @"source fixture writes");
            NoteObject *note = [importer noteWithFile:path];
            Check(note && [[[note contentString] string] isEqualToString:source], @"text import preserves leading space, tabs, Unicode, CRLF, CR and trailing newlines");
            Check(fileEncodingOfNote(note) == encoding, @"text import records the explicit encoding");
            Check([[note sourceDataReturningError:NULL] isEqual:bytes], @"unchanged source exports the exact original bytes and BOM");
            Check([[note sourceSyntaxIdentifier] isEqualToString:@"markdown"], @"Markdown file extension supplies local syntax");
            [library addNewNote:note];
            if (index == 0) firstImported = note;
            Check([[note sourceDataReturningError:NULL] isEqual:bytes], @"library attachment preserves source bytes");
            NSString *edited = [source stringByAppendingString:@"Edited\r\n"];
            [note setContentString:[[[NSAttributedString alloc] initWithString:edited] autorelease]];
            NSMutableData *expected = [NSMutableData dataWithData:boms[index]];
            [expected appendData:[edited dataUsingEncoding:encoding]];
            Check([[note sourceDataReturningError:NULL] isEqual:expected], @"edited source retains encoding, BOM and line endings");
        }
        NSString *oddBOMPath = [TestDirectory stringByAppendingPathComponent:@"odd-bom.txt"];
        NSMutableData *oddBytes = [NSMutableData dataWithData:boms[0]];
        [oddBytes appendData:[@"ab" dataUsingEncoding:NSUTF8StringEncoding]];
        [oddBytes writeToFile:oddBOMPath atomically:YES];
        Check([[[[importer noteWithFile:oddBOMPath] contentString] string] isEqualToString:@"ab"], @"UTF-8 BOM detection works with an odd byte count");
        NSString *emptyPath = [TestDirectory stringByAppendingPathComponent:@"empty.txt"];
        [[NSData data] writeToFile:emptyPath atomically:YES];
        Check([[[importer noteWithFile:emptyPath] contentString] length] == 0, @"empty source imports without a synthetic body");
        for (NSString *extension in @[@"json", @"textile", @"txt", @"csv", @"tsv"]) {
            NSString *path = [TestDirectory stringByAppendingPathComponent:[@"unchanged." stringByAppendingString:extension]];
            NSString *body = @"a,b\r\n  x\t y\r\n";
            [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSArray *notes = [importer notesInFile:path];
            Check([notes count] == 1 && [[[[notes firstObject] contentString] string] isEqualToString:body], @"text import creates one unchanged source note");
            NSString *syntax = [@[@"json", @"textile"] containsObject:extension] ? extension : @"plain";
            Check([[[notes firstObject] sourceSyntaxIdentifier] isEqualToString:syntax], @"filename hint does not guess unsupported syntax");
        }
        for (NSString *extension in @[@"rtf", @"rtfd", @"rtx", @"nvhelp", @"doc", @"docx", @"pdf", @"html", @"webarchive"]) {
            NSString *path = [TestDirectory stringByAppendingPathComponent:[@"removed." stringByAppendingString:extension]];
            [@"{\\rtf1 legacy}" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            Check([importer noteWithFile:path] == nil, @"rich-text and rendered-document imports are unavailable");
        }
        NoteObject *plain = MakeNote(library, @"Plain", @"source\r\n");
        Check([[plain sourceSyntaxIdentifier] isEqualToString:@"plain"], @"new notes start with Plain Text syntax");
        CFAbsoluteTime modified = modifiedDateOfNote(plain);
        NSDictionary *syncBefore = [[plain syncServicesMD] copy];
        NSUndoManager *undo = [plain undoManager];
        BOOL couldUndo = [undo canUndo];
        __block NSUInteger notifications = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NVNoteSyntaxDidChangeNotification object:plain queue:nil usingBlock:^(NSNotification *notification) { notifications++; }];
        [plain setSourceSyntaxIdentifier:@"json"];
        [plain setSourceSyntaxIdentifier:@"json"];
        Check(notifications == 1 && modifiedDateOfNote(plain) == modified && [undo canUndo] == couldUndo, @"syntax changes notify once without changing dates or Undo");
        Check([[plain syncServicesMD] isEqual:syncBefore] || (!syncBefore && ![plain syncServicesMD]), @"syntax changes do not enter sync metadata");
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        [syncBefore release];
        [plain setTitleString:@"Renamed"];
        [plain updateWithSyncBody:@"remote source" andTitle:@"Remote title"];
        Check([[plain sourceSyntaxIdentifier] isEqualToString:@"json"], @"rename and sync content changes retain local syntax");
        SimplenoteEntryModifier *modifier = [[[SimplenoteEntryModifier alloc] initWithEntries:@[plain] operation:@selector(fetcherForCreatingNote:) simperiumToken:@"fixture"] autorelease];
        SyncResponseFetcher *fetcher = [modifier fetcherForCreatingNote:plain];
        NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:[fetcher valueForKey:@"dataToSend"] options:0 error:NULL];
        Check(payload && !payload[@"syntax"] && !payload[@"sourceMetadata"] && !payload[@"originalData"], @"Simplenote request has no local source metadata");

        NSData *noteArchive = [NSKeyedArchiver archivedDataWithRootObject:plain];
        NSData *prefsArchive = [NSKeyedArchiver archivedDataWithRootObject:[library notationPrefs]];
        NoteObject *restored = [NSKeyedUnarchiver unarchiveObjectWithData:noteArchive];
        NVSourcePrefsDelegate *owner = [[[NVSourcePrefsDelegate alloc] init] autorelease];
        owner->prefs = [NSKeyedUnarchiver unarchiveObjectWithData:prefsArchive];
        [restored setDelegate:owner];
        Check([[restored sourceSyntaxIdentifier] isEqualToString:@"json"], @"library archive restores syntax by the unchanged note UUID");
        owner->prefs = [[[NotationPrefs alloc] init] autorelease];
        Check([[restored sourceSyntaxIdentifier] isEqualToString:@"plain"], @"another library does not inherit source metadata");
        for (NSNumber *format in @[@(RTFTextFormat), @(HTMLFormat), @(WordDocFormat), @(WordXMLFormat)]) {
            [[library notationPrefs] setNotesStorageFormat:[format integerValue]];
            Check([[library notationPrefs] notesStorageFormat] == SingleDatabaseFormat, @"removed storage format cannot be selected");
            Check(![plain updateFromData:[NSMutableData data] inFormat:[format integerValue]], @"removed storage format cannot decode a document body");
            Check([plain exportToDirectoryRef:NULL withFilename:nil usingFormat:[format intValue] overwrite:NO] == kDataFormattingErr, @"removed document export fails before touching files");
        }
        NotationPrefs *legacyPrefs = [[[NotationPrefs alloc] init] autorelease];
        [legacyPrefs setValue:@(RTFTextFormat) forKey:@"notesStorageFormat"];
        NotationPrefs *decodedLegacy = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:legacyPrefs]];
        Check([decodedLegacy notesStorageFormat] == SingleDatabaseFormat, @"legacy rich-text file settings open archived characters without rewriting old files");

        NSMutableAttributedString *rich = [[[NSMutableAttributedString alloc] initWithString:@"source" attributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:24], NSUnderlineStyleAttributeName: @1}] autorelease];
        NoteObject *normalized = [[[NoteObject alloc] initWithNoteBody:rich title:@"Authored styles" delegate:nil format:SingleDatabaseFormat labels:@""] autorelease];
        Check([[normalized contentString] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] == nil && [[[normalized contentString] string] isEqualToString:@"source"], @"note model accepts characters without authored styles");
        [normalized setContentString:rich];
        Check([[normalized contentString] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] == nil, @"model updates discard authored rich-text attributes");
        [[normalized valueForKey:@"contentString"] addAttribute:NSUnderlineStyleAttributeName value:@1 range:NSMakeRange(0, 6)];
        NoteObject *decodedRich = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:normalized]];
        Check([[decodedRich contentString] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] == nil && [[[decodedRich contentString] string] isEqualToString:@"source"], @"archive decoding keeps legacy characters without authored formatting");

        NSString *legacyText = @"  café\r\n\t£10\n";
        NSData *legacyBytes = [legacyText dataUsingEncoding:NSWindowsCP1252StringEncoding];
        NSString *legacyPath = [TestDirectory stringByAppendingPathComponent:@"legacy.txt"];
        [legacyBytes writeToFile:legacyPath atomically:YES];
        [[NSFileManager defaultManager] setTextEncodingAttribute:NSWindowsCP1252StringEncoding atFSPath:[legacyPath fileSystemRepresentation]];
        NoteObject *legacy = [importer noteWithFile:legacyPath];
        [library addNewNote:legacy];
        Check([[[legacy contentString] string] isEqualToString:legacyText] && [[legacy sourceDataReturningError:NULL] isEqual:legacyBytes], @"recorded legacy encoding preserves original bytes");
        NSString *unrepresentable = [legacyText stringByAppendingString:@"😀"];
        [legacy setContentString:[[[NSAttributedString alloc] initWithString:unrepresentable] autorelease]];
        NSError *encodingError = nil;
        Check([legacy sourceDataReturningError:&encodingError] == nil && encodingError && fileEncodingOfNote(legacy) == NSWindowsCP1252StringEncoding, @"unrepresentable edits report an error without replacing characters or silently changing encoding");
        Check([[NSData dataWithContentsOfFile:legacyPath] isEqual:legacyBytes], @"encoding failure leaves the original file intact");
        Check([legacy upgradeEncodingToUTF8] && [[legacy sourceDataReturningError:NULL] isEqual:[unrepresentable dataUsingEncoding:NSUTF8StringEncoding]], @"explicit UTF-8 conversion preserves every source character");
        // Exercise the actual writer and export path against disposable directories.
        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        [library flushAllNoteChanges];
        NoteObject *stored = firstImported;
        NSString *storedPath = [stored noteFilePath];
        Check(storedPath && [[NSData dataWithContentsOfFile:storedPath] isEqual:[stored sourceDataReturningError:NULL]], @"plain-file storage writes the same source bytes as the source contract");
        FSRef exportDirectory;
        Check(FSPathMakeRef((const UInt8*)[TestDirectory fileSystemRepresentation], &exportDirectory, NULL) == noErr, @"temporary export directory resolves");
        Check([stored exportToDirectoryRef:&exportDirectory withFilename:@"exported-source.txt" usingFormat:PlainTextFormat overwrite:NO] == noErr, @"source export writes to the requested file");
        Check([[NSData dataWithContentsOfFile:[TestDirectory stringByAppendingPathComponent:@"exported-source.txt"]] isEqual:[stored sourceDataReturningError:NULL]], @"source export contains original characters and encoding bytes");
        NSDictionary *storedMetadata = [[[[library notationPrefs] valueForKey:@"sourceMetadataByNoteUUID"] copy] autorelease];
        NSData *actualArchive = [NSData dataWithContentsOfFile:[TestDirectory stringByAppendingPathComponent:@"Notes/Notes & Settings"]];
        FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:actualArchive];
        OSStatus archiveError = noErr;
        NSArray *reopenedNotes = [frozen unpackedNotesReturningError:&archiveError];
        Check(frozen && archiveError == noErr && [reopenedNotes count] == [[library allNotes] count], @"the on-disk library archive reopens its source notes");
        Check([[[frozen notationPrefs] valueForKey:@"sourceMetadataByNoteUUID"] isEqual:storedMetadata], @"the on-disk library archive preserves local syntax metadata");
        NVSourcePrefsDelegate *reopenedOwner = [[[NVSourcePrefsDelegate alloc] init] autorelease];
        reopenedOwner->prefs = [frozen notationPrefs];
        BOOL matchedSource = NO;
        for (NoteObject *candidate in reopenedNotes) {
            if (memcmp([candidate uniqueNoteIDBytes], [stored uniqueNoteIDBytes], sizeof(CFUUIDBytes)) == 0) {
                [candidate setDelegate:reopenedOwner];
                matchedSource = [[candidate sourceDataReturningError:NULL] isEqual:[stored sourceDataReturningError:NULL]] && [[candidate sourceSyntaxIdentifier] isEqualToString:@"markdown"];
            }
        }
        Check(matchedSource, @"reopened note restores encoding, BOM, original bytes, and syntax together");
        for (NSDictionary *metadata in [storedMetadata allValues]) Check([[metadata allKeys] isEqual:@[@"syntax"]], @"library preferences contain syntax only, with source bytes inside the note archive");
        NotationPrefs *encryptedPrefs = [[[NotationPrefs alloc] init] autorelease];
        [encryptedPrefs setPassphraseData:[@"disposable source fixture password" dataUsingEncoding:NSUTF8StringEncoding] inKeychain:NO];
        [encryptedPrefs setDoesEncryption:YES];
        NSData *encryptedArchive = [FrozenNotation frozenDataWithExistingNotes:[NSMutableArray arrayWithObject:stored] deletedNotes:[NSMutableSet set] prefs:encryptedPrefs];
        FrozenNotation *encryptedFrozen = [NSKeyedUnarchiver unarchiveObjectWithData:encryptedArchive];
        NSArray *decryptedNotes = [encryptedFrozen unpackedNotesWithPrefs:encryptedPrefs returningError:&archiveError];
        NoteObject *decrypted = [decryptedNotes firstObject];
        Check(encryptedArchive && [[encryptedFrozen notationPrefs] doesEncryption] && archiveError == noErr && [[decrypted sourceDataReturningError:NULL] isEqual:[stored sourceDataReturningError:NULL]], @"encrypted library archive restores exact source bytes after decryption");
        Check([[decrypted valueForKey:@"sourceOriginalData"] isEqual:[stored valueForKey:@"sourceOriginalData"]] && [[[encryptedFrozen notationPrefs] valueForKey:@"sourceMetadataByNoteUUID"] count] == 0, @"original imported bytes are part of encrypted note data and absent from public library settings");
        NoteObject *pending = [importer noteWithFile:legacyPath];
        [pending setTitleString:@"Pending conversion"];
        [library addNewNote:pending];
        [library flushAllNoteChanges];
        NSString *pendingPath = [[pending noteFilePath] copy];
        [pending setContentString:[[[NSAttributedString alloc] initWithString:unrepresentable] autorelease]];
        Check([library flushAllNoteChanges] && [pending sourceConversionPending] && SourceConversionOffers > 0, @"canceling conversion saves source and the pending conversion state to the library");
        Check([[NSData dataWithContentsOfFile:pendingPath] isEqual:legacyBytes], @"canceling conversion leaves the existing plain file unchanged");
        [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:5]} ofItemAtPath:pendingPath error:NULL];
        [library synchronizeNotesFromDirectory];
        Check([[[pending contentString] string] isEqualToString:unrepresentable], @"a file metadata event cannot replace source awaiting explicit conversion");
        [library flushAllNoteChanges]; [library closeJournal]; [library stopFileNotifications];
        NSString *reopenPath = [TestDirectory stringByAppendingPathComponent:@"Reopened Notes"];
        Check([[NSFileManager defaultManager] copyItemAtPath:[TestDirectory stringByAppendingPathComponent:@"Notes"] toPath:reopenPath error:NULL], @"saved conversion fixture copies into a separate library directory");
        FSRef reopenRef;
        Check(FSPathMakeRef((const UInt8*)[reopenPath fileSystemRepresentation], &reopenRef, NULL) == noErr, @"reopened library directory resolves");
        OSStatus reopenError = noErr;
        NSUInteger previousOffers = SourceConversionOffers;
        NotationController *reopenedLibrary = [[[NotationController alloc] initWithDirectoryRef:&reopenRef error:&reopenError] autorelease];
        NoteObject *reopenedPending = [reopenedLibrary noteForUUIDBytes:[pending uniqueNoteIDBytes]];
        Check(reopenedLibrary && reopenError == noErr && [reopenedPending sourceConversionPending] && [[[reopenedPending contentString] string] isEqualToString:unrepresentable], @"reopening restores the pending conversion and every edited source character");
        [reopenedLibrary synchronizeNoteChanges:nil];
        Check(SourceConversionOffers > previousOffers && fileEncodingOfNote(reopenedPending) == NSWindowsCP1252StringEncoding, @"reopening retries the conversion request without silently changing encoding");
        NSString *reopenedPendingPath = [[reopenedPending noteFilePath] copy];
        Check([[NSData dataWithContentsOfFile:reopenedPendingPath] isEqual:legacyBytes], @"reopen retry preserves the original plain-file bytes until conversion is accepted");
        Check([reopenedPending upgradeEncodingToUTF8] && ![reopenedPending sourceConversionPending], @"explicit conversion completes the pending source-file write");
        Check([[NSData dataWithContentsOfFile:reopenedPendingPath] isEqual:[unrepresentable dataUsingEncoding:NSUTF8StringEncoding]], @"accepted conversion writes all preserved source characters as UTF-8");
        [reopenedLibrary flushAllNoteChanges];
        FrozenNotation *completedFrozen = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithContentsOfFile:[reopenPath stringByAppendingPathComponent:@"Notes & Settings"]]];
        BOOL clearedInArchive = NO;
        for (NoteObject *candidate in [completedFrozen unpackedNotesReturningError:&reopenError]) {
            if (memcmp([candidate uniqueNoteIDBytes], [pending uniqueNoteIDBytes], sizeof(CFUUIDBytes)) == 0) clearedInArchive = ![candidate sourceConversionPending];
        }
        Check(clearedInArchive, @"successful conversion clears its persisted retry state");
        [reopenedLibrary closeJournal]; [reopenedLibrary stopFileNotifications];
        [pendingPath release]; [reopenedPendingPath release];
        NSLog(@"SOURCE STORAGE CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
