    @try {
        HistoryRecords=[NSMutableArray array];
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        [self searchForString:@""]; Pump();
        NSString *prefix=[@"" stringByPaddingToLength:48 withString:@"x" startingAtIndex:0];
        // These literal reference states do not read the editor after a command.
        NSArray *sources=@[[prefix stringByAppendingString:@" tailword"],
            [prefix stringByAppendingString:@"  tailword"],[prefix stringByAppendingString:@" "]];
        NSArray *names=@[@"single",@"double",@"trailing"];
        NoteObject *note=MakeNote(library,@"Seeded separator commands",sources[0]);
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
            @"actual source windows share storage and own independent production typesetters");
        Check(first.textContainer.containerSize.width<second.textContainer.containerSize.width,
            @"the shared editors retain different layout widths");
        [[note undoManager] removeAllActions];
        ObserveCommand(note,first,second,sources[0],@"baseline",0);
        uint32_t seed=2;
        NSUInteger state=0,command=0;
        NSMutableSet *directions=[NSMutableSet set];
        for (NSUInteger step=0;step<12;step++) {
            seed=1664525U*seed+1013904223U;
            NSUInteger next=(state+1+((seed>>16)&1))%3;
            NSString *transition=[NSString stringWithFormat:@"%@ -> %@",names[state],names[next]];
            [directions addObject:transition];
            AppController *browser=(step%2)?peer:self;
            LinkingEditor *actor=(step%2)?second:first;
            [browser.window makeKeyAndOrderFront:browser]; [browser.window makeFirstResponder:actor];
            NSString *operation=nil;
            if (state==0 && next==1) {
                actor.selectedRange=NSMakeRange(prefix.length+1,0);
                [actor insertText:@" " replacementRange:actor.selectedRange]; operation=@"insert";
            } else if (state==1 && next==0) {
                actor.selectedRange=NSMakeRange(prefix.length+2,0);
                [actor deleteBackward:browser]; operation=@"delete";
            } else if (state==0 && next==2) {
                actor.selectedRange=NSMakeRange(prefix.length+1,8);
                [actor deleteBackward:browser]; operation=@"delete selection";
            } else if (state==1 && next==2) {
                [actor insertText:@"" replacementRange:NSMakeRange(prefix.length+1,9)]; operation=@"replace";
            } else if (state==2) {
                actor.selectedRange=NSMakeRange(prefix.length+1,0);
                [actor insertText:(next==0?@"tailword":@" tailword") replacementRange:actor.selectedRange]; operation=@"insert";
            } else Check(NO,@"every seeded transition has a native edit command");
            [browser finishEditing]; Pump();
            ObserveCommand(note,first,second,sources[next],[NSString stringWithFormat:@"%lu %@ %@",(unsigned long)step+1,operation,transition],++command);
            [actor undo:browser]; Pump();
            ObserveCommand(note,first,second,sources[state],[NSString stringWithFormat:@"%lu Undo %@",(unsigned long)step+1,transition],++command);
            [actor redo:browser]; Pump();
            ObserveCommand(note,first,second,sources[next],[NSString stringWithFormat:@"%lu Redo %@",(unsigned long)step+1,transition],++command);
            state=next;
        }
        Check(command==36 && directions.count==6,@"seed 2 covers all six directed transitions in exactly 36 native edit/history commands");
        Check([library flushAllNoteChanges],@"the disposable library flush succeeds");
        [library closeJournal];
        NSLog(@"SEEDED SEPARATOR HISTORY PASSED (%lu checks; seed=2; nativeCommands=%lu)",(unsigned long)Checks,(unsigned long)command);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL: SEEDED SEPARATOR HISTORY EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
