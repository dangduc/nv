- (void)nv_cWaitForHighlightState:(BOOL)enabled browsers:(NSArray *)browsers at:(NSUInteger)index {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    BOOL valid = NO;
    while (!valid && [deadline timeIntervalSinceNow] > 0) {
        Pump(); valid = YES;
        for (AppController *browser in browsers)
            if ((ContrarianHighlight(browser, index) != nil) != enabled) valid = NO;
    }
    Check(valid, enabled ? @"both real search views restore their source decorations" :
        @"the global checkbox removes source decorations from both real search views");
}

- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NoteObject *note = MakeNote([self sharedNotationController], @"needle palette controls", @"prefix needle suffix");
        [note setSourceSyntaxIdentifier:@"plain"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"the fixture creates a second real browser");
        NSArray *browsers = @[self, peer];
        for (AppController *browser in browsers) {
            [browser searchForString:@"needle" mode:@"exact"];
            [browser revealNote:note options:0];
            [browser setUserColorScheme:browser];
        }
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [[peer window] setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [prefsController setShouldHighlightSearchTerms:YES sender:nil];
        NSUInteger match = [[textView string] rangeOfString:@"needle"].location;
        Check(match != NSNotFound && [textView textStorage] == [[peer valueForKey:@"textView"] textStorage],
            @"opposite-appearance browsers share the real searched source");
        [self nv_cWaitForHighlightState:YES browsers:browsers at:match];
        NSAttributedString *beforeSource = [[[textView textStorage] copy] autorelease];
        PrefsWindowController *settings = [[[PrefsWindowController alloc] init] autorelease];
        [settings showWindow:self];
        [settings switchViews:[[settings valueForKey:@"items"] objectForKey:@"Fonts & Colors"]];
        NSWindow *settingsWindow = [settings valueForKey:@"window"];
        NSButton *checkbox = [settings valueForKey:@"highlightSearchTermsButton"];
        NSColorWell *darkWell = [settings valueForKey:@"darkSearchHighlightColorWell"];
        NSColorWell *lightWell = [settings valueForKey:@"searchHighlightColorWell"];
        NSColorPanel *panel = [NSColorPanel sharedColorPanel];
        for (NSUInteger tick = 0; tick < 8; tick++) Pump();
        Check([checkbox state] == NSControlStateValueOn && [checkbox window] == settingsWindow,
            @"the visible global highlight checkbox starts enabled");
        [checkbox performClick:self]; Pump();
        Check(![prefsController highlightSearchTerms] && [checkbox state] == NSControlStateValueOff,
            @"a native checkbox click disables the shared highlight preference");
        [self nv_cWaitForHighlightState:NO browsers:browsers at:match];
        [darkWell activate:YES]; [panel orderFront:self]; Pump();
        for (NSUInteger step = 0; step < 4; step++) {
            [settingsWindow setAppearance:[NSAppearance appearanceNamed:
                step % 2 ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua]];
            [settingsWindow display]; Pump();
            Check([darkWell isActive] && ![lightWell isActive],
                @"Settings appearance changes retain the selected dark color-panel target");
            NSArray *before = ContrarianPalette(prefsController);
            NSColor *replacement = [NSColor colorWithCalibratedRed:.21 + .09 * step green:.65 blue:.31 alpha:1];
            Check(!SameContrarianColor(before[5], replacement), @"the active dark edit changes the prior value");
            [panel setColor:replacement]; Pump();
            NSArray *after = ContrarianPalette(prefsController);
            BOOL onlyDark = YES;
            for (NSUInteger index = 0; index < 6; index++)
                if (!SameContrarianColor(after[index], index == 5 ? replacement : before[index])) onlyDark = NO;
            Check(onlyDark && SameContrarianColor([darkWell color], replacement),
                @"the shared native panel edits only dark highlight despite the Settings appearance");
            [window setAppearance:[NSAppearance appearanceNamed:
                step % 2 ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua]];
            [[peer window] setAppearance:[NSAppearance appearanceNamed:
                step % 2 ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
            for (NSUInteger tick = 0; tick < 4; tick++) Pump();
            Check(![prefsController highlightSearchTerms] && [checkbox state] == NSControlStateValueOff,
                @"editing colors and changing browser appearance retain the disabled global preference");
            [self nv_cWaitForHighlightState:NO browsers:browsers at:match];
        }
        [darkWell deactivate];
        [lightWell activate:YES]; Pump();
        NSColor *newLight = [NSColor colorWithCalibratedRed:.75 green:.21 blue:.42 alpha:1];
        NSColor *savedDark = [[prefsController darkSearchTermHighlightColor] retain];
        [panel setColor:newLight]; Pump();
        Check([lightWell isActive] && ![darkWell isActive] &&
            SameContrarianColor([prefsController searchTermHighlightColorRaw:YES], newLight) &&
            SameContrarianColor([prefsController darkSearchTermHighlightColor], savedDark),
            @"switching the native panel to the light well leaves the dark palette intact");
        [self nv_cWaitForHighlightState:NO browsers:browsers at:match];
        [lightWell deactivate]; [panel orderOut:self];
        [checkbox performClick:self]; Pump();
        Check([prefsController highlightSearchTerms] && [checkbox state] == NSControlStateValueOn,
            @"the same global checkbox re-enables search highlights");
        [self nv_cWaitForHighlightState:YES browsers:browsers at:match];
        Check(![self usesDarkUserColorScheme] && [peer usesDarkUserColorScheme] &&
            SameContrarianColor(ContrarianHighlight(self, match), newLight) &&
            SameContrarianColor(ContrarianHighlight(peer, match), savedDark),
            @"re-enabled real search decorations use the latest independent light and dark edits");
        [savedDark release];
        [NSApp sendAction:@selector(setBWColorScheme:) to:app from:self]; Pump();
        [self nv_cWaitForHighlightState:YES browsers:browsers at:match];
        [checkbox performClick:self]; Pump();
        [self nv_cWaitForHighlightState:NO browsers:browsers at:match];
        [NSApp sendAction:@selector(setUserColorScheme:) to:app from:self]; Pump();
        [self nv_cWaitForHighlightState:NO browsers:browsers at:match];
        [checkbox performClick:self]; Pump();
        [self nv_cWaitForHighlightState:YES browsers:browsers at:match];
        Check([[textView textStorage] isEqualToAttributedString:beforeSource] &&
            [[[note contentString] string] isEqual:@"prefix needle suffix"],
            @"checkbox, color-panel, scheme, and appearance transitions preserve source content and attributes");
        NSLog(@"CONTRARIAN ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
