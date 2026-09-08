- (void)nv_runTests {
    NVApplicationController *app = [NVApplicationController sharedController];
    NotationController *library = [self sharedNotationController];
    [self nv_activateBrowser];
    [app newWindow:self];
    AppController *peer = [[app browserControllers] lastObject];
    LinkingEditor *other = [peer valueForKey:@"textView"];
    Check(peer != self, @"presentation fixture has two native browser windows");
    NSArray *fixtures = @[
        @{@"syntax":@"markdown", @"source":@"# Stable heading\n\nhttps://example.com/a\n\nTyping: ", @"token":@"Stable"},
        @{@"syntax":@"html", @"source":@"<h1>Stable</h1><p>https://example.com/a</p><p>Typing: </p>", @"token":@"h1"},
        @{@"syntax":@"json", @"source":@"{\"stable\":42,\"url\":\"https://example.com/a\",\"typing\":\"\"}", @"token":@"stable"}
    ];
    for (NSUInteger dark = 0; dark < 2; dark++) {
        [[GlobalPrefs defaultPrefs] setBackgroundTextColor:dark ? [NSColor blackColor] : [NSColor whiteColor] sender:self];
        [[GlobalPrefs defaultPrefs] setForegroundTextColor:dark ? [NSColor whiteColor] : [NSColor blackColor] sender:self];
        for (NSDictionary *fixture in fixtures) {
            NSString *source = fixture[@"source"], *syntax = fixture[@"syntax"];
            NSString *label = [NSString stringWithFormat:@"%@ %@", syntax, dark ? @"dark" : @"light"];
            NoteObject *note = MakeNote(library, label, source);
            [self revealNote:note options:0]; [peer revealNote:note options:0];
            NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:syntax action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
            [item setRepresentedObject:syntax]; [self selectSourceSyntax:item];
            NSUInteger token = [source rangeOfString:fixture[@"token"]].location;
            NSUInteger link = [source rangeOfString:@"https://"].location;
            Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([other layoutManager]); }), [label stringByAppendingString:@" has current syntax in both native editors"]);
            Check([[textView layoutManager] delegate] == textView && [[other layoutManager] delegate] == other, @"color assertions use native layout drawing delegates");
            NSColor *initial = [[CRColor(textView, token) copy] autorelease];
            NSColor *peerInitial = [[CRColor(other, token) copy] autorelease];
            Check(initial && peerInitial && ![initial isEqual:[self foregrndColor]], [label stringByAppendingString:@" token has non-default drawn syntax color"]);
            Check(CRWait(^BOOL { return [[textView textStorage] attribute:NSLinkAttributeName atIndex:link effectiveRange:NULL] != nil; }), [label stringByAppendingString:@" native link detector recognizes fixture URL"]);
            [self nv_activateBrowser]; [window makeFirstResponder:textView];
            Check([window firstResponder] == textView, @"native Source owns keyboard focus before insertion");
            [textView insertText:@" " replacementRange:NSMakeRange([source length],0)];
            Check(!NVSourceCapturesAreCurrent([textView layoutManager]), @"character insertion makes semantic captures obsolete synchronously");
            Check([CRColor(textView,token) isEqual:initial] && [CRColor(other,token) isEqual:peerInitial], [label stringByAppendingString:@" provisional display retains drawn token color in both windows"]);
            Check([CRColor(textView,link) isEqual:[[textView preferredLinkAttributes] objectForKey:NSForegroundColorAttributeName]], [label stringByAppendingString:@" link foreground wins over retained syntax"]);
            [[textView layoutManager] addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(token,2)];
            [[other layoutManager] addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor cyanColor] forCharacterRange:NSMakeRange(token,2)];
            Check([CRDraw(textView,token,NULL)[NSBackgroundColorAttributeName] isEqual:[NSColor yellowColor]] && [CRDraw(other,token,NULL)[NSBackgroundColorAttributeName] isEqual:[NSColor cyanColor]], @"provisional syntax preserves distinct native search backgrounds per window");
            Check(CRDraw(textView,token,NULL)[NVSourceCaptureAttributeName] == nil, @"private capture never reaches drawn attribute result");
            [self finishEditing];
            Check([[[note contentString] string] isEqual:[source stringByAppendingString:@" "]] && [[other string] isEqual:[textView string]], @"color retention preserves exact committed source in both editors");
            [textView undo:self];
            Check(CRWait(^BOOL { return [[textView string] isEqual:source] && [[[note contentString] string] isEqual:source]; }), @"native Undo removes exactly the insertion");
            [textView redo:self];
            Check(CRWait(^BOOL { return [[textView string] isEqual:[source stringByAppendingString:@" "]]; }), @"native Redo restores exactly the insertion");
            Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]) && NVSourceCapturesAreCurrent([other layoutManager]); }), @"both windows eventually receive fresh captures after Undo and Redo");
            Check([CRColor(textView,token) isEqual:initial] && [CRColor(other,token) isEqual:peerInitial], @"fresh captures preserve the same appearance-specific drawn token color");
        }
    }
    NSString *original = @"# Composition heading\n\nTyping: ";
    NoteObject *note = MakeNote(library, @"Native composition", original);
    [self revealNote:note options:0]; [peer revealNote:note options:0];
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"Markdown" action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
    [item setRepresentedObject:@"markdown"]; [self selectSourceSyntax:item];
    Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]); }), @"composition starts with parsed heading");
    NSUInteger heading = [original rangeOfString:@"Composition"].location;
    NSColor *headingColor = [[CRColor(textView,heading) copy] autorelease];
    [self nv_activateBrowser]; [window makeFirstResponder:textView];
    NSAttributedString *marked = [[[NSAttributedString alloc] initWithString:@"draft" attributes:@{NSForegroundColorAttributeName:[NSColor magentaColor], NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle)}] autorelease];
    [textView setMarkedText:marked selectedRange:NSMakeRange(5,0) replacementRange:NSMakeRange([original length],0)];
    NSRange markedRange = [textView markedRange];
    Check(markedRange.location == [original length] && markedRange.length == 5 && [textView hasMarkedText], @"native marked-text API establishes an actual five-character composition");
    Check(!NVSourceCapturesAreCurrent([textView layoutManager]) && [CRColor(textView,heading) isEqual:headingColor], @"unaffected heading keeps its drawn color during pending composition analysis");
    // Adversarial but legal display state: old syntax spans can intersect a native
    // composition. Install one outside character processing, then call the actual
    // drawing delegate with native marked-text foreground and underline values.
    [[textView layoutManager] addTemporaryAttribute:NVSourceCaptureAttributeName value:@"text.title" forCharacterRange:markedRange];
    [[textView layoutManager] addTemporaryAttributes:@{NSForegroundColorAttributeName:[NSColor magentaColor], NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle)} forCharacterRange:markedRange];
    NSRange drawnRange;
    NSDictionary *drawn = CRDraw(textView,markedRange.location,&drawnRange);
    Check([drawn[NSForegroundColorAttributeName] isEqual:[NSColor magentaColor]] && [drawn[NSUnderlineStyleAttributeName] integerValue] == NSUnderlineStyleSingle, @"native marked appearance wins over an overlapping retained syntax capture");
    Check(drawn[NVSourceCaptureAttributeName] == nil && NSIntersectionRange(drawnRange,markedRange).length == drawnRange.length, @"marked drawing strips private syntax and bounds its effective range to the composition");
    [textView unmarkText]; [self finishEditing];
    Check([[[note contentString] string] isEqual:[original stringByAppendingString:@"draft"]], @"committing native composition preserves exact source");
    Check([[note contentString] attribute:NVSourceCaptureAttributeName atIndex:heading effectiveRange:NULL] == nil, @"composition display captures never enter the note model");
    [[textView layoutManager] removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:markedRange];
    [[textView layoutManager] removeTemporaryAttribute:NSUnderlineStyleAttributeName forCharacterRange:markedRange];
    Check(CRWait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]); }), @"composition eventually receives current syntax captures");
    NSLog(@"CONTRARIAN REVIEW COMPLETE: %lu checks", (unsigned long)Checks);
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
}
