
    @try {
        HistoryRecords = [NSMutableArray array];
        Class typeClass = NSClassFromString(@"NVSourceTypesetter");
        Check(typeClass && class_getInstanceVariable(typeClass, "paragraphMeasure") &&
            class_getInstanceVariable(typeClass, "lineBreaks"), @"the actual app supplies the observed production typesetter");
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = app.library;
        GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
        [prefs setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        [self searchForString:@""]; Pump();
        LinkingEditor *editor = [self valueForKey:@"textView"];
        NSString *phase = [NSString stringWithUTF8String:getenv("NV_HISTORY_PHASE")];
        NSString *expectedPath = [TestDirectory stringByAppendingPathComponent:@"expected.json"];
        if ([phase isEqual:@"reopen"]) {
            NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:expectedPath]
                options:0 error:NULL];
            Check(expected != nil && [[library allNotes] count] == 1, @"P2 fresh app process reopens exactly the saved note");
            NoteObject *note = [[library allNotes] lastObject];
            Check([HistoryUUID(note) isEqual:expected[@"uuid"]] && [titleOfNote(note) isEqual:expected[@"title"]],
                @"P2 reopen preserves the saved note UUID and title");
            [self revealNote:note options:0]; Pump();
            [self.window setContentSize:NSMakeSize(535, 610)]; Pump();
            Check(HistoryExactSource(editor, note, expected[@"source"]),
                @"P2 reopened model and editor preserve exact saved UTF-8 source including spaces and Unicode");
            HistoryObserve(editor, @"P2 fresh process after reopening saved source");
            Check(HistoryExactSource(editor, note, expected[@"source"]),
                @"P2 fresh layout does not rewrite the reopened source");
        } else {
            NSString *base = @"The editor owns its layout while the note owns shared history. "
                "Words must remain complete as the source window changes width.\n"
                "Unicode source stays exact: Việt 中文 👩🏽‍💻 a\u0301.\tThe tab and ordinary spaces    remain part of the source.";
            NoteObject *note = MakeNote(library, @"Origin closed before Undo", base);
            [self revealNote:note options:0]; Pump();
            [self.window setContentSize:NSMakeSize(490, 610)];
            [app newWindow:self]; Pump();
            AppController *origin = [app.browserControllers lastObject];
            [origin revealNote:note options:0]; Pump();
            LinkingEditor *originEditor = [origin valueForKey:@"textView"];
            [origin.window setContentSize:NSMakeSize(805, 610)]; Pump();
            Check(editor.textStorage == originEditor.textStorage &&
                editor.layoutManager.typesetter != originEditor.layoutManager.typesetter,
                @"P1 both source windows share one storage and own separate typesetters");
            HistoryObserve(editor, @"P1 original source in surviving editor");
            [[note undoManager] removeAllActions];
            NSString *addition = [@"\nOrigin window appended this final paragraph before it closed.\n"
                stringByAppendingString:[@"" stringByPaddingToLength:72 withString:@" " startingAtIndex:0]];
            NSString *changed = [base stringByAppendingString:addition];
            HistoryReplace(origin, originEditor, NSMakeRange(base.length, 0), addition);
            Check(HistoryExactSource(editor, note, changed) && HistoryExactSource(originEditor, note, changed),
                @"P1 edit from the originating window commits exact source to both editors and the model");
            HistoryObserve(originEditor, @"P1 originating editor before closure");
            [origin.window close]; Pump();
            Check(app.browserControllers.count == 1 && [note.undoManager canUndo],
                @"P1 the shared Undo action survives closure of its originating window");
            [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:editor];
            [self.window setContentSize:NSMakeSize(715, 610)]; Pump();
            [editor undo:self]; Pump();
            Check(HistoryExactSource(editor, note, base), @"P1 survivor Undo restores the exact pre-edit source and model");
            HistoryObserve(editor, @"P1 Undo after originating window closes");
            [editor redo:self]; Pump();
            Check(HistoryExactSource(editor, note, changed), @"P1 survivor Redo restores the exact source from the closed editor");
            HistoryObserve(editor, @"P1 Redo after originating window closes");

            // P2: repeated layout is display-only, then a new process must read
            // the same UTF-8 source and note identity from the flushed library.
            NVNoteEditingSession *session = [app editingSessionForNote:note];
            uint64_t generation = session.sourceGeneration;
            CFAbsoluteTime modified = modifiedDateOfNote(note);
            BOOL undo = [note.undoManager canUndo], redo = [note.undoManager canRedo];
            for (NSNumber *width in @[@510, @745, @535]) {
                [self.window setContentSize:NSMakeSize(width.doubleValue, 610)]; Pump();
                [editor.layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0, editor.string.length)
                    actualCharacterRange:NULL];
                HistoryObserve(editor, [NSString stringWithFormat:@"P2 resize and full invalidation at %@", width]);
                Check(HistoryExactSource(editor, note, changed) && session.sourceGeneration == generation &&
                    modifiedDateOfNote(note) == modified && [note.undoManager canUndo] == undo && [note.undoManager canRedo] == redo,
                    @"P2 repeated layout preserves exact source, generation, modification date, and Undo availability");
            }
            NSDictionary *expected = @{@"source":changed, @"uuid":HistoryUUID(note), @"title":titleOfNote(note)};
            Check([[NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingPrettyPrinted error:NULL]
                writeToFile:expectedPath atomically:YES], @"P2 save the independent expected source and identity for the next app process");
        }
        Check([library flushAllNoteChanges], @"the actual library flush succeeds before process exit");
        [library closeJournal];
        NSLog(@"DURABILITY REVIEW PASSED (%lu checks, %@ phase)", (unsigned long)Checks, phase);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: DURABILITY EXCEPTION %@ %@\n%@", exception.name, exception.reason, exception.callStackSymbols);
        exit(1);
    }
}
@end
