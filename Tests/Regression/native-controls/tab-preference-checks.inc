- (void)nv_checkTabPreferenceWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL oldIndent = [prefsController tabKeyIndents];
    BOOL oldPlacement = [prefsController searchInTitleBar];
    NSString *oldPane = [[prefsController lastSelectedPreferencesPane] copy];
    NSString *originalSource = [[[alpha contentString] string] copy];
    Check(oldIndent, @"Tab defaults to Indent lines in a new preferences domain");

    // Load Settings with the original nvALT key already saved as the other choice.
    [defaults setBool:NO forKey:@"TabKeyIndents"];
    [self showPreferencesWindow:self]; Pump();
    NSMatrix *matrix = [prefsWindowController valueForKey:@"tabKeyRadioMatrix"];
    NSWindow *settings = [prefsWindowController valueForKey:@"window"];
    NSToolbarItem *editing = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Editing"] autorelease];
    [[settings toolbar] setSelectedItemIdentifier:@"Editing"];
    [prefsWindowController switchViews:editing]; Pump();
    Check([matrix numberOfRows] == 2 && [matrix selectedRow] == 1 && ![prefsController tabKeyIndents],
        @"Settings honors the saved legacy TabKeyIndents choice");

    for (NSInteger row = 0; row < 2; row++) {
        [matrix selectCellAtRow:row column:0];
        Check([matrix sendAction:[matrix action] to:[matrix target]], @"the Tab radio dispatches its Settings action");
        [defaults synchronize];
        NSDictionary *saved = [defaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        Check([prefsController tabKeyIndents] == (row == 0) && [saved[@"TabKeyIndents"] boolValue] == (row == 0),
            @"each radio choice persists under the original preference key");
        [settings orderOut:self]; [prefsWindowController showWindow:self]; Pump();
        Check([matrix selectedRow] == row, @"reopening Settings retains the selected Tab radio");
    }
    [matrix selectCellAtRow:0 column:0]; [matrix sendAction:[matrix action] to:[matrix target]];
    const char *artifacts = getenv("NV_UI_ARTIFACTS");
    if (artifacts) {
        [settings displayIfNeeded]; Pump();
        CGImageRef capture = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
            (CGWindowID)[settings windowNumber], kCGWindowImageBoundsIgnoreFraming);
        Check(capture != NULL, @"the desktop captures the Editing settings");
        NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
        CGImageRelease(capture);
        NSString *path = [[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:@"tab-key-settings.png"];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
            @"the Editing settings screenshot is saved");
    }
    [settings orderOut:self];
    [prefsController setLastSelectedPreferencesPane:oldPane sender:self]; [oldPane release];
    [self setViewingNote:NO]; [peer setViewingNote:NO];
    [self searchForString:@""]; [self revealNote:alpha options:0];
    [peer searchForString:@""]; [peer revealNote:alpha options:0];
    LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
    Check([textView textStorage] == [peerEditor textStorage], @"Tab checks share one source between two browser windows");
    [self nv_activateBrowser];

    for (NSNumber *placement in @[@NO, @YES]) {
        [prefsController setSearchInTitleBar:[placement boolValue] sender:nil];
        for (NSNumber *indent in @[@YES, @NO]) {
            [prefsController setTabIndenting:[indent boolValue] sender:nil];
            [self focusNoteBody];
            [textView insertText:@"alpha\nbeta" replacementRange:NSMakeRange(0, [[textView string] length])];
            [textView setSelectedRange:NSMakeRange(2, 0)];
            [self nv_sendFocusKey:NSTabCharacter keyCode:kVK_Tab modifiers:0];
            if ([indent boolValue]) {
                Check([[textView string] isEqual:@"al\tpha\nbeta"] && [window firstResponder] == textView,
                    @"Indent lines inserts a literal tab at the caret and keeps body focus");
            } else {
                Check([[textView string] isEqual:@"alpha\nbeta"] && [self searchFieldHasFocus],
                    @"Move typing focus sends body Tab to Search without editing text");
                [self nv_sendFocusKey:NSTabCharacter keyCode:kVK_Tab modifiers:0];
                Check([window firstResponder] == textView, @"Search Tab returns to the selected body");
            }
            [textView setSelectedRange:NSMakeRange(0, [[textView string] length])];
            NSString *before = [[textView string] copy];
            NSString *expected = [@"\t" stringByAppendingString:[before stringByReplacingOccurrencesOfString:@"\n" withString:@"\n\t"]];
            [self nv_sendFocusKey:NSTabCharacter keyCode:kVK_Tab modifiers:NSEventModifierFlagOption];
            Check([[textView string] isEqual:expected] && [[peerEditor string] isEqual:expected] &&
                [window firstResponder] == textView, @"Option-Tab indents all selected lines in either mode and updates the peer");
            [textView undo:self]; Pump();
            Check([[textView string] isEqual:before] && [[peerEditor string] isEqual:before],
                @"one Undo reverses the entire block indentation in both windows");
            [textView redo:self]; Pump();
            Check([[textView string] isEqual:expected], @"one Redo restores the entire block indentation");
            [before release];
            [self nv_pressShiftTab];
            Check([self searchFieldHasFocus], @"body Shift-Tab moves backward in either Tab preference mode");
            [self nv_pressShiftTab];
            Check([window firstResponder] == textView && [[textView string] isEqual:expected],
                @"Search Shift-Tab returns to the body without indenting in either mode");
        }
    }

    [prefsController setTabIndenting:YES sender:nil];
    // Explicit expected strings cover logical line boundaries rather than wrapping or implementation details.
    NSArray *fixtures = @[
        @[@"abc", @1, @1, @"a\tc", @2, @0],
        @[@"a\nb\nc", @0, @2, @"\ta\nb\nc", @1, @2],
        @[@"a\nb\nc", @1, @3, @"\ta\n\tb\nc", @2, @4],
        @[@"a\r\nb\r\nc", @0, @6, @"\ta\r\n\tb\r\nc", @1, @7],
        @[@"a\r\nb", @2, @2, @"\ta\r\n\tb", @3, @3],
        @[@"a\r\nb", @0, @2, @"\ta\r\nb", @1, @2],
        @[@"\n\na\n", @0, @4, @"\t\n\t\n\ta\n", @1, @6],
        @[@"😀é\nβ", @2, @3, @"\t😀é\n\tβ", @3, @4],
        @[@"a\u2028b", @0, @3, @"\ta\u2028\tb", @1, @4],
        @[@"a\n", @2, @0, @"a\n\t", @3, @0]
    ];
    for (NSArray *fixture in fixtures) {
        [textView insertText:fixture[0] replacementRange:NSMakeRange(0, [[textView string] length])];
        [textView setSelectedRange:NSMakeRange([fixture[1] unsignedIntegerValue], [fixture[2] unsignedIntegerValue])];
        [self nv_sendFocusKey:NSTabCharacter keyCode:kVK_Tab modifiers:0];
        Check([[textView string] isEqual:fixture[3]] && [[[alpha contentString] string] isEqual:fixture[3]],
            [NSString stringWithFormat:@"Tab preserves source characters and line endings for %@", fixture[0]]);
        Check(NSEqualRanges([textView selectedRange], NSMakeRange([fixture[4] unsignedIntegerValue], [fixture[5] unsignedIntegerValue])),
            @"Tab keeps the caret or selection on the indented text");
    }
    [prefsController setTabIndenting:NO sender:nil];
    [peer nv_activateBrowser]; [peer focusNoteBody];
    [peer nv_sendFocusKey:NSTabCharacter keyCode:kVK_Tab modifiers:0];
    Check([peer searchFieldHasFocus], @"a preference change applies to an already open peer window");
    [self nv_activateBrowser]; [self focusNoteBody];
    [textView insertText:originalSource replacementRange:NSMakeRange(0, [[textView string] length])];
    [originalSource release];
    [peer searchForString:@"Beta"]; [peer revealNote:beta options:0];
    [prefsController setTabIndenting:oldIndent sender:nil];
    [prefsController setSearchInTitleBar:oldPlacement sender:nil];
    [self searchForString:@"al" mode:@"exact"]; [self revealNote:alpha options:0];
}
