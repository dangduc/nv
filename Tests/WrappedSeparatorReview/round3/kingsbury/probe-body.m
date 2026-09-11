    @try {
        HistoryRecords=[NSMutableArray array];
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        [self searchForString:@""]; Pump();
        NSString *prefix=[@"" stringByPaddingToLength:48 withString:@"x" startingAtIndex:0];
        NSString *shortPrefix=[prefix substringToIndex:47];
        NSString *ascii=[prefix stringByAppendingString:@" tailword"];
        // Explicit states and UTF-16 replacement ranges are independent of editor readback.
        NSArray *sources=@[ascii,[prefix stringByAppendingString:@" éailword"],ascii,
            [shortPrefix stringByAppendingString:@"中 tailword"],ascii,
            [prefix stringByAppendingString:@" t\u0301ailword"],ascii,
            [prefix stringByAppendingString:@" \u0301tailword"],ascii,
            [shortPrefix stringByAppendingString:@"x\u0301 tailword"],ascii];
        NSArray *replacements=@[@"é",@"t",@"中",@"x",@"t\u0301",@"t",@"\u0301",@"",@"x\u0301",@"x"];
        NSRange ranges[]={NSMakeRange(49,1),NSMakeRange(49,1),NSMakeRange(47,1),NSMakeRange(47,1),
            NSMakeRange(49,1),NSMakeRange(49,2),NSMakeRange(49,0),NSMakeRange(49,1),NSMakeRange(47,1),NSMakeRange(47,2)};
        NSArray *labels=@[@"accented right neighbor",@"restore ASCII right neighbor",@"CJK left neighbor",
            @"restore ASCII left neighbor",@"combining right neighbor",@"remove right combining mark",
            @"combining mark attached to space",@"detach combining mark from space",@"combining left neighbor",@"restore ASCII prefix"];
        NoteObject *note=MakeNote(library,@"Unicode separator history",ascii);
        NoteObject *other=MakeNote(library,@"Detached note",@"Other note body.");
        [self revealNote:note options:0]; Pump();
        LinkingEditor *first=[self valueForKey:@"textView"];
        [self.window setContentSize:NSMakeSize(550,610)];
        [app newWindow:self]; Pump();
        AppController *peer=[app.browserControllers lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *second=[peer valueForKey:@"textView"];
        [peer.window setContentSize:NSMakeSize(825,610)]; Pump();
        Check(first.textStorage==second.textStorage && first.layoutManager.typesetter!=second.layoutManager.typesetter &&
            [first.layoutManager.typesetter isKindOfClass:NSClassFromString(@"NVSourceTypesetter")],
            @"actual editors share storage with independent production typesetters");
        Check(first.textContainer.containerSize.width<second.textContainer.containerSize.width,
            @"the shared editors retain different widths");
        [[note undoManager] removeAllActions];
        NSUInteger command=0;
        ObserveUnicode(note,first,second,ascii,@"baseline",command);
        for (NSUInteger step=0;step<10;step++) {
            AppController *browser=(step%2)?peer:self;
            LinkingEditor *actor=(step%2)?second:first;
            [browser.window makeKeyAndOrderFront:browser]; [browser.window makeFirstResponder:actor];
            [actor insertText:replacements[step] replacementRange:ranges[step]];
            [browser finishEditing]; Pump();
            ObserveUnicode(note,first,second,sources[step+1],labels[step],++command);
            [actor undo:browser]; Pump();
            ObserveUnicode(note,first,second,sources[step],[labels[step] stringByAppendingString:@" Undo"],++command);
            [actor redo:browser]; Pump();
            ObserveUnicode(note,first,second,sources[step+1],[labels[step] stringByAppendingString:@" Redo"],++command);
            if (step==6 || step==9) {
                [self revealNote:other options:0]; Pump();
                Check(HistoryExactSource(first,other,@"Other note body.") && HistoryExactSource(second,note,sources[step+1]),
                    @"one detached editor cannot replace its peer's source");
                [peer revealNote:other options:0]; Pump();
                ObserveCommand(other,first,second,@"Other note body.",@"both editors switch away",command);
                [self revealNote:note options:0]; Pump();
                Check(HistoryExactSource(first,note,sources[step+1]) && HistoryExactSource(second,other,@"Other note body."),
                    @"one reattached editor cannot replace its peer's other note");
                [peer revealNote:note options:0]; Pump();
                Check(first.textStorage==second.textStorage,@"reattached editors recover shared storage");
                ObserveUnicode(note,first,second,sources[step+1],@"both editors reattach",command);
            }
        }
        Check(command==30,@"ten neighbor transitions complete with native Undo and Redo");
        Check([library flushAllNoteChanges],@"the disposable library flush succeeds");
        [library closeJournal];
        NSLog(@"UNICODE SEPARATOR HISTORY PASSED (%lu checks; nativeCommands=%lu)",(unsigned long)Checks,(unsigned long)command);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: UNICODE SEPARATOR HISTORY EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
