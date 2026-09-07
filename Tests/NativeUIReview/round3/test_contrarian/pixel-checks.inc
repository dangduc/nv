- (void)nv_runTests {
    @try {
        extern NSDictionary *NVMeasureRowPixels(NSTableView *, NSInteger, NSInteger, NSString *);
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSWindow *browserWindow = [self window];
        [NSApp activateIgnoringOtherApps:YES];
        [browserWindow makeKeyAndOrderFront:self];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while ((! [NSApp isActive] || ![browserWindow isKeyWindow] || [app activeBrowser] != self) &&
            [deadline timeIntervalSinceNow] > 0) Pump();
        Check([NSApp isActive] && [browserWindow isKeyWindow] && [app activeBrowser] == self,
            @"native activation makes the pixel fixture browser key and active");
        [browserWindow setContentSize:NSMakeSize(1000, 650)];
        [self setNotesListHeight:220];
        [[GlobalPrefs defaultPrefs] setAlternatingRows:YES sender:self];
        for (NSUInteger index = 0; index < 6; index++) {
            MakeNote(library, [NSString stringWithFormat:@"Ink MMMMM row %02lu", (unsigned long)index], @"disposable body");
        }
        [self searchForString:@""]; Pump();
        Check([notesTableView numberOfRows] == 6 && [notesTableView usesAlternatingRowBackgroundColors],
            @"six real note rows use the native alternating background preference");
        [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [browserWindow makeFirstResponder:textView];
        NSInteger titleColumn = [notesTableView columnWithIdentifier:NoteTitleColumnString];
        Check(titleColumn >= 0, @"the visible list contains the title column");
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            [browserWindow setAppearance:[NSAppearance appearanceNamed:appearance]];
            [notesTableView setNeedsDisplay:YES];
            for (NSUInteger iteration = 0; iteration < 5; iteration++) Pump();
            [[browserWindow contentView] layoutSubtreeIfNeeded];
            [browserWindow displayIfNeeded];
            NSLog(@"ROW_APPEARANCE window=%@ list=%@ table=%@ alternating=%d selected=%ld",
                [[browserWindow effectiveAppearance] name], [[notesSubview effectiveAppearance] name],
                [[notesTableView effectiveAppearance] name], [notesTableView usesAlternatingRowBackgroundColors],
                (long)[notesTableView selectedRow]);
            BOOL whiteRows = YES, darkText = YES;
            for (NSInteger row = 1; row <= 2; row++) {
                Check(![[notesTableView selectedRowIndexes] containsIndex:row], @"pixel sample contains an unselected populated row");
                NSString *name = [NSString stringWithFormat:@"%@-row-%ld", appearance, (long)row];
                NSDictionary *pixels = NVMeasureRowPixels(notesTableView, row, titleColumn, name);
                whiteRows &= [pixels[@"opaque"] unsignedIntegerValue] > 1000 &&
                    [pixels[@"medianBrightness"] doubleValue] > .85 && [pixels[@"paleFraction"] doubleValue] > .7;
                darkText &= [pixels[@"darkTitlePixels"] unsignedIntegerValue] > 10;
            }
            Check(whiteRows, @"unselected alternating note rows retain a pale background under the window appearance");
            Check(darkText, @"the pale note rows contain visible dark title glyph pixels");
        }
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"ROW PIXEL TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
