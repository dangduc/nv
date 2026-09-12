    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        Pump();

        // Foundation returns a NULL buffer pointer for zero-length data. A note with an empty
        // body caches exactly that as its source baseline once it is read back from disk.
        NSString *emptyPath = [TestDirectory stringByAppendingPathComponent:@"zero-length-source.txt"];
        Check([[NSData data] writeToFile:emptyPath atomically:YES], @"zero-length fixture writes");
        NSData *reread = [NSData dataWithContentsOfFile:emptyPath];
        Check(reread && [reread length] == 0, @"zero-length file reads back as empty data");
        Check([reread bytes] == NULL, @"zero-length data exposes a NULL buffer pointer");

        // The low-level writer must accept a zero-length write, and must still reject a
        // missing buffer when there are bytes to write.
        FSRef fixtureRef;
        Check(FSPathMakeRef((const UInt8 *)[emptyPath fileSystemRepresentation], &fixtureRef, NULL) == noErr,
              @"zero-length fixture resolves to an FSRef");
        Check(FSRefWriteData(&fixtureRef, 16384, 0, NULL, 0, false) == noErr,
              @"zero-length write with a NULL buffer succeeds");
        Check(FSRefWriteData(&fixtureRef, 16384, 4, NULL, 0, false) == paramErr,
              @"a NULL buffer with bytes to write is still rejected");
        Check(FSRefWriteData(NULL, 16384, 0, NULL, 0, false) == paramErr,
              @"a missing FSRef is still rejected");

        // An empty-body note must survive the rewrite that a storage-format change performs,
        // which is the pass that previously failed with paramErr once the note had been
        // loaded from disk and its NULL-pointer source baseline was cached.
        NoteObject *empty = MakeNote(library, @"Empty Source Note", @"");
        Check([empty writeUsingCurrentFileFormat], @"an empty-body note writes on creation");
        NSString *notePath = [[TestDirectory stringByAppendingPathComponent:@"Notes"]
                              stringByAppendingPathComponent:filenameOfNote(empty)];
        Check([[NSFileManager defaultManager] fileExistsAtPath:notePath], @"the empty note reaches disk");
        Check([[NSData dataWithContentsOfFile:notePath] length] == 0, @"the empty note is a zero-length file");

        // Adopt the on-disk bytes the way loading a note from disk does, then rewrite.
        [empty rememberSourceData:[NSData dataWithContentsOfFile:notePath] encoding:fileEncodingOfNote(empty)];
        Check([[empty sourceDataReturningError:NULL] bytes] != NULL,
              @"cached zero-length source never yields a NULL buffer to the writers");
        Check([empty writeUsingCurrentFileFormat], @"an empty-body note rewrites after its source baseline is cached");
        Check([empty writeUsingCurrentFileFormat], @"repeated rewrites of an empty-body note keep succeeding");

        // A failed write leaves its temporary file behind, so the directory is the check.
        NSUInteger strays = 0;
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[TestDirectory stringByAppendingPathComponent:@"Notes"] error:NULL]) {
            if ([name length] > 1 && [name characterAtIndex:0] == '.' && isdigit([name characterAtIndex:1])) strays++;
        }
        Check(strays == 0, @"no orphaned temporary files remain after writing empty-body notes");

        NSLog(@"EMPTY SOURCE WRITE CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
