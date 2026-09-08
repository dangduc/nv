    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        [library stopFileNotifications];
        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NSString *seed = @"seed café\r\n";
        NSString *local = @"seed café\r\nlocal 😀\r\n";
        NSData *seedBytes = [seed dataUsingEncoding:NSWindowsCP1252StringEncoding];
        ReviewParentWindow = [self window];
        Swap([NSApplication class], @selector(mainWindow), @selector(nv_reviewMainWindow));
        Swap([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:), @selector(nv_captureSheet:completionHandler:));
        NSString *fixture = [TestDirectory stringByAppendingPathComponent:@"delete-pending.txt"];
        Check([seedBytes writeToFile:fixture atomically:YES], @"write isolated deletion fixture");
        [[NSFileManager defaultManager] setTextEncodingAttribute:NSWindowsCP1252StringEncoding atFSPath:[fixture fileSystemRepresentation]];
        NoteObject *note = [[importer noteWithFile:fixture] retain];
        [library addNewNote:note];
        Check([library flushAllNoteChanges], @"persist original source");
        NSString *path = [[note noteFilePath] copy];
        [note setContentString:[[[NSAttributedString alloc] initWithString:local] autorelease]];
        Check([library flushAllNoteChanges] && [note sourceConversionPending], @"unrepresentable edit schedules production conversion offer");
        Pump();
        Check(CapturedConversion != nil && ConversionSheets == 1, @"capture production conversion completion while modeling an open sheet");
        [library removeNote:note];
        Check(![[library allNotes] containsObject:note] && ![[NSFileManager defaultManager] fileExistsAtPath:path], @"delete through library removes note and its source file");
        CapturedConversion(NSAlertFirstButtonReturn);
        [CapturedConversion release]; CapturedConversion = nil;
        BOOL recreated = [[NSFileManager defaultManager] fileExistsAtPath:path];
        NSLog(@"HISTORY delete-pending: member=%d recreated=%d source=%@", [[library allNotes] containsObject:note], recreated, [[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:path] encoding:NSUTF8StringEncoding] autorelease]);
        Check(recreated && ![[library allNotes] containsObject:note], @"REPRO: stale conversion completion recreates a deleted source file");
        [library synchronizeNotesFromDirectory];
        BOOL resurrected = NO;
        for (NoteObject *candidate in [library allNotes]) if ([[[candidate contentString] string] isEqualToString:local]) resurrected = YES;
        Check(resurrected, @"REPRO: directory reconciliation resurrects deleted source as a note");
        [path release]; [note release];
        fixture = [TestDirectory stringByAppendingPathComponent:@"replace-pending.txt"];
        Check([seedBytes writeToFile:fixture atomically:YES], @"write isolated replacement fixture");
        [[NSFileManager defaultManager] setTextEncodingAttribute:NSWindowsCP1252StringEncoding atFSPath:[fixture fileSystemRepresentation]];
        note = [[importer noteWithFile:fixture] retain];
        [library addNewNote:note]; [library flushAllNoteChanges];
        path = [[note noteFilePath] copy];
        [note setContentString:[[[NSAttributedString alloc] initWithString:local] autorelease]];
        Check([library flushAllNoteChanges] && [note sourceConversionPending], @"replacement history schedules conversion");
        Pump();
        Check(CapturedConversion != nil, @"replacement history captures conversion completion");
        [library removeNote:note];
        NSString *replacementSource = @"new replacement body that must survive\r\n";
        NoteObject *replacement = MakeNote(library, @"replace-pending", replacementSource);
        Check([library flushAllNoteChanges] && [[replacement noteFilePath] isEqualToString:path], @"new note reuses the deleted note's available source filename");
        Check([[NSData dataWithContentsOfFile:path] isEqual:[replacementSource dataUsingEncoding:NSUTF8StringEncoding]], @"replacement source is durably written before stale conversion completion");
        CapturedConversion(NSAlertFirstButtonReturn);
        [CapturedConversion release]; CapturedConversion = nil;
        BOOL replacementOnDisk = [[NSData dataWithContentsOfFile:path] isEqual:[replacementSource dataUsingEncoding:NSUTF8StringEncoding]];
        NSLog(@"HISTORY replace-pending: replacementOnDisk=%d source=%@", replacementOnDisk, [[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:path] encoding:NSUTF8StringEncoding] autorelease]);
        for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[library notesDirectoryURL] path] error:NULL]) {
            if ([entry hasPrefix:@"replace-pending"]) NSLog(@"REPLACEMENT FILE %@: %@", entry, [NSString stringWithContentsOfFile:[[[library notesDirectoryURL] path] stringByAppendingPathComponent:entry] encoding:NSUTF8StringEncoding error:NULL]);
        }
        [library synchronizeNotesFromDirectory];
        NSLog(@"REPLACEMENT MODEL: %@ file=%@", [[replacement contentString] string], [replacement noteFilePath]);
        Check(!replacementOnDisk, @"REPRO: stale conversion changes the source file of a different acknowledged note");
        [path release]; [note release];
        Swap([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:), @selector(nv_captureSheet:completionHandler:));

        Swap([EncodingsManager class], @selector(offerUTF8ConversionForNote:), @selector(nv_ignoreConversion:));
        Swap([WALStorageController class], @selector(synchronize), @selector(nv_failSelectedSync));
        fixture = [TestDirectory stringByAppendingPathComponent:@"failed-conflict-sync.txt"];
        Check([seedBytes writeToFile:fixture atomically:YES], @"write isolated conflict fixture");
        [[NSFileManager defaultManager] setTextEncodingAttribute:NSWindowsCP1252StringEncoding atFSPath:[fixture fileSystemRepresentation]];
        note = [importer noteWithFile:fixture];
        [library addNewNote:note];
        Check([library flushAllNoteChanges], @"persist conflict seed");
        path = [[note noteFilePath] copy];
        [note setContentString:[[[NSAttributedString alloc] initWithString:local] autorelease]];
        Check([library flushAllNoteChanges] && [note sourceConversionPending], @"persist conflict local source pending conversion");
        NSString *external = @"external version one\r\n";
        NSData *externalBytes = [external dataUsingEncoding:NSWindowsCP1252StringEncoding];
        Check([externalBytes writeToFile:path atomically:NO], @"external writer completes first version");
        NSUInteger countBefore = [[library allNotes] count];
        FailConflictSync = YES;
        for (NSUInteger i = 0; i < 3; i++) {
            Check(![note upgradeEncodingToUTF8], @"failed conflict synchronization blocks original source replacement");
            Check([[NSData dataWithContentsOfFile:path] isEqual:externalBytes] && [note sourceConversionPending], @"failed synchronization retains disk external source and pending local source");
        }
        NSUInteger copiesAfterFailure = [[library allNotes] count] - countBefore;
        NSLog(@"HISTORY conflict-retry: failedSyncs=%lu duplicateCopies=%lu", (unsigned long)FailedSyncs, (unsigned long)copiesAfterFailure);
        Check(copiesAfterFailure == 3, @"REPRO: each failed synchronization creates another copy of the same external version");
        FailConflictSync = NO;
        Check([note upgradeEncodingToUTF8] && ![note sourceConversionPending], @"successful retry completes pending conversion");
        NSUInteger firstVersionCopies = 0;
        for (NoteObject *candidate in [library allNotes]) if ([[[candidate contentString] string] isEqualToString:external]) firstVersionCopies++;
        Check(firstVersionCopies == 4, @"REPRO: successful retry leaves four identical conflict notes from one external version");
        Check([[NSData dataWithContentsOfFile:path] isEqual:[local dataUsingEncoding:NSUTF8StringEncoding]], @"successful conversion retains exact local source");
        Check([library flushAllNoteChanges], @"flush all surviving versions");
        FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithContentsOfFile:[TestDirectory stringByAppendingPathComponent:@"Notes/Notes & Settings"]]];
        OSStatus error = noErr; NSUInteger archivedCopies = 0;
        for (NoteObject *candidate in [frozen unpackedNotesReturningError:&error]) if ([[[candidate contentString] string] isEqualToString:external]) archivedCopies++;
        Check(error == noErr && archivedCopies == 4, @"reopening archive retains all four duplicate conflict records");
        NSLog(@"KINGSBURY ROUND 2 PROBE COMPLETED: %lu checks", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
