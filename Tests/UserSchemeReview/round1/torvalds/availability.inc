// Exact pre-change method body from upstream/master 78d9442, renamed for the control.
- (IBAction)nv_legacyUserColorScheme:(id)sender {
    userScheme=2;
    [[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
    [self setForegrndColor:[prefsController foregroundTextColor]];
    [self setBackgrndColor:[prefsController backgroundTextColor]];
    NSMenu *mainM = [NSApp mainMenu];
    NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
    mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
    viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
    [[mainM itemAtIndex:0] setState:0];
    [[mainM itemAtIndex:1] setState:0];
    [[mainM itemAtIndex:2] setState:1];
    [[viewM itemAtIndex:0] setState:0];
    [[viewM itemAtIndex:1] setState:0];
    [[viewM itemAtIndex:2] setState:1];
    [self updateColorScheme];
}

- (void)nv_runTests {
    @try {
        BOOL legacy = getenv("NV_LEGACY_USER_SCHEME") != NULL;
        Check([window effectiveAppearance] != nil, @"the real browser has an effective appearance");
        NSException *caught = nil;
        NVSimulateMissingDrawingAppearance = YES;
        @try {
            if (legacy) [self nv_legacyUserColorScheme:self];
            else [self setUserColorScheme:self];
        } @catch (NSException *exception) { caught = [[exception retain] autorelease]; }
        NVSimulateMissingDrawingAppearance = NO;
        if (caught) NSLog(@"Unavailable-selector observation (%@): %@", legacy ? @"legacy control" : @"PR path", caught);
        Check(caught == nil, @"selecting User Scheme succeeds without the macOS 11 drawing-appearance selector");
        NSLog(@"TORVALDS AVAILABILITY CONTROL PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
