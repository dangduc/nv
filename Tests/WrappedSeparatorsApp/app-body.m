    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        GlobalPrefs *prefs=[GlobalPrefs defaultPrefs];
        NSFont *font=[NSFont fontWithName:@"Menlo-Regular" size:18];
        Check(font!=nil,@"the test font is available");
        [prefs setNoteBodyFont:font sender:self];
        [self searchForString:@""]; Pump();
        LinkingEditor *editor=[self valueForKey:@"textView"];
        NSString *token=[@"" stringByPaddingToLength:48 withString:@"x" startingAtIndex:0];
        NSString *single=[token stringByAppendingString:@" nextword"];
        NSString *doubleSpace=[token stringByAppendingString:@"  nextword"];
        NoteObject *note=MakeNote(library,@"Wrapped single separator",single);
        [self revealNote:note options:0]; Pump();
        SeparatorColumns(self.window,editor,48);
        Check([editor.layoutManager.typesetter isKindOfClass:NSClassFromString(@"NVSourceTypesetter")] &&
            editor.layoutManager.delegate==editor,@"the real editor uses the production typesetter and glyph delegate");
        CGFloat available=editor.textContainer.containerSize.width-2*editor.textContainer.lineFragmentPadding;
        CGFloat tokenWidth=48*SeparatorAdvance(font);
        Check(available>=tokenWidth-0.02 && available<tokenWidth+SeparatorAdvance(font),
            @"the actual window fits the full-width token but cannot fit its following space");
        Check(fabs(SeparatorPosition(editor,47).y-SeparatorPosition(editor,0).y)<0.02,
            @"the full-width word remains on one visual line");
        Check(SeparatorStartsAtMargin(editor,49),@"one separator after a full-width word leaves nextword flush left");
        Check(SeparatorExact(editor,single) && [[[[note contentString] string] dataUsingEncoding:NSUTF8StringEncoding]
            isEqual:[single dataUsingEncoding:NSUTF8StringEncoding]],@"collapsed layout preserves the exact source and model");
        NSMutableArray *records=[NSMutableArray arrayWithObject:@{@"case":@"single separator",@"lines":WordWrapLines(editor)}];

        [app newWindow:self]; Pump();
        AppController *peer=[app.browserControllers lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *peerEditor=[peer valueForKey:@"textView"];
        SeparatorColumns(peer.window,peerEditor,72);
        Check(editor.textStorage==peerEditor.textStorage && editor.layoutManager.typesetter!=peerEditor.layoutManager.typesetter,
            @"two windows share source and own separate typesetters");
        NSPoint wideStart=SeparatorPosition(peerEditor,0),wideWord=SeparatorPosition(peerEditor,49);
        Check(fabs(wideStart.y-wideWord.y)<0.02 && fabs(wideWord.x-wideStart.x-49*SeparatorAdvance(font))<0.05,
            @"the wider peer shows the same separator at its ordinary inline width");

        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:editor];
        [[note undoManager] removeAllActions];
        editor.selectedRange=NSMakeRange(49,0);
        WordWrapSpaceKey(editor,NO); [self finishEditing]; Pump();
        Check(SeparatorExact(editor,doubleSpace) && SeparatorExact(peerEditor,doubleSpace),@"a native Space key converts the shared separator to two literal spaces");
        Check(SeparatorLiteralIndent(editor,50,2),@"two separator spaces retain two cells of indentation after the automatic wrap");
        [editor undo:self]; Pump();
        Check(SeparatorExact(editor,single) && SeparatorStartsAtMargin(editor,49),@"Undo changes double spaces back to a collapsed single separator");
        [peerEditor redo:peer]; Pump();
        Check(SeparatorExact(editor,doubleSpace) && SeparatorLiteralIndent(editor,50,2),@"Redo from the peer restores both literal spaces");
        [editor undo:self]; Pump();

        NSString *trailing=[token stringByAppendingString:@" "];
        [note setContentString:[[[NSAttributedString alloc] initWithString:trailing] autorelease]]; Pump();
        [[note undoManager] removeAllActions];
        editor.selectedRange=NSMakeRange(0,0); NSRect startCaret=WordWrapCaret(editor);
        editor.selectedRange=NSMakeRange(trailing.length,0); NSRect trailingCaret=WordWrapCaret(editor);
        Check(trailingCaret.origin.y>startCaret.origin.y && fabs(trailingCaret.origin.x-startCaret.origin.x-SeparatorAdvance(font))<0.05,
            @"a single trailing space remains literal and advances the caret beyond the margin");
        [editor insertText:@"nextword" replacementRange:editor.selectedRange]; [self finishEditing]; Pump();
        Check(SeparatorExact(editor,single) && SeparatorStartsAtMargin(editor,49),@"typing after a trailing space turns it into a collapsed separator");
        [peerEditor undo:peer]; Pump();
        Check(SeparatorExact(editor,trailing),@"Undo from the peer restores the trailing-space source");
        editor.selectedRange=NSMakeRange(trailing.length,0); trailingCaret=WordWrapCaret(editor);
        Check(trailingCaret.origin.y>startCaret.origin.y && fabs(trailingCaret.origin.x-startCaret.origin.x-SeparatorAdvance(font))<0.05,
            @"Undo restores literal trailing-space caret geometry");
        [editor redo:self]; Pump();
        Check(SeparatorExact(editor,single) && SeparatorStartsAtMargin(editor,49),@"Redo restores collapsed-separator geometry");

        NSPasteboard *board=[NSPasteboard pasteboardWithUniqueName];
        editor.selectedRange=NSMakeRange(0,editor.string.length);
        Check(editor.selectedRange.length==single.length,@"native copy has the complete logical source selected");
        Check([editor writeSelectionToPasteboard:board types:editor.writablePasteboardTypes],@"native copy writes the selected source to a private pasteboard");
        Check([[[board stringForType:NSPasteboardTypeString] dataUsingEncoding:NSUTF8StringEncoding] isEqual:[single dataUsingEncoding:NSUTF8StringEncoding]],
            @"native copy retains the separator in exact logical source");
        NoteObject *pasted=MakeNote(library,@"Private paste target",@"");
        [self revealNote:pasted options:0]; Pump();
        editor.selectedRange=NSMakeRange(0,0);
        Check([editor readSelectionFromPasteboard:board type:NSPasteboardTypeString],@"native paste reads the private source copy");
        [self finishEditing]; Pump();
        Check(SeparatorExact(editor,single) && [[[pasted contentString] string] isEqual:single] && SeparatorExact(peerEditor,single),
            @"paste preserves exact source while the peer stays attached to the original note");
        [self revealNote:note options:0]; Pump();
        Check(editor.textStorage==peerEditor.textStorage && SeparatorStartsAtMargin(editor,49),@"note reattachment restores the correct local wrap geometry");
        [board releaseGlobally];

        NSArray *fixtures=@[
            @{@"name":@"real newline indentation",@"source":[token stringByAppendingString:@"\n nextword"],@"word":@50,@"spaces":@1},
            @{@"name":@"NBSP indentation",@"source":[token stringByAppendingString:@"\n\u00a0nextword"],@"word":@50,@"spaces":@1}];
        for (NSDictionary *fixture in fixtures) {
            [note setContentString:[[[NSAttributedString alloc] initWithString:fixture[@"source"]] autorelease]]; Pump();
            Check(SeparatorExact(editor,fixture[@"source"]) && SeparatorLiteralIndent(editor,[fixture[@"word"] unsignedIntegerValue],[fixture[@"spaces"] unsignedIntegerValue]),
                [fixture[@"name"] stringByAppendingString:@" remains literal"]);
            [records addObject:@{@"case":fixture[@"name"],@"lines":WordWrapLines(editor)}];
        }
        NSString *tabbed=[token stringByAppendingString:@"\n\tnextword"];
        [note setContentString:[[[NSAttributedString alloc] initWithString:tabbed] autorelease]]; Pump();
        Check(SeparatorExact(editor,tabbed) && SeparatorPosition(editor,50).x>SeparatorPosition(editor,0).x,
            @"a real newline followed by Tab retains its native indentation");
        NSString *spaces=[@"" stringByPaddingToLength:50 withString:@" " startingAtIndex:0];
        [note setContentString:[[[NSAttributedString alloc] initWithString:spaces] autorelease]]; Pump();
        editor.selectedRange=NSMakeRange(0,0); startCaret=WordWrapCaret(editor);
        editor.selectedRange=NSMakeRange(spaces.length,0); NSRect spacesCaret=WordWrapCaret(editor);
        Check(SeparatorExact(editor,spaces) && spacesCaret.origin.y>startCaret.origin.y &&
            fabs(spacesCaret.origin.x-startCaret.origin.x-2*SeparatorAdvance(font))<0.05,
            @"an all-space source wraps literally and preserves the final two cells");

        NSString *prose=@"A single separator stays in the source while each wrapped line begins at the text margin. "
            "The visible layout changes without deleting spaces or changing copied text.\n\n"
            "Two  spaces remain literal.\n Leading indentation stays visible.\n\n"
            "Shared notes keep their source, selections, and editing history when the window width changes.";
        NoteObject *example=MakeNote(library,@"Wrapped separators",prose);
        [self revealNote:example options:0];
        [prefs setShowNotesList:NO sender:nil]; [prefs setShowTitleInTopSection:YES sender:nil];
        [prefs setShowTagsInTopSection:NO sender:nil]; [prefs setShowBodyControlsInTopSection:YES sender:nil];
        [self.window setContentSize:NSMakeSize(555,560)];
        if (@available(macOS 10.14,*)) [self.window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:nil]; Pump();
        Check(WordWrapLines(editor).count>[[prose componentsSeparatedByString:@"\n"] count],@"the screenshot includes automatic visual wraps");
        Check(WordWrapCapture(self.window,[NSString stringWithUTF8String:getenv("NV_SEPARATOR_CAPTURE")]),@"save the synthetic production-window screenshot");
        [records addObject:@{@"case":@"illustration",@"lines":WordWrapLines(editor)}];
        Check([[NSJSONSerialization dataWithJSONObject:@{@"checks":@(Checks),@"fixtures":records} options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:getenv("NV_SEPARATOR_RESULT")] atomically:YES],@"save compact line observations");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"WRAPPED SEPARATORS APP PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"WRAPPED SEPARATORS APP EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
