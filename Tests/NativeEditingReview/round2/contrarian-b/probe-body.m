    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();

        __block NSUInteger fixture = 0;
        void (^Prepare)(NSString *, NSArray *) = ^(NSString *source, NSArray *selections) {
            NoteObject *note = MakeNote(library,
                [NSString stringWithFormat:@"Contrarian B round two %lu", (unsigned long)fixture++], source);
            [browser revealNote:note options:0]; Pump();
            [[browser window] makeKeyAndOrderFront:self];
            [[browser window] makeFirstResponder:editor];
            [editor setSelectedRanges:selections affinity:NSSelectionAffinityDownstream stillSelecting:NO];
            Check([[browser window] firstResponder] == editor && [editor isEditable],
                  @"source editor is the editable first responder");
        };
        NSTextView *(^Reference)(NSString *, NSArray *) = ^NSTextView *(NSString *source, NSArray *selections) {
            NSTextView *reference = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
            [reference setRichText:NO];
            [reference setImportsGraphics:NO];
            [reference setString:source];
            [reference setSelectedRanges:selections affinity:NSSelectionAffinityDownstream stillSelecting:NO];
            return reference;
        };

        NSTextView *reference = Reference(@"defaults", @[[NSValue valueWithRange:NSMakeRange(0, 0)]]);
        Check([editor smartInsertDeleteEnabled] == [reference smartInsertDeleteEnabled],
              @"Smart Copy/Paste matches a plain NSTextView");
        Check([editor isContinuousSpellCheckingEnabled] == [reference isContinuousSpellCheckingEnabled],
              @"continuous spelling matches a plain NSTextView");
        Check([editor isGrammarCheckingEnabled] == [reference isGrammarCheckingEnabled],
              @"grammar checking matches a plain NSTextView");
        Check([editor isAutomaticSpellingCorrectionEnabled] == [reference isAutomaticSpellingCorrectionEnabled],
              @"spelling correction matches a plain NSTextView");
        Check([editor isAutomaticQuoteSubstitutionEnabled] == [reference isAutomaticQuoteSubstitutionEnabled],
              @"Smart Quotes match a plain NSTextView");
        Check([editor isAutomaticDashSubstitutionEnabled] == [reference isAutomaticDashSubstitutionEnabled],
              @"Smart Dashes match a plain NSTextView");
        Check([editor isAutomaticTextReplacementEnabled] == [reference isAutomaticTextReplacementEnabled],
              @"text replacement matches a plain NSTextView");
        Check([editor isAutomaticLinkDetectionEnabled] == [reference isAutomaticLinkDetectionEnabled],
              @"automatic link detection matches a plain NSTextView");
        Check([editor isAutomaticDataDetectionEnabled] == [reference isAutomaticDataDetectionEnabled],
              @"automatic data detection matches a plain NSTextView");
        Check([editor enabledTextCheckingTypes] == [reference enabledTextCheckingTypes],
              @"enabled text checking types match a plain NSTextView");
        Check([editor baseWritingDirection] == [reference baseWritingDirection],
              @"base writing direction matches a plain NSTextView");
        Check([editor infoForBinding:NSValueBinding] == nil &&
              [reference infoForBinding:NSValueBinding] == nil,
              @"source text is not diverted through a value binding");

        NSArray *edgeFixtures = @[
            @[@"a\r\nb", @3],
            @[@"a👨‍👩‍👧‍👦b", @12],
            @[@"ae\u0301b", @3],
            @[@"a🇻🇳b", @5],
            @[@"a1️⃣b", @4],
            @[@"אבג abc", @3],
            @[@"a\u2028b", @2]
        ];
        for (NSArray *fixtureData in edgeFixtures) {
            NSString *source = [fixtureData objectAtIndex:0];
            NSUInteger location = [[fixtureData objectAtIndex:1] unsignedIntegerValue];
            NSArray *selection = @[[NSValue valueWithRange:NSMakeRange(location, 0)]];
            Prepare(source, selection);
            reference = Reference(source, selection);
            [editor deleteBackward:self]; [reference deleteBackward:self]; Pump();
            Check([[editor string] isEqual:[reference string]] &&
                  [[editor selectedRanges] isEqual:[reference selectedRanges]],
                  [NSString stringWithFormat:@"Backspace and selection match NSTextView for %@", source]);
        }

        NSString *multi = @"one two three";
        NSArray *ranges = @[
            [NSValue valueWithRange:NSMakeRange(0, 3)],
            [NSValue valueWithRange:NSMakeRange(8, 5)]
        ];
        Prepare(multi, ranges);
        reference = Reference(multi, ranges);
        [editor insertText:@"X" replacementRange:NSMakeRange(NSNotFound, 0)];
        [reference insertText:@"X" replacementRange:NSMakeRange(NSNotFound, 0)]; Pump();
        Check([[editor string] isEqual:[reference string]] &&
              [[editor selectedRanges] isEqual:[reference selectedRanges]],
              @"multiple-selection replacement matches NSTextView");

        Prepare(@"alpha beta", @[[NSValue valueWithRange:NSMakeRange(10, 0)]]);
        reference = Reference(@"alpha beta", @[[NSValue valueWithRange:NSMakeRange(10, 0)]]);
        NSMenuItem *editorItem = [[[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@""] autorelease];
        NSMenuItem *referenceItem = [[[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@""] autorelease];
        Check([editor validateMenuItem:editorItem] == [reference validateMenuItem:referenceItem],
              @"ordinary first-responder menu validation matches NSTextView");

        // Install an observation shim only on NSTextView's implementation. If the
        // source subclass calls super, its modifier event must cross this boundary.
        SEL flagsSelector = @selector(flagsChanged:);
        Method inheritedFlagsMethod = class_getInstanceMethod([NSTextView class], flagsSelector);
        IMP nativeFlagsIMP = method_getImplementation(inheritedFlagsMethod);
        const char *flagsTypes = method_getTypeEncoding(inheritedFlagsMethod);
        class_addMethod([NSTextView class], flagsSelector, nativeFlagsIMP, flagsTypes);
        Method textViewFlagsMethod = class_getInstanceMethod([NSTextView class], flagsSelector);
        __block NSUInteger nativeDispatches = 0;
        IMP observingIMP = imp_implementationWithBlock(^(id target, NSEvent *event) {
            nativeDispatches++;
            ((void (*)(id, SEL, id))nativeFlagsIMP)(target, flagsSelector, event);
        });
        IMP replacedIMP = method_setImplementation(textViewFlagsMethod, observingIMP);

        NSEvent *shiftEvent = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
            location:NSZeroPoint modifierFlags:NSEventModifierFlagShift timestamp:0
            windowNumber:[[browser window] windowNumber] context:nil characters:@""
            charactersIgnoringModifiers:@"" isARepeat:NO keyCode:56];
        [reference flagsChanged:shiftEvent];
        Check(nativeDispatches == 1, @"plain NSTextView dispatches modifier changes through its native handler");
        nativeDispatches = 0;

        __block NSUInteger legacyNotifications = 0;
        id observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:@"ModTimersShouldReset" object:nil queue:nil usingBlock:^(NSNotification *note) {
                legacyNotifications++;
            }];
        [editor flagsChanged:shiftEvent]; Pump();
        Check(nativeDispatches == 0,
              @"source editor bypasses NSTextView's modifier-key handler");
        Check(legacyNotifications == 1,
              @"source modifier key triggers the legacy word-count timer path");
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        method_setImplementation(textViewFlagsMethod, replacedIMP);
        imp_removeBlock(observingIMP);

        NSLog(@"CONTRARIAN B ROUND 2 EVIDENCE PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"CONTRARIAN B ROUND 2 EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
