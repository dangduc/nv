- (void)danR2_reset {
    FileWrites = SnapshotWrites = JournalWrites = 0;
}
- (void)danR2_assertFiles:(NSArray *)notes bodies:(NSArray *)bodies {
    BOOL exact = YES;
    for (NSUInteger i = 0; i < [notes count]; i++) {
        NoteObject *note = notes[i];
        exact = exact && [[[note contentString] string] isEqualToString:bodies[i]] &&
            [[NSData dataWithContentsOfFile:[note noteFilePath]] isEqual:[bodies[i] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    Check(exact, @"all model characters and physical UTF-8 source bytes match the independent expected strings");
}
- (void)danR2_phase:(NSString *)phase files:(NSUInteger)files journal:(NSUInteger)journal snapshots:(NSUInteger)snapshots
         directory:(NSString *)directory startRecords:(NSUInteger)start {
    Check(FileWrites == files && JournalWrites == journal && SnapshotWrites == snapshots,
        [NSString stringWithFormat:@"%@ produces expected file, journal, and snapshot write counts", phase]);
    Check([MeasuredJournal synchronize], @"measured journal synchronization succeeds");
    NSUInteger actual = DanR2PhysicalRecords(directory) - start;
    Check(actual == journal, @"complete physical journal records match the observed successful writer calls");
    NSLog(@"DAN_R2_PHASE name=%@ files=%lu journal=%lu snapshots=%lu physical=%lu", phase,
        (unsigned long)FileWrites, (unsigned long)JournalWrites, (unsigned long)SnapshotWrites, (unsigned long)actual);
}
- (void)nv_runTests {
    @try {
        NSString *directory = [TestDirectory stringByAppendingPathComponent:@"PlainMeasured"];
        Check([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL], @"create disposable plain-file library");
        NotationController *library = DanR2Open(directory);
        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        // Directory notifications are outside this isolated scheduler experiment.
        [library stopFileNotifications];
        NSMutableArray *notes = [NSMutableArray array], *sessions = [NSMutableArray array], *expected = [NSMutableArray array];
        for (NSUInteger i = 0; i < 8; i++) {
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:DanR2Body(i)] autorelease]
                title:[NSString stringWithFormat:@"Plain %02lu", (unsigned long)i] delegate:library format:PlainTextFormat labels:@""] autorelease];
            [library addNewNote:note];
            [notes addObject:note]; [expected addObject:DanR2Body(i)];
            [sessions addObject:[[[NVNoteEditingSession alloc] initWithNote:note] autorelease]];
        }
        DanR2Pump(.35);
        Check([library flushAllNoteChanges], @"fixture files and initial snapshot are fully stored before counting");
        [self danR2_assertFiles:notes bodies:expected];
        DanR2Swap([NotationController class], @selector(storeDataAtomicallyInNotesDirectory:withName:destinationRef:verifyWithSelector:verificationDelegate:), @selector(danR2_store:withName:destinationRef:verifyWithSelector:verificationDelegate:));
        DanR2Swap([NotationController class], @selector(scheduleWriteForNote:), @selector(danR2_schedule:));
        DanR2Swap([WALStorageController class], @selector(writeNoteObject:), @selector(danR2_write:));
        MeasuredLibrary = library; MeasuredJournal = [library valueForKey:@"walWriter"];
        Check(MeasuredJournal != nil && [library currentNoteStorageFormat] == PlainTextFormat, @"plain-file workload uses the real journal and file writer");
        for (NSUInteger deleting = 0; deleting < 2; deleting++) {
            [self danR2_reset]; NSUInteger start = DanR2PhysicalRecords(directory);
            for (NSUInteger edit = 0; edit < 40; edit++) {
                for (NVNoteEditingSession *session in sessions) {
                    NSTextStorage *storage = [session textStorage];
                    [storage replaceCharactersInRange:NSMakeRange([storage length] - (deleting ? 1 : 0), deleting ? 1 : 0)
                                           withString:deleting ? @"" : @"x"];
                    [session commitTextChanges];
                }
            }
            Check(FileWrites == 0 && JournalWrites == 0 && SnapshotWrites == 0, @"320 source commits queue without synchronous persistence");
            for (NSUInteger i = 0; i < 8; i++) [expected replaceObjectAtIndex:i withObject:deleting ? DanR2Body(i) :
                [DanR2Body(i) stringByAppendingString:[@"" stringByPaddingToLength:40 withString:@"x" startingAtIndex:0]]];
            Check([library flushAllNoteChanges], @"explicit flush drains the source burst");
            [self danR2_phase:deleting ? @"delete-burst" : @"insert-burst" files:8 journal:8 snapshots:1 directory:directory startRecords:start];
            [self danR2_assertFiles:notes bodies:expected];
            [self danR2_reset]; start = DanR2PhysicalRecords(directory);
            for (NSUInteger repeat = 0; repeat < 5; repeat++) Check([library flushAllNoteChanges], @"unchanged flush succeeds");
            [self danR2_phase:deleting ? @"unchanged-after-delete" : @"unchanged-after-insert" files:0 journal:0 snapshots:0 directory:directory startRecords:start];
        }
        [self danR2_reset]; NSUInteger start = DanR2PhysicalRecords(directory);
        NSMutableArray *dates = [NSMutableArray array];
        for (NoteObject *note in notes) [dates addObject:@(modifiedDateOfNote(note))];
        for (NSUInteger edit = 1; edit <= 12; edit++) for (NoteObject *note in notes) [note setSelectedRange:NSMakeRange(edit, 1)];
        Check([library flushAllNoteChanges], @"selection metadata flush succeeds");
        [self danR2_phase:@"selection-only" files:0 journal:8 snapshots:1 directory:directory startRecords:start];
        BOOL datesUnchanged = YES;
        for (NSUInteger i = 0; i < 8; i++) datesUnchanged = datesUnchanged && modifiedDateOfNote(notes[i]) == [dates[i] doubleValue];
        Check(datesUnchanged, @"selection metadata preserves source modification dates");
        [self danR2_assertFiles:notes bodies:expected];
        [self danR2_reset]; start = DanR2PhysicalRecords(directory);
        for (NSUInteger edit = 0; edit < 12; edit++) for (NoteObject *note in notes)
            [note setLabelString:[NSString stringWithFormat:@"local%lu", (unsigned long)edit]];
        Check([library flushAllNoteChanges], @"tag metadata flush succeeds");
        [self danR2_phase:@"tags-only" files:8 journal:8 snapshots:1 directory:directory startRecords:start];
        [self danR2_assertFiles:notes bodies:expected];
        [self danR2_reset]; start = DanR2PhysicalRecords(directory);
        for (NSUInteger edit = 0; edit < 12; edit++) for (NoteObject *note in notes)
            [note setSourceSyntaxIdentifier:@[@"markdown", @"html", @"json"][edit % 3]];
        Check(FileWrites == 0 && JournalWrites == 0 && SnapshotWrites == 0, @"syntax changes defer their preference save");
        DanR2Pump(.4);
        [self danR2_phase:@"syntax-only" files:0 journal:0 snapshots:1 directory:directory startRecords:start];
        [self danR2_assertFiles:notes bodies:expected];
        [self danR2_reset]; start = DanR2PhysicalRecords(directory);
        NVNoteEditingSession *session = sessions[0];
        for (NSUInteger edit = 0; edit < 20; edit++) {
            NSTextStorage *storage = [session textStorage];
            [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@"y"];
            [session commitTextChanges]; DanR2Pump(.01);
        }
        Check(FileWrites == 0 && JournalWrites == 0, @"sub-delay paced edits remain batched");
        DanR2Pump(3.0);
        [self danR2_phase:@"idle-source-save" files:1 journal:1 snapshots:0 directory:directory startRecords:start];
        [expected replaceObjectAtIndex:0 withObject:[DanR2Body(0) stringByAppendingString:[@"" stringByPaddingToLength:20 withString:@"y" startingAtIndex:0]]];
        [self danR2_assertFiles:notes bodies:expected];
        [self danR2_reset]; start = DanR2PhysicalRecords(directory);
        Check([library flushAllNoteChanges], @"snapshot flush after idle note save succeeds");
        [self danR2_phase:@"snapshot-after-idle" files:0 journal:0 snapshots:1 directory:directory startRecords:start];
        [self danR2_reset]; start = DanR2PhysicalRecords(directory);
        for (NSUInteger repeat = 0; repeat < 5; repeat++) Check([library flushAllNoteChanges], @"final unchanged flush succeeds");
        [self danR2_phase:@"final-unchanged" files:0 journal:0 snapshots:0 directory:directory startRecords:start];
        for (NVNoteEditingSession *editor in sessions) [editor close];
        MeasuredLibrary = nil; MeasuredJournal = nil;
        [library closeAllResources]; [library release];
        library = DanR2Open(directory); [library stopFileNotifications];
        Check([[library allNotes] count] == 8, @"eight plain notes survive a real controller close and reopen");
        NSMutableArray *ordered = [NSMutableArray array]; BOOL metadata = YES;
        for (NSUInteger i = 0; i < 8; i++) {
            NSString *title = [NSString stringWithFormat:@"Plain %02lu", (unsigned long)i];
            NoteObject *match = nil;
            for (NoteObject *note in [library allNotes]) if ([titleOfNote(note) isEqualToString:title]) { match = note; break; }
            Check(match != nil, @"reopened note retains its unique title and filename identity");
            [ordered addObject:match];
            metadata = metadata && [labelsOfNote(match) isEqualToString:@"local11"] &&
                [[match sourceSyntaxIdentifier] isEqualToString:@"json"] && NSEqualRanges([match lastSelectedRange], NSMakeRange(12, 1));
        }
        Check(metadata, @"tags, local syntax, and selection metadata survive the real reopen");
        [self danR2_assertFiles:ordered bodies:expected];
        [library closeAllResources]; [library release];
        NSLog(@"DAN_R2_RESULT app=%@ notes=8 sourceCommits=660 selectionChanges=96 tagChanges=96 syntaxChanges=96 phases=10 checks=%lu",
            NSClassFromString(@"SimplenoteSession") ? @"baseline" : @"current", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@", exception); _exit(1); }
}
