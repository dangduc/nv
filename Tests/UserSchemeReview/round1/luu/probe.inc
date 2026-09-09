- (NSColor *)luu_drawColorAt:(NSUInteger)index editor:(LinkingEditor *)editor {
    NSLayoutManager *layout = [editor layoutManager];
    NSRange range;
    NSDictionary *temporary = [layout temporaryAttributesAtCharacterIndex:index effectiveRange:&range];
    return [editor layoutManager:layout shouldUseTemporaryAttributes:temporary forDrawingToScreen:YES
        atCharacterIndex:index effectiveRange:&range][NSForegroundColorAttributeName];
}

- (void)nv_runTests {
    @try {
        if (@available(macOS 10.14, *)) Check(YES, @"native application appearance is available");
        else Check(NO, @"native application appearance is available");
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [self sharedNotationController];
        NSColor *lightForeground = LuuColor(.1, .2, .3), *darkForeground = LuuColor(.9, .8, .7);
        NSColor *lightBackground = LuuColor(.98, .98, .98), *darkBackground = LuuColor(.03, .03, .03);
        [prefsController setForegroundTextColor:lightForeground sender:self];
        [prefsController setBackgroundTextColor:lightBackground sender:self];
        [prefsController setDarkForegroundTextColor:darkForeground sender:self];
        [prefsController setDarkBackgroundTextColor:darkBackground sender:self];
        [prefsController setShouldHighlightSearchTerms:YES sender:self];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"a real peer browser exists");
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        for (AppController *browser in @[self, peer]) {
            [[browser window] setAppearance:nil];
            [browser setUserColorScheme:browser];
        }
        NSArray *fixtures = @[
            @[@"markdown", @"# Heading\nordinary source and **bold** needle\n", @"Heading", @"ordinary"],
            @[@"html", @"<article>ordinary source <b>needle</b></article>\n", @"article", @"ordinary"],
            @[@"json", @"{\"needle\": 17, \"other\": true}\n", @"needle", @"\n"]
        ];
        for (NSArray *fixture in fixtures) {
            NoteObject *note = MakeNote(library, fixture[0], fixture[1]);
            [note setSourceSyntaxIdentifier:fixture[0]];
            for (AppController *browser in @[self, peer]) {
                [browser searchForString:@"needle" mode:@"exact"];
                [browser revealNote:note options:0];
            }
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
            while ((!NVSourceCapturesAreCurrent([textView layoutManager]) || !NVSourceCapturesAreCurrent([peerEditor layoutManager])) &&
                [deadline timeIntervalSinceNow] > 0) Pump();
            Check(NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([peerEditor layoutManager]),
                [NSString stringWithFormat:@"%@ has real current captures in both editors", fixture[0]]);
            Check([textView textStorage] == [peerEditor textStorage], @"the two syntax views share one source storage");
            NSUInteger token = [[textView string] rangeOfString:fixture[2]].location;
            NSUInteger ordinary = [[textView string] rangeOfString:fixture[3]].location;
            NSString *capture = [[textView layoutManager] temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:token effectiveRange:NULL];
            Check(capture != nil && ![capture isEqualToString:@"none"], @"the syntax sample has a nonempty parser capture");
            Check([[textView layoutManager] temporaryAttribute:NVSourceCaptureAttributeName atCharacterIndex:ordinary effectiveRange:NULL] == nil,
                @"the ordinary sample has no syntax override");
            NSAttributedString *before = [[[textView textStorage] copy] autorelease];
            NSAttributedString *modelBefore = [[[note contentString] copy] autorelease];
            NVNoteEditingSession *session = [app editingSessionForNote:note];
            NVSourceHighlighter *highlighter = [session valueForKey:@"sourceHighlighter"];
            uint64_t generation = [highlighter generation];
            NSUInteger callsBefore = __atomic_load_n(&LuuParserCalls, __ATOMIC_RELAXED);
            NSColor *previousSyntax = nil;
            CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
            for (NSUInteger transition = 0; transition < 6; transition++) {
                BOOL dark = transition % 2;
                if (@available(macOS 10.14, *))
                    [NSApp setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
                for (AppController *browser in @[self, peer]) [[browser window] display];
                for (NSUInteger i = 0; i < 2; i++) Pump();
                for (AppController *browser in @[self, peer]) {
                    LinkingEditor *editor = [browser valueForKey:@"textView"];
                    Check([[browser window] appearance] == nil && [browser usesDarkUserColorScheme] == dark &&
                        LuuSameColor([editor backgroundColor], dark ? darkBackground : lightBackground),
                        @"an unpinned real window inherits application appearance and switches its palette");
                    Check(LuuSameColor([self luu_drawColorAt:ordinary editor:editor], dark ? darkForeground : lightForeground),
                        @"ordinary drawing resolves the newly inherited palette");
                    Check(NVSourceCapturesAreCurrent([editor layoutManager]) &&
                        !LuuSameColor([self luu_drawColorAt:token editor:editor], dark ? darkForeground : lightForeground),
                        @"existing current syntax captures stay colored across the appearance change");
                }
                NSColor *currentSyntax = [self luu_drawColorAt:token editor:textView];
                Check(!previousSyntax || !LuuSameColor(previousSyntax, currentSyntax),
                    @"syntax glyph brightness changes with the actual editor background");
                previousSyntax = currentSyntax;
            }
            NSLog(@"OBSERVATION: %@ six two-window appearance updates with explicit 100ms pumps took %.3fms",
                fixture[0], (CFAbsoluteTimeGetCurrent() - started) * 1000);
            Check([highlighter generation] == generation && __atomic_load_n(&LuuParserCalls, __ATOMIC_RELAXED) == callsBefore,
                @"six appearance changes neither invalidate source analysis nor call the parser again");
            Check([[textView textStorage] isEqualToAttributedString:before] && [[note contentString] isEqualToAttributedString:modelBefore],
                @"syntax recoloring preserves all shared source and model attributes");
        }
        NSLog(@"LUU USER SCHEME ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
