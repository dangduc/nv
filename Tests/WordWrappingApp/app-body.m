    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = app.library;
        GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
        LinkingEditor *editor = [self valueForKey:@"textView"];
        [self searchForString:@""]; Pump();
        Check([editor.layoutManager.typesetter isKindOfClass:NSClassFromString(@"NVSourceTypesetter")],
            @"the copied production app installs its source typesetter");
        Check(editor.layoutManager.delegate == editor, @"the source editor retains its glyph delegate");
        for (NSString *name in @[@"keyDown:", @"insertText:replacementRange:", @"deleteBackward:",
            @"drawInsertionPointInRect:color:turnedOn:"]) {
            SEL selector = NSSelectorFromString(name);
            Check(class_getMethodImplementation([LinkingEditor class],selector) ==
                class_getMethodImplementation([NSTextView class],selector),
                [NSString stringWithFormat:@"%@ remains native",name]);
        }

        NSArray *settings = @[@{@"font":@"Menlo-Regular",@"size":@14,@"width":@470},
            @{@"font":@"Helvetica",@"size":@19,@"width":@570},
            @{@"font":@"Menlo-Regular",@"size":@22,@"width":@690}];
        NSString *prose = @"Dark and light modes have separate note body color styles, including different syntax colors. "
            "Support more source formats and preserve complete words when the editor window becomes narrower. "
            "The preview remains separate from the editable source.\n\n"
            "Ordinary spaces still advance the insertion point when they overflow the available line width.";
        NSDictionary *sources = @{@"plain":prose, @"markdown":[@"# Word wrapping\n\n" stringByAppendingString:prose],
            @"html":[NSString stringWithFormat:@"<article>\n<p>%@</p>\n</article>",prose],
            @"json":[NSString stringWithFormat:@"{\n  \"description\": \"%@\"\n}",[prose stringByReplacingOccurrencesOfString:@"\n" withString:@" "]]};
        NSMutableArray *records = [NSMutableArray array];
        for (NSDictionary *setting in settings) {
            NSFont *font = [NSFont fontWithName:setting[@"font"] size:[setting[@"size"] doubleValue]];
            Check(font != nil, @"the requested native test font is available");
            [prefs setNoteBodyFont:font sender:self];
            for (NSString *syntax in @[@"plain",@"markdown",@"html",@"json"]) {
                NoteObject *note = MakeNote(library,[NSString stringWithFormat:@"Words %@ %@",syntax,setting[@"font"]],sources[syntax]);
                [note setSourceSyntaxIdentifier:syntax];
                [self revealNote:note options:0]; Pump();
                [self.window setContentSize:NSMakeSize([setting[@"width"] doubleValue],640)]; Pump();
                Check([[editor.textStorage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] isEqual:font],
                    @"the fixture uses the chosen font in the actual source storage");
                NSArray *lines = WordWrapLines(editor);
                Check(lines.count > [[editor.string componentsSeparatedByString:@"\n"] count],
                    @"the prose contains automatic visual line breaks");
                Check(WordWrapPreservesWords(editor), @"visual line breaks preserve each fitting prose word");
                Check([editor.string isEqual:sources[syntax]] && [[[note contentString] string] isEqual:sources[syntax]],
                    @"layout preserves the exact source and note body");
                [records addObject:@{@"setting":setting,@"syntax":syntax,@"lines":lines}];
            }
        }

        // In the rejected native-word-wrap approach, appended spaces moved beta.
        for (NSDictionary *setting in @[@{@"font":@"Menlo-Regular",@"size":@18,@"width":@560},settings[1]]) {
            [prefs setNoteBodyFont:[NSFont fontWithName:setting[@"font"] size:[setting[@"size"] doubleValue]] sender:self];
            NoteObject *note = MakeNote(library,@"Stable words while holding Space",@"alpha beta");
            [note setSourceSyntaxIdentifier:@"plain"];
            [self revealNote:note options:0]; Pump();
            [self.window setContentSize:NSMakeSize([setting[@"width"] doubleValue],640)];
            [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:editor]; Pump();
            Check(self.window.firstResponder == editor, @"the actual source editor receives repeated Space events");
            editor.selectedRange = NSMakeRange(editor.string.length,0);
            NSArray *positions = [[WordWrapPositions(editor,NSMakeRange(0,10)) copy] autorelease];
            NSMutableString *expected = [NSMutableString stringWithString:@"alpha beta"];
            NSRect previous = WordWrapCaret(editor);
            NSUInteger transitions = 0;
            NSMutableArray *thresholds = [NSMutableArray array];
            for (NSUInteger count = 1; count <= 201; count++) {
                WordWrapSpaceKey(editor,count > 1);
                [expected appendString:@" "];
                NSRect caret = WordWrapCaret(editor);
                Check([editor.string isEqual:expected] && NSEqualRanges(editor.selectedRange,NSMakeRange(expected.length,0)),
                    @"repeated Space preserves exact source characters and the logical insertion point");
                Check(WordWrapCaretAdvances(previous,caret), @"repeated Space advances native caret geometry");
                Check([positions isEqual:WordWrapPositions(editor,NSMakeRange(0,10))],
                    @"appended spaces leave every existing letter at its original visual position");
                if (NSMinY(caret) > NSMinY(previous)+0.02) transitions++;
                if (count == 39 || count == 40) [thresholds addObject:@{@"spaces":@(count),@"caret":NSStringFromRect(caret)}];
                previous = caret;
            }
            Check(transitions >= 2, @"repeated spaces cross multiple visual line boundaries");
            [self finishEditing]; Pump();
            Check([[[note contentString] string] isEqual:expected], @"repeated spaces commit unchanged to the note model");
            [[note undoManager] removeAllActions];
            [editor deleteBackward:self]; [self finishEditing]; Pump();
            Check(editor.string.length == expected.length-1, @"native Backspace removes one trailing space");
            [editor undo:self]; Pump();
            Check([editor.string isEqual:expected], @"shared Undo restores the removed space");
            [editor redo:self]; Pump();
            Check(editor.string.length == expected.length-1, @"shared Redo removes the same space again");
            [records addObject:@{@"setting":setting,@"repeatTransitions":@(transitions),@"thresholds":thresholds}];
        }

        [prefs setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        NoteObject *shared = MakeNote(library,@"Shared window word wrapping",prose);
        NoteObject *other = MakeNote(library,@"Different paragraph cache",@"unrelated words with a different paragraph length\nsecond paragraph");
        [self revealNote:shared options:0]; Pump();
        [app newWindow:self]; Pump();
        AppController *peer = [app.browserControllers lastObject];
        [peer revealNote:shared options:0]; Pump();
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        NVNoteEditingSession *session = [app editingSessionForNote:shared];
        id firstTypesetter = editor.layoutManager.typesetter, secondTypesetter = peerEditor.layoutManager.typesetter;
        Check(editor.textStorage == peerEditor.textStorage && editor.textStorage == session.textStorage,
            @"both windows retain the shared note storage");
        Check(firstTypesetter != secondTypesetter && [secondTypesetter isKindOfClass:NSClassFromString(@"NVSourceTypesetter")],
            @"each real editor owns a distinct source typesetter");
        [self.window setContentSize:NSMakeSize(470,640)]; [peer.window setContentSize:NSMakeSize(840,640)]; Pump();
        Check(WordWrapLines(editor).count > WordWrapLines(peerEditor).count &&
            WordWrapPreservesWords(editor) && WordWrapPreservesWords(peerEditor),
            @"shared source wraps whole words independently at each window width");
        NSArray *firstLayout = [[WordWrapLines(editor) copy] autorelease];
        [peer revealNote:other options:0]; Pump();
        Check([firstLayout isEqual:WordWrapLines(editor)] && editor.textStorage != peerEditor.textStorage,
            @"a peer note switch cannot reuse its paragraph cache in the original window");
        [peer revealNote:shared options:0]; Pump();
        Check(editor.textStorage == peerEditor.textStorage && editor.layoutManager.typesetter == firstTypesetter &&
            peerEditor.layoutManager.typesetter == secondTypesetter, @"note reattachment preserves independent typesetter ownership");

        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:editor];
        editor.selectedRange = NSMakeRange(editor.string.length,0);
        NSPasteboard *board = [NSPasteboard pasteboardWithUniqueName];
        [board declareTypes:@[NSPasteboardTypeString] owner:nil];
        NSString *pasted = @"\n\nPasted words wrap naturally. Unicode remains unchanged: Việt 中文 👩🏽‍💻.\tTab followed by spaces    ";
        [board setString:pasted forType:NSPasteboardTypeString];
        [[shared undoManager] removeAllActions];
        Check([editor readSelectionFromPasteboard:board type:NSPasteboardTypeString], @"native paste reads a private pasteboard");
        [self finishEditing]; Pump();
        NSString *combined = [prose stringByAppendingString:pasted];
        Check([editor.string isEqual:combined] && [peerEditor.string isEqual:combined] &&
            [[[shared contentString] string] isEqual:combined], @"paste preserves exact Unicode source in both windows and the model");
        Check(WordWrapPreservesWords(editor) && WordWrapPreservesWords(peerEditor), @"pasted prose wraps whole words in both windows");
        [editor undo:self]; Pump();
        Check([editor.string isEqual:prose] && [peerEditor.string isEqual:prose], @"paste Undo restores both shared editors");
        [editor redo:self]; Pump();
        Check([editor.string isEqual:combined] && [peerEditor.string isEqual:combined], @"paste Redo restores both shared editors");
        [board releaseGlobally];
        for (NSString *syntax in @[@"markdown",@"html",@"json",@"plain"]) {
            [shared setSourceSyntaxIdentifier:syntax]; Pump();
            Check([editor.string isEqual:combined] && [peerEditor.string isEqual:combined] &&
                WordWrapPreservesWords(editor) && WordWrapPreservesWords(peerEditor),
                @"changing source syntax keeps word boundaries and shared source intact");
        }

        [self finishEditing]; Pump(); Pump();
        NSAttributedString *attributes = [editor.textStorage copy];
        uint64_t generation = session.sourceGeneration;
        CFAbsoluteTime modified = modifiedDateOfNote(shared);
        BOOL undo = [[shared undoManager] canUndo], redo = [[shared undoManager] canRedo];
        editor.selectedRange = NSMakeRange(7,0); peerEditor.selectedRange = NSMakeRange(20,0);
        for (NSUInteger pass = 0; pass < 8; pass++) {
            [self.window setContentSize:NSMakeSize(470+(pass%3)*115,640)];
            [editor.layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0,editor.string.length) actualCharacterRange:NULL];
            WordWrapLines(peerEditor);
            Check(WordWrapPreservesWords(editor), @"resize and repeated layout retain complete words");
        }
        Check([editor.textStorage isEqualToAttributedString:attributes] && session.sourceGeneration == generation &&
            modifiedDateOfNote(shared) == modified && ![session hasPendingTextChanges],
            @"layout leaves source attributes, generation, modified date, and dirty state unchanged");
        Check([[shared undoManager] canUndo] == undo && [[shared undoManager] canRedo] == redo &&
            NSEqualRanges(editor.selectedRange,NSMakeRange(7,0)) && NSEqualRanges(peerEditor.selectedRange,NSMakeRange(20,0)),
            @"layout preserves Undo, Redo, and each window selection");
        [attributes release];
        [peer.window close]; Pump();
        Check([editor.string isEqual:combined] && WordWrapPreservesWords(editor),
            @"the surviving window continues to lay out after its peer closes");

        // This is a native bitmap of the actual copied app, with disposable content.
        NoteObject *example = MakeNote(library,@"Word wrapping",prose);
        [example setSourceSyntaxIdentifier:@"plain"];
        [self revealNote:example options:0];
        [prefs setShowNotesList:NO sender:nil];
        [prefs setShowTitleInTopSection:YES sender:nil];
        [prefs setShowTagsInTopSection:NO sender:nil];
        [prefs setShowBodyControlsInTopSection:YES sender:nil];
        [self.window setContentSize:NSMakeSize(540,580)];
        if (@available(macOS 10.14, *)) [self.window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [self.window makeFirstResponder:nil]; Pump();
        Check(WordWrapPreservesWords(editor), @"the screenshot fixture displays complete words");
        Check(WordWrapCapture(self.window,[NSString stringWithUTF8String:getenv("NV_WORD_WRAP_CAPTURE")]),
            @"save the native production-window screenshot");
        Check([[NSJSONSerialization dataWithJSONObject:@{@"checks":@(Checks),@"fixtures":records}
            options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[NSString stringWithUTF8String:getenv("NV_WORD_WRAP_RESULT")] atomically:YES],
            @"save observed line breaks and 39/40-space caret geometry");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"WORD WRAPPING APP PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"WORD WRAPPING APP EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
