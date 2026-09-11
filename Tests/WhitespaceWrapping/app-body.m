    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();
        [[browser window] setContentSize:NSMakeSize(480,600)];
        Check([editor.layoutManager delegate] == editor, @"existing editor layout delegate remains installed");
        Check([editor respondsToSelector:@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)],
            @"production editor supplies the glyph adjustment");
        for (NSString *selectorName in @[@"keyDown:", @"insertText:replacementRange:", @"deleteBackward:",
            @"drawInsertionPointInRect:color:turnedOn:"]) {
            SEL selector = NSSelectorFromString(selectorName);
            Check(method_getImplementation(class_getInstanceMethod([LinkingEditor class],selector)) ==
                method_getImplementation(class_getInstanceMethod([NSTextView class],selector)),
                [NSString stringWithFormat:@"%@ remains native", selectorName]);
        }
        NoteObject *note = nil;
        for (NSString *syntax in @[@"plain", @"markdown"]) {
            for (NSNumber *fontSize in @[@12,@22]) {
                note = MakeNote(library, [NSString stringWithFormat:@"Space wrap %@ %@",syntax,fontSize], @"");
                [browser revealNote:note options:0]; Pump();
                [note setSourceSyntaxIdentifier:syntax];
                [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:fontSize.doubleValue] sender:self];
                [[browser window] makeKeyAndOrderFront:self];
                [[browser window] makeFirstResponder:editor];
                Check([[browser window] firstResponder] == editor, @"actual editor has keyboard focus");
                [editor setSelectedRange:NSMakeRange(0,0)];
                for (NSUInteger i=0; i<201; i++) {
                    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:browser.window.windowNumber
                        context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:i>0 keyCode:49];
                    [NSApp sendEvent:event];
                    Check(editor.string.length == i+1 && NSEqualRanges(editor.selectedRange,NSMakeRange(i+1,0)),
                        @"Space preserves source length and selection");
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
                }
                Pump();
                NSString *spaces = [@"" stringByPaddingToLength:201 withString:@" " startingAtIndex:0];
                Check([editor.string isEqual:spaces] && [[[note contentString] string] isEqual:spaces],
                    @"source and committed note contain exactly 201 ordinary spaces");
                Check(WrapLineCount(editor) > 1, @"spaces wrap in the production layout");
                NSRect before = WrapCaret(editor);
                Check(before.size.height > 0 && before.origin.y > editor.textContainerInset.height,
                    @"caret advances onto a subsequent visual line");
                [[note undoManager] removeAllActions];
                [editor deleteBackward:self]; Pump();
                NSRect after = WrapCaret(editor);
                Check(editor.string.length == 200 && NSEqualRanges(editor.selectedRange,NSMakeRange(200,0)),
                    @"native Backspace deletes one source space");
                Check(after.origin.y < before.origin.y ||
                    (after.origin.y == before.origin.y && after.origin.x < before.origin.x),
                    @"caret moves backward after deletion");
                [editor undo:self]; Pump();
                Check([editor.string isEqual:spaces], @"shared Undo restores the deleted space");
            }
        }
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        [peer.window setContentSize:NSMakeSize(720,600)]; Pump();
        Check(peerEditor.textStorage == editor.textStorage, @"windows share the original source storage");
        Check(WrapLineCount(peerEditor) > 1 && WrapLineCount(editor) > WrapLineCount(peerEditor),
            @"shared editors wrap spaces independently at different widths");
        NSUInteger narrowLines = WrapLineCount(editor);
        CGFloat narrowWidth = editor.textContainer.size.width;
        [browser.window setContentSize:NSMakeSize(900,600)]; Pump();
        Check(editor.textContainer.size.width > narrowWidth && WrapLineCount(editor) < narrowLines,
            @"resizing reflows existing space glyphs");
        [[peer window] close]; Pump();
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"SPACE WRAP APP PASSED (%lu checks)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"SPACE WRAP APP EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
