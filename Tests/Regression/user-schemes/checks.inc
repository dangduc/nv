- (void)nv_captureSchemeWindow:(NSWindow *)captureWindow name:(NSString *)name {
    const char *directory = getenv("NV_USER_SCHEMES_ARTIFACTS");
    if (!directory) return;
    [captureWindow display]; Pump();
    CGImageRef capture = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)[captureWindow windowNumber], kCGWindowImageDefault);
    Check(capture != NULL, @"WindowServer captures the disposable scheme window");
    NSBitmapImageRep *image = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
    CGImageRelease(capture);
    NSString *path = [[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:name];
    Check([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
        @"the scheme screenshot writes successfully");
}

- (void)nv_setSchemeAppearance:(BOOL)dark {
    if (@available(macOS 10.14, *))
        [window setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
    else Check(NO, @"the User Scheme integration checks require macOS 10.14 or later");
    [window display];
    for (NSUInteger i = 0; i < 4; i++) Pump();
    // No explicit application appearance callback: the view must observe AppKit.
    Check([self usesDarkUserColorScheme] == dark, @"User Scheme follows the owning window's effective appearance");
}

- (void)nv_checkSchemeColors:(NSArray *)colors {
    NSColor *foreground = colors[0], *background = colors[1], *highlight = colors[2];
    Check(SameSchemeColor([self foregrndColor], foreground) && SameSchemeColor([self backgrndColor], background),
        @"the owning browser uses the expected User Scheme foreground and background");
    Check(SameSchemeColor([textView backgroundColor], background) &&
        SameSchemeColor([[textView enclosingScrollView] backgroundColor], background),
        @"the editor and scroll view display the owning browser background");
    NSLayoutManager *layout = [textView layoutManager];
    NSUInteger ordinary = [[textView string] rangeOfString:@"ordinary"].location;
    NSUInteger url = [[textView string] rangeOfString:@"https://example.invalid/"].location;
    Check(ordinary != NSNotFound && url != NSNotFound, @"the shared source contains ordinary text and a parsed link");
    NSColor *expectedHighlight = ExpectedHighlight(highlight, background);
    NSDate *highlightDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!SameSchemeColor([layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:ordinary effectiveRange:NULL],
        expectedHighlight) && [highlightDeadline timeIntervalSinceNow] > 0) Pump();
    NSRange range;
    NSDictionary *temporary = [layout temporaryAttributesAtCharacterIndex:ordinary effectiveRange:&range];
    NSDictionary *drawing = [textView layoutManager:layout shouldUseTemporaryAttributes:temporary
        forDrawingToScreen:YES atCharacterIndex:ordinary effectiveRange:&range];
    Check(SameSchemeColor(drawing[NSForegroundColorAttributeName], foreground),
        @"ordinary glyph drawing uses the owning browser foreground");
    Check(SameSchemeColor(temporary[NSBackgroundColorAttributeName], expectedHighlight) &&
        SameSchemeColor(drawing[NSBackgroundColorAttributeName], temporary[NSBackgroundColorAttributeName]),
        @"the real search highlight composites the selected palette over this editor background");
    temporary = [layout temporaryAttributesAtCharacterIndex:url effectiveRange:&range];
    drawing = [textView layoutManager:layout shouldUseTemporaryAttributes:temporary
        forDrawingToScreen:YES atCharacterIndex:url effectiveRange:&range];
    Check([[textView textStorage] attribute:NSLinkAttributeName atIndex:url effectiveRange:NULL] != nil &&
        SameSchemeColor(drawing[NSForegroundColorAttributeName], [textView linkTextAttributes][NSForegroundColorAttributeName]),
        @"URL drawing uses the editor's refreshed link color while retaining the URL attribute");
    Check(!SameSchemeColor([textView insertionPointColor], background), @"the caret remains distinct from the selected background");
}

- (void)nv_checkStoredSchemeColors:(NSArray *)light dark:(NSArray *)dark {
    Check(SameSchemeColor([prefsController foregroundTextColor], light[0]) &&
        SameSchemeColor([prefsController backgroundTextColor], light[1]) &&
        SameSchemeColor([prefsController searchTermHighlightColorRaw:YES], light[2]),
        @"the existing getters retain the raw light palette independently of appearance");
    Check(SameSchemeColor([prefsController darkForegroundTextColor], dark[0]) &&
        SameSchemeColor([prefsController darkBackgroundTextColor], dark[1]) &&
        SameSchemeColor([prefsController darkSearchTermHighlightColor], dark[2]),
        @"the new getters retain the independent raw dark palette and highlight alpha");
}

- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [self sharedNotationController];
        BOOL reopened = atoi(getenv("NV_REVIEW_PHASE")) == 2;
        NSArray *light = reopened ? FinalLightColors() : @[LegacyForeground(), LegacyBackground(), LegacyHighlight()];
        NSArray *dark = reopened ? FinalDarkColors() : @[[prefsController darkForegroundTextColor],
            [prefsController darkBackgroundTextColor], [prefsController darkSearchTermHighlightColor]];
        [self nv_checkStoredSchemeColors:light dark:dark];
        Check([[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"] == 2,
            @"the persisted User Scheme choice remains the existing value 2");
        if (!reopened) {
            Check(!SameSchemeColor(dark[0], light[0]) && !SameSchemeColor(dark[1], light[1]) &&
                !SameSchemeColor(dark[0], dark[1]), @"an existing installation gets an independent usable dark default palette");
        }
        [prefsController setShouldHighlightSearchTerms:YES sender:self];
        [prefsController setMakeURLsClickable:YES sender:self];
        NoteObject *note = reopened ? [[library allNotes] firstObject] : MakeNote(library,
            @"ordinary source sample", @"ordinary source text\nhttps://example.invalid/\nUser Scheme follows each window's appearance.");
        Check(note != nil && [library totalNoteCount] == 1, @"the fixture owns one disposable note across both launches");
        [note setSourceSyntaxIdentifier:@"plain"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self && [peer sharedNotationController] == library, @"two real browser windows share the same library");
        for (AppController *browser in @[self, peer]) {
            [[browser window] setContentSize:NSMakeSize(850, 600)];
            [browser setNotesListHeight:125];
            [browser setUserColorScheme:browser];
            [browser searchForString:@"ordinary" mode:@"exact"];
            [browser revealNote:note options:0]; Pump();
            Check([browser selectedNoteObject] == note, @"both search views select the shared fixture note");
        }
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        Check([textView textStorage] == [peerEditor textStorage], @"the two editors share source storage");
        [self nv_setSchemeAppearance:NO]; [peer nv_setSchemeAppearance:YES];
        [self nv_checkSchemeColors:light]; [peer nv_checkSchemeColors:dark];
        if (reopened) {
            [self nv_checkStoredSchemeColors:FinalLightColors() dark:FinalDarkColors()];
            NSLog(@"USER SCHEMES RELAUNCH PASSED (%lu checks)", (unsigned long)Checks);
            exit(0);
        }
        NSAttributedString *sourceBefore = [[[textView textStorage] copy] autorelease];
        NSAttributedString *storedBefore = [[[note contentString] copy] autorelease];
        NSUndoManager *undo = [note undoManager];
        [undo removeAllActions];
        [undo setGroupsByEvent:NO];
        NVUserSchemeUndoSentinel *sentinel = [[[NVUserSchemeUndoSentinel alloc] init] autorelease];
        [undo beginUndoGrouping]; [[undo prepareWithInvocationTarget:sentinel] mark];
        [undo setActionName:@"Scheme fixture sentinel"]; [undo endUndoGrouping];
        NSColor *lightLink = [[textView linkTextAttributes][NSForegroundColorAttributeName] retain];
        NSColor *lightCaret = [[textView insertionPointColor] retain];
        [self nv_setSchemeAppearance:YES]; [peer nv_setSchemeAppearance:NO];
        [self nv_checkSchemeColors:dark]; [peer nv_checkSchemeColors:light];
        Check(!SameSchemeColor([textView linkTextAttributes][NSForegroundColorAttributeName], lightLink) &&
            !SameSchemeColor([textView insertionPointColor], lightCaret),
            @"automatic appearance changes refresh both link and caret colors");
        [lightLink release]; [lightCaret release];
        [self nv_setSchemeAppearance:NO]; [peer nv_setSchemeAppearance:YES];
        // The shared isolation runner replaces launch before the normal Settings allocation.
        if (!prefsWindowController) prefsWindowController = [[PrefsWindowController alloc] init];
        [prefsWindowController showWindow:self];
        [prefsWindowController switchViews:[[prefsWindowController valueForKey:@"items"] objectForKey:@"Fonts & Colors"]];
        [[prefsWindowController valueForKey:@"toolbar"] setSelectedItemIdentifier:@"Fonts & Colors"];
        NSWindow *settingsWindow = [prefsWindowController valueForKey:@"window"];
        NSDate *settingsDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (![settingsWindow isKeyWindow] && [settingsDeadline timeIntervalSinceNow] > 0) Pump();
        NSArray *wellNames = @[@"foregroundColorWell", @"backgroundColorWell", @"searchHighlightColorWell",
            @"darkForegroundColorWell", @"darkBackgroundColorWell", @"darkSearchHighlightColorWell"];
        NSArray *original = [light arrayByAddingObjectsFromArray:dark];
        NSArray *replacements = [FinalLightColors() arrayByAddingObjectsFromArray:FinalDarkColors()];
        Check([settingsWindow isKeyWindow] && ![window isKeyWindow] && ![[peer window] isKeyWindow],
            @"Settings is key while both browser palettes update in inactive windows");
        for (NSUInteger i = 0; i < [wellNames count]; i++) {
            NSColorWell *well = [prefsWindowController valueForKey:wellNames[i]];
            Check(well && [well window] == settingsWindow && ![well isHiddenOrHasHiddenAncestor] &&
                SameSchemeColor([well color], original[i]), @"each visible color well starts with its own stored palette value");
            [well setColor:replacements[i]];
            Check([NSApp sendAction:[well action] to:[well target] from:well], @"the native color well dispatches its configured action");
            Pump();
            NSMutableArray *expectedLight = [[light mutableCopy] autorelease];
            NSMutableArray *expectedDark = [[dark mutableCopy] autorelease];
            for (NSUInteger changed = 0; changed <= i; changed++) {
                if (changed < 3) expectedLight[changed] = replacements[changed];
                else expectedDark[changed - 3] = replacements[changed];
            }
            [self nv_checkStoredSchemeColors:expectedLight dark:expectedDark];
            [self nv_checkSchemeColors:expectedLight]; [peer nv_checkSchemeColors:expectedDark];
        }
        [settingsWindow setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [self nv_captureSchemeWindow:settingsWindow name:@"settings-light.png"];
        if (@available(macOS 10.14, *)) [settingsWindow setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [self nv_captureSchemeWindow:settingsWindow name:@"settings-dark.png"];
        [settingsWindow orderOut:self];
        [self nv_activateBrowser];
        [self nv_captureSchemeWindow:window name:@"source-light.png"];
        [peer nv_activateBrowser];
        [self nv_captureSchemeWindow:[peer window] name:@"source-dark.png"];
        Check([[textView textStorage] isEqualToAttributedString:sourceBefore],
            @"appearance and all six settings actions preserve the shared source attributes");
        Check([[note contentString] isEqualToAttributedString:storedBefore],
            @"appearance and all six settings actions preserve the stored note attributes");
        Check([undo canUndo] && [[undo undoActionName] isEqualToString:@"Scheme fixture sentinel"],
            @"palette changes preserve the pre-existing Undo action");
        [undo undo];
        Check(SchemeUndoCallbacks == 1 && ![undo canUndo], @"palette changes add no source Undo actions");
        Check([[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"] == 2 &&
            [[self valueForKey:@"userScheme"] integerValue] == 2 && [[peer valueForKey:@"userScheme"] integerValue] == 2,
            @"both palettes remain one unchanged User Scheme menu choice");
        Check([library flushAllNoteChanges], @"the shared note checkpoints before relaunch");
        [library flushEverything]; [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"USER SCHEMES FIRST LAUNCH PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
