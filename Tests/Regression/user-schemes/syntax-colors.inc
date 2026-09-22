- (void)nv_captureSyntaxWindow:(NSWindow *)captureWindow name:(NSString *)name {
    const char *directory = getenv("NV_USER_SCHEMES_ARTIFACTS");
    if (!directory) return;
    [captureWindow display]; Pump();
    CGImageRef capture = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)[captureWindow windowNumber], kCGWindowImageDefault);
    Check(capture != NULL, @"WindowServer captures the syntax settings");
    NSBitmapImageRep *image = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
    CGImageRelease(capture);
    NSString *path = [[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:name];
    Check([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
        @"the syntax settings screenshot writes successfully");
}

- (void)nv_checkSyntaxEditor:(LinkingEditor *)editor dark:(BOOL)dark custom:(BOOL)custom {
    NSArray *captures = @[@"comment", @"string.special.key", @"string", @"number", @"text.title", @"punctuation", @"escape"];
    for (NSUInteger kind = 0; kind < NVSyntaxColorCount; kind++) {
        NSColor *expected = custom ? CustomSyntaxColor(kind, dark) : [prefsController defaultSyntaxColorForKind:kind darkBackground:dark];
        Check(SameSchemeColor([editor sourceColorForCapture:captures[kind]], expected),
            [NSString stringWithFormat:@"%@ uses the %@ %@ palette", captures[kind], dark ? @"dark" : @"light", custom ? @"custom" : @"default"]);
    }
    Check([editor sourceColorForCapture:nil] == nil && [editor sourceColorForCapture:@"none"] == nil,
        @"uncaptured source keeps its normal foreground color");
    Check(SameSchemeColor([editor sourceColorForCapture:@"attribute"], [editor sourceColorForCapture:@"string.special.key"]) &&
        SameSchemeColor([editor sourceColorForCapture:@"constant.builtin"], [editor sourceColorForCapture:@"number"]) &&
        SameSchemeColor([editor sourceColorForCapture:@"tag"], [editor sourceColorForCapture:@"text.title"]) &&
        SameSchemeColor([editor sourceColorForCapture:@"text.literal"], [editor sourceColorForCapture:@"string"]),
        @"capture aliases retain their syntax color categories");
    NSUInteger key = [[editor string] rangeOfString:@"title"].location;
    NSLayoutManager *layout = [editor layoutManager];
    NSRange range;
    NSDictionary *temporary = [layout temporaryAttributesAtCharacterIndex:key effectiveRange:&range];
    Check([temporary[NVSourceCaptureAttributeName] isEqual:@"string.special.key"], @"the production parser supplies a real key capture");
    NSDictionary *drawing = [editor layoutManager:layout shouldUseTemporaryAttributes:temporary
        forDrawingToScreen:YES atCharacterIndex:key effectiveRange:&range];
    Check(SameSchemeColor(drawing[NSForegroundColorAttributeName], [editor sourceColorForCapture:@"string.special.key"]),
        @"TextKit draws the parsed key with the selected palette");
}

- (void)nv_runTests {
    @try {
        BOOL reopened = atoi(getenv("NV_REVIEW_PHASE")) == 2;
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [self sharedNotationController];
        // Exercise both syntax palettes; Dark appearance now defaults to a light background.
        [prefsController setDarkBackgroundTextColor:[NSColor colorWithCalibratedWhite:0.10 alpha:1.0] sender:self];
        NoteObject *note = reopened ? [[library allNotes] firstObject] : MakeNote(library, @"Syntax color sample",
            @"{\n  \"title\": \"ordinary source text\",\n  \"count\": 42,\n  \"enabled\": true\n}");
        [note setSourceSyntaxIdentifier:@"json"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        NSAppearance *darkAppearance = nil;
        if (@available(macOS 10.14, *)) darkAppearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        Check(darkAppearance != nil, @"the syntax palette probe requires Dark Aqua support");
        for (AppController *browser in @[self, peer]) {
            [[browser window] setAppearance:browser == self ? [NSAppearance appearanceNamed:NSAppearanceNameAqua] : darkAppearance];
            [browser setUserColorScheme:self];
            [browser revealNote:note options:0];
        }
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while ((!NVSourceCapturesAreCurrent([textView layoutManager]) || !NVSourceCapturesAreCurrent([peerEditor layoutManager])) &&
            [deadline timeIntervalSinceNow] > 0) Pump();
        [self nv_checkSyntaxEditor:textView dark:NO custom:reopened];
        [self nv_checkSyntaxEditor:peerEditor dark:YES custom:reopened];
        NSAttributedString *sourceBefore = [[[textView textStorage] copy] autorelease];
        NSAttributedString *storedBefore = [[[note contentString] copy] autorelease];
        NSUndoManager *undo = [note undoManager];
        [undo removeAllActions];
        [undo setGroupsByEvent:NO];
        NVUserSchemeUndoSentinel *sentinel = [[[NVUserSchemeUndoSentinel alloc] init] autorelease];
        [undo beginUndoGrouping]; [[undo prepareWithInvocationTarget:sentinel] mark];
        [undo setActionName:@"Syntax fixture sentinel"]; [undo endUndoGrouping];
        if (!prefsWindowController) prefsWindowController = [[PrefsWindowController alloc] init];
        [prefsWindowController showWindow:self];
        [prefsWindowController switchViews:[[prefsWindowController valueForKey:@"items"] objectForKey:@"Fonts & Colors"]];
        NSWindow *settings = [prefsWindowController valueForKey:@"window"];
        NSView *pane = [prefsWindowController valueForKey:@"fontsColorsView"];
        NSButton *syntaxButton = nil;
        for (NSView *view in [pane subviews]) {
            if ([view isKindOfClass:[NSButton class]] && [(NSButton *)view action] == @selector(showSyntaxColors:)) syntaxButton = (NSButton *)view;
        }
        Check(syntaxButton && ![syntaxButton isHiddenOrHasHiddenAncestor] && NSContainsRect([pane bounds], [syntaxButton frame]),
            @"Fonts & Colors contains a visible Syntax Colors button");
        [syntaxButton performClick:self]; Pump();
        NSWindow *sheet = [prefsWindowController valueForKey:@"syntaxColorsSheet"];
        NSArray *wells = [prefsWindowController valueForKey:@"syntaxColorWells"];
        Check([sheet sheetParent] == settings && [wells count] == 14, @"the syntax sheet contains the complete two-column matrix");
        for (NSColorWell *well in wells) {
            NSUInteger index = [well tag], kind = index % NVSyntaxColorCount;
            BOOL dark = index >= NVSyntaxColorCount;
            NSColor *expected = reopened ? CustomSyntaxColor(kind, dark) : [prefsController defaultSyntaxColorForKind:kind darkBackground:dark];
            Check([well window] == sheet && NSContainsRect([[sheet contentView] bounds], [well frame]) &&
                ![well isHiddenOrHasHiddenAncestor] && SameSchemeColor([well color], expected),
                @"each syntax well displays the saved color within the visible sheet");
        }
        if (!reopened) {
            [settings setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
            [self nv_captureSyntaxWindow:sheet name:@"syntax-settings-light.png"];
            [settings setAppearance:darkAppearance];
            [self nv_captureSyntaxWindow:sheet name:@"syntax-settings-dark.png"];
            for (NSColorWell *well in wells) {
                NSUInteger index = [well tag], kind = index % NVSyntaxColorCount;
                BOOL dark = index >= NVSyntaxColorCount;
                [textView display]; [peerEditor display];
                [well setColor:CustomSyntaxColor(kind, dark)];
                SyntaxRedrawnEditors = [[NSMutableSet alloc] init];
                Check([NSApp sendAction:[well action] to:[well target] from:well], @"the syntax well dispatches its real preference action");
                Check([SyntaxRedrawnEditors containsObject:[NSValue valueWithPointer:textView]] &&
                    [SyntaxRedrawnEditors containsObject:[NSValue valueWithPointer:peerEditor]], @"a palette edit requests redraw in both inactive editors");
                [SyntaxRedrawnEditors release]; SyntaxRedrawnEditors = nil;
                Check(SameSchemeColor([prefsController syntaxColorForKind:kind darkBackground:dark], CustomSyntaxColor(kind, dark)),
                    @"each action updates its own persisted category");
                Check(SameSchemeColor([prefsController syntaxColorForKind:kind darkBackground:!dark],
                    dark ? CustomSyntaxColor(kind, NO) : [prefsController defaultSyntaxColorForKind:kind darkBackground:YES]),
                    @"editing one column preserves the other column");
            }
            [self nv_checkSyntaxEditor:textView dark:NO custom:YES];
            [self nv_checkSyntaxEditor:peerEditor dark:YES custom:YES];
            NSColorWell *panelWell = [wells firstObject];
            [panelWell activate:YES];
            [[NSColorPanel sharedColorPanel] setColor:[NSColor magentaColor]]; Pump();
            Check(SameSchemeColor([prefsController syntaxColorForKind:NVSyntaxColorComment darkBackground:NO], [NSColor magentaColor]),
                @"the native color panel edits the active syntax well while its sheet is open");
            [[NSColorPanel sharedColorPanel] setColor:CustomSyntaxColor(NVSyntaxColorComment, NO)]; Pump();
            [panelWell deactivate]; [[NSColorPanel sharedColorPanel] orderOut:self];
            // The actual editor background controls syntax brightness, even under Dark Aqua.
            NSColor *darkBackground = [[prefsController darkBackgroundTextColor] retain];
            [prefsController setDarkBackgroundTextColor:[NSColor whiteColor] sender:self]; Pump();
            [self nv_checkSyntaxEditor:peerEditor dark:NO custom:YES];
            [prefsController setDarkBackgroundTextColor:darkBackground sender:self]; [darkBackground release]; Pump();
            [self setBWColorScheme:self];
            [self nv_checkSyntaxEditor:textView dark:NO custom:NO];
            [self setLCColorScheme:self];
            [self nv_checkSyntaxEditor:textView dark:NO custom:NO];
            [self setSystemColorScheme:self];
            [self nv_checkSyntaxEditor:textView dark:NO custom:NO];
            [self setUserColorScheme:self];
            [self nv_checkSyntaxEditor:textView dark:NO custom:YES];
        } else {
            NSButton *reset = nil;
            for (NSView *view in [[sheet contentView] subviews]) {
                if ([view isKindOfClass:[NSButton class]] && [(NSButton *)view action] == @selector(resetSyntaxColors:)) reset = (NSButton *)view;
            }
            Check(reset != nil, @"the syntax sheet offers Restore Syntax Defaults");
            [reset performClick:self];
            [self nv_checkSyntaxEditor:textView dark:NO custom:NO];
            [self nv_checkSyntaxEditor:peerEditor dark:YES custom:NO];
            for (NSColorWell *well in wells) Check(SameSchemeColor([well color],
                [prefsController defaultSyntaxColorForKind:[well tag] % NVSyntaxColorCount darkBackground:[well tag] >= NVSyntaxColorCount]),
                @"restoring syntax defaults refreshes every well");
            Check(SameSchemeColor([prefsController foregroundTextColor], LegacyForeground()) &&
                SameSchemeColor([prefsController backgroundTextColor], LegacyBackground()) &&
                SameSchemeColor([prefsController searchTermHighlightColorRaw:YES], LegacyHighlight()),
                @"restoring syntax defaults preserves the other custom colors");
        }
        [prefsWindowController closeSyntaxColors:self]; Pump();
        Check([sheet sheetParent] == nil && ![sheet isVisible], @"Done removes the syntax sheet");
        [syntaxButton performClick:self]; Pump();
        Check([sheet sheetParent] == settings, @"the existing syntax sheet can reopen");
        for (NSColorWell *well in wells) Check(SameSchemeColor([well color],
            [prefsController syntaxColorForKind:[well tag] % NVSyntaxColorCount darkBackground:[well tag] >= NVSyntaxColorCount]),
            @"reopening refreshes syntax wells from preferences");
        [prefsWindowController closeSyntaxColors:self]; [settings close]; Pump();
        Check([[textView textStorage] isEqualToAttributedString:sourceBefore] && [[note contentString] isEqualToAttributedString:storedBefore],
            @"syntax palette changes preserve source and stored note attributes");
        Check(NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([peerEditor layoutManager]),
            @"palette changes preserve valid parser captures");
        Check([undo canUndo] && [[undo undoActionName] isEqual:@"Syntax fixture sentinel"], @"syntax palette changes preserve the Undo action");
        [undo undo];
        Check(SchemeUndoCallbacks == 1 && ![undo canUndo], @"syntax palette changes add no Undo actions");
        Check([library flushAllNoteChanges], @"the syntax fixture checkpoints before relaunch");
        [library flushEverything]; [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"SYNTAX COLORS %@ PASSED (%lu checks)", reopened ? @"RELAUNCH" : @"FIRST LAUNCH", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
