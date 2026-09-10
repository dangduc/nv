    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();

        NSArray *nativeBoundarySelectors = @[
            NSStringFromSelector(@selector(keyDown:)),
            NSStringFromSelector(@selector(performKeyEquivalent:)),
            NSStringFromSelector(@selector(insertTab:)),
            NSStringFromSelector(@selector(insertBacktab:)),
            NSStringFromSelector(@selector(readSelectionFromPasteboard:type:)),
            NSStringFromSelector(@selector(writeSelectionToPasteboard:type:)),
            NSStringFromSelector(@selector(dragSelectionWithEvent:offset:slideBack:)),
            NSStringFromSelector(@selector(validRequestorForSendType:returnType:))
        ];
        for (NSString *selectorName in nativeBoundarySelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            Method editorMethod = class_getInstanceMethod([LinkingEditor class], selector);
            Method nativeMethod = class_getInstanceMethod([NSTextView class], selector);
            Check(editorMethod && nativeMethod &&
                  method_getImplementation(editorMethod) == method_getImplementation(nativeMethod),
                  [NSString stringWithFormat:@"%@ is inherited from NSTextView", selectorName]);
        }

        __block NSUInteger fixtureNumber = 0;
        void (^Prepare)(NSString *) = ^(NSString *source) {
            NoteObject *note = MakeNote(library,
                                        [NSString stringWithFormat:@"Contrarian native boundary %lu", (unsigned long)fixtureNumber++],
                                        source);
            [browser revealNote:note options:0]; Pump();
            [[browser window] makeKeyAndOrderFront:self];
            [[browser window] makeFirstResponder:editor];
            Check([[browser window] firstResponder] == editor && [editor isEditable],
                  @"source editor is the active first responder");
        };
        NSTextView *(^Reference)(NSString *) = ^NSTextView *(NSString *source) {
            NSTextView *reference = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
            [reference setRichText:NO];
            [reference setImportsGraphics:NO];
            [reference setString:source];
            return reference;
        };

        Prepare(@"native source");
        NSTextView *reference = Reference(@"native source");
        Check([editor isContinuousSpellCheckingEnabled] == [reference isContinuousSpellCheckingEnabled],
              @"continuous spelling starts at the native NSTextView default");
        Check([editor isAutomaticSpellingCorrectionEnabled] == [reference isAutomaticSpellingCorrectionEnabled],
              @"automatic spelling correction starts at the native NSTextView default");
        Check([editor isAutomaticQuoteSubstitutionEnabled] == [reference isAutomaticQuoteSubstitutionEnabled],
              @"smart quotes start at the native NSTextView default");
        Check([editor isAutomaticDashSubstitutionEnabled] == [reference isAutomaticDashSubstitutionEnabled],
              @"smart dashes start at the native NSTextView default");
        Check([editor isAutomaticTextReplacementEnabled] == [reference isAutomaticTextReplacementEnabled],
              @"text replacement starts at the native NSTextView default");
        BOOL smartInsertParity = [editor smartInsertDeleteEnabled] == [reference smartInsertDeleteEnabled];
        NSLog(@"REVIEW OBSERVATION: smart insert/delete editor=%d native=%d",
              [editor smartInsertDeleteEnabled], [reference smartInsertDeleteEnabled]);

        NSArray *legacyKeys = @[@"CheckSpellingInNoteBody", @"TabKeyIndents", @"AutoSuggestLinks",
                                @"UseSoftTabs", @"UseAutoPairing", @"rtl", @"UseSmartInsertDelete",
                                @"NVSourceSmartQuotes", @"NVSourceSmartDashes", @"NVSourceTextReplacement",
                                @"NVSourceSmartInsertDelete"];
        NSArray *featureValues = @[
            @([editor isContinuousSpellCheckingEnabled]),
            @([editor isAutomaticSpellingCorrectionEnabled]),
            @([editor isAutomaticQuoteSubstitutionEnabled]),
            @([editor isAutomaticDashSubstitutionEnabled]),
            @([editor isAutomaticTextReplacementEnabled]),
            @([editor smartInsertDeleteEnabled]),
            @([editor baseWritingDirection])
        ];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in legacyKeys) [defaults setBool:YES forKey:key];
        [defaults synchronize]; Pump();
        NSArray *afterLegacyDefaults = @[
            @([editor isContinuousSpellCheckingEnabled]),
            @([editor isAutomaticSpellingCorrectionEnabled]),
            @([editor isAutomaticQuoteSubstitutionEnabled]),
            @([editor isAutomaticDashSubstitutionEnabled]),
            @([editor isAutomaticTextReplacementEnabled]),
            @([editor smartInsertDeleteEnabled]),
            @([editor baseWritingDirection])
        ];
        Check([featureValues isEqual:afterLegacyDefaults],
              @"legacy saved defaults cannot mutate native editor-local features");

        SEL toggleCases[] = {
            @selector(toggleContinuousSpellChecking:),
            @selector(toggleSmartInsertDelete:),
            @selector(toggleAutomaticQuoteSubstitution:),
            @selector(toggleAutomaticDashSubstitution:),
            @selector(toggleAutomaticTextReplacement:)
        };
        for (NSUInteger index = 0; index < sizeof(toggleCases) / sizeof(toggleCases[0]); index++) {
            SEL action = toggleCases[index];
            id target = [NSApp targetForAction:action to:nil from:nil];
            Check(target == editor, [NSString stringWithFormat:@"%@ resolves through the first responder", NSStringFromSelector(action)]);
        }

        BOOL beforeSpell = [editor isContinuousSpellCheckingEnabled];
        Check([NSApp sendAction:@selector(toggleContinuousSpellChecking:) to:nil from:nil],
              @"native spelling toggle is routable"); Pump();
        Check([editor isContinuousSpellCheckingEnabled] != beforeSpell,
              @"native spelling toggle changes only the active editor state");
        [NSApp sendAction:@selector(toggleContinuousSpellChecking:) to:nil from:nil]; Pump();

        Prepare(@"before ");
        [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
        reference = Reference(@"before ");
        [reference setSelectedRange:NSMakeRange([[reference string] length], 0)];
        NSPasteboard *readPasteboard = [NSPasteboard pasteboardWithUniqueName];
        NSDictionary *foreignAttributes = @{NSFontAttributeName:[NSFont boldSystemFontOfSize:25],
                                             NSForegroundColorAttributeName:[NSColor redColor]};
        NSAttributedString *rich = [[[NSAttributedString alloc] initWithString:@"styled" attributes:foreignAttributes] autorelease];
        NSData *rtf = [rich RTFFromRange:NSMakeRange(0, [rich length]) documentAttributes:@{}];
        [readPasteboard declareTypes:@[NSRTFPboardType] owner:nil];
        [readPasteboard setData:rtf forType:NSRTFPboardType];
        BOOL editorRead = [editor readSelectionFromPasteboard:readPasteboard type:NSRTFPboardType];
        BOOL referenceRead = [reference readSelectionFromPasteboard:readPasteboard type:NSRTFPboardType]; Pump();
        Check(editorRead == referenceRead && [[editor string] isEqual:[reference string]] &&
              [[editor string] isEqual:@"before styled"],
              @"rich paste imports the same source characters as a plain NSTextView");
        NSDictionary *pastedAttributes = [[editor textStorage] attributesAtIndex:8 effectiveRange:NULL];
        Check(![[pastedAttributes objectForKey:NSFontAttributeName] isEqual:[NSFont boldSystemFontOfSize:25]] &&
              ![[pastedAttributes objectForKey:NSForegroundColorAttributeName] isEqual:[NSColor redColor]],
              @"plain source paste does not retain foreign font or foreground color");

        [editor setSelectedRange:NSMakeRange(7, 6)];
        NSPasteboard *writePasteboard = [NSPasteboard pasteboardWithUniqueName];
        [writePasteboard declareTypes:@[NSStringPboardType] owner:nil];
        BOOL editorWrote = [editor writeSelectionToPasteboard:writePasteboard type:NSStringPboardType];
        Check(editorWrote && [[writePasteboard stringForType:NSStringPboardType] isEqual:@"styled"],
              @"native copy writes selected source text");

        if (!smartInsertParity)
            NSLog(@"CONTRARIAN FINDING: decoded source editor does not use native smart insert/delete default");
        NSLog(@"CONTRARIAN NATIVE BOUNDARY PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(smartInsertParity ? 0 : 2);
    } @catch (NSException *exception) {
        NSLog(@"CONTRARIAN NATIVE BOUNDARY EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
