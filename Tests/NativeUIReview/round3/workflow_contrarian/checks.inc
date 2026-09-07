- (void)nv_activate {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ((![NSApp isActive] || [NSApp keyWindow] != window || [NSApp mainWindow] != window) &&
        [deadline timeIntervalSinceNow] > 0) Pump();
    NSLog(@"ACTIVATION active=%d key=%d main=%d browser=%d", [NSApp isActive], [NSApp keyWindow] == window,
        [NSApp mainWindow] == window, [[NVApplicationController sharedController] activeBrowser] == self);
    Check([NSApp isActive] && [NSApp keyWindow] == window && [NSApp mainWindow] == window &&
        [[NVApplicationController sharedController] activeBrowser] == self,
        @"native activation supplies the intended key window, main window, and command target");
}
- (void)nv_key:(unichar)character code:(unsigned short)code flags:(NSEventModifierFlags)flags {
    NSString *characters = [NSString stringWithCharacters:&character length:1];
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags
        timestamp:0 windowNumber:[window windowNumber] context:nil characters:characters
        charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
    [window sendEvent:event];
    Pump();
    NSLog(@"KEY code=%u modifiers=%lu row=%ld count=%ld first=%@", code, (unsigned long)flags,
        (long)[notesTableView selectedRow], (long)[notesTableView numberOfSelectedRows], NSStringFromClass([[window firstResponder] class]));
}
- (void)nv_checkSelectedRow:(NSInteger)row {
    NoteObject *expected = [[self browserSession] noteObjectAtFilteredIndex:row];
    Check([notesTableView selectedRow] == row && [notesTableView numberOfSelectedRows] == 1,
        @"arrow key selects exactly the expected row");
    Check([self selectedNoteObject] == expected && [[textView string] isEqualToString:[[expected contentString] string]],
        @"selected row, current note, and visible body agree after native arrow dispatch");
}
- (void)nv_runTests {
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        Check(SkippedSync, @"fixture suppresses sync startup explicitly");
        MakeNote(library, @"Alpha workflow", @"Alpha body marker");
        MakeNote(library, @"Beta workflow", @"Beta body marker");
        MakeNote(library, @"Gamma workflow", @"Gamma body marker");
        [self nv_activate];
        [window setContentSize:NSMakeSize(760, 580)];
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [self setSystemColorScheme:self];
        [self setNotesListHeight:160];
        [self searchForString:@""]; Pump();
        Check([notesTableView numberOfRows] == 3, @"Dark Aqua workflow fixture contains three visible notes");
        [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        Check([window makeFirstResponder:notesTableView] && [window firstResponder] == notesTableView,
            @"the native notes table owns keyboard focus");
        [self nv_checkSelectedRow:0];
        [self nv_key:NSDownArrowFunctionKey code:125 flags:NSEventModifierFlagFunction];
        [self nv_checkSelectedRow:1];
        [self nv_key:NSUpArrowFunctionKey code:126 flags:NSEventModifierFlagFunction];
        [self nv_checkSelectedRow:0];
        Check([window firstResponder] == notesTableView && [[[self browserSession] searchString] length] == 0,
            @"Down and Up preserve table focus and the empty search query");
        NSLog(@"CASE arrow-navigation PASSED");

        [self nv_activate];
        [self nv_key:NSDownArrowFunctionKey code:125 flags:NSEventModifierFlagFunction | NSEventModifierFlagShift];
        Check([[notesTableView selectedRowIndexes] isEqualToIndexSet:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]],
            @"Shift-Down extends selection from the first row to the second row");
        Check([self selectedNoteObject] == nil && ![noteTitleField isEnabled] && ![noteTagsField isEnabled],
            @"multiple selection leaves no editable single-note metadata target");
        [self nv_key:NSUpArrowFunctionKey code:126 flags:NSEventModifierFlagFunction];
        Check([notesTableView numberOfSelectedRows] == 1, @"unmodified Up restores a single selected row");
        [self nv_checkSelectedRow:[notesTableView selectedRow]];
        NoteObject *selected = [self selectedNoteObject];
        NSString *body = [[[selected contentString] string] copy];
        Check([window makeFirstResponder:notesTableView] && [window firstResponder] == notesTableView,
            @"Tab traversal starts with the native table as first responder");
        NSUInteger tabs = 0;
        while ([window firstResponder] != textView && tabs < 3) {
            [self nv_key:NSTabCharacter code:48 flags:0];
            tabs++;
            NSLog(@"TAB_PATH step=%lu destination=%@", (unsigned long)tabs,
                [window firstResponder] == textView ? @"body" :
                ([noteTitleField currentEditor] ? @"title" : ([noteTagsField currentEditor] ? @"tags" :
                ([field currentEditor] ? @"search" : NSStringFromClass([[window firstResponder] class])))));
        }
        Check([window firstResponder] == textView, @"at most three Tab keys traverse from the table through native fields into the body");
        Check([self selectedNoteObject] == selected && [[textView string] isEqualToString:body] && [library totalNoteCount] == 3,
            @"Tab preserves the selected note, its body, and the library note count");
        NSLog(@"CASE multiselection-to-body PASSED");
        [body release];

        NSRect listRect = [notesScrollView convertRect:[notesScrollView bounds] toView:nil];
        NSRect bodyRect = [textScrollView convertRect:[textScrollView bounds] toView:nil];
        NSLog(@"STACK list=%@ body=%@", NSStringFromRect(listRect), NSStringFromRect(bodyRect));
        Check(NSMinY(listRect) >= NSMaxY(bodyRect) && fabs(NSMinX(listRect) - NSMinX(bodyRect)) < 2,
            @"the notes list remains above the editor in the native window");
        NSInteger unselectedRow = [notesTableView selectedRow] == 2 ? 0 : 2;
        NSRect rowRect = NSInsetRect([notesTableView rectOfRow:unselectedRow], 4, 3);
        NSBitmapImageRep *rowBitmap = [notesTableView bitmapImageRepForCachingDisplayInRect:rowRect];
        [notesTableView cacheDisplayInRect:rowRect toBitmapImageRep:rowBitmap];
        NSUInteger white = 0, dark = 0, total = [rowBitmap pixelsWide] * [rowBitmap pixelsHigh];
        for (NSInteger y = 0; y < [rowBitmap pixelsHigh]; y++) for (NSInteger x = 0; x < [rowBitmap pixelsWide]; x++) {
            NSColor *c = [[rowBitmap colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if ([c redComponent] > .97 && [c greenComponent] > .97 && [c blueComponent] > .97) white++;
            if ([c redComponent] < .35 && [c greenComponent] < .35 && [c blueComponent] < .35) dark++;
        }
        NSLog(@"DRAWN_ROW row=%ld white=%lu dark=%lu total=%lu corner=%@", (long)unselectedRow,
            (unsigned long)white, (unsigned long)dark, (unsigned long)total, [rowBitmap colorAtX:0 y:0]);
        NSView *content = [window contentView];
        NSBitmapImageRep *bitmap = [content bitmapImageRepForCachingDisplayInRect:[content bounds]];
        [content cacheDisplayInRect:[content bounds] toBitmapImageRep:bitmap];
        NSString *path = [[NSString stringWithUTF8String:getenv("NV_WORKFLOW_ARTIFACTS")] stringByAppendingPathComponent:@"dark-keyboard-result.png"];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
            @"native populated-browser drawing writes to the review artifact");
        Check(white > total * .65 && dark > 20, @"an unselected populated base row draws white background pixels and dark title pixels under Dark Aqua");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"WORKFLOW PROBES PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
