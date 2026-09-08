    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NSString *expected = @"  café £ –\r\n";
        NSData *macBytes = [expected dataUsingEncoding:NSMacOSRomanStringEncoding];
        NSString *path = [TestDirectory stringByAppendingPathComponent:@"macroman.txt"];
        Check([macBytes writeToFile:path atomically:YES], @"unmarked MacRoman fixture writes");
        Check([[NSFileManager defaultManager] textEncodingAttributeOfFSPath:[path fileSystemRepresentation]] == 0, @"fixture has no text-encoding xattr");
        NSStringEncoding previousEncoding = NSMacOSRomanStringEncoding;
        NSMutableString *previousText = [NSMutableString newShortLivedStringFromData:[NSMutableData dataWithData:macBytes] ofGuessedEncoding:&previousEncoding withPath:[path fileSystemRepresentation] orWithFSRef:NULL];
        Check([previousText isEqualToString:expected], @"previous importer decoder preserves unmarked MacRoman characters");
        NoteObject *imported = [importer noteWithFile:path];
        Check(imported != nil, @"source importer accepts the same fixture");
        NSLog(@"EVIDENCE legacy expected UTF8 hex=%@ actual UTF8 hex=%@ original encoding=%lu current encoding=%lu", [expected dataUsingEncoding:NSUTF8StringEncoding], [[[imported contentString] string] dataUsingEncoding:NSUTF8StringEncoding], (unsigned long)previousEncoding, (unsigned long)fileEncodingOfNote(imported));
        Check(![[[imported contentString] string] isEqualToString:expected], @"CONFIRMED: changed fallback silently changes MacRoman characters");
        Check([[imported sourceDataReturningError:NULL] isEqualToData:macBytes], @"original-byte retention masks the incorrect source decoding on unchanged export");
        NSString *taggedPath = [TestDirectory stringByAppendingPathComponent:@"tagged.txt"];
        [macBytes writeToFile:taggedPath atomically:YES];
        [[NSFileManager defaultManager] setTextEncodingAttribute:NSMacOSRomanStringEncoding atFSPath:[taggedPath fileSystemRepresentation]];
        Check([[[[importer noteWithFile:taggedPath] contentString] string] isEqualToString:expected], @"REJECTED: explicit MacRoman xattrs remain honored");
        NSData *utf8 = [expected dataUsingEncoding:NSUTF8StringEncoding];
        NSString *utf8Path = [TestDirectory stringByAppendingPathComponent:@"utf8.txt"];
        [utf8 writeToFile:utf8Path atomically:YES];
        Check([[[[importer noteWithFile:utf8Path] contentString] string] isEqualToString:expected], @"REJECTED: unmarked UTF-8 remains correct");
        const unsigned char bomBytes[] = {0xFF, 0xFE};
        NSMutableData *bomData = [NSMutableData dataWithBytes:bomBytes length:sizeof(bomBytes)];
        [bomData appendData:[expected dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
        NSStringEncoding guessed = NSWindowsCP1252StringEncoding;
        Check([[NoteObject sourceStringFromData:bomData encoding:&guessed path:nil] isEqualToString:expected] && guessed == NSUTF16LittleEndianStringEncoding, @"REJECTED: BOM overrides an incompatible encoding hint");
        NSLog(@"CONTRARIAN DATA REVIEW CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
