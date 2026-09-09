- (void)nv_setReviewAppearance:(BOOL)dark {
    [window setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
    [window display];
    for (NSUInteger i = 0; i < 3; i++) Pump();
}

- (void)nv_runTests {
    @try {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray *lightKeys = @[@"ForegroundTextColor", @"BackgroundTextColor", @"SearchTermHighlightColor"];
        NSArray *darkKeys = @[@"DarkForegroundTextColor", @"DarkBackgroundTextColor", @"DarkSearchTermHighlightColor"];
        NSDictionary *persistent = [defaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        for (NSUInteger i = 0; i < 3; i++) {
            Check([[defaults dataForKey:lightKeys[i]] isEqual:NVLegacyArchives[i]],
                @"startup preserves the original light color archive bytes");
            Check([defaults dataForKey:darkKeys[i]] != nil && persistent[darkKeys[i]] == nil,
                @"a dark fallback exists only in registration defaults before the user edits it");
        }

        NSArray *allKeys = [lightKeys arrayByAddingObjectsFromArray:darkKeys];
        NSMutableArray *beforeNil = [NSMutableArray array];
        for (NSString *key in allKeys) [beforeNil addObject:[defaults dataForKey:key]];
        NVLegacyPaletteSeed *observer = [[[NVLegacyPaletteSeed alloc] init] autorelease];
        [prefsController registerWithTarget:observer forChangesInSettings:
            @selector(setForegroundTextColor:sender:), @selector(setBackgroundTextColor:sender:),
            @selector(setSearchTermHighlightColor:sender:), @selector(setDarkForegroundTextColor:sender:),
            @selector(setDarkBackgroundTextColor:sender:), @selector(setDarkSearchTermHighlightColor:sender:), nil];
        [prefsController setForegroundTextColor:nil sender:self];
        [prefsController setBackgroundTextColor:nil sender:self];
        [prefsController setSearchTermHighlightColor:nil sender:self];
        [prefsController setDarkForegroundTextColor:nil sender:self];
        [prefsController setDarkBackgroundTextColor:nil sender:self];
        [prefsController setDarkSearchTermHighlightColor:nil sender:self];
        for (NSUInteger i = 0; i < [allKeys count]; i++)
            Check([[defaults dataForKey:allKeys[i]] isEqual:beforeNil[i]], @"a nil palette setter leaves its archived preference unchanged");
        Check(NVPreferenceCallbacks == 0, @"nil palette setters produce no preference callbacks");
        [prefsController unregisterTarget:observer];

        [self setUserColorScheme:self];
        for (NSUInteger iteration = 0; iteration < 6; iteration++) {
            BOOL dark = iteration % 2;
            @autoreleasepool { [self nv_setReviewAppearance:dark]; }
            Check([self usesDarkUserColorScheme] == dark &&
                NVSameRGBA([self foregrndColor], dark ? [prefsController darkForegroundTextColor] : [prefsController foregroundTextColor]) &&
                NVSameRGBA([self backgrndColor], dark ? [prefsController darkBackgroundTextColor] : [prefsController backgroundTextColor]),
                @"browser foreground and background survive the palette callback autorelease pool");
        }
        for (NSUInteger i = 0; i < 3; i++)
            Check([[defaults dataForKey:lightKeys[i]] isEqual:NVLegacyArchives[i]],
                @"appearance transitions do not rewrite the original light archive or color space");
        Check(NVSameRGBA([[prefsController searchTermHighlightAttributes] objectForKey:NSBackgroundColorAttributeName],
            [prefsController searchTermHighlightColorRaw:NO]),
            @"the legacy highlight dictionary still equals the legacy light compositing getter in dark appearance");

        NSDictionary *retainedAttributes = nil;
        NSColor *retainedColor = nil;
        @autoreleasepool {
            retainedAttributes = [[prefsController searchTermHighlightAttributes] retain];
            retainedColor = [[retainedAttributes objectForKey:NSBackgroundColorAttributeName] retain];
            [prefsController setSearchTermHighlightColor:[NSColor redColor] sender:self];
            [prefsController setBackgroundTextColor:[NSColor blueColor] sender:self];
        }
        Check(NVSameRGBA([retainedAttributes objectForKey:NSBackgroundColorAttributeName], retainedColor),
            @"a retained highlight result remains valid and unchanged after later preferences and pool drainage");
        Check(!NVSameRGBA([[prefsController searchTermHighlightAttributes] objectForKey:NSBackgroundColorAttributeName], retainedColor),
            @"a new highlight read reflects later preferences independently of the retained result");
        [retainedAttributes release]; [retainedColor release];

        NSColor *background = [NSColor colorWithCalibratedRed:.1 green:.3 blue:.8 alpha:1];
        for (NSUInteger alpha = 0; alpha <= 1; alpha++) {
            NSColor *raw = [NSColor colorWithCalibratedRed:.8 green:.2 blue:.1 alpha:alpha];
            [prefsController setDarkSearchTermHighlightColor:raw sender:self];
            NSColor *actual = [[prefsController searchTermHighlightAttributesForDarkAppearance:YES backgroundColor:background]
                objectForKey:NSBackgroundColorAttributeName];
            Check(NVSameRGBA(actual, alpha ? raw : background), @"the dark highlight handles the exact transparent and opaque endpoints");
        }

        for (NSUInteger scheme = 0; scheme < 2; scheme++) {
            if (scheme == 0) [self setBWColorScheme:self]; else [self setLCColorScheme:self];
            NSColor *foreground = [[self foregrndColor] retain], *background = [[self backgrndColor] retain];
            for (NSUInteger dark = 0; dark < 2; dark++) {
                [self nv_setReviewAppearance:dark];
                Check([[defaults objectForKey:@"ColorScheme"] integerValue] == scheme && ![self usesDarkUserColorScheme] &&
                    NVSameRGBA([self foregrndColor], foreground) && NVSameRGBA([self backgrndColor], background),
                    @"fixed color schemes keep their selection and colors across light and dark appearance");
            }
            [foreground release]; [background release];
        }
        [self setSystemColorScheme:self];
        for (NSUInteger dark = 0; dark < 2; dark++) {
            [self nv_setReviewAppearance:dark];
            [[window effectiveAppearance] performAsCurrentDrawingAppearance:^{
                Check([defaults integerForKey:@"ColorScheme"] == 3 && ![self usesDarkUserColorScheme] &&
                    NVSameRGBA([self foregrndColor], [NSColor textColor]) && NVSameRGBA([self backgrndColor], [NSColor textBackgroundColor]),
                    @"System keeps value 3 and resolves native colors without selecting the dark User palette");
            }];
        }
        NSLog(@"TORVALDS ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
