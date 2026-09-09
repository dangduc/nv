- (void)nv_onlyToggleToolbar:(BOOL)visible { [toolbar setVisible:visible]; }

- (void)nv_r2CheckSearchWithQuery:(NSString *)query note:(NoteObject *)note {
    [self bringFocusToControlField:self];
    Check([toolbar isVisible] && [[[toolbar items] valueForKey:@"itemIdentifier"] isEqual:@[@"Search"]],
        @"Search recovers exactly one valid toolbar item");
    Check([field window] == window && ![field isHiddenOrHasHiddenAncestor] &&
        [field currentEditor] != nil && [window firstResponder] == [field currentEditor],
        @"recovered Search has a visible native editor immediately");
    Check([[field stringValue] isEqual:query] && [[[self browserSession] searchString] isEqual:query] && [self selectedNoteObject] == note,
        @"toolbar recovery preserves the query and selected note");
    Check([dualFieldItem view] == [field superview] && NSEqualRects([field frame], [[dualFieldItem view] bounds]),
        @"four container constraints keep the search frame equal to container bounds");
}

- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *note = [MakeNote(library, @"Toolbar State", @"unchanged ordinary source") retain];
        [prefsController setAutoCompleteSearches:NO sender:nil];
        [self nv_activateBrowser];
        [self searchForString:@"State" mode:@"exact"]; [self revealNote:note options:0]; Pump();
        [window setContentSize:NSMakeSize(760, 480)]; Pump();
        NSView *originalContainer = [[dualFieldItem view] retain];
        DualField *originalField = [field retain];
        NSUInteger cases = 0;
        if (@available(macOS 11.0, *)) {
            for (NSNumber *style in @[@(NSWindowToolbarStyleExpanded), @(NSWindowToolbarStyleUnifiedCompact)]) {
                for (NSNumber *display in @[@(NSToolbarDisplayModeIconOnly), @(NSToolbarDisplayModeIconAndLabel), @(NSToolbarDisplayModeLabelOnly)]) {
                    for (NSNumber *size in @[@(NSToolbarSizeModeRegular), @(NSToolbarSizeModeSmall)]) {
                        [window makeFirstResponder:notesTableView];
                        [window setToolbarStyle:[style integerValue]];
                        [toolbar setDisplayMode:[display integerValue]]; [toolbar setSizeMode:[size integerValue]];
                        [[[window contentView] superview] layoutSubtreeIfNeeded]; Pump();
                        [toolbar validateVisibleItems];
                        NSLog(@"MODE style=%@ display=%@ size=%@ container=%@ field=%@ hidden=%d", style, display, size,
                            NSStringFromRect([[dualFieldItem view] frame]), NSStringFromRect([field frame]), [field isHiddenOrHasHiddenAncestor]);
                        Check([dualFieldItem isEnabled] && [field isEnabled] && [field isEditable] &&
                            [dualFieldItem view] == originalContainer && field == originalField,
                            @"display and size changes preserve the enabled search item and original controls");
                        [self nv_r2CheckSearchWithQuery:@"State" note:note];
                        Check(NSWidth([field bounds]) >= 140 && NSHeight([field bounds]) == 24,
                            @"ordinary toolbar modes keep the field's minimum width and fixed editing height");
                        [self setDualFieldIsVisible:NO]; Pump();
                        Check(![toolbar isVisible], @"hiding the toolbar works while its search editor is active");
                        [window makeFirstResponder:notesTableView];
                        [self setDualFieldIsVisible:YES]; Pump();
                        Check([window firstResponder] == notesTableView,
                            @"showing the toolbar does not steal a later notes-list responder");
                        [self nv_r2CheckSearchWithQuery:@"State" note:note];
                        Check([window titleVisibility] == NSWindowTitleHidden && [[window title] isEqual:@"Toolbar State"],
                            @"toolbar style changes retain the semantic note title without making it visible");
                        cases++;
                    }
                }
            }
        }
        Check(cases == 12, @"all twelve native toolbar style/display/size combinations ran");
        [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly]; [toolbar setSizeMode:NSToolbarSizeModeRegular];
        for (NSString *identifier in @[@"", @"UninstalledPluginAction", @"NewNote", @"Preview", @"More"])
            Check([self toolbar:toolbar itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES] == nil,
                @"the delegate rejects an unknown or obsolete toolbar identifier");

        if (getenv("NV_TITLEBAR_R2_NO_REINSERT"))
            Swap([AppController class], @selector(setDualFieldIsVisible:), @selector(nv_onlyToggleToolbar:));
        for (NSArray *identifiers in @[@[], @[@"UninstalledPluginAction"], @[@"NewNote", @"Preview", @"More"]]) {
            [window makeFirstResponder:notesTableView];
            NSMutableDictionary *configuration = [[[toolbar configurationDictionary] mutableCopy] autorelease];
            [configuration setObject:identifiers forKey:@"TB Item Identifiers"];
            [configuration setObject:@NO forKey:@"TB Is Shown"];
            [toolbar setConfigurationFromDictionary:configuration]; Pump();
            NSLog(@"RESTORE identifiers=%@ realized=%@", identifiers, [[toolbar items] valueForKey:@"itemIdentifier"]);
            Check([[toolbar items] count] == 0, @"a restored configuration with no valid identifiers contains no search item");
            [self nv_r2CheckSearchWithQuery:@"State" note:note];
            [self nv_r2CheckSearchWithQuery:@"State" note:note];
            Check([dualFieldItem view] == originalContainer && field == originalField,
                @"empty-layout recovery reuses the retained container and nib field");
        }
        Check([[note.contentString string] isEqual:@"unchanged ordinary source"] && [library totalNoteCount] == 1,
            @"toolbar transitions neither edit source nor create another note");
        [originalContainer release]; [originalField release]; [note release];
        NSLog(@"TORVALDS_R2_PASS checks=%lu combinations=%lu", (unsigned long)Checks, (unsigned long)cases);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) {
        NSLog(@"TORVALDS_R2_EXCEPTION %@ %@", [exception name], [exception reason]); exit(2);
    }
}
