- (void)nv_ouCheckPaletteForScheme:(NSUInteger)scheme dark:(BOOL)dark foreground:(NSColor *)lightFG
    background:(NSColor *)lightBG darkForeground:(NSColor *)darkFG darkBackground:(NSColor *)darkBG
    highlight:(NSColor *)lightHL darkHighlight:(NSColor *)darkHL {
    __block NSColor *foreground = nil, *background = nil;
    if (scheme == 0) { foreground = OUColor(.02,.02,.02,1); background = OUColor(.98,.98,.98,1); }
    else if (scheme == 1) { foreground = OUColor(.243,.243,.243,1); background = OUColor(.902,.902,.902,1); }
    else if (scheme == 2) { foreground = dark ? darkFG : lightFG; background = dark ? darkBG : lightBG; }
    else [[window effectiveAppearance] performAsCurrentDrawingAppearance:^{
        foreground = [[NSColor textColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        background = [[NSColor textBackgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    }];
    Check([self usesDarkUserColorScheme] == (scheme == 2 && dark),
        @"appearance selects the dark custom palette only inside User Scheme");
    Check(OUSame([self foregrndColor], foreground) && OUSame([self backgrndColor], background) &&
        OUSame([textView backgroundColor], background),
        @"the resolved browser and editor colors obey the selected scheme contract");
    // Exercise the editor's decoration boundary without worker timing or fuzzy result fixtures.
    [textView setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, 6)]]];
    NSColor *actual = [[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName
        atCharacterIndex:0 effectiveRange:NULL];
    Check(OUSame(actual, OUBlend(scheme == 2 && dark ? darkHL : lightHL, background)),
        @"temporary search backgrounds blend the selected raw color over this browser's actual background");
}

- (void)nv_runTests {
    @try {
        NSColor *lightFG = OUColor(.13,.19,.29,1), *lightBG = OUColor(.91,.95,.99,1);
        NSColor *darkFG = OUColor(.77,.86,.95,1), *darkBG = OUColor(.03,.07,.11,1);
        NSColor *lightHL = OUColor(.99,.21,.13,.35), *darkHL = OUColor(.22,.78,.92,.65);
        [prefsController setForegroundTextColor:lightFG sender:nil];
        [prefsController setBackgroundTextColor:lightBG sender:nil];
        [prefsController setDarkForegroundTextColor:darkFG sender:nil];
        [prefsController setDarkBackgroundTextColor:darkBG sender:nil];
        [prefsController setSearchTermHighlightColor:lightHL sender:nil];
        [prefsController setDarkSearchTermHighlightColor:darkHL sender:nil];
        NVApplicationController *app = [NVApplicationController sharedController];
        NoteObject *note = MakeNote([self sharedNotationController], @"Palette boundary", @"needle ordinary source");
        [note setSourceSyntaxIdentifier:@"plain"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"the independent fixture creates a second real browser");
        for (AppController *browser in @[self, peer]) [browser revealNote:note options:0];
        Pump();
        Check([textView textStorage] == [[peer valueForKey:@"textView"] textStorage],
            @"opposite-appearance browsers use one shared source storage");
        NSAttributedString *source = [[[textView textStorage] copy] autorelease];
        NSArray *actions = @[@"setBWColorScheme:", @"setLCColorScheme:", @"setUserColorScheme:", @"setSystemColorScheme:"];
        NSArray *pairs = @[@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua],
            @[NSAppearanceNameDarkAqua, NSAppearanceNameAqua],
            @[NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua],
            @[NSAppearanceNameAccessibilityHighContrastDarkAqua, NSAppearanceNameAccessibilityHighContrastAqua]];
        for (NSUInteger scheme = 0; scheme < actions.count; scheme++) {
            Check([NSApp sendAction:NSSelectorFromString(actions[scheme]) to:app from:self],
                @"the application dispatches the existing shared Color Scheme command");
            for (NSUInteger pair = 0; pair < pairs.count; pair++) {
                NSArray *browsers = @[self, peer];
                for (NSUInteger index = 0; index < browsers.count; index++)
                    [[browsers[index] window] setAppearance:[NSAppearance appearanceNamed:pairs[pair][index]]];
                for (NSUInteger tick = 0; tick < 3; tick++) Pump();
                NSLog(@"MATRIX: scheme=%lu appearance=%@ / %@", (unsigned long)scheme, pairs[pair][0], pairs[pair][1]);
                for (NSUInteger index = 0; index < browsers.count; index++) {
                    BOOL dark = (pair % 2 == 0) ? index == 1 : index == 0;
                    [browsers[index] nv_ouCheckPaletteForScheme:scheme dark:dark foreground:lightFG
                        background:lightBG darkForeground:darkFG darkBackground:darkBG highlight:lightHL darkHighlight:darkHL];
                }
            }
        }
        Check([[textView textStorage] isEqualToAttributedString:source],
            @"all scheme and appearance transitions preserve shared source attributes");
        Check(OUSame([prefsController foregroundTextColor], lightFG) &&
            OUSame([prefsController darkForegroundTextColor], darkFG) &&
            OUSame([prefsController backgroundTextColor], lightBG) &&
            OUSame([prefsController darkBackgroundTextColor], darkBG),
            @"palette resolution leaves the raw preference values unchanged");
        NSDictionary *oldLight = [[prefsController searchTermHighlightAttributes] retain];
        NSDictionary *oldDark = [[prefsController searchTermHighlightAttributesForDarkAppearance:YES backgroundColor:darkBG] retain];
        NSColor *replacement = OUColor(.8,.3,.7,.2);
        [prefsController setDarkSearchTermHighlightColor:replacement sender:nil];
        NSDictionary *nextDark = [prefsController searchTermHighlightAttributesForDarkAppearance:YES backgroundColor:darkBG];
        Check(OUSame(oldDark[NSBackgroundColorAttributeName], OUBlend(darkHL, darkBG)) &&
            OUSame(nextDark[NSBackgroundColorAttributeName], OUBlend(replacement, darkBG)),
            @"a preference change produces fresh decorations without mutating returned dictionaries");
        Check(OUSame(oldLight[NSBackgroundColorAttributeName], [prefsController searchTermHighlightColorRaw:NO]) &&
            OUSame([prefsController searchTermHighlightAttributes][NSBackgroundColorAttributeName], OUBlend(lightHL, lightBG)),
            @"the legacy highlight accessors keep their light-palette contract after a dark edit");
        [oldLight release]; [oldDark release];
        NSLog(@"OUSTERHOUT ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1);
    }
}
