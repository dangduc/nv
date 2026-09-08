        // Complete the real sheet callbacks after other-window note lifetime changes.
        Swap([EncodingsManager class], @selector(offerUTF8ConversionForNote:), @selector(nv_cancelConversionForNote:));
        SourceConversionParent = [self window];
        Swap([NSApplication class], @selector(mainWindow), @selector(nv_sourceConversionMainWindow));
        Swap([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:), @selector(nv_captureSourceConversionSheet:completionHandler:));
        for (NSString *history in @[@"before-sheet", @"open-sheet", @"replacement", @"delete-undo"]) {
            NoteObject *offered = [[importer noteWithFile:legacyPath] retain];
            NSString *title = [@"Conversion lifetime " stringByAppendingString:history];
            [offered setTitleString:title];
            [library addNewNote:offered];
            Check([library flushAllNoteChanges], @"conversion lifetime fixture writes its initial source");
            NSString *path = [[offered noteFilePath] copy];
            [offered setContentString:[[[NSAttributedString alloc] initWithString:unrepresentable] autorelease]];
            NSUInteger sheetsBefore = SourceConversionSheets;
            Check([library flushAllNoteChanges] && [offered sourceConversionPending], @"production writer schedules the live imported note's conversion offer");
            if ([history isEqualToString:@"before-sheet"]) {
                [library removeNote:offered];
                Pump();
                [[EncodingsManager sharedManager] offerUTF8ConversionForNote:offered];
                Pump();
                Check(SourceConversionSheets == sheetsBefore && ![[NSFileManager defaultManager] fileExistsAtPath:path], @"deletion cancels queued presentation and rejects new offers for the removed note");
            } else {
                Pump();
                Check(SourceCapturedConversion != nil && SourceConversionSheets == sheetsBefore + 1, @"production conversion request reaches sheet presentation");
                void (^obsoleteCompletion)(NSModalResponse) = [SourceCapturedConversion copy];
                [SourceCapturedConversion release]; SourceCapturedConversion = nil;
                [library removeNote:offered];
                if ([history isEqualToString:@"replacement"]) {
                    NSString *replacementBody = @"replacement note keeps this acknowledged source\r\n";
                    NoteObject *replacement = MakeNote(library, title, replacementBody);
                    Check([library flushAllNoteChanges] && [[replacement noteFilePath] isEqualToString:path], @"replacement note durably reuses the deleted source filename");
                    NSUInteger noteCount = [[library allNotes] count];
                    obsoleteCompletion(NSAlertFirstButtonReturn);
                    [library synchronizeNotesFromDirectory];
                    Check([[replacement noteFilePath] isEqualToString:path] && [[NSData dataWithContentsOfFile:path] isEqual:[replacementBody dataUsingEncoding:NSUTF8StringEncoding]] && [[library allNotes] count] == noteCount, @"obsolete acceptance cannot rename or replace another note's file or create conflict notes");
                } else if ([history isEqualToString:@"delete-undo"]) {
                    // addNewNote: is the registered deletion Undo operation.
                    [library addNewNote:offered];
                    Pump();
                    Check(SourceCapturedConversion != nil && SourceConversionSheets == sheetsBefore + 2, @"restoring the same note creates an independent conversion request");
                    obsoleteCompletion(NSAlertFirstButtonReturn);
                    Check([offered sourceConversionPending] && fileEncodingOfNote(offered) == NSWindowsCP1252StringEncoding, @"old completion cannot authorize the restored note or cancel its new request");
                    SourceCapturedConversion(NSAlertFirstButtonReturn);
                    [SourceCapturedConversion release]; SourceCapturedConversion = nil;
                    Check(![offered sourceConversionPending] && [[NSData dataWithContentsOfFile:[offered noteFilePath]] isEqual:[unrepresentable dataUsingEncoding:NSUTF8StringEncoding]], @"current completion still converts the restored live note successfully");
                } else {
                    obsoleteCompletion(NSAlertFirstButtonReturn);
                    [library synchronizeNotesFromDirectory];
                    Check([library noteForUUIDBytes:[offered uniqueNoteIDBytes]] == nil && ![[NSFileManager defaultManager] fileExistsAtPath:path], @"accepting an old sheet cannot recreate a deleted source file");
                }
                [obsoleteCompletion release];
            }
            [path release]; [offered release];
        }
        Swap([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:), @selector(nv_captureSourceConversionSheet:completionHandler:));
        Swap([NSApplication class], @selector(mainWindow), @selector(nv_sourceConversionMainWindow));
        SourceConversionParent = nil;
        Swap([EncodingsManager class], @selector(offerUTF8ConversionForNote:), @selector(nv_cancelConversionForNote:));

        NoteObject *retrying = [importer noteWithFile:legacyPath];
        [retrying setTitleString:@"Conflict synchronization retries"];
        [library addNewNote:retrying];
        [library flushAllNoteChanges];
        NSString *retryPath = [[retrying noteFilePath] copy];
        [retrying setContentString:[[[NSAttributedString alloc] initWithString:unrepresentable] autorelease]];
        Check([library flushAllNoteChanges] && [retrying sourceConversionPending], @"retry history persists pending local conversion");
        NSString *firstVersion = @"external retry version one café\r\n";
        NSString *secondVersion = @"external retry version two £\r\n";
        NSData *firstBytes = [firstVersion dataUsingEncoding:NSWindowsCP1252StringEncoding];
        NSMutableData *secondBytes = [NSMutableData dataWithData:boms[1]];
        [secondBytes appendData:[secondVersion dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
        Check([firstBytes writeToFile:retryPath atomically:NO], @"external writer completes the first retry version");
        ProtectedSourceFilename = filenameOfNote(retrying); ExpectedExternalSource = firstVersion;
        ConflictJournalSynchronized = NO; ProtectedSourceWrites = 0;
        FailSourceConflictSync = YES;
        NSUInteger failuresBefore = FailedSourceConflictSyncs;
        for (NSUInteger attempt = 0; attempt < 3; attempt++) {
            Check(![retrying upgradeEncodingToUTF8] && [retrying sourceConversionPending], @"failed conflict synchronization keeps conversion pending");
            Check(SourceNotesWithBody(library, firstVersion) == 1 && [[NSData dataWithContentsOfFile:retryPath] isEqual:firstBytes], @"repeated synchronization failure reuses one conflict copy and retains original external bytes");
        }
        Check(FailedSourceConflictSyncs == failuresBefore + 3 && ProtectedSourceWrites == 0, @"each retry reaches synchronization without replacing the original source");
        Check([secondBytes writeToFile:retryPath atomically:NO], @"external writer completes a distinct second version during failed retries");
        ExpectedExternalSource = secondVersion;
        Check(![retrying upgradeEncodingToUTF8] && SourceNotesWithBody(library, firstVersion) == 1 && SourceNotesWithBody(library, secondVersion) == 1, @"a distinct external version gets its own copy while prior versions remain");
        for (NoteObject *candidate in [library allNotes]) {
            if (![[[candidate contentString] string] isEqualToString:secondVersion]) continue;
            NoteObject *decodedConflict = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:candidate]];
            Check([decodedConflict isSourceConflictCopyOfNote:retrying data:secondBytes encoding:NSUTF16LittleEndianStringEncoding], @"conflict provenance and encoding identity survive archive decoding before directory reconciliation");
        }
        Check([library flushAllNoteChanges] && [retrying sourceConversionPending], @"archive stores pending conversion and retained conflict identities despite synchronization failure");
        ProtectedSourceFilename = nil; ExpectedExternalSource = nil;
        NSString *retryReopenPath = [TestDirectory stringByAppendingPathComponent:@"Retry Reopened Notes"];
        [library stopFileNotifications];
        Check([[NSFileManager defaultManager] copyItemAtPath:[TestDirectory stringByAppendingPathComponent:@"Notes"] toPath:retryReopenPath error:NULL], @"copy the failed-retry archive and source files to an isolated reopen directory");
        FSRef retryReopenRef; OSStatus retryReopenError = noErr;
        Check(FSPathMakeRef((const UInt8 *)[retryReopenPath fileSystemRepresentation], &retryReopenRef, NULL) == noErr, @"retry reopen directory resolves");
        NotationController *retryReopenedLibrary = [[[NotationController alloc] initWithDirectoryRef:&retryReopenRef error:&retryReopenError] autorelease];
        NoteObject *retryReopened = [retryReopenedLibrary noteForUUIDBytes:[retrying uniqueNoteIDBytes]];
        Check(retryReopenedLibrary && retryReopenError == noErr && [retryReopened sourceConversionPending], @"reopen restores the pending conversion after failed conflict persistence");
        [retryReopenedLibrary synchronizeNoteChanges:nil];
        Check(SourceNotesWithBody(retryReopenedLibrary, firstVersion) == 1 && SourceNotesWithBody(retryReopenedLibrary, secondVersion) == 1, @"reopen retry reuses the archived conflict identity for each external version");
        FailSourceConflictSync = NO;
        ProtectedSourceFilename = filenameOfNote(retryReopened); ExpectedExternalSource = secondVersion;
        ConflictJournalSynchronized = NO; ProtectedSourceWrites = 0;
        Check([retryReopened upgradeEncodingToUTF8] && ![retryReopened sourceConversionPending] && ProtectedSourceWrites == 1, @"successful retry synchronizes the reused conflict record before replacing original source");
        Check(SourceNotesWithBody(retryReopenedLibrary, firstVersion) == 1 && SourceNotesWithBody(retryReopenedLibrary, secondVersion) == 1 && [[NSData dataWithContentsOfFile:[retryReopened noteFilePath]] isEqual:[unrepresentable dataUsingEncoding:NSUTF8StringEncoding]], @"successful retry preserves two distinct external versions and every local source character");
        ProtectedSourceFilename = nil; ExpectedExternalSource = nil;
        Check([retryReopenedLibrary flushAllNoteChanges], @"flush successfully completed retry history");
        [retryReopenedLibrary closeJournal]; [retryReopenedLibrary stopFileNotifications];
        // Finish the original fixture too, so later reopen checks do not retry it.
        Check([retrying upgradeEncodingToUTF8] && SourceNotesWithBody(library, firstVersion) == 1 && SourceNotesWithBody(library, secondVersion) == 1, @"the original library also completes without duplicate conflict copies");
        [retryPath release];
