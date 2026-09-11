    @try {
        HistoryRecords=[NSMutableArray array];
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        GlobalPrefs *prefs=[GlobalPrefs defaultPrefs];
        [prefs setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        [self searchForString:@""]; Pump();
        LinkingEditor *editor=[self valueForKey:@"textView"];
        Check([editor.layoutManager.typesetter isKindOfClass:NSClassFromString(@"NVSourceTypesetter")] && editor.layoutManager.delegate==editor,
            @"the copied app supplies its real source typesetter and glyph delegate");
        NSString *phase=[NSString stringWithUTF8String:getenv("NV_HISTORY_PHASE")];
        NSString *expectedPath=[TestDirectory stringByAppendingPathComponent:@"expected.json"];
        if ([phase isEqual:@"reopen"]) {
            NSDictionary *expected=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:expectedPath] options:0 error:NULL];
            Check(expected && [[library allNotes] count]==1,@"fresh process reopens exactly the saved history fixture");
            NoteObject *note=[[library allNotes] lastObject];
            [self revealNote:note options:0]; Pump();
            [self.window setContentSize:NSSizeFromString(expected[@"windowSize"])]; Pump();
            Check([HistoryUUID(note) isEqual:expected[@"uuid"]] && HistoryExactSource(editor,note,expected[@"source"]),
                @"reopen preserves the note UUID and all source bytes after paragraph changes");
            editor.selectedRange=NSRangeFromString(expected[@"selection"]);
            Check([CopySelection(editor) isEqual:expected[@"copied"]],@"the saved logical selection copies the same phrase after reopen");
            HistoryObserve(editor,@"reopened paragraph history");
            Check([HistoryGeometry(editor.layoutManager,editor.textContainer) isEqual:expected[@"geometry"]],
                @"identical font and window size reproduce the saved native glyph geometry");
        } else {
            NSString *left=@"A full paragraph has fitting words separated by single spaces and finishes before a real newline.";
            NSString *right=[SelectedPhrase stringByAppendingString:@" while shared edits change preceding paragraphs. "
                "Unicode remains exact: Việt e\u0301 👩🏽‍💻.\nThe final paragraph keeps trailing spaces  "];
            NSString *split=[NSString stringWithFormat:@"%@\n %@",left,right];
            NSString *merged=[NSString stringWithFormat:@"%@ %@",left,right];
            NoteObject *note=MakeNote(library,@"Anchored separator history",split);
            [self revealNote:note options:0]; Pump();
            [self.window setContentSize:NSMakeSize(490,610)];
            [app newWindow:self]; Pump();
            AppController *peer=[app.browserControllers lastObject];
            [peer revealNote:note options:0]; Pump();
            LinkingEditor *observer=[peer valueForKey:@"textView"];
            [peer.window setContentSize:NSMakeSize(815,610)]; Pump();
            observer.selectedRange=[split rangeOfString:SelectedPhrase];
            Check(editor.textStorage==observer.textStorage && editor.layoutManager.typesetter!=observer.layoutManager.typesetter,
                @"two actual windows share source with independent typesetters");
            AnchoredState(note,editor,observer,split,@"initial paragraph boundary");
            [[note undoManager] removeAllActions];
            for (NSUInteger pass=0;pass<2;pass++) {
                NSString *label=[NSString stringWithFormat:@"pass %lu",(unsigned long)(pass+1)];
                HistoryReplace(self,editor,NSMakeRange(left.length,2),@" ");
                AnchoredState(note,editor,observer,merged,[label stringByAppendingString:@" join paragraphs"]);
                [prefs setNoteBodyFont:[NSFont fontWithName:pass?@"Menlo-Regular":@"Helvetica" size:pass?18:19] sender:self];
                [self.window setContentSize:NSMakeSize(pass?585:485,610)];
                [peer.window setContentSize:NSMakeSize(pass?615:815,610)]; Pump();
                AnchoredState(note,editor,observer,merged,[label stringByAppendingString:@" change font and widths"]);
                HistoryReplace(self,editor,NSMakeRange(left.length,1),@"\n ");
                AnchoredState(note,editor,observer,split,[label stringByAppendingString:@" split paragraphs"]);
                [editor undo:self]; Pump();
                AnchoredState(note,editor,observer,merged,[label stringByAppendingString:@" Undo split"]);
                [editor undo:self]; Pump();
                AnchoredState(note,editor,observer,split,[label stringByAppendingString:@" Undo join"]);
                [editor redo:self]; Pump();
                AnchoredState(note,editor,observer,merged,[label stringByAppendingString:@" Redo join"]);
                [editor redo:self]; Pump();
                AnchoredState(note,editor,observer,split,[label stringByAppendingString:@" Redo split"]);
            }
            HistoryReplace(self,editor,NSMakeRange(left.length,2),@" ");
            AnchoredState(note,editor,observer,merged,@"final paragraph merge before save");
            NSString *copied=CopySelection(observer);
            NSDictionary *expected=@{@"uuid":HistoryUUID(note),@"source":merged,@"copied":copied,
                @"selection":NSStringFromRange(observer.selectedRange),@"windowSize":NSStringFromSize(self.window.contentView.frame.size),
                @"geometry":HistoryGeometry(editor.layoutManager,editor.textContainer)};
            Check([[NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingPrettyPrinted error:NULL]
                writeToFile:expectedPath atomically:YES],@"save independent source, copy, selection, and geometry expectations");
        }
        Check([library flushAllNoteChanges],@"the actual library flush succeeds");
        [library closeJournal];
        NSLog(@"SEPARATOR HISTORY PASSED (%lu checks, %@ phase)",(unsigned long)Checks,phase);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: SEPARATOR HISTORY EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
