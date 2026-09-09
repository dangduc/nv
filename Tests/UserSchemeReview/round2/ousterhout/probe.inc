- (void)nv_ouCheckResolvedPalette {
    BOOL dark = [self usesDarkUserColorScheme];
    NSUInteger scheme = [[self valueForKey:@"userScheme"] unsignedIntegerValue];
    __block NSColor *foreground, *background;
    if (scheme == 2) {
        foreground = dark ? [prefsController darkForegroundTextColor] : [prefsController foregroundTextColor];
        background = dark ? [prefsController darkBackgroundTextColor] : [prefsController backgroundTextColor];
    } else {
        if (@available(macOS 11.0, *)) [[window effectiveAppearance] performAsCurrentDrawingAppearance:^{
            foreground = [[NSColor textColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            background = [[NSColor textBackgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        }];
        else { Check(NO, @"this review requires a current macOS host"); return; }
    }
    Check(OUSameColor([self foregrndColor], foreground) && OUSameColor([self backgrndColor], background) &&
        OUSameColor([textView backgroundColor], background),
        @"the nested update retains the palette resolved for the owning browser");
}

- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NoteObject *note = MakeNote([self sharedNotationController], @"Scoped appearance", @"ordinary source for both native windows");
        [note setSourceSyntaxIdentifier:@"plain"];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"the fixture has two native browser controllers");
        for (AppController *browser in @[self, peer]) [browser revealNote:note options:0];
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [[peer window] setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        for (NSUInteger tick = 0; tick < 3; tick++) Pump();
        Check([textView textStorage] == [[peer valueForKey:@"textView"] textStorage],
            @"both native browsers attach to one shared source storage");
        NSAttributedString *original = [[[textView textStorage] copy] autorelease];
        NSAppearance *previous = [[NSAppearance currentAppearance] retain];
        NSAppearance *sentinel = [NSAppearance appearanceNamed:NSAppearanceNameAccessibilityHighContrastAqua];
        OUOuter = self; OUInner = peer;
        Swap([AppController class], @selector(updateColorScheme), @selector(nv_ouScopedUpdate));
        for (NSUInteger forcedFallback = 0; forcedFallback < 2; forcedFallback++) {
            if (forcedFallback) Swap([AppController class], @selector(browserAppearanceChanged), @selector(nv_ouFallbackAppearanceChanged));
            for (NSUInteger outerScheme = 2; outerScheme <= 3; outerScheme++) {
                for (NSUInteger innerScheme = 2; innerScheme <= 3; innerScheme++) {
                    OUWatching = NO;
                    if (outerScheme == 2) [self setUserColorScheme:self]; else [self setSystemColorScheme:self];
                    if (innerScheme == 2) [peer setUserColorScheme:peer]; else [peer setSystemColorScheme:peer];
                    for (NSUInteger failure = 0; failure < 2; failure++) {
                        OUOuterCalls = OUInnerCalls = 0;
                        OUThrowInner = failure;
                        [NSAppearance setCurrentAppearance:sentinel];
                        OUWatching = YES;
                        NSException *caught = nil;
                        NSLog(@"SCOPE: fallback=%lu outer=%lu inner=%lu failure=%lu",
                            (unsigned long)forcedFallback, (unsigned long)outerScheme,
                            (unsigned long)innerScheme, (unsigned long)failure);
                        @try { [self browserAppearanceChanged]; }
                        @catch (NSException *exception) { caught = exception; }
                        OUWatching = NO;
                        Check(OUOuterCalls == 1 && OUInnerCalls == 1,
                            @"one outer update invokes exactly one nested peer update");
                        Check(failure ? [[caught name] isEqual:@"OUNestedAppearanceFailure"] : caught == nil,
                            @"the nested exception propagates only in the injected failure case");
                        Check([NSAppearance currentAppearance] == sentinel,
                            @"the complete nested scope restores the original caller appearance");
                        if (!failure) {
                            [self nv_ouCheckResolvedPalette]; [peer nv_ouCheckResolvedPalette];
                        }
                    }
                }
            }
            if (forcedFallback) Swap([AppController class], @selector(browserAppearanceChanged), @selector(nv_ouFallbackAppearanceChanged));
        }
        Swap([AppController class], @selector(updateColorScheme), @selector(nv_ouScopedUpdate));
        [NSAppearance setCurrentAppearance:previous]; [previous release];
        Check([[textView textStorage] isEqualToAttributedString:original],
            @"nested successful and failed appearance updates leave the shared source unchanged");
        NSLog(@"OUSTERHOUT ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) {
        OUWatching = NO;
        NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1);
    }
}
