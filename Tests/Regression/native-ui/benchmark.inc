- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NSMutableArray *notes = [NSMutableArray array];
        for (NSUInteger i = 0; i < 10000; i++) {
            NSString *title = [NSString stringWithFormat:@"Note %05lu", (unsigned long)i];
            NSString *body = [NSString stringWithFormat:@"Project %lu meeting notes. Tasks and decisions for the next release. Search, edit, and review this document.", (unsigned long)(i % 100)];
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
                title:title delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
            [notes addObject:note];
        }
        [library addNotes:notes]; Pump();
        [[self window] setContentSize:NSMakeSize(640, 480)]; Pump();
        if ([self respondsToSelector:@selector(setNotesListHeight:)]) [self setNotesListHeight:160];
        else {
            // The same fixture also runs against the pre-modernization binary.
            id pane = [self valueForKey:@"notesSubview"];
            void (*setDimension)(id, SEL, CGFloat) = (void *)[pane methodForSelector:NSSelectorFromString(@"setDimension:")];
            setDimension(pane, NSSelectorFromString(@"setDimension:"), 160);
            [[self valueForKey:@"splitView"] performSelector:@selector(adjustSubviews)];
        }
        Pump();
        NSMutableArray *searchTimes = [NSMutableArray array], *scrollTimes = [NSMutableArray array];
        for (NSUInteger pass = 0; pass < 30; pass++) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            for (NSString *query in @[@"project", @"project 2", @"project 23", @""])
                [[self browserSession] filterNotesFromString:query];
            [searchTimes addObject:@((CFAbsoluteTimeGetCurrent() - start) * 1000)];
        }
        NSTableView *table = [self valueForKey:@"notesTableView"];
        for (NSUInteger pass = 0; pass < 60; pass++) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            [table scrollRowToVisible:(pass * 157) % 10000];
            NSRect rect = [table visibleRect];
            NSBitmapImageRep *bitmap = [table bitmapImageRepForCachingDisplayInRect:rect];
            [table cacheDisplayInRect:rect toBitmapImageRep:bitmap];
            [scrollTimes addObject:@((CFAbsoluteTimeGetCurrent() - start) * 1000)];
        }
        [searchTimes sortUsingSelector:@selector(compare:)];
        [scrollTimes sortUsingSelector:@selector(compare:)];
        NSLog(@"BENCHMARK notes=10000 query_sequence_median_ms=%@ query_sequence_p95_ms=%@ scroll_draw_median_ms=%@ scroll_draw_p95_ms=%@ viewport=%@",
            searchTimes[15], searchTimes[28], scrollTimes[30], scrollTimes[57], NSStringFromRect([table visibleRect]));
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@", exception); exit(1); }
}
