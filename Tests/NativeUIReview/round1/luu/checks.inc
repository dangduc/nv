- (void)nv_runTests {
 @try {
    NotationController *library = [[NVApplicationController sharedController] library];
    LinkingEditor *bodyEditor = [self valueForKey:@"textView"];
    if (strcmp(getenv("NV_LUU_CASE"), "links") == 0) {
        NoteObject *note = MakeNote(library, @"Link contrast", @"ordinary text https://example.invalid/path ordinary text");
        [self revealNote:note options:0]; Pump();
        [bodyEditor insertText:@"ordinary text https://example.invalid/path ordinary text" replacementRange:NSMakeRange(0, [[bodyEditor string] length])]; Pump();
        [[GlobalPrefs defaultPrefs] setMakeURLsClickable:NO sender:self];
        [self setForegrndColor:[NSColor whiteColor]];
        [self setBackgrndColor:[NSColor blackColor]];
        [self updateColorScheme]; Pump();
        NSTextStorage *storage = [bodyEditor textStorage];
        NSRange link = [[storage string] rangeOfString:@"https://example.invalid/path"];
        Check([storage attribute:NSLinkAttributeName atIndex:link.location effectiveRange:NULL] != nil, @"real URL retains its link attribute when clickable URLs are disabled");
        NSMutableArray *brightnesses = [NSMutableArray array];
        for (NSNumber *location in @[@0, @(link.location)]) {
            NSUInteger index = [location unsignedIntegerValue];
            NSRange range = NSMakeRange(index, 1);
            NSDictionary *temporary = nil;
            if ([bodyEditor respondsToSelector:@selector(layoutManager:shouldUseTemporaryAttributes:forDrawingToScreen:atCharacterIndex:effectiveRange:)]) {
                temporary = [bodyEditor layoutManager:[bodyEditor layoutManager] shouldUseTemporaryAttributes:@{} forDrawingToScreen:YES atCharacterIndex:index effectiveRange:&range];
            }
            NSColor *effective = temporary[NSForegroundColorAttributeName] ?: [storage attribute:NSForegroundColorAttributeName atIndex:index effectiveRange:NULL] ?: [NSColor blackColor];
            CGFloat brightness = [[effective colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent];
            [brightnesses addObject:@(brightness)];
        }
        NSLog(@"LINK_CONTRAST ordinary=%@ link=%@ expected_both_above=0.8", brightnesses[0], brightnesses[1]);
        NSView *view = [bodyEditor enclosingScrollView];
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
        [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bitmap];
        NSString *destination = [NSString stringWithUTF8String:getenv("NV_LUU_ARTIFACT") ?: "/tmp/nv-luu-link.png"];
        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:destination atomically:YES];
        Check([brightnesses[0] doubleValue] > .8 && [brightnesses[1] doubleValue] > .8, @"nonclickable URL uses the readable ordinary foreground");
    } else {
        NSMutableArray *notes = [NSMutableArray array];
        for (NSUInteger i = 0; i < 10000; i++) {
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Project %lu meeting notes and decisions for release.", (unsigned long)(i % 100)]] autorelease] title:[NSString stringWithFormat:@"Note %05lu", (unsigned long)i] delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
            [notes addObject:note];
        }
        [library addNotes:notes]; Pump();
        [[self window] setContentSize:NSMakeSize(640, 480)]; Pump();
        if ([self respondsToSelector:@selector(setNotesListHeight:)]) [self setNotesListHeight:160];
        else {
            id pane = [self valueForKey:@"notesSubview"];
            void (*setDimension)(id, SEL, CGFloat) = (void *)[pane methodForSelector:NSSelectorFromString(@"setDimension:")];
            setDimension(pane, NSSelectorFromString(@"setDimension:"), 160);
            [[self valueForKey:@"splitView"] performSelector:@selector(adjustSubviews)];
        }
        Pump();
        NSMutableArray *searchTimes = [NSMutableArray array], *drawTimes = [NSMutableArray array], *resizeTimes = [NSMutableArray array];
        [self searchForString:@""]; Pump();
        NSTextField *search = [self valueForKey:@"field"];
        NSArray *queries = @[@"Note 0", @"Note 00", @"Note 000", @""];
        // Search matches each term as a substring, including repeated digits inside the title.
        NSArray *expectedRows = @[@10000, @1171, @109, @10000];
        for (NSUInteger index = 0; index < [queries count]; index++) {
            NSTextView *editor = (id)[search currentEditor];
            [editor insertText:queries[index] replacementRange:NSMakeRange(0, [[editor string] length])];
            Check([[[self browserSession] searchString] isEqual:queries[index]], @"field-editor insertion reaches the browser query");
            Check([[self valueForKey:@"notesTableView"] numberOfRows] == [expectedRows[index] integerValue], [NSString stringWithFormat:@"query %@ produces %@ rows (actual %ld)", queries[index], expectedRows[index], (long)[[self valueForKey:@"notesTableView"] numberOfRows]]);
        }
        Check([library totalNoteCount] == 10000, @"search never creates a note in the timing fixture");
        for (NSUInteger pass = 0; pass < 12; pass++) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            for (NSString *query in @[@"Note 0", @"Note 00", @"Note 000", @""]) {
                NSTextView *editor = (id)[search currentEditor];
                if (!editor) { NSLog(@"FAIL: search lost focus during benchmark"); exit(1); }
                [editor insertText:query replacementRange:NSMakeRange(0, [[editor string] length])];
            }
            [searchTimes addObject:@((CFAbsoluteTimeGetCurrent() - start) * 1000)];
        }
        NSTableView *table = [self valueForKey:@"notesTableView"];
        NSLog(@"TABLE_VIEWPORT %@ row_height=%.2f", NSStringFromRect([table visibleRect]), [table rowHeight]);
        for (NSUInteger pass = 0; pass < 30; pass++) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            [table scrollRowToVisible:(pass * 157) % 10000];
            NSRect rect = [table visibleRect];
            NSBitmapImageRep *bitmap = [table bitmapImageRepForCachingDisplayInRect:rect];
            [table cacheDisplayInRect:rect toBitmapImageRep:bitmap];
            [drawTimes addObject:@((CFAbsoluteTimeGetCurrent() - start) * 1000)];
        }
        for (NSUInteger pass = 0; pass < 20; pass++) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            [[self window] setContentSize:NSMakeSize(640 + (pass % 2) * 160, 480 + (pass % 2) * 100)];
            [[[self window] contentView] layoutSubtreeIfNeeded];
            [resizeTimes addObject:@((CFAbsoluteTimeGetCurrent() - start) * 1000)];
        }
        for (NSArray *sample in @[@[@"full_search_4queries", searchTimes], @[@"table_bitmap", drawTimes], @[@"resize_layout", resizeTimes]]) {
            NSMutableArray *times = sample[1]; [times sortUsingSelector:@selector(compare:)];
            NSLog(@"PERF %@ samples=%lu median_ms=%@ p95_ms=%@", sample[0], (unsigned long)[times count], times[[times count]/2], times[MIN([times count]-1, (NSUInteger)([times count]*.95))]);
        }
        [self searchForString:@""];
        for (NSNumber *size in @[@262144, @1048576]) {
            NSMutableString *body = [NSMutableString string];
            while ([body length] < [size unsignedIntegerValue]) [body appendString:@"A paragraph with ordinary words and https://example.invalid/links for drawing.\n"];
            NSMutableAttributedString *linkedBody = [[[NSMutableAttributedString alloc] initWithString:body attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]] autorelease];
            [linkedBody addLinkAttributesForRange:NSMakeRange(0, [linkedBody length])];
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:linkedBody title:[NSString stringWithFormat:@"Large %@", size] delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
            [library addNewNote:note]; Pump();
            CFAbsoluteTime revealStart = CFAbsoluteTimeGetCurrent();
            [self revealNote:note options:0];
            [[bodyEditor layoutManager] ensureLayoutForTextContainer:[bodyEditor textContainer]];
            double reveal = (CFAbsoluteTimeGetCurrent() - revealStart)*1000;
            NSMutableArray *times = [NSMutableArray array];
            for (NSUInteger pass=0; pass<8; pass++) {
                NSRect rect = [bodyEditor visibleRect];
                rect.size = NSMakeSize(MIN(600, rect.size.width), MIN(180, rect.size.height));
                CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                NSBitmapImageRep *bitmap = [bodyEditor bitmapImageRepForCachingDisplayInRect:rect];
                [bodyEditor cacheDisplayInRect:rect toBitmapImageRep:bitmap];
                [times addObject:@((CFAbsoluteTimeGetCurrent()-start)*1000)];
            }
            [times sortUsingSelector:@selector(compare:)];
            NSLog(@"LARGE_BODY chars=%lu first_reveal_and_full_layout_ms=%.3f draw_median_ms=%@ draw_p95_ms=%@ draw_size=600x180 editor_viewport=%@", (unsigned long)[body length], reveal, times[4], times[7], NSStringFromRect([bodyEditor visibleRect]));
        }
    }
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"LUU PROBES PASSED"); exit(0);
 } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
