
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();

        NSArray *nativeSelectors = @[
            NSStringFromSelector(@selector(deleteBackward:)),
            NSStringFromSelector(@selector(insertNewline:)),
            NSStringFromSelector(@selector(insertTab:)),
            NSStringFromSelector(@selector(insertBacktab:)),
            NSStringFromSelector(@selector(performKeyEquivalent:)),
            NSStringFromSelector(@selector(keyDown:)),
            NSStringFromSelector(@selector(moveToBeginningOfLine:)),
            NSStringFromSelector(@selector(selectionRangeForProposedRange:granularity:)),
            NSStringFromSelector(@selector(insertText:)),
            NSStringFromSelector(@selector(insertText:replacementRange:)),
            NSStringFromSelector(@selector(rangeForUserCompletion)),
            NSStringFromSelector(@selector(flagsChanged:))
        ];
        for (NSString *selectorName in nativeSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            Check(method_getImplementation(class_getInstanceMethod([LinkingEditor class], selector)) ==
                  method_getImplementation(class_getInstanceMethod([NSTextView class], selector)),
                  [NSString stringWithFormat:@"%@ uses the native NSTextView implementation", selectorName]);
        }

        SEL bodyCompletionSelector = @selector(textView:completions:forPartialWordRange:indexOfSelectedItem:);
        id sourceDelegate = [editor delegate];
        Check(sourceDelegate == browser, @"source editor delegates to its browser controller");
        Check(![sourceDelegate respondsToSelector:bodyCompletionSelector],
              @"source editor delegate does not provide note-title completions");
        Check([browser respondsToSelector:@selector(control:textView:completions:forPartialWordRange:indexOfSelectedItem:)],
              @"tag-field completion delegate remains available");

        Method iBeamMethod = class_getClassMethod([NSCursor class], @selector(IBeamCursor));
        IMP nativeIBeamImplementation = method_getImplementation(iBeamMethod);
        NSColor *originalBackground = [[editor backgroundColor] retain];
        [editor setBackgroundColor:[NSColor blackColor]];
        Check(method_getImplementation(iBeamMethod) == nativeIBeamImplementation,
              @"source editor appearance cannot replace the process-wide I-beam implementation");
        Check([editor insertionPointColor] != nil,
              @"source editor retains a view-local insertion-point color");
        [editor setBackgroundColor:originalBackground];
        [originalBackground release];

        NSTextFinder *finder = [editor valueForKey:@"textFinder"];
        Check(finder != nil && [editor usesFindBar] && [finder client] == editor,
              @"source editor owns one supported NSTextFinder client path");

        __block NSUInteger fixtureNumber = 0;
        void (^Prepare)(NSString *) = ^(NSString *source) {
            NoteObject *note = MakeNote(library, [NSString stringWithFormat:@"Native source editing %lu", (unsigned long)fixtureNumber++], source);
            [browser revealNote:note options:0]; Pump();
            [[browser window] makeKeyAndOrderFront:self];
            [[browser window] makeFirstResponder:editor];
            Check([[browser window] firstResponder] == editor && [editor isEditable], @"source editor owns keyboard focus");
        };
        NSTextView *(^Reference)(NSString *, NSRange) = ^NSTextView *(NSString *source, NSRange selection) {
            NSTextView *reference = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
            [reference setRichText:NO];
            [reference setString:source];
            [reference setSelectedRange:selection];
            return reference;
        };

        NSTextView *initialReference = Reference(@"", NSMakeRange(0, 0));
        Check([editor smartInsertDeleteEnabled] == [initialReference smartInsertDeleteEnabled],
              @"decoded source editor starts with native smart insert/delete behavior");

        NSDictionary *bodyAttributes = [prefsController noteBodyAttributes];
        Check([bodyAttributes objectForKey:NSFontAttributeName] != nil,
              @"source presentation retains the configured body font");
        Check([bodyAttributes objectForKey:NSParagraphStyleAttributeName] == nil,
              @"source attributes leave paragraph and tab layout to AppKit");

        Prepare(@"\tvalue");
        NSDictionary *sourceAttributes = [[editor textStorage] attributesAtIndex:0 effectiveRange:NULL];
        NSParagraphStyle *nativeParagraph = [NSParagraphStyle defaultParagraphStyle];
        Check([sourceAttributes objectForKey:NSFontAttributeName] != nil &&
              [sourceAttributes objectForKey:NSParagraphStyleAttributeName] == nil,
              @"stored source text retains font presentation without a paragraph override");
        Check([[nativeParagraph tabStops] count] > 0 && [nativeParagraph defaultTabInterval] == 0.0,
              @"AppKit supplies the source editor's native tab-stop layout");

        Prepare(@"    alpha");
        [editor setSelectedRange:NSMakeRange(9, 0)];
        NSTextView *reference = Reference(@"    alpha", NSMakeRange(9, 0));
        [editor insertNewline:self]; [reference insertNewline:self]; Pump();
        Check([[editor string] isEqual:[reference string]] && [[editor string] isEqual:@"    alpha\n"],
              @"Return uses native behavior without carrying indentation");

        Prepare(@"- item");
        [editor setSelectedRange:NSMakeRange(6, 0)];
        reference = Reference(@"- item", NSMakeRange(6, 0));
        [editor insertNewline:self]; [reference insertNewline:self]; Pump();
        Check([[editor string] isEqual:[reference string]] && [[editor string] isEqual:@"- item\n"],
              @"Return does not continue source list markers");

        NSString *legacyBlank = @"open, relaxed        o  a\n          out     ê  ô  â  u\n           in  i  e  ơ  ă  ư\n\n\n    \n";
        Prepare(legacyBlank);
        [editor setSelectedRange:NSMakeRange([legacyBlank length], 0)];
        reference = Reference(legacyBlank, NSMakeRange([legacyBlank length], 0));
        [editor deleteBackward:self]; [reference deleteBackward:self]; Pump();
        Check([[editor string] isEqual:[reference string]] && [[editor string] hasSuffix:@"    "],
              @"Backspace treats legacy blank-line whitespace as ordinary source text");

        Prepare(@"alpha\n    omega");
        [editor setSelectedRange:NSMakeRange(10, 0)];
        reference = Reference(@"alpha\n    omega", NSMakeRange(10, 0));
        [editor deleteBackward:self]; [reference deleteBackward:self]; Pump();
        Check([[editor string] isEqual:[reference string]] && [[editor string] isEqual:@"alpha\n   omega"],
              @"Backspace removes one native text unit instead of a soft-tab indent");

        Prepare(@"value");
        [editor setSelectedRange:NSMakeRange(5, 0)];
        reference = Reference(@"value", NSMakeRange(5, 0));
        [editor insertTab:self]; [reference insertTab:self]; Pump();
        Check([[editor string] isEqual:[reference string]] && NSEqualRanges([editor selectedRange], [reference selectedRange]),
              @"Tab matches a plain NSTextView");

        Prepare(@"");
        [editor insertText:@"(" replacementRange:NSMakeRange(0, 0)]; Pump();
        Check([[editor string] isEqual:@"("], @"typing an opening character does not insert a pair");

        Prepare(@"()");
        [editor setSelectedRange:NSMakeRange(1, 0)];
        [editor deleteBackward:self]; Pump();
        Check([[editor string] isEqual:@")"], @"Backspace between a pair removes only the preceding character");

        Prepare(@"[[Al");
        [editor setSelectedRange:NSMakeRange(4, 0)];
        [editor insertText:@"p" replacementRange:[editor selectedRange]]; Pump();
        Check([[editor string] isEqual:@"[[Alp"], @"typing a note link does not invoke title completion");

        Prepare(@"(alpha)");
        reference = Reference(@"(alpha)", NSMakeRange(0, 1));
        NSRange editorSelection = [editor selectionRangeForProposedRange:NSMakeRange(0, 1) granularity:NSSelectByWord];
        NSRange referenceSelection = [reference selectionRangeForProposedRange:NSMakeRange(0, 1) granularity:NSSelectByWord];
        Check(NSEqualRanges(editorSelection, referenceSelection), @"word selection matches a plain NSTextView");

        BOOL nativeSpelling = [reference isContinuousSpellCheckingEnabled];
        NSWritingDirection nativeDirection = [reference baseWritingDirection];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in @[@"CheckSpellingInNoteBody", @"TabKeyIndents", @"AutoSuggestLinks", @"UseSoftTabs", @"UseAutoPairing", @"rtl"])
            [defaults setBool:YES forKey:key];
        [defaults synchronize]; Pump();
        Check([editor isContinuousSpellCheckingEnabled] == nativeSpelling,
              @"removed spelling preference cannot override NSTextView behavior");
        Check([editor baseWritingDirection] == nativeDirection,
              @"removed global RTL preference cannot override NSTextView direction");

        Check(![prefsController respondsToSelector:@selector(tabKeyIndents)] &&
              ![prefsController respondsToSelector:@selector(checkSpellingAsYouType)] &&
              ![prefsController respondsToSelector:@selector(linksAutoSuggested)] &&
              ![prefsController respondsToSelector:@selector(softTabs)] &&
              ![prefsController respondsToSelector:@selector(useAutoPairing)] &&
              ![prefsController respondsToSelector:@selector(rtl)],
              @"legacy editing and global RTL preference APIs are removed");

        NoteObject *undoNote = [browser selectedNoteObject];
        [[undoNote undoManager] removeAllActions];
        [editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
        [editor insertText:@"!" replacementRange:[editor selectedRange]]; Pump();
        [editor undo:self]; Pump();
        Check([[[undoNote contentString] string] isEqual:[editor string]] && ![[editor string] hasSuffix:@"!"],
              @"shared note Undo remains connected to native source edits");

        NSLog(@"SOURCE EDITING PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"SOURCE EDITING EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
