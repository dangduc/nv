// Run with Tests/ViewControlsReview/run-probe.py in a disposable app and library.
- (BOOL)nv_color:(NSColor *)color matchesRGB:(unsigned int)rgb {
    color = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return color && fabs([color redComponent] - ((rgb >> 16) & 255) / 255.0) < .005 &&
        fabs([color greenComponent] - ((rgb >> 8) & 255) / 255.0) < .005 &&
        fabs([color blueComponent] - (rgb & 255) / 255.0) < .005 &&
        fabs([color alphaComponent] - 1.0) < .005;
}

- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *note = MakeNote(library, @"Field notes",
            @"A small place for ideas, plans, and things worth keeping.\n\n"
             "Today\n\n"
             "- Write down ideas while they are fresh.\n"
             "- Find a thought with a few remembered words.\n"
             "- Leave room for something unexpected.\n\n"
             "A useful reminder\n\n"
             "Small ideas can grow into something worth sharing.\n");
        MakeNote(library, @"Weekend garden", @"A few ideas for the garden: rosemary, mint, and room to grow.");
        MakeNote(library, @"Reading list", @"Books and ideas to return to on a quiet afternoon.");
        [note setSourceSyntaxIdentifier:@"plain"];
        [prefsController setAutoCompleteSearches:NO sender:self];
        [prefsController setShouldHighlightSearchTerms:YES sender:self];
        [self setUserColorScheme:self];
        NSRect visible = [[window screen] visibleFrame];
        [window setFrame:NSMakeRect(floor(NSMidX(visible) - 420), floor(NSMidY(visible) - 320), 840, 640) display:YES];
        [self setNotesListHeight:125];
        [self searchForString:@"ideas" mode:@"exact"];
        [self revealNote:note options:0];
        [self focusNoteBody];
        [textView setSelectedRange:NSMakeRange([[textView string] length], 0)];

        for (NSUInteger dark = 0; dark < 2; dark++) {
            [window setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
            for (NSUInteger i = 0; i < 20; i++) Pump();
            Check([self usesDarkUserColorScheme] == (BOOL)dark, @"User Scheme follows the capture window appearance");
            Check([self nv_color:[self foregrndColor] matchesRGB:0x000000], @"default text is opaque sRGB #000000");
            Check([self nv_color:[textView backgroundColor] matchesRGB:dark ? 0xFFEFC9 : 0xFDE9D9],
                @"editor uses the requested default background");
            NSUInteger match = [[textView string] rangeOfString:@"ideas"].location;
            Check(match != NSNotFound && [self selectedNoteObject] == note, @"the selected sample contains the search term");
            NSRange range;
            NSLayoutManager *layout = [textView layoutManager];
            NSDictionary *temporary = [layout temporaryAttributesAtCharacterIndex:match effectiveRange:&range];
            NSDictionary *drawing = [textView layoutManager:layout shouldUseTemporaryAttributes:temporary
                forDrawingToScreen:YES atCharacterIndex:match effectiveRange:&range];
            Check([self nv_color:drawing[NSForegroundColorAttributeName] matchesRGB:0x000000],
                @"search match glyphs draw in black");
            Check([self nv_color:drawing[NSBackgroundColorAttributeName] matchesRGB:dark ? 0xFFC600 : 0xF5C1C0],
                @"search matches draw with the requested default highlight");
            [window display]; Pump();
            CGImageRef capture = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
                (CGWindowID)[window windowNumber], kCGWindowImageDefault);
            Check(capture != NULL, @"WindowServer captures only the sample app window");
            NSBitmapImageRep *image = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
            CGImageRelease(capture);
            const char *directory = getenv("NV_USER_SCHEMES_ARTIFACTS");
            Check(directory != NULL, @"screenshot output directory is set");
            NSString *path = [[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:
                dark ? @"user-scheme-defaults-dark.png" : @"user-scheme-defaults-light.png"];
            Check([[image representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES],
                @"unmodified screenshot is saved");
        }
        NSLog(@"USER_SCHEME_DEFAULTS_CAPTURE_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
