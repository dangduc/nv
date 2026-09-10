    @try {
        GlobalPrefs *preferences = [GlobalPrefs defaultPrefs];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *note = MakeNote(library, @"Hidden tab width", @"\tvalue");
        [browser revealNote:note options:0];
        Pump();

        [[browser window] makeKeyAndOrderFront:self];
        [[browser window] makeFirstResponder:editor];
        Pump();

        Check([[browser window] firstResponder] == editor,
              @"source editor owns first responder for the preference probe");
        Check([preferences numberOfSpacesInTab] == 11,
              @"obsolete NumberOfSpacesInTab command-line default reaches GlobalPrefs");

        NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:12.0];
        Check(font != nil && [font isFixedPitch],
              @"probe has a fixed-pitch body font");
        // Keep NotationPrefs from immediately restoring its archived base font;
        // the editor remains an independent GlobalPrefs observer.
        [preferences setNoteBodyFont:font sender:browser];
        Pump();
        NSParagraphStyle *configured = [preferences noteBodyParagraphStyle];
        NSMutableString *spaces = [NSMutableString string];
        for (NSUInteger index = 0; index < 11; index++) [spaces appendString:@" "];
        CGFloat expectedInterval = [spaces sizeWithAttributes:
            [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]].width;

        Check([[configured tabStops] count] == 0,
              @"nvALT removes every native paragraph tab stop");
        Check(fabs([configured defaultTabInterval] - expectedInterval) < 0.01,
              @"obsolete preference controls nvALT's replacement tab interval");

        NSTextView *reference = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
        [reference setRichText:NO];
        [reference setFont:font];
        [reference setString:@"\tX"];
        NSParagraphStyle *native = [NSParagraphStyle defaultParagraphStyle];
        Check([[native tabStops] count] > 0 && [native defaultTabInterval] == 0.0,
              @"fresh NSTextView paragraphs retain AppKit's tab-stop layout");
        Check(![configured isEqual:native],
              @"nvALT's source paragraph layout differs from AppKit's default");

        NSTextView *configuredView = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
        [configuredView setRichText:NO];
        [configuredView setFont:font];
        [configuredView setString:@"\tX"];
        [[configuredView textStorage] addAttribute:NSParagraphStyleAttributeName value:configured
                                              range:NSMakeRange(0, 2)];
        [[configuredView layoutManager] ensureLayoutForTextContainer:[configuredView textContainer]];
        [[reference layoutManager] ensureLayoutForTextContainer:[reference textContainer]];
        CGFloat configuredX = [[configuredView layoutManager] locationForGlyphAtIndex:1].x;
        CGFloat nativeX = [[reference layoutManager] locationForGlyphAtIndex:1].x;
        Check(configuredX > nativeX * 2.0,
              @"hidden eleven-space preference visibly changes tab layout");

        NSLog(@"CONTRARIAN FINDING: NumberOfSpacesInTab=%ld customInterval=%.3f nativeStops=%lu nativeInterval=%.3f customX=%.3f nativeX=%.3f",
              (long)[preferences numberOfSpacesInTab], [configured defaultTabInterval],
              (unsigned long)[[native tabStops] count], [native defaultTabInterval], configuredX, nativeX);
        NSLog(@"ROUND 2 CONTRARIAN A PASSED (%lu checks)", (unsigned long)Checks);

        [library flushAllNoteChanges];
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"ROUND 2 CONTRARIAN A EXCEPTION %@ %@\n%@",
              [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
