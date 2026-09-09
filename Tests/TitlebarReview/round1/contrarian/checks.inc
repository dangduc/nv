- (void)nv_contrarianWaitForSearch {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check([[self browserSession] searchResultsAreCurrent] && ![[self browserSession] searchError],
        @"search accepts a complete result before interaction assertions");
}
- (NSMenuItem *)nv_contrarianMenuItem:(SEL)action {
    NSMutableArray *menus = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
    for (NSUInteger i = 0; i < [menus count]; i++) for (NSMenuItem *item in [[menus objectAtIndex:i] itemArray]) {
        if ([item action] == action) return item;
        if ([item submenu]) [menus addObject:[item submenu]];
    }
    return nil;
}
- (void)nv_contrarianDispatch:(SEL)action {
    NSMenuItem *item = [self nv_contrarianMenuItem:action];
    Check(item != nil, [NSString stringWithFormat:@"menu retains %@", NSStringFromSelector(action)]);
    [[item menu] update];
    Check([item isEnabled] && [NSApp sendAction:action to:[item target] from:item],
        [NSString stringWithFormat:@"native menu dispatches %@", NSStringFromSelector(action)]);
    Pump();
}
- (void)nv_contrarianSelectMode:(NSString *)mode {
    NSMenu *menu = [(NSSearchFieldCell *)[field cell] searchMenuTemplate];
    NSMenuItem *target = nil;
    for (NSMenuItem *item in [menu itemArray]) if ([[item representedObject] isEqual:mode]) target = item;
    Check(target != nil && [target target] == self && [target action] == @selector(selectSearchMode:),
        @"the native magnifying-glass menu retains the browser-specific mode command");
    Check([NSApp sendAction:[target action] to:[target target] from:target], @"mode selection dispatch succeeds");
    [self nv_contrarianWaitForSearch];
    Check([[self searchMode] isEqual:mode] && [field currentEditor] != nil,
        @"switching mode preserves native search editing");
    NSUInteger checked = 0;
    for (NSMenuItem *item in [[(NSSearchFieldCell *)[field cell] searchMenuTemplate] itemArray]) {
        if ([item state] == NSControlStateValueOn) {
            checked++;
            Check([[item representedObject] isEqual:mode], @"the requested search mode owns the native menu check");
        }
    }
    Check(checked == 1, @"search mode remains a single checked choice");
    Check([[field accessibilityLabel] isEqual:[field placeholderString]] &&
        [[[field accessibilityLabel] lowercaseString] containsString:mode],
        @"accessible search name announces the selected mode");
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        [self nv_activateBrowser];
        NoteObject *alpha = [MakeNote(library, @"Corpus Alpha", @"one thousand words") retain];
        NoteObject *beta = [MakeNote(library, @"Corpus Beta", @"ordinary content") retain];
        [prefsController setAutoCompleteSearches:NO sender:nil];
        [prefsController setShowTitleInTopSection:NO sender:nil];
        [prefsController setShowTagsInTopSection:NO sender:nil];
        [prefsController setShowBodyControlsInTopSection:NO sender:nil];
        [prefsController setShowNotesList:NO sender:nil];
        [window setContentSize:NSMakeSize(480, 420)]; Pump();
        Check([noteTitleField isHidden] && [noteTagsField isHidden] && [bodyModeControl isHidden] &&
            ![prefsController showNotesList], @"fixture hides all note header controls and the notes list");
        [self searchForString:@"tousand" mode:@"exact"]; [self nv_contrarianWaitForSearch];
        Check([[self browserSession] resultCount] == 0, @"literal negative control rejects a noncontiguous body query");
        [self nv_contrarianSelectMode:@"fuzzy"];
        Check([[[self browserSession] searchString] isEqual:@"tousand"] &&
            [[self browserSession] resultCount] == 1 && [[self browserSession] noteObjectAtFilteredIndex:0] == alpha,
            @"fuzzy mode finds the body-only subsequence with every other control hidden");
        [self nv_contrarianSelectMode:@"exact"];
        Check([[[self browserSession] searchString] isEqual:@"tousand"] && [[self browserSession] resultCount] == 0,
            @"switching back to Exact preserves query and removes the fuzzy-only row");
        NSUInteger noteCount = [library totalNoteCount];
        [[(NSSearchFieldCell *)[field cell] cancelButtonCell] performClick:field];
        [self nv_contrarianWaitForSearch];
        Check([[field stringValue] length] == 0 && [[[self browserSession] searchString] length] == 0 &&
            [library totalNoteCount] == noteCount, @"native clear button clears both query models without creating a note");
        // The nib uses cell-based accessibility: AppKit ignores the view and exposes its search cell.
        NSArray *children = [[field superview] accessibilityChildren];
        id accessibleSearch = [children firstObject];
        NSLog(@"ACCESSIBILITY exposed=%@ role=%@ subrole=%@", accessibleSearch,
            [accessibleSearch accessibilityAttributeValue:NSAccessibilityRoleAttribute],
            [accessibleSearch accessibilityAttributeValue:NSAccessibilitySubroleAttribute]);
        Check([children count] == 1 && accessibleSearch == [field cell] &&
            [[accessibleSearch accessibilityAttributeValue:NSAccessibilityRoleAttribute] isEqual:NSAccessibilityTextFieldRole] &&
            [[accessibleSearch accessibilityAttributeValue:NSAccessibilitySubroleAttribute] isEqual:NSAccessibilitySearchFieldSubrole],
            @"search remains an accessible native search text field inside the new generic container");
        [self searchForString:@"" mode:@"exact"]; [self revealNote:alpha options:0]; Pump();
        Check([window titleVisibility] == NSWindowTitleHidden, @"the selected note title remains visually hidden");
        if (getenv("NV_CONTRARIAN_NEGATIVE")) [window setTitle:@""];
        Check([[window title] isEqual:@"Corpus Alpha"] && [[window accessibilityTitle] isEqual:@"Corpus Alpha"],
            @"visually hidden title retains the selected note identity for accessibility");
        [self bringFocusToControlField:self]; Pump();
        [(id)[field currentEditor] doCommandBySelector:@selector(insertTab:)]; Pump();
        Check([window firstResponder] == textView, @"Tab reaches editable source with the notes list and header hidden");
        [self nv_contrarianDispatch:@selector(toggleSourcePreview:)];
        Check([self isViewingNote], @"View menu opens Preview when its removed icon and header toggle are absent");
        [self nv_contrarianDispatch:@selector(toggleSourcePreview:)];
        Check(![self isViewingNote] && [window firstResponder] == textView,
            @"View menu returns to editable source with all alternate controls hidden");
        [self searchForString:@"Created From Search" mode:@"exact"]; [self nv_contrarianWaitForSearch];
        [(id)[field currentEditor] doCommandBySelector:@selector(insertNewline:)]; Pump();
        Check([library totalNoteCount] == noteCount + 1 &&
            [titleOfNote([self selectedNoteObject]) isEqual:@"Created From Search"] && [window firstResponder] == textView,
            @"Return creates and focuses a source note while every other note control is hidden");
        [self searchForString:@"" mode:@"exact"]; [self revealNote:beta options:0]; Pump();
        Check([[window accessibilityTitle] isEqual:@"Corpus Beta"] && [window titleVisibility] == NSWindowTitleHidden,
            @"semantic window title follows note changes while visual title stays hidden");
        Check([[[alpha contentString] string] isEqual:@"one thousand words"] &&
            [[[beta contentString] string] isEqual:@"ordinary content"], @"source characters survive all search and hidden-control operations");
        [alpha release]; [beta release];
        NSLog(@"CONTRARIAN_REVIEW_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) {
        NSLog(@"CONTRARIAN_REVIEW_EXCEPTION %@ %@", [exception name], [exception reason]); exit(2);
    }
}
