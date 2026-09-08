    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NotationController *library = [[NVApplicationController sharedController] library];
        NSString *text = @" \t“café” £ € –\r\nline\rfinal\n\n";
        NSString *edited = [text stringByAppendingString:@" plus\r\n"];
        NSArray *encodings = @[@(NSWindowsCP1252StringEncoding), @(NSMacOSRomanStringEncoding), @(NSUTF8StringEncoding), @(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding), @(NSUTF32LittleEndianStringEncoding), @(NSUTF32BigEndianStringEncoding)];
        const unsigned char utf8[] = {0xEF, 0xBB, 0xBF}, utf16le[] = {0xFF, 0xFE}, utf16be[] = {0xFE, 0xFF}, utf32le[] = {0xFF, 0xFE, 0, 0}, utf32be[] = {0, 0, 0xFE, 0xFF};
        NSArray *boms = @[[NSData data], [NSData data], [NSData dataWithBytes:utf8 length:3], [NSData dataWithBytes:utf16le length:2], [NSData dataWithBytes:utf16be length:2], [NSData dataWithBytes:utf32le length:4], [NSData dataWithBytes:utf32be length:4]];
        NSUInteger archiveEncodingChanges = 0, archiveByteFailures = 0;
        for (NSUInteger index = 0; index < [encodings count]; index++) {
            NSStringEncoding encoding = [encodings[index] unsignedIntegerValue];
            NSData *bytes = SourceBytes(text, encoding, boms[index]);
            NSString *path = [TestDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"tagged-%lu.json", (unsigned long)index]];
            Check([bytes writeToFile:path atomically:YES], @"tagged neighboring-encoding fixture writes");
            [[NSFileManager defaultManager] setTextEncodingAttribute:encoding atFSPath:[path fileSystemRepresentation]];
            Check([[NSFileManager defaultManager] textEncodingAttributeOfFSPath:[path fileSystemRepresentation]] == encoding, @"fixture encoding attribute round-trips");
            NoteObject *note = [importer noteWithFile:path];
            Check(note && [[[note contentString] string] isEqualToString:text], @"tagged source imports exact characters and mixed line endings");
            [library addNewNote:note];
            Check([[note sourceDataReturningError:NULL] isEqualToData:bytes], @"unchanged source retains all tagged bytes");
            [note setSourceSyntaxIdentifier:@"html"];
            NSData *prefsData = [NSKeyedArchiver archivedDataWithRootObject:[library notationPrefs]];
            NVReviewSourceOwner *owner = [[[NVReviewSourceOwner alloc] init] autorelease];
            owner->prefs = [NSKeyedUnarchiver unarchiveObjectWithData:prefsData];
            NoteObject *restored = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:note]];
            [restored setDelegate:owner];
            Check([[[restored contentString] string] isEqualToString:text] && [[restored sourceSyntaxIdentifier] isEqualToString:@"html"], @"keyed archive restores source and local syntax by note UUID");
            NSStringEncoding restoredEncoding = fileEncodingOfNote(restored);
            if (restoredEncoding != encoding) archiveEncodingChanges++;
            NSError *error = nil;
            NSData *restoredBytes = [restored sourceDataReturningError:&error];
            if (![restoredBytes isEqualToData:bytes]) archiveByteFailures++;
            NSLog(@"EVIDENCE archive case=%lu original=%llu restored=%llu original_bytes=%lu restored_bytes=%lu same_bytes=%d error=%@", (unsigned long)index, (unsigned long long)encoding, (unsigned long long)restoredEncoding, (unsigned long)[bytes length], (unsigned long)[restoredBytes length], [restoredBytes isEqualToData:bytes], error);
            // The production setter ignores nil; attach the complete disposable library before editing.
            [restored setDelegate:library];
            [restored setContentString:[[[NSAttributedString alloc] initWithString:edited] autorelease]];
            NSData *editedBytes = [restored sourceDataReturningError:&error];
            NSData *expectedBytes = SourceBytes(edited, encoding, boms[index]);
            if (![editedBytes isEqualToData:expectedBytes]) archiveByteFailures++;
            NSLog(@"EVIDENCE edited archive case=%lu expected_bytes=%lu actual_bytes=%lu same_bytes=%d error=%@", (unsigned long)index, (unsigned long)[expectedBytes length], (unsigned long)[editedBytes length], [editedBytes isEqualToData:expectedBytes], error);
        }
        NSUInteger literalMarkLosses = 0;
        for (NSUInteger index = 2; index < [encodings count]; index++) {
            NSStringEncoding encoding = [encodings[index] unsignedIntegerValue];
            NSStringEncoding wrongHint = NSWindowsCP1252StringEncoding;
            NSString *empty = [NoteObject sourceStringFromData:boms[index] encoding:&wrongHint path:nil];
            Check(empty && [empty length] == 0 && wrongHint == encoding, @"BOM-only note remains empty and has the correct explicit encoding");
            NSString *leadingMark = @"\uFEFFliteral\r\n";
            NSData *twiceMarked = SourceBytes(leadingMark, encoding, boms[index]);
            wrongHint = NSWindowsCP1252StringEncoding;
            NSString *decoded = [NoteObject sourceStringFromData:twiceMarked encoding:&wrongHint path:nil];
            NSLog(@"EVIDENCE leading mark encoding=%llu expected_length=%lu actual_length=%lu equal=%d", (unsigned long long)encoding, (unsigned long)[leadingMark length], (unsigned long)[decoded length], [decoded isEqualToString:leadingMark]);
            if (encoding == NSUTF8StringEncoding) {
                NSStringEncoding legacyHint = NSMacOSRomanStringEncoding;
                NSString *legacy = [NSMutableString newShortLivedStringFromData:[NSMutableData dataWithData:twiceMarked] ofGuessedEncoding:&legacyHint withPath:NULL orWithFSRef:NULL];
                Check([legacy isEqualToString:leadingMark], @"control: the previous decoder retains literal U+FEFF for this odd-byte fixture");
                NSString *singlePass = [[[NSString alloc] initWithData:twiceMarked encoding:NSUTF8StringEncoding] autorelease];
                Check([singlePass isEqualToString:leadingMark], @"control: Foundation consumes exactly one UTF-8 BOM when given the complete data");
            }
            if (![decoded isEqualToString:leadingMark]) literalMarkLosses++;
            NSString *markedPath = [TestDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"marked-%lu.txt", (unsigned long)index]];
            [twiceMarked writeToFile:markedPath atomically:YES];
            NoteObject *markedNote = [importer noteWithFile:markedPath];
            Check(markedNote && [[markedNote sourceDataReturningError:NULL] isEqualToData:twiceMarked], @"unchanged literal-mark fixture retains the original bytes");
            [markedNote setContentString:[[[NSAttributedString alloc] initWithString:[[[markedNote contentString] string] stringByAppendingString:@"edit"]] autorelease]];
            NSData *actualEditedMark = [markedNote sourceDataReturningError:NULL];
            NSData *expectedEditedMark = SourceBytes([leadingMark stringByAppendingString:@"edit"], encoding, boms[index]);
            NSLog(@"EVIDENCE edited literal mark encoding=%llu expected_bytes=%@ actual_bytes=%@ same_bytes=%d", (unsigned long long)encoding, expectedEditedMark, actualEditedMark, [expectedEditedMark isEqualToData:actualEditedMark]);
        }
        NSData *ambiguous = [text dataUsingEncoding:NSWindowsCP1252StringEncoding];
        NSStringEncoding hint = NSWindowsCP1252StringEncoding;
        Check([[NoteObject sourceStringFromData:ambiguous encoding:&hint path:nil] isEqualToString:text], @"explicit CP-1252 hint outranks the MacRoman fallback");
        NSString *ascii = @" \tASCII\r\n\r\n";
        NSData *asciiBytes = [ascii dataUsingEncoding:NSASCIIStringEncoding];
        hint = NSWindowsCP1252StringEncoding;
        Check([[NoteObject sourceStringFromData:asciiBytes encoding:&hint path:nil] isEqualToString:ascii] && hint == NSWindowsCP1252StringEncoding, @"ASCII-only source retains an explicit legacy encoding hint");
        NSLog(@"EVIDENCE archive_encoding_changes=%lu archive_byte_failures=%lu literal_mark_losses=%lu", (unsigned long)archiveEncodingChanges, (unsigned long)archiveByteFailures, (unsigned long)literalMarkLosses);
        NSLog(@"ROUND 2 CONTRARIAN DATA CHECKS COMPLETED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
