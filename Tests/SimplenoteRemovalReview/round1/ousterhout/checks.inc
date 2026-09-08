- (void)nv_runTests {
    BOOL baseline = [[NSProcessInfo processInfo].arguments containsObject:@"NVReviewBaseline"];
    NSLog(@"Archive boundary review, baseline=%d", baseline);
    NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
    [prefs setPreferencesAreStored];
    NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"# Local café 😀\r\n\tunsent\n"] autorelease]
        title:@"Boundary title" delegate:nil format:SingleDatabaseFormat labels:@"review, 日本語"] autorelease];
    for (NSUInteger i = 0; i < 17; i++) [note incrementLSN];
    DeletedNoteObject *deleted = [DeletedNoteObject deletedNoteWithNote:note];
    FrozenNotation *frozen = baseline ?
        [[[FrozenNotation alloc] initWithNotes:[NSMutableArray arrayWithObject:note] deletedNotes:[NSMutableSet setWithObject:deleted] prefs:prefs] autorelease] :
        [[[FrozenNotation alloc] initWithNotes:[NSMutableArray arrayWithObject:note] prefs:prefs] autorelease];
    Check(frozen != nil, @"actual model factory creates the isolated archive");

    NSArray *originals = @[note, deleted, prefs, frozen];
    NSArray *keys = @[@"syncServicesMD", @"syncServicesMD", @"syncServiceAccounts", @"deletedNoteSet"];
    for (NSUInteger i = 0; i < originals.count; i++) {
        id original = originals[i]; NSString *key = keys[i]; NSData *encoded = nil;
        ObsoleteDecodes = 0;
        id decoded = DecoratedRoundtrip(original, key, &encoded);
        Check([decoded isMemberOfClass:[original class]], [NSString stringWithFormat:@"%@ fixture decodes through the actual model class", [original class]]);
        Check(ArchiveHasKey(encoded, key), @"injected archive really contains the obsolete field");
        Check(ObsoleteDecodes == (baseline ? 1 : 0), [NSString stringWithFormat:@"%@ visits obsolete payload %lu time(s), expected %d", [original class], (unsigned long)ObsoleteDecodes, baseline ? 1 : 0]);
        NSData *rewritten = [NSKeyedArchiver archivedDataWithRootObject:decoded];
        Check(ArchiveHasKey(rewritten, key) == baseline, @"rewrite retains the old field only in the baseline");
        id reopened = [NSKeyedUnarchiver unarchiveObjectWithData:rewritten];
        Check(reopened != nil, @"rewritten archive reopens");
        if (i < 2) {
            Check(memcmp([reopened uniqueNoteIDBytes], [original uniqueNoteIDBytes], sizeof(CFUUIDBytes)) == 0 &&
                  [reopened logSequenceNumber] == [original logSequenceNumber], @"archive boundary preserves all UUID bytes and the journal sequence");
            Check([reopened isEqual:original] && [original isEqual:reopened] && [reopened hash] == [original hash], @"live note and tombstone identity preserve symmetric equality and hash");
        }
        if (i == 0) {
            Check([[[reopened contentString] string] isEqual:[[note contentString] string]] &&
                  [titleOfNote(reopened) isEqual:titleOfNote(note)] && [labelsOfNote(reopened) isEqual:labelsOfNote(note)], @"body, title, tags survive obsolete metadata removal");
        } else if (i == 2) {
            Check([reopened notesStorageFormat] == SingleDatabaseFormat && ![reopened doesEncryption], @"local storage preferences survive obsolete account removal");
            Check(baseline || [decoded preferencesChanged], @"obsolete account presence marks current preferences for rewrite");
        } else if (i == 3) {
            OSStatus error = noErr; NSArray *notes = [reopened unpackedNotesReturningError:&error];
            Check(error == noErr && notes.count == 1 && [[[[notes firstObject] contentString] string] isEqual:[[note contentString] string]], @"library boundary preserves the packed local note while omitting remote deletion history");
        }
    }

    // A tombstone must own a copied identity, not depend on source lifetime.
    SourceDeallocations = 0;
    NVReviewLogSource *source = [[NVReviewLogSource alloc] init];
    CFUUIDBytes expected = *[source uniqueNoteIDBytes];
    DeletedNoteObject *tombstone = [[DeletedNoteObject alloc] initWithExistingObject:source];
    memset([source uniqueNoteIDBytes], 0, sizeof(CFUUIDBytes));
    [source release];
    Check(SourceDeallocations == (baseline ? 0 : 1), @"current local tombstone releases source lifetime dependency");
    Check(memcmp([tombstone uniqueNoteIDBytes], &expected, sizeof(expected)) == 0 && [tombstone logSequenceNumber] == 0xf1234567U, @"copied identity and unsigned sequence survive mutation and release of the source");
    for (NSUInteger i = 0; i < 32; i++) {
        DeletedNoteObject *keyed = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:tombstone]];
        DeletedNoteObject *sequential = [NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:tombstone]];
        Check([keyed isEqual:sequential] && [keyed logSequenceNumber] == [tombstone logSequenceNumber] &&
              [sequential logSequenceNumber] == [tombstone logSequenceNumber], @"keyed and sequential tombstone copies agree after sequence advance");
        [tombstone incrementLSN];
        Check([keyed youngerThanLogObject:tombstone] && ![tombstone youngerThanLogObject:keyed], @"local protocol ordering agrees across both archive formats");
    }
    [tombstone release];
    Check(SourceDeallocations == 1, @"source allocation is released exactly once");
    NSLog(@"PASS: %lu archive boundary review assertions", (unsigned long)Checks);
    [NSApp terminate:self];
}
