    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();

        NSTextView *(^Reference)(NSString *, NSRange) = ^NSTextView *(NSString *source, NSRange selection) {
            NSTextView *reference = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
            [reference setRichText:NO];
            [reference setImportsGraphics:NO];
            [reference setString:source];
            [reference setSelectedRange:selection];
            return reference;
        };
        __block NSUInteger fixture = 0;
        void (^Prepare)(NSString *, NSRange) = ^(NSString *source, NSRange selection) {
            NoteObject *note = MakeNote(library,
                [NSString stringWithFormat:@"Luu round three fixture %lu", (unsigned long)fixture++], source);
            [browser revealNote:note options:0]; Pump();
            [[browser window] makeKeyAndOrderFront:self];
            [[browser window] makeFirstResponder:editor];
            [editor setSelectedRange:selection];
            Check([[browser window] firstResponder] == editor,
                  @"source editor owns first responder for the fixture");
        };
        void (^CompareCommand)(NSString *, NSRange, SEL, NSString *) =
        ^(NSString *source, NSRange selection, SEL command, NSString *label) {
            Prepare(source, selection);
            NSTextView *reference = Reference(source, selection);
            [editor doCommandBySelector:command];
            [reference doCommandBySelector:command];
            Pump();
            Check([[editor string] isEqual:[reference string]] &&
                  NSEqualRanges([editor selectedRange], [reference selectedRange]), label);
        };

        NSArray *nativeSelectors = @[
            NSStringFromSelector(@selector(keyDown:)),
            NSStringFromSelector(@selector(flagsChanged:)),
            NSStringFromSelector(@selector(performKeyEquivalent:)),
            NSStringFromSelector(@selector(deleteBackward:)),
            NSStringFromSelector(@selector(deleteForward:)),
            NSStringFromSelector(@selector(deleteWordBackward:)),
            NSStringFromSelector(@selector(deleteWordForward:)),
            NSStringFromSelector(@selector(insertTab:)),
            NSStringFromSelector(@selector(insertBacktab:)),
            NSStringFromSelector(@selector(insertNewline:)),
            NSStringFromSelector(@selector(complete:)),
            NSStringFromSelector(@selector(rangeForUserCompletion)),
            NSStringFromSelector(@selector(selectionRangeForProposedRange:granularity:)),
            NSStringFromSelector(@selector(paste:)),
            NSStringFromSelector(@selector(readSelectionFromPasteboard:type:)),
            NSStringFromSelector(@selector(draggingEntered:)),
            NSStringFromSelector(@selector(performDragOperation:))
        ];
        for (NSString *selectorName in nativeSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            Check(class_getMethodImplementation([LinkingEditor class], selector) ==
                  class_getMethodImplementation([NSTextView class], selector),
                  [NSString stringWithFormat:@"%@ resolves to NSTextView", selectorName]);
        }

        id sourceDelegate = [editor delegate];
        SEL completionSelector = @selector(textView:completions:forPartialWordRange:indexOfSelectedItem:);
        Check(sourceDelegate == browser && ![sourceDelegate respondsToSelector:completionSelector],
              @"source completion has no nv note-title provider");

        NSTextView *fresh = Reference(@"", NSMakeRange(0, 0));
        Check([editor isContinuousSpellCheckingEnabled] == [fresh isContinuousSpellCheckingEnabled],
              @"continuous spelling matches fresh NSTextView");
        Check([editor isAutomaticSpellingCorrectionEnabled] == [fresh isAutomaticSpellingCorrectionEnabled],
              @"spelling correction matches fresh NSTextView");
        Check([editor smartInsertDeleteEnabled] == [fresh smartInsertDeleteEnabled],
              @"Smart Copy/Paste matches fresh NSTextView");
        Check([editor isAutomaticQuoteSubstitutionEnabled] == [fresh isAutomaticQuoteSubstitutionEnabled],
              @"Smart Quotes matches fresh NSTextView");
        Check([editor isAutomaticDashSubstitutionEnabled] == [fresh isAutomaticDashSubstitutionEnabled],
              @"Smart Dashes matches fresh NSTextView");
        Check([editor isAutomaticTextReplacementEnabled] == [fresh isAutomaticTextReplacementEnabled],
              @"text replacement matches fresh NSTextView");
        Check([editor baseWritingDirection] == [fresh baseWritingDirection],
              @"writing direction matches fresh NSTextView");
        Check([[prefsController noteBodyAttributes] objectForKey:NSParagraphStyleAttributeName] == nil,
              @"old tab width cannot install a paragraph override");

        NSString *legacyWhitespace = @"open, relaxed        o  a\n          out     ê  ô  â  u\n           in  i  e  ơ  ă  ư\n\n\n    \n";
        Prepare(legacyWhitespace, NSMakeRange([legacyWhitespace length], 0));
        fresh = Reference(legacyWhitespace, NSMakeRange([legacyWhitespace length], 0));
        for (NSUInteger step = 0; step < 9; step++) {
            [editor deleteBackward:self]; [fresh deleteBackward:self]; Pump();
            Check([[editor string] isEqual:[fresh string]] &&
                  NSEqualRanges([editor selectedRange], [fresh selectedRange]),
                  [NSString stringWithFormat:@"reported Backspace sequence step %lu matches NSTextView",
                   (unsigned long)(step + 1)]);
        }

        NSArray *clusters = @[
            @"a🙂z",
            @"cafe\u0301z",
            @"👨🏽‍💻z",
            @"🇺🇳z",
            @"क्‍षz",
            @"مرحباz",
            @"a\r\nz"
        ];
        for (NSString *source in clusters) {
            NSUInteger location = [source rangeOfString:@"z"].location;
            CompareCommand(source, NSMakeRange(location, 0), @selector(deleteBackward:),
                           [NSString stringWithFormat:@"Backspace before z matches NSTextView for %@", source]);
        }
        CompareCommand(@"👩‍🔬 alphabet", NSMakeRange(0, 5), @selector(deleteBackward:),
                       @"Backspace over a composed selection matches NSTextView");
        CompareCommand(@"alpha beta", NSMakeRange(10, 0), @selector(deleteWordBackward:),
                       @"Option-Backspace command matches NSTextView");
        CompareCommand(@"alpha beta", NSMakeRange(0, 0), @selector(deleteWordForward:),
                       @"Option-Delete command matches NSTextView");
        CompareCommand(@"alpha", NSMakeRange(2, 0), @selector(deleteForward:),
                       @"forward delete matches NSTextView");
        CompareCommand(@"alpha", NSMakeRange(5, 0), @selector(insertTab:),
                       @"Tab command matches NSTextView");
        CompareCommand(@"    alpha", NSMakeRange(9, 0), @selector(insertNewline:),
                       @"Return does not carry indentation beyond NSTextView behavior");

        Prepare(@"A🙂B", NSMakeRange(3, 0));
        fresh = Reference(@"A🙂B", NSMakeRange(3, 0));
        NSWindow *referenceWindow = [[[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, 500, 300)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
        NSScrollView *referenceScroll = [[[NSScrollView alloc] initWithFrame:[[referenceWindow contentView] bounds]] autorelease];
        [referenceScroll setDocumentView:fresh];
        [[referenceWindow contentView] addSubview:referenceScroll];
        NSEvent *(^DeleteEvent)(NSWindow *, NSEventModifierFlags) =
        ^NSEvent *(NSWindow *eventWindow, NSEventModifierFlags flags) {
            return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags
                timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:[eventWindow windowNumber]
                context:nil characters:@"\x7f" charactersIgnoringModifiers:@"\x7f"
                isARepeat:NO keyCode:51];
        };
        [editor keyDown:DeleteEvent([browser window], 0)];
        [referenceWindow makeKeyAndOrderFront:self];
        [referenceWindow makeFirstResponder:fresh];
        [fresh keyDown:DeleteEvent(referenceWindow, 0)]; Pump();
        Check([[editor string] isEqual:[fresh string]] &&
              NSEqualRanges([editor selectedRange], [fresh selectedRange]),
              @"real keyDown Backspace matches NSTextView across an emoji boundary");

        Prepare(@"alpha beta", NSMakeRange(10, 0));
        fresh = Reference(@"alpha beta", NSMakeRange(10, 0));
        NSEvent *shift = [NSEvent keyEventWithType:NSFlagsChanged location:NSZeroPoint
            modifierFlags:NSEventModifierFlagShift timestamp:[NSDate timeIntervalSinceReferenceDate]
            windowNumber:[[browser window] windowNumber] context:nil characters:@""
            charactersIgnoringModifiers:@"" isARepeat:NO keyCode:56];
        [editor flagsChanged:shift]; [fresh flagsChanged:shift]; Pump();
        Check([[editor string] isEqual:[fresh string]] &&
              NSEqualRanges([editor selectedRange], [fresh selectedRange]),
              @"modifier event leaves text and selection at NSTextView state");

        void (^ComparePasteboard)(NSPasteboard *, NSString *, NSString *) =
        ^(NSPasteboard *pasteboard, NSString *type, NSString *label) {
            Prepare(@"paste: ", NSMakeRange(7, 0));
            NSTextView *reference = Reference(@"paste: ", NSMakeRange(7, 0));
            BOOL sourceResult = [editor readSelectionFromPasteboard:pasteboard type:type];
            BOOL referenceResult = [reference readSelectionFromPasteboard:pasteboard type:type];
            Pump();
            Check(sourceResult == referenceResult && [[editor string] isEqual:[reference string]] &&
                  NSEqualRanges([editor selectedRange], [reference selectedRange]), label);
        };
        NSPasteboard *plainBoard = [NSPasteboard pasteboardWithUniqueName];
        [plainBoard declareTypes:@[NSPasteboardTypeString] owner:nil];
        [plainBoard setString:@"plain 🙂" forType:NSPasteboardTypeString];
        ComparePasteboard(plainBoard, NSPasteboardTypeString,
                          @"plain Unicode paste matches NSTextView");

        NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc]
            initWithString:@"styled"] autorelease];
        [styled addAttribute:NSForegroundColorAttributeName value:[NSColor magentaColor]
                       range:NSMakeRange(0, [styled length])];
        [styled addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:29]
                       range:NSMakeRange(0, [styled length])];
        NSPasteboard *rtfBoard = [NSPasteboard pasteboardWithUniqueName];
        [rtfBoard declareTypes:@[NSPasteboardTypeRTF] owner:nil];
        [rtfBoard setData:[styled RTFFromRange:NSMakeRange(0, [styled length]) documentAttributes:@{}]
                  forType:NSPasteboardTypeRTF];
        ComparePasteboard(rtfBoard, NSPasteboardTypeRTF,
                          @"RTF paste imports the same source characters as NSTextView");

        NSPasteboard *htmlBoard = [NSPasteboard pasteboardWithUniqueName];
        [htmlBoard declareTypes:@[NSPasteboardTypeHTML] owner:nil];
        [htmlBoard setData:[@"<b>bold</b> &amp; plain" dataUsingEncoding:NSUTF8StringEncoding]
                   forType:NSPasteboardTypeHTML];
        ComparePasteboard(htmlBoard, NSPasteboardTypeHTML,
                          @"HTML paste imports the same source characters as NSTextView");

        NSArray *toggleSelectors = @[
            NSStringFromSelector(@selector(toggleContinuousSpellChecking:)),
            NSStringFromSelector(@selector(toggleSmartInsertDelete:)),
            NSStringFromSelector(@selector(toggleAutomaticQuoteSubstitution:)),
            NSStringFromSelector(@selector(toggleAutomaticDashSubstitution:)),
            NSStringFromSelector(@selector(toggleAutomaticLinkDetection:)),
            NSStringFromSelector(@selector(toggleAutomaticTextReplacement:))
        ];
        NSArray *(^ToggleStates)(void) = ^NSArray *{
            return @[
                @([editor isContinuousSpellCheckingEnabled]),
                @([editor smartInsertDeleteEnabled]),
                @([editor isAutomaticQuoteSubstitutionEnabled]),
                @([editor isAutomaticDashSubstitutionEnabled]),
                @([editor isAutomaticLinkDetectionEnabled]),
                @([editor isAutomaticTextReplacementEnabled])
            ];
        };
        NSArray *initialStates = [ToggleStates() copy];
        for (NSUInteger index = 0; index < [toggleSelectors count]; index++) {
            SEL selector = NSSelectorFromString([toggleSelectors objectAtIndex:index]);
            Check([NSApp sendAction:selector to:nil from:self],
                  [NSString stringWithFormat:@"%@ reaches the source first responder",
                   [toggleSelectors objectAtIndex:index]]);
            Pump();
            Check(![[ToggleStates() objectAtIndex:index] isEqual:[initialStates objectAtIndex:index]],
                  [NSString stringWithFormat:@"%@ changes its native editor state",
                   [toggleSelectors objectAtIndex:index]]);
            [NSApp sendAction:selector to:nil from:self]; Pump();
        }
        Check([ToggleStates() isEqual:initialStates], @"Text menu toggles restore their native states");
        [initialStates release];

        // Use Selection for Find follows AppKit: it installs the selected source
        // text in the shared Find pasteboard.
        Prepare(@"one needle two needle", NSMakeRange(4, 6));
        NSPasteboard *findBoard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
        [findBoard declareTypes:@[NSPasteboardTypeString] owner:nil];
        [findBoard setString:@"stale-find-value" forType:NSPasteboardTypeString];
        NSMenuItem *useSelection = [[[NSMenuItem alloc] initWithTitle:@"Use Selection"
            action:@selector(performFindPanelAction:) keyEquivalent:@""] autorelease];
        [useSelection setTag:NSFindPanelActionSetFindString];
        [editor performFindPanelAction:useSelection]; Pump();
        Check([[findBoard stringForType:NSPasteboardTypeString] isEqual:@"needle"],
              @"Use Selection for Find installs the selected source text");

        // A native Find Next consumes the existing Find pasteboard. nvALT's
        // wrapper instead replaces it with ordinary clipboard text whenever
        // the note search field is empty. Record the discrepancy directly.
        NSPasteboard *generalBoard = [NSPasteboard generalPasteboard];
        [generalBoard declareTypes:@[NSPasteboardTypeString] owner:nil];
        [generalBoard setString:@"clipboard-decoy" forType:NSPasteboardTypeString];
        [browser searchForString:@""]; Pump();
        NSMenuItem *findNext = [[[NSMenuItem alloc] initWithTitle:@"Find Next"
            action:@selector(performFindPanelAction:) keyEquivalent:@""] autorelease];
        [findNext setTag:NSFindPanelActionNext];
        [editor performFindPanelAction:findNext]; Pump();
        Check([[findBoard stringForType:NSPasteboardTypeString] isEqual:@"clipboard-decoy"],
              @"reproduced: Find Next replaces the active find string with clipboard text");

        NSTextView *nativeFindReference = Reference(@"one needle two needle", NSMakeRange(4, 6));
        [findBoard declareTypes:@[NSPasteboardTypeString] owner:nil];
        [findBoard setString:@"needle" forType:NSPasteboardTypeString];
        NSMenuItem *nativeNext = [[[NSMenuItem alloc] initWithTitle:@"Find Next"
            action:@selector(performTextFinderAction:) keyEquivalent:@""] autorelease];
        [nativeNext setTag:NSTextFinderActionNextMatch];
        [nativeFindReference performTextFinderAction:nativeNext]; Pump();
        Check([[findBoard stringForType:NSPasteboardTypeString] isEqual:@"needle"],
              @"fresh NSTextView Find Next preserves the active find string");

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        Check([defaults boolForKey:@"CheckSpellingInNoteBody"] &&
              [defaults boolForKey:@"TabKeyIndents"] &&
              [defaults boolForKey:@"AutoSuggestLinks"] &&
              [defaults boolForKey:@"UseSoftTabs"] &&
              [defaults boolForKey:@"UseAutoPairing"] &&
              [defaults boolForKey:@"rtl"] &&
              [defaults integerForKey:@"NumberOfSpacesInTab"] == 17,
              @"retired defaults were present throughout the runtime comparison");

        NSLog(@"LUU ROUND 3 REPRODUCED FIND REGRESSION (%lu checks)",
              (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults]
            removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"LUU ROUND 3 EXCEPTION %@ %@\n%@", [exception name], [exception reason],
              [exception callStackSymbols]);
        exit(1);
    }
}
@end
