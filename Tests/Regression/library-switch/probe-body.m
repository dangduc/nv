    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        MakeNote(library, @"First Library Note", @"body one");
        MakeNote(library, @"Second Library Note", @"body two");
        Pump();
        [notesTableView reloadData];
        Pump();
        Check([notesTableView numberOfRows] > 0, @"the table shows the first library's rows");

        // A data source that has never held a row keeps its backing array unallocated, so
        // -immutableObjects legitimately returns NULL. Attaching one while the table's cached
        // row count still describes the previous library is the state that used to crash.
        FastListDataSource *emptySource = [[[FastListDataSource alloc] init] autorelease];
        Check([emptySource count] == 0, @"a fresh data source is empty");
        Check([emptySource immutableObjects] == NULL, @"a fresh data source exposes a NULL backing array");

        // The stale-count window cannot be staged directly: -setDataSource: invalidates the
        // table's cached row count. It opens during a real library switch, which the end-to-end
        // case below performs.

        // End to end: the Preferences "Other..." path switches libraries by writing the alias
        // default. applicationDidFinishLaunching: normally registers this observer, and the
        // harness replaces that method, so register it here.
        [[GlobalPrefs defaultPrefs] registerForSettingChange:@selector(setAliasDataForDefaultDirectory:sender:) withTarget:self];

        NSString *secondPath = [TestDirectory stringByAppendingPathComponent:@"SecondLibrary"];
        Check([[NSFileManager defaultManager] createDirectoryAtPath:secondPath withIntermediateDirectories:YES attributes:nil error:NULL],
              @"second library directory is created");
        FSRef secondRef;
        Check(FSPathMakeRef((const UInt8 *)[secondPath fileSystemRepresentation], &secondRef, NULL) == noErr,
              @"second library resolves to an FSRef");
        NSData *secondAlias = [NSData aliasDataForFSRef:&secondRef];
        Check(secondAlias != nil, @"second library produces alias data");
        NSData *firstAlias = [[[[NVApplicationController sharedController] library] aliasDataForNoteDirectory] retain];
        Check(firstAlias != nil, @"first library produces alias data");

        [[GlobalPrefs defaultPrefs] setAliasDataForDefaultDirectory:secondAlias sender:nil];
        for (int i = 0; i < 30; i++) Pump();
        NotationController *switched = [[NVApplicationController sharedController] library];
        Check(switched != library, @"changing the notes folder installs a different library");
        Check([[switched allNotes] count] == 0, @"the empty folder opens as an empty library");

        // Give the empty library a row, so the table's cached count is non-zero on the way back.
        MakeNote(switched, @"Note In Second Library", @"body");
        Pump();
        [notesTableView reloadData];
        Pump();

        [[GlobalPrefs defaultPrefs] setAliasDataForDefaultDirectory:firstAlias sender:nil];
        for (int i = 0; i < 30; i++) Pump();
        NotationController *restored = [[NVApplicationController sharedController] library];
        Check([[restored allNotes] count] == 2, @"switching back restores the original library's notes");
        [firstAlias release];

        NSLog(@"LIBRARY SWITCH CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
