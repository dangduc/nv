- (void)nv_runTests {
    @try {
        if (@available(macOS 11.0, *)) {
            NotationController *library = [self sharedNotationController];
            NoteObject *note = MakeNote(library, @"Editor contract", @"direct legacy text");
            [note setSourceSyntaxIdentifier:@"plain"];
            [self revealNote:note options:0];
            [prefsController setDarkBackgroundTextColor:[NSColor colorWithCalibratedRed:.1 green:.2 blue:.3 alpha:1] sender:self];
            [prefsController setDarkSearchTermHighlightColor:[NSColor colorWithCalibratedRed:.8 green:.4 blue:.2 alpha:.5] sender:self];
            [self setUserColorScheme:self];
            [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
            [window display]; Pump();
            NSAttributedString *sourceBefore = [[[textView textStorage] copy] autorelease];
            NVExpectedAppearance = [textView effectiveAppearance];
            NVExpectedBackground = [self backgrndColor];
            NSAppearance *previous = [[NSAppearance currentAppearance] retain];
            NSAppearance *caller = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            [NSAppearance setCurrentAppearance:caller];
            Check(caller != NVExpectedAppearance, @"the caller has a different appearance from the editor");
            Swap([GlobalPrefs class], @selector(searchTermHighlightAttributesForDarkAppearance:backgroundColor:),
                @selector(nv_reviewHighlightForDarkAppearance:backgroundColor:));

            for (NSUInteger fallback = 0; fallback < 2; fallback++) {
                if (fallback) Swap([LinkingEditor class], @selector(currentSearchHighlightAttributes), @selector(nv_reviewFallbackHighlightAttributes));
                NSLog(@"EDITOR CONTRACT PATH: %@", fallback ? @"forced production fallback" : @"compiled production modern");
                NVWatchResolution = YES;
                NSUInteger calls = NVResolutionCalls;
                NVResolutionMode = 1;
                Check([textView currentSearchHighlightAttributes] == nil && NVResolutionCalls == calls + 1,
                    @"a nil preference result remains nil after exactly one resolver call");
                Check([NSAppearance currentAppearance] == caller, @"nil results restore the caller appearance");

                NVResolutionMode = 2;
                NSDictionary *owned = nil;
                NSUInteger deaths = NVResultDeaths;
                calls = NVResolutionCalls;
                @autoreleasepool { owned = [[textView currentSearchHighlightAttributes] retain]; }
                Check(NVResultDeaths == deaths && NVResolutionCalls == calls + 1,
                    @"the caller-retained dictionary survives the helper callback and autorelease pool");
                Check(NVSameColor([owned objectForKey:NSBackgroundColorAttributeName], [NSColor redColor]),
                    @"the retained dictionary contains its original value");
                [owned release];
                Check(NVResultDeaths == deaths + 1, @"the caller release destroys the result exactly once without a retained helper owner");
                Check([NSAppearance currentAppearance] == caller, @"an owned result restores the caller appearance");

                NVResolutionMode = 3;
                NSException *caught = nil;
                calls = NVResolutionCalls;
                @try { [textView currentSearchHighlightAttributes]; }
                @catch (NSException *exception) { caught = exception; }
                Check([[caught name] isEqual:@"NVResolutionFailure"] && NVResolutionCalls == calls + 1,
                    @"a resolver exception propagates after exactly one call");
                Check([NSAppearance currentAppearance] == caller, @"resolver exceptions restore the caller appearance");

                NVResolutionMode = 0;
                NSColor *expected = [NSColor colorWithCalibratedRed:.45 green:.3 blue:.25 alpha:1];
                calls = NVResolutionCalls;
                [textView setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, 6)]]];
                Check(NVResolutionCalls == calls + 1 && NVSameColor([[textView layoutManager]
                    temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL], expected),
                    @"direct range publication calls the helper once and installs the expected opaque blend");
                Check([NSAppearance currentAppearance] == caller, @"direct range publication restores the caller appearance");
                CFRange legacyRange = CFRangeMake(7, 6);
                const void *legacyValues[] = { &legacyRange };
                CFArrayRef ranges = CFArrayCreate(kCFAllocatorDefault, legacyValues, 1, NULL);
                calls = NVResolutionCalls;
                [textView highlightRangesTemporarily:ranges];
                CFRelease(ranges);
                Check(NVResolutionCalls == calls + 1 && NVSameColor([[textView layoutManager]
                    temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:7 effectiveRange:NULL], expected),
                    @"legacy range publication calls the helper once and installs the same opaque blend");
                Check([NSAppearance currentAppearance] == caller, @"legacy range publication restores the caller appearance");
                NVResolutionMode = 1;
                [textView setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, 6)]]];
                Check([[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] == nil &&
                    [[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:7 effectiveRange:NULL] == nil,
                    @"a nil direct-publication result clears old direct and legacy decorations");
                Check([[textView textStorage] isEqualToAttributedString:sourceBefore],
                    @"all helper outcomes preserve the complete source attributes");
                NVWatchResolution = NO;
                if (fallback) Swap([LinkingEditor class], @selector(currentSearchHighlightAttributes), @selector(nv_reviewFallbackHighlightAttributes));
            }
            Swap([GlobalPrefs class], @selector(searchTermHighlightAttributesForDarkAppearance:backgroundColor:),
                @selector(nv_reviewHighlightForDarkAppearance:backgroundColor:));
            [NSAppearance setCurrentAppearance:previous];
            [previous release];
            NSLog(@"TORVALDS ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
            exit(0);
        }
        Check(NO, @"this controlled simulation requires macOS 11 or later");
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
