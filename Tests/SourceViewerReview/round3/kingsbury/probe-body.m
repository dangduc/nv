    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        [library stopFileNotifications];
        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        Swap([EncodingsManager class], @selector(offerUTF8ConversionForNote:), @selector(nv_round3IgnoreConversion:));
        Swap([WALStorageController class], @selector(synchronize), @selector(nv_round3Synchronize));
        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NSData *seed = [@"seed café\r\n" dataUsingEncoding:NSWindowsCP1252StringEncoding];
        NSString *local = @"local edited café 😀\r\n";
        NSString *external = @"identical external café\r\n";
        NSData *externalBytes = [external dataUsingEncoding:NSWindowsCP1252StringEncoding];
        NSString *edited = @"independent edit to the conflict café\r\n";
        NSData *editedBytes = [edited dataUsingEncoding:NSWindowsCP1252StringEncoding];
        NSUInteger (^bodyCount)(NotationController *, NSString *) = ^NSUInteger(NotationController *owner, NSString *body) {
            NSUInteger count = 0;
            for (NoteObject *candidate in [owner allNotes]) if ([[[candidate contentString] string] isEqualToString:body]) count++;
            return count;
        };
        NoteObject *(^matchingCopy)(NotationController *, NoteObject *) = ^NoteObject *(NotationController *owner, NoteObject *origin) {
            for (NoteObject *candidate in [owner allNotes]) if ([candidate isSourceConflictCopyOfNote:origin data:externalBytes encoding:NSWindowsCP1252StringEncoding] && [[NSData dataWithContentsOfFile:[candidate noteFilePath]] isEqual:externalBytes]) return candidate;
            return nil;
        };
        NoteObject *(^pendingNote)(NSString *) = ^NoteObject *(NSString *title) {
            NSString *fixture = [TestDirectory stringByAppendingPathComponent:[title stringByAppendingPathExtension:@"txt"]];
            Check([seed writeToFile:fixture atomically:YES], @"write isolated CP-1252 seed");
            [[NSFileManager defaultManager] setTextEncodingAttribute:NSWindowsCP1252StringEncoding atFSPath:[fixture fileSystemRepresentation]];
            NoteObject *note = [importer noteWithFile:fixture];
            [library addNewNote:note];
            Check([library flushAllNoteChanges], @"persist initial source");
            [note setContentString:[[[NSAttributedString alloc] initWithString:local] autorelease]];
            Check([library flushAllNoteChanges] && [note sourceConversionPending], @"persist pending unrepresentable local edit");
            Check([externalBytes writeToFile:[note noteFilePath] atomically:NO], @"external writer completes source version before conversion");
            return note;
        };
        for (NSString *history in @[@"model-edited-copy", @"disk-edited-copy", @"deleted-copy-file", @"removed-copy-note"]) {
            NoteObject *origin = pendingNote(history);
            NSString *originPath = [[origin noteFilePath] copy];
            NSUInteger initialExternalCount = bodyCount(library, external);
            FailReviewSynchronization = YES;
            NSUInteger failuresBefore = ReviewFailedSynchronizations;
            Check(![origin upgradeEncodingToUTF8], @"injected WAL synchronization failure blocks first source conversion");
            Check(ReviewFailedSynchronizations == failuresBefore + 1, @"first failure occurs at the production synchronization boundary");
            NoteObject *copy = [matchingCopy(library, origin) retain];
            Check(copy != nil && bodyCount(library, external) == initialExternalCount + 1, @"failed synchronization leaves one copy for this origin and external version");
            NSString *copyPath = [[copy noteFilePath] copy];
            CFUUIDBytes copyUUID = *[copy uniqueNoteIDBytes];
            if ([history isEqualToString:@"model-edited-copy"]) {
                [copy setContentString:[[[NSAttributedString alloc] initWithString:edited] autorelease]];
                Check(![copy isSourceConflictCopyOfNote:origin data:externalBytes encoding:NSWindowsCP1252StringEncoding], @"independent model edit excludes old copy from retry reuse");
            } else if ([history isEqualToString:@"disk-edited-copy"]) {
                Check([editedBytes writeToFile:copyPath atomically:NO], @"external writer modifies conflict file before reconciliation");
            } else if ([history isEqualToString:@"deleted-copy-file"]) {
                Check([[NSFileManager defaultManager] removeItemAtPath:copyPath error:NULL], @"remove conflict file while its note remains in the library");
            } else {
                [library removeNote:copy];
                Check([library noteForUUIDBytes:&copyUUID] == nil, @"remove conflict note through the production library operation");
            }
            Check(![origin upgradeEncodingToUTF8], @"second synchronization failure still blocks original replacement");
            Check([[NSData dataWithContentsOfFile:originPath] isEqual:externalBytes] && [origin sourceConversionPending], @"failed retry retains both pending local source and external original file");
            NoteObject *retryCopy = matchingCopy(library, origin);
            Check(retryCopy != nil, @"retry retains a copy matching the current origin and exact external bytes");
            if ([history isEqualToString:@"deleted-copy-file"]) {
                Check(retryCopy == copy && [[NSData dataWithContentsOfFile:copyPath] isEqual:externalBytes], @"retry recreates the missing copy file under the existing copy UUID");
            } else {
                Check(retryCopy != copy, @"edited or removed copy is replaced by a separate conflict note");
            }
            if ([history isEqualToString:@"disk-edited-copy"]) {
                Check([[NSData dataWithContentsOfFile:copyPath] isEqual:editedBytes], @"retry does not overwrite an externally modified conflict file");
            }
            FailReviewSynchronization = NO;
            Check([origin upgradeEncodingToUTF8] && ![origin sourceConversionPending], @"recovered synchronization allows original conversion");
            Check([[NSData dataWithContentsOfFile:originPath] isEqual:[local dataUsingEncoding:NSUTF8StringEncoding]], @"successful conversion writes exact pending local source");
            [library synchronizeNotesFromDirectory];
            Check([library flushAllNoteChanges], @"reconcile and persist all source versions after recovered synchronization");
            if ([history isEqualToString:@"model-edited-copy"] || [history isEqualToString:@"disk-edited-copy"]) {
                if ([history isEqualToString:@"disk-edited-copy"]) {
                    NSLog(@"AFTER FLUSH diskEditedRetained=%d modelEdited=%d", [[NSData dataWithContentsOfFile:[copy noteFilePath]] isEqual:editedBytes], [[[copy contentString] string] isEqualToString:edited]);
                    Check([[NSData dataWithContentsOfFile:[copy noteFilePath]] isEqual:editedBytes], @"initial queue drain retains externally edited conflict bytes even before model refresh");
                    [library synchronizeNotesFromDirectory];
                    Check([library flushAllNoteChanges], @"a second reconciliation observes conflict-file edits after the pending write queue drains");
                }
                Check([[[copy contentString] string] isEqualToString:edited], @"independently edited conflict characters survive retry and reconciliation");
                Check([[NSData dataWithContentsOfFile:[copy noteFilePath]] isEqual:editedBytes], @"independently edited conflict bytes survive the final flush");
            }
            Check([matchingCopy(library, origin) isSourceConflictCopyOfNote:origin data:externalBytes encoding:NSWindowsCP1252StringEncoding], @"final library retains the exact external version for this origin");
            NSLog(@"HISTORY %@ completed", history);
            [copyPath release]; [originPath release]; [copy release];
        }
        NoteObject *first = pendingNote(@"distinct-origin-one");
        NoteObject *second = pendingNote(@"distinct-origin-two");
        FailReviewSynchronization = YES;
        Check(![first upgradeEncodingToUTF8] && ![second upgradeEncodingToUTF8], @"two distinct origins each stop at failed synchronization");
        NoteObject *firstCopy = matchingCopy(library, first), *secondCopy = matchingCopy(library, second);
        Check(firstCopy && secondCopy && firstCopy != secondCopy, @"identical external bytes from distinct origin UUIDs get distinct copies");
        Check(![firstCopy isSourceConflictCopyOfNote:second data:externalBytes encoding:NSWindowsCP1252StringEncoding] && ![secondCopy isSourceConflictCopyOfNote:first data:externalBytes encoding:NSWindowsCP1252StringEncoding], @"conflict provenance cannot authorize cross-origin reuse");
        CFUUIDBytes firstID = *[first uniqueNoteIDBytes], secondID = *[second uniqueNoteIDBytes];
        CFUUIDBytes firstCopyID = *[firstCopy uniqueNoteIDBytes], secondCopyID = *[secondCopy uniqueNoteIDBytes];
        NSUInteger expectedCount = [[library allNotes] count];
        for (NSUInteger cycle = 0; cycle < 3; cycle++) {
            Check([library flushAllNoteChanges], @"archive pending origins and conflict copies while synchronization reports failure");
            [library closeJournal]; [library stopFileNotifications];
            NSString *reopenPath = [TestDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"Reopen %lu", (unsigned long)cycle]];
            Check([[NSFileManager defaultManager] copyItemAtPath:[[library notesDirectoryURL] path] toPath:reopenPath error:NULL], @"copy persisted archive and notes into isolated recovery directory");
            FSRef reopenRef; OSStatus reopenError = noErr;
            Check(FSPathMakeRef((const UInt8 *)[reopenPath fileSystemRepresentation], &reopenRef, NULL) == noErr, @"resolve recovery directory");
            library = [[[NotationController alloc] initWithDirectoryRef:&reopenRef error:&reopenError] autorelease];
            Check(library && reopenError == noErr, @"production library initialization reopens persisted archive");
            [library stopFileNotifications];
            first = [library noteForUUIDBytes:&firstID]; second = [library noteForUUIDBytes:&secondID];
            Check(first && second && [first sourceConversionPending] && [second sourceConversionPending], @"reopen retains both pending source identities");
            Check(![first upgradeEncodingToUTF8] && ![second upgradeEncodingToUTF8], @"recovered origins still stop before replacing originals while synchronization fails");
            firstCopy = matchingCopy(library, first); secondCopy = matchingCopy(library, second);
            Check(firstCopy == [library noteForUUIDBytes:&firstCopyID] && secondCopy == [library noteForUUIDBytes:&secondCopyID], @"repeated recovery and retry preserve each conflict-copy UUID");
            Check([[library allNotes] count] == expectedCount, @"repeated archive recovery adds no duplicate conflict copies");
        }
        FailReviewSynchronization = NO;
        Check([first upgradeEncodingToUTF8] && [second upgradeEncodingToUTF8], @"both recovered origins complete after synchronization recovers");
        Check([library flushAllNoteChanges] && [[library allNotes] count] == expectedCount, @"completed history persists without cross-origin reuse or duplicate copies");
        [library closeJournal]; [library stopFileNotifications];
        NSLog(@"KINGSBURY ROUND 3 PASSED: %lu checks, %lu injected synchronization failures", (unsigned long)Checks, (unsigned long)ReviewFailedSynchronizations);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
