
    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        EncodingsManager *manager = [EncodingsManager sharedManager];
        Swap([EncodingsManager class], @selector(offerUTF8ConversionForNote:), @selector(nv_reviewDeclineConversion:));
        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NSString *seed = @"seed café\r\n";
        NSString *local = @"seed café\r\nlocal 😀\r\n";
        NSString *external = @"external durable update\r\n";
        for (NSString *history in @[@"external-update", @"reinterpret"]) {
            NSString *fixture = [TestDirectory stringByAppendingPathComponent:[history stringByAppendingString:@".txt"]];
            NSData *seedBytes = [seed dataUsingEncoding:NSWindowsCP1252StringEncoding];
            Check([seedBytes writeToFile:fixture atomically:YES], @"write original CP-1252 fixture");
            [[NSFileManager defaultManager] setTextEncodingAttribute:NSWindowsCP1252StringEncoding atFSPath:[fixture fileSystemRepresentation]];
            NoteObject *note = [importer noteWithFile:fixture];
            [library addNewNote:note];
            Check([library flushAllNoteChanges], @"persist imported source");
            NSString *path = [[note noteFilePath] copy];
            Check([[NSData dataWithContentsOfFile:path] isEqual:seedBytes], @"file starts with exact imported source bytes");
            [note setContentString:[[[NSAttributedString alloc] initWithString:local] autorelease]];
            Check([library flushAllNoteChanges] && [note sourceConversionPending], @"local edit durably enters canceled conversion state");
            Check([[NSData dataWithContentsOfFile:path] isEqual:seedBytes], @"cancel leaves old file intact");
            if ([history isEqualToString:@"external-update"]) {
                Check([external writeToFile:path atomically:NO encoding:NSWindowsCP1252StringEncoding error:NULL], @"external editor completes a distinct source write");
                [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:10]} ofItemAtPath:path error:NULL];
                [library synchronizeNotesFromDirectory];
                Check([[[note contentString] string] isEqualToString:local], @"pending local edit survives external reconciliation");
                Check([[NSData dataWithContentsOfFile:path] isEqual:[external dataUsingEncoding:NSWindowsCP1252StringEncoding]], @"external writer's acknowledged source is still on disk before conversion");
                Check([note upgradeEncodingToUTF8] && [library flushAllNoteChanges], @"later explicit conversion and flush succeed");
                BOOL conflictPreserved = NO;
                for (NoteObject *candidate in [library allNotes]) if ([[[candidate contentString] string] containsString:@"external durable update"]) conflictPreserved = YES;
                BOOL externalOnDisk = [[NSData dataWithContentsOfFile:path] isEqual:[external dataUsingEncoding:NSWindowsCP1252StringEncoding]];
                NSLog(@"HISTORY external-update: pending=%d local=%@ externalOnDisk=%d conflictPreserved=%d noteCount=%lu", [note sourceConversionPending], [[note contentString] string], externalOnDisk, conflictPreserved, (unsigned long)[[library allNotes] count]);
                Check(!externalOnDisk && !conflictPreserved, @"REPRO: conversion overwrites the external update without preserving a conflict note");
            } else {
                // Establish the state set by showPanelForNote: without displaying its sheet.
                [manager setValue:note forKey:@"note"];
                FSRef ref; Check(FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], &ref, NULL) == noErr, @"resolve source file for encoding sheet predicate");
                Ivar fsrefIvar = class_getInstanceVariable([EncodingsManager class], "fsRef");
                memcpy((char *)(void *)manager + ivar_getOffset(fsrefIvar), &ref, sizeof(ref));
                BOOL permitsReinterpretation = [manager shouldUpdateNoteFromDisk];
                Check(permitsReinterpretation, @"encoding sheet permits reinterpretation without its overwrite warning");
                Check([note setFileEncodingAndReinterpret:NSMacOSRomanStringEncoding], @"encoding sheet's production reinterpretation operation succeeds");
                Check([library flushAllNoteChanges], @"flush reinterpreted body to archive");
                BOOL localSurvives = [[[note contentString] string] containsString:@"local 😀"];
                NSData *archive = [NSData dataWithContentsOfFile:[TestDirectory stringByAppendingPathComponent:@"Notes/Notes & Settings"]];
                FrozenNotation *frozen = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
                OSStatus err = noErr; BOOL archivedLocal = NO;
                for (NoteObject *candidate in [frozen unpackedNotesReturningError:&err]) {
                    if (memcmp([candidate uniqueNoteIDBytes], [note uniqueNoteIDBytes], sizeof(CFUUIDBytes)) == 0) archivedLocal = [[[candidate contentString] string] containsString:@"local 😀"];
                }
                NSLog(@"HISTORY reinterpret: permits=%d pending=%d liveLocal=%d archivedLocal=%d source=%@", permitsReinterpretation, [note sourceConversionPending], localSurvives, archivedLocal, [[note contentString] string]);
                Check(!localSurvives && !archivedLocal, @"REPRO: changing encoding discards pending source from live model and durable archive");
            }
            [path release];
        }
        NSLog(@"KINGSBURY ROUND 1 PROBE COMPLETED: %lu checks; %lu canceled conversion offers", (unsigned long)Checks, (unsigned long)ConversionOffers);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
