- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [self sharedNotationController];
        if (@available(macOS 11.0, *)) Check(YES, @"the native dynamic-color oracle is available");
        else Check(NO, @"the native dynamic-color oracle is available");
        NSColor *foreground = [NSColor textColor];
        NSColor *background = [NSColor textBackgroundColor];
        NSColorList *systemColors = [NSColorList colorListNamed:@"System"];
        NSColor *highlight = [systemColors colorWithKey:@"selectedTextBackgroundColor"];
        Check([[NSColorList availableColorLists] containsObject:systemColors] && highlight != nil,
            @"the named highlight is selectable from an available native Color Panel list");
        [prefsController setForegroundTextColor:foreground sender:self];
        [prefsController setBackgroundTextColor:background sender:self];
        [prefsController setSearchTermHighlightColor:highlight sender:self];
        [prefsController setDarkForegroundTextColor:foreground sender:self];
        [prefsController setDarkBackgroundTextColor:background sender:self];
        [prefsController setDarkSearchTermHighlightColor:highlight sender:self];
        [prefsController setShouldHighlightSearchTerms:YES sender:self];
        Check([[prefsController foregroundTextColor] type] == NSColorTypeCatalog &&
            [[prefsController darkBackgroundTextColor] type] == NSColorTypeCatalog,
            @"native named foreground and background survive archive-backed preference setters");
        NoteObject *note = MakeNote(library, @"Dynamic color sample", @"ordinary needle text");
        [note setSourceSyntaxIdentifier:@"plain"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"a real peer browser exists");
        for (AppController *browser in @[self, peer]) {
            [[browser window] setAppearance:nil];
            [browser setUserColorScheme:browser];
            [browser searchForString:@"needle" mode:@"exact"];
            [browser revealNote:note options:0];
        }
        if (!prefsWindowController) prefsWindowController = [[PrefsWindowController alloc] init];
        [prefsWindowController showWindow:self];
        [prefsWindowController switchViews:[[prefsWindowController valueForKey:@"items"] objectForKey:@"Fonts & Colors"]];
        NSColorPanel *panel = [NSColorPanel sharedColorPanel];
        [panel setMode:NSColorPanelModeColorList];
        NSColorWell *well = [prefsWindowController valueForKey:@"darkSearchHighlightColorWell"];
        [well activate:YES];
        [panel setColor:[NSColor redColor]]; Pump();
        Check(NVDynamicSameColor([prefsController darkSearchTermHighlightColor], [NSColor redColor]),
            @"the native color panel changes the active dark highlight well");
        [panel setColor:highlight]; Pump();
        Check([[prefsController darkSearchTermHighlightColor] type] == NSColorTypeCatalog &&
            [[[prefsController darkSearchTermHighlightColor] colorNameComponent] isEqual:@"selectedTextBackgroundColor"],
            @"the native color panel stores the selected System catalog color in the new dark slot");
        [well deactivate]; [panel orderOut:self];
        [[prefsWindowController valueForKey:@"window"] orderOut:self];
        NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        NSAppearance *dark = nil;
        if (@available(macOS 10.14, *)) dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSLog(@"ORACLE: foreground light=%@ dark=%@ highlight light=%@ dark=%@", NVDynamicResolvedColor(foreground, light),
            NVDynamicResolvedColor(foreground, dark), NVDynamicResolvedColor(highlight, light), NVDynamicResolvedColor(highlight, dark));
        Check(!NVDynamicSameColor(NVDynamicResolvedColor(foreground, light), NVDynamicResolvedColor(foreground, dark)) &&
            !NVDynamicSameColor(NVDynamicResolvedColor(highlight, light), NVDynamicResolvedColor(highlight, dark)),
            @"the chosen native foreground and highlight actually differ by appearance");
        NSAttributedString *before = [[[textView textStorage] copy] autorelease];
        NSUInteger needle = [[textView string] rangeOfString:@"needle"].location;
        NSUInteger mismatches = 0;
        for (NSUInteger transition = 0; transition < 4; transition++) {
            NSAppearance *appearance = transition % 2 ? dark : light;
            [NSApp setAppearance:appearance];
            for (AppController *browser in @[self, peer]) [[browser window] display];
            for (NSUInteger i = 0; i < 3; i++) Pump();
            for (AppController *browser in @[self, peer]) {
                LinkingEditor *editor = [browser valueForKey:@"textView"];
                NSColor *expectedBackground = NVDynamicResolvedColor(background, appearance);
                Check(NVDynamicSameColor([browser backgrndColor], expectedBackground) &&
                    NVDynamicSameColor([browser foregrndColor], NVDynamicResolvedColor(foreground, appearance)),
                    @"both native named palette channels resolve under the inherited appearance");
                NSColor *expected = NVDynamicExpectedHighlight(highlight, expectedBackground, appearance);
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
                NSColor *actual = nil;
                do {
                    actual = [[editor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:needle effectiveRange:NULL];
                    if (NVDynamicSameColor(actual, expected)) break;
                    Pump();
                } while ([deadline timeIntervalSinceNow] > 0);
                NSLog(@"OBSERVATION: app=%@ window=%@ expected-highlight=%@ actual-highlight=%@", [appearance name],
                    [[[browser window] effectiveAppearance] name], expected, actual);
                if (NVDynamicSameColor(actual, expected))
                    Check(YES, @"the asynchronous Exact highlight resolves the named color under the inherited appearance");
                else {
                    mismatches++;
                    NSLog(@"MISMATCH: the asynchronous Exact highlight used the wrong native appearance");
                }
            }
        }
        Check([[textView textStorage] isEqualToAttributedString:before], @"native named-color transitions preserve shared source attributes");
        NSLog(@"DYNAMIC HIGHLIGHT RESULT: %lu appearance mismatches", (unsigned long)mismatches);
        Check(mismatches == 0, @"every asynchronous named highlight resolves under its browser's current appearance");
        NSLog(@"DYNAMIC USER SCHEME PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
