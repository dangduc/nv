- (void)nv_luuCreateFromSearch:(NSString *)expected label:(NSString *)label {
    NotationController *library = [[NVApplicationController sharedController] library];
    NSUInteger before = [library totalNoteCount];
    Check([self searchFieldHasFocus], [label stringByAppendingString:@": native search editor owns focus"]);
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    Check([[NSApp mainMenu] performKeyEquivalent:event], [label stringByAppendingString:@": menu handles Command-N"]);
    NSLog(@"OBSERVATION: %@ synchronous Command-N duration %.3f ms", label,
        (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
    Pump();
    NoteObject *created = [[self selectedNoteObject] retain];
    Check(created && [library totalNoteCount] == before + 1,
        [label stringByAppendingString:@": exactly one note is selected and created"]);
    Check([[titleOfNote(created) dataUsingEncoding:NSUTF8StringEncoding]
        isEqual:[expected dataUsingEncoding:NSUTF8StringEncoding]],
        [label stringByAppendingString:@": full title preserves the field editor UTF-8 bytes"]);
    Check([[field stringValue] length] == 0 && [[[self browserSession] searchString] length] == 0,
        [label stringByAppendingString:@": consuming the mutable editor cannot erase the copied title"]);
    [self searchForString:@"Recovery query" mode:@"exact"];
    Check([[self browserSession] searchResultsAreCurrent] &&
        [[[self browserSession] searchString] isEqual:@"Recovery query"],
        [label stringByAppendingString:@": subsequent search publishes normally"]);
    [library removeNote:created]; [created release]; Pump();
}

- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        [prefsController setShowTitleInTopSection:NO sender:nil];
        [prefsController setAutoCompleteSearches:YES sender:nil];
        NSArray *cases = @[
            @[@"decomposed accents", @"Cafe\u0301, nai\u0308ve", @"exact"],
            @[@"joined emoji", @"Family 👨‍👩‍👧‍👦 and coder 👩🏽‍💻", @"fuzzy"],
            @[@"bidirectional text", @"עברית العربية English", @"exact"],
            @[@"surrounding spaces", @"  keep both margins  ", @"fuzzy"],
            @[@"whitespace-only title", @"   ", @"exact"],
            @[@"large title", [@"long-title-" stringByPaddingToLength:8192 withString:@"é📝" startingAtIndex:0], @"fuzzy"]
        ];
        for (NSArray *entry in cases) {
            [self searchForString:@"stale submitted query" mode:entry[2]];
            NSTextView *editor = (id)[field currentEditor];
            NSAttributedString *input = [[[NSAttributedString alloc] initWithString:entry[1]
                attributes:@{NSForegroundColorAttributeName: [NSColor redColor]}] autorelease];
            [editor insertText:input replacementRange:NSMakeRange(0, [[editor string] length])];
            [editor setSelectedRange:NSMakeRange(1, MIN((NSUInteger)2, [[editor string] length] - 1))];
            Check([[editor string] isEqual:entry[1]], [entry[0] stringByAppendingString:@": native insertion retains input"]);
            [self nv_luuCreateFromSearch:entry[1] label:entry[0]];
        }

        // A marked replacement covers only part of the input. A title must include
        // the unmarked prefix and suffix too, without retaining composition state.
        [self searchForString:@"before OLD after" mode:@"fuzzy"];
        NSTextView *editor = (id)[field currentEditor];
        [editor setMarkedText:@"日本語" selectedRange:NSMakeRange(3, 0) replacementRange:NSMakeRange(7, 3)];
        [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification
            object:field userInfo:@{@"NSFieldEditor": editor}]];
        Check([editor hasMarkedText] && [[editor string] isEqual:@"before 日本語 after"],
            @"partial composition retains its unmarked prefix and suffix");
        [self nv_luuCreateFromSearch:@"before 日本語 after" label:@"partial composition"];
        Check([[[NVApplicationController sharedController] library] totalNoteCount] == 0,
            @"all supplementary notes are removed from the disposable library");
        NSLog(@"DAN LUU-INSPIRED ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
