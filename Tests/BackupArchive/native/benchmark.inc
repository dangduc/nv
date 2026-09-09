static void Benchmark(NSUInteger count) {
    @autoreleasepool {
        NSMutableArray *notes = [NSMutableArray arrayWithCapacity:count];
        NSString *paragraph = @"## Source fixture\nA paragraph with café, 雪, links, JSON {\"enabled\":true}, and a list item.\n";
        NSMutableString *ordinary = [NSMutableString string];
        while ([ordinary lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < 2048) [ordinary appendString:paragraph];
        NSUInteger sourceBytes = 0;
        for (NSUInteger index = 0; index < count; index++) {
            NSString *body = [ordinary stringByAppendingFormat:@"\nrecord=%lu", (unsigned long)index];
            if (index == 0) {
                NSMutableString *large = [NSMutableString stringWithCapacity:5 * 1024 * 1024];
                NSUInteger largeBytes = 0, chunkBytes = [ordinary lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                while (largeBytes < 5 * 1024 * 1024) { [large appendString:ordinary]; largeBytes += chunkBytes; }
                body = large;
            }
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
                title:[NSString stringWithFormat:@"Note %lu", (unsigned long)index] delegate:nil format:SingleDatabaseFormat labels:@"fixture"] autorelease];
            NSData *original = [body dataUsingEncoding:NSUTF8StringEncoding];
            sourceBytes += [original length];
            [note rememberSourceData:original encoding:NSUTF8StringEncoding];
            [notes addObject:note];
        }
        NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
        [prefs setBackupCheckpointGeneration:1 date:[NSDate date]];
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        NSData *data = [FrozenNotation frozenDataWithExistingNotes:notes prefs:prefs];
        NSTimeInterval captured = [NSDate timeIntervalSinceReferenceDate];
        NSError *error = nil;
        NSDictionary *restored = [NVBackupArchive restoredArchiveFromData:data error:&error];
        NSTimeInterval finished = [NSDate timeIntervalSinceReferenceDate];
        Check(restored && !error && [[restored objectForKey:@"noteCount"] unsignedIntegerValue] == count, @"benchmark round trip preserves all notes");
        struct rusage usage; getrusage(RUSAGE_SELF, &usage);
        printf("ARCHIVE_BENCHMARK notes=%lu source_bytes=%lu archive_bytes=%lu capture_ms=%.2f restore_ms=%.2f process_peak_rss_mib=%.2f\n",
            (unsigned long)count, (unsigned long)sourceBytes, (unsigned long)[data length],
            (captured-start)*1000, (finished-captured)*1000, (double)usage.ru_maxrss/1048576.0);
    }
}
