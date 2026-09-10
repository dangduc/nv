    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();

        NoteObject *completion = MakeNote(library, @"LuuRoundTwoCompletionQZ", @"candidate");
        NoteObject *target = MakeNote(library, @"Luu round two target", @"LuuRoundTwoCompletionQ");
        (void)completion;
        [browser revealNote:target options:0]; Pump();
        [[browser window] makeKeyAndOrderFront:self];
        [[browser window] makeFirstResponder:editor];
        Check([[browser window] firstResponder] == editor && [editor delegate] == (id)browser,
              @"source editor is active with the browser integration delegate");

        SEL completionSelector = @selector(textView:completions:forPartialWordRange:indexOfSelectedItem:);
        Check(![[editor delegate] respondsToSelector:completionSelector],
              @"source delegate no longer supplies note-title completions");
        Check(class_getMethodImplementation([LinkingEditor class], @selector(complete:)) ==
              class_getMethodImplementation([NSTextView class], @selector(complete:)),
              @"manual completion uses NSTextView's implementation");

        NSTextView *(^Reference)(NSString *, NSRange) = ^NSTextView *(NSString *source, NSRange selection) {
            NSTextView *reference = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
            [reference setRichText:NO];
            [reference setString:source];
            [reference setSelectedRange:selection];
            return reference;
        };
        NSTextView *reference = Reference(@"", NSMakeRange(0, 0));
        Check([editor smartInsertDeleteEnabled] == [reference smartInsertDeleteEnabled],
              @"Smart Copy/Paste startup state matches a fresh NSTextView");
        Check([editor isContinuousSpellCheckingEnabled] == [reference isContinuousSpellCheckingEnabled],
              @"continuous spelling startup state matches a fresh NSTextView");
        Check([editor isAutomaticSpellingCorrectionEnabled] == [reference isAutomaticSpellingCorrectionEnabled],
              @"spelling correction startup state matches a fresh NSTextView");
        Check([editor isAutomaticQuoteSubstitutionEnabled] == [reference isAutomaticQuoteSubstitutionEnabled],
              @"Smart Quotes startup state matches a fresh NSTextView");
        Check([editor isAutomaticDashSubstitutionEnabled] == [reference isAutomaticDashSubstitutionEnabled],
              @"Smart Dashes startup state matches a fresh NSTextView");
        Check([editor isAutomaticTextReplacementEnabled] == [reference isAutomaticTextReplacementEnabled],
              @"text replacement startup state matches a fresh NSTextView");
        Check([editor baseWritingDirection] == [reference baseWritingDirection],
              @"writing direction startup state matches a fresh NSTextView");

        // The runner supplies every retired nv preference as a launch argument.
        // If an old install can still alter startup behavior, these comparisons fail.
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        Check([defaults boolForKey:@"CheckSpellingInNoteBody"] &&
              [defaults boolForKey:@"TabKeyIndents"] &&
              [defaults boolForKey:@"AutoSuggestLinks"] &&
              [defaults boolForKey:@"UseSoftTabs"] &&
              [defaults boolForKey:@"UseAutoPairing"] &&
              [defaults boolForKey:@"rtl"],
              @"retired preferences were present before the source editor decoded");

        NSArray *toggleSelectors = @[
            NSStringFromSelector(@selector(toggleContinuousSpellChecking:)),
            NSStringFromSelector(@selector(toggleSmartInsertDelete:)),
            NSStringFromSelector(@selector(toggleAutomaticQuoteSubstitution:)),
            NSStringFromSelector(@selector(toggleAutomaticDashSubstitution:)),
            NSStringFromSelector(@selector(toggleAutomaticTextReplacement:))
        ];
        NSArray *(^ToggleStates)(void) = ^NSArray *{
            return @[
                @([editor isContinuousSpellCheckingEnabled]),
                @([editor smartInsertDeleteEnabled]),
                @([editor isAutomaticQuoteSubstitutionEnabled]),
                @([editor isAutomaticDashSubstitutionEnabled]),
                @([editor isAutomaticTextReplacementEnabled])
            ];
        };
        NSArray *initialToggleStates = [ToggleStates() copy];
        for (NSUInteger index = 0; index < [toggleSelectors count]; index++) {
            SEL action = NSSelectorFromString([toggleSelectors objectAtIndex:index]);
            Check([NSApp sendAction:action to:nil from:self],
                  [NSString stringWithFormat:@"%@ routes through the first-responder chain", [toggleSelectors objectAtIndex:index]]);
            Pump();
            Check(![[ToggleStates() objectAtIndex:index] isEqual:[initialToggleStates objectAtIndex:index]],
                  [NSString stringWithFormat:@"%@ changes the active source editor", [toggleSelectors objectAtIndex:index]]);
            [NSApp sendAction:action to:nil from:self]; Pump();
        }
        Check([ToggleStates() isEqual:initialToggleStates], @"native menu toggles restore their initial states");
        [initialToggleStates release];

        void (^Prepare)(NSString *, NSRange) = ^(NSString *source, NSRange selection) {
            NoteObject *note = MakeNote(library, [NSString stringWithFormat:@"Luu source fixture %lu", (unsigned long)Checks], source);
            [browser revealNote:note options:0]; Pump();
            [[browser window] makeFirstResponder:editor];
            [editor setSelectedRange:selection];
        };

        NSString *legacyWhitespace = @"open, relaxed        o  a\n          out     ê  ô  â  u\n           in  i  e  ơ  ă  ư\n\n\n    \n";
        Prepare(legacyWhitespace, NSMakeRange([legacyWhitespace length], 0));
        reference = Reference(legacyWhitespace, NSMakeRange([legacyWhitespace length], 0));
        for (NSUInteger step = 0; step < 7; step++) {
            [editor deleteBackward:self]; [reference deleteBackward:self]; Pump();
            Check([[editor string] isEqual:[reference string]] &&
                  NSEqualRanges([editor selectedRange], [reference selectedRange]),
                  [NSString stringWithFormat:@"repeated Backspace step %lu matches NSTextView", (unsigned long)(step + 1)]);
        }

        NSArray *deleteFixtures = @[
            @[@"    text", @4],
            @[@"a🙂z", @3],
            @[@"caféz", @5],
            @[@"👨‍👩‍👧‍👦z", @11],
            @[@"alpha\n    omega", @10]
        ];
        for (NSArray *fixture in deleteFixtures) {
            NSString *source = [fixture objectAtIndex:0];
            NSRange selection = NSMakeRange([[fixture objectAtIndex:1] unsignedIntegerValue], 0);
            Prepare(source, selection);
            reference = Reference(source, selection);
            [editor deleteBackward:self]; [reference deleteBackward:self]; Pump();
            Check([[editor string] isEqual:[reference string]] &&
                  NSEqualRanges([editor selectedRange], [reference selectedRange]),
                  [NSString stringWithFormat:@"Backspace matches NSTextView for %@", source]);
        }

        Prepare(@"alpha", NSMakeRange(5, 0));
        reference = Reference(@"alpha", NSMakeRange(5, 0));
        [editor insertTab:self]; [reference insertTab:self]; Pump();
        Check([[editor string] isEqual:[reference string]] &&
              NSEqualRanges([editor selectedRange], [reference selectedRange]),
              @"Tab matches a plain NSTextView");

        Prepare(@"paste: ", NSMakeRange(7, 0));
        reference = Reference(@"paste: ", NSMakeRange(7, 0));
        NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:@"foreign"] autorelease];
        [styled addAttribute:NSForegroundColorAttributeName value:[NSColor magentaColor]
                      range:NSMakeRange(0, [styled length])];
        [styled addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:31]
                      range:NSMakeRange(0, [styled length])];
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        NSData *rtf = [styled RTFFromRange:NSMakeRange(0, [styled length]) documentAttributes:@{}];
        [pasteboard declareTypes:@[NSRTFPboardType] owner:nil];
        [pasteboard setData:rtf forType:NSRTFPboardType];
        BOOL editorRead = [editor readSelectionFromPasteboard:pasteboard type:NSRTFPboardType];
        BOOL referenceRead = [reference readSelectionFromPasteboard:pasteboard type:NSRTFPboardType];
        Pump();
        Check(editorRead == referenceRead && [[editor string] isEqual:[reference string]] &&
              [[editor string] isEqualToString:@"paste: foreign"],
              @"rich paste imports the same source characters as a plain NSTextView");
        NSRange insertedRange = NSMakeRange(7, 7);
        __block BOOL retainedForeignStyle = NO;
        [[editor textStorage] enumerateAttributesInRange:insertedRange options:0
            usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
                if ([[attributes objectForKey:NSForegroundColorAttributeName] isEqual:[NSColor magentaColor]] ||
                    [[[attributes objectForKey:NSFontAttributeName] fontName] isEqual:[[NSFont boldSystemFontOfSize:31] fontName]]) {
                    retainedForeignStyle = YES;
                    *stop = YES;
                }
            }];
        Check(!retainedForeignStyle, @"plain source insertion drops foreign color and font attributes");

        NSLog(@"LUU ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"LUU ROUND 2 EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
