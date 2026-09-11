    @try {
        NVApplicationController*app=[NVApplicationController sharedController];NotationController*library=app.library;
        [[NSUserDefaults standardUserDefaults]setBool:NO forKey:@"QuitWhenClosingMainWindow"];
        History=[NSMutableArray array];
        SEL selector=@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:);
        Method method=class_getInstanceMethod(LinkingEditor.class,selector);Check(method!=NULL,@"both builds contain the production glyph policy");
        OriginalGlyphMethod=method_getImplementation(method);method_setImplementation(method,(IMP)ObserveGlyphs);
        [self searchForString:@""];Pump();
        [[GlobalPrefs defaultPrefs]setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular"size:18]sender:self];
        LinkingEditor*peer=[self valueForKey:@"textView"];
        [self.window setContentSize:NSMakeSize(560,620)];
        NoteObject*geometry=MakeNote(library,@"Geometry control",Spaces(201));[self revealNote:geometry options:0];Pump();
        NSUInteger wrapLines=Lines(peer);Check(wrapLines>1,@"both policy versions wrap the same space control");
        for(NSNumber*count in @[@63,@64,@65,@257])for(NSNumber*external in @[@NO,@YES]){
            NSString*label=[NSString stringWithFormat:@"spaces-%@-external-%@",count,external];
            NSString*seed=@"HEADER\nalpha beta             END";
            NSString*prefix=[seed substringToIndex:seed.length-3];
            NSString*mark=[Spaces(count.unsignedIntegerValue)stringByAppendingString:@"e\u0302 👩🏽‍💻"];
            NSString*live=[prefix stringByAppendingString:mark];
            NoteObject*note=MakeNote(library,label,seed);[note setSourceSyntaxIdentifier:@"plain"];
            [self revealNote:note options:0];Pump();
            NVNoteEditingSession*session=[app editingSessionForNote:note];
            [note.undoManager removeAllActions];[peer setSelectedRange:NSMakeRange(2,3)];
            [app newWindow:self];Pump();
            AppController*owner=[[app browserControllers]lastObject];Check(owner!=self,@"the composition owner is an additional browser");
            [owner searchForString:@""];[owner revealNote:note options:0];[owner.window setContentSize:NSMakeSize(840,620)];Pump();
            LinkingEditor*editor=[owner valueForKey:@"textView"];
            [owner.window makeKeyAndOrderFront:self];[owner.window makeFirstResponder:editor];
            [editor setMarkedText:mark selectedRange:NSMakeRange(mark.length,0) replacementRange:NSMakeRange(seed.length-3,3)];
            State([label stringByAppendingString:@"/marked"],session,@[peer,editor],live,seed,YES);
            PureRegeneration(@[peer,editor],session);
            NSString*remote=external.boolValue?[@"remote →\n"stringByAppendingString:seed]:seed;
            NSString*committed=external.boolValue?[@"remote →\n"stringByAppendingString:live]:live;
            if(external.boolValue){
                [note setContentString:[[[NSAttributedString alloc]initWithString:remote]autorelease]];
                State([label stringByAppendingString:@"/remote-pending"],session,@[peer,editor],live,remote,YES);
                PureRegeneration(@[peer,editor],session);
            }
            Check(editor.hasMarkedText,@"the owner still has native marked text immediately before closure");
            [owner.window close];Pump();
            // No references to the former owner or its editor after closure.
            Check(app.browserControllers.count==1&&app.browserControllers[0]==self,@"closing the owner leaves the original peer alive");
            Check(session.textStorage.layoutManagers.count==1,@"owner closure detaches exactly its layout manager");
            State([label stringByAppendingString:@"/owner-closed"],session,@[peer],committed,committed,NO);
            PureRegeneration(@[peer],session);
            [self.window makeKeyAndOrderFront:self];[self.window makeFirstResponder:peer];
            [peer setSelectedRange:NSMakeRange(committed.length,0)];
            [peer insertText:@"!"replacementRange:peer.selectedRange];Pump();
            NSString*edited=[committed stringByAppendingString:@"!"];
            State([label stringByAppendingString:@"/peer-edit"],session,@[peer],edited,edited,NO);
            [peer undo:self];Pump();State([label stringByAppendingString:@"/undo-peer-edit"],session,@[peer],committed,committed,NO);
            [peer undo:self];Pump();State([label stringByAppendingString:@"/undo-closed-composition"],session,@[peer],remote,remote,NO);
            [peer redo:self];Pump();State([label stringByAppendingString:@"/redo-closed-composition"],session,@[peer],committed,committed,NO);
            [peer redo:self];Pump();State([label stringByAppendingString:@"/redo-peer-edit"],session,@[peer],edited,edited,NO);
            [app newWindow:self];Pump();AppController*reopened=[[app browserControllers]lastObject];
            [reopened searchForString:@""];[reopened revealNote:note options:0];Pump();
            LinkingEditor*reopenedEditor=[reopened valueForKey:@"textView"];
            Check(session.textStorage.layoutManagers.count==2,@"reopening attaches one new layout to the cached session");
            State([label stringByAppendingString:@"/reopened"],session,@[peer,reopenedEditor],edited,edited,NO);
            PureRegeneration(@[peer,reopenedEditor],session);
            [reopened.window makeKeyAndOrderFront:self];[reopened.window makeFirstResponder:reopenedEditor];
            [reopenedEditor setSelectedRange:NSMakeRange(edited.length,0)];[reopenedEditor deleteBackward:self];Pump();
            State([label stringByAppendingString:@"/reopened-delete"],session,@[peer,reopenedEditor],committed,committed,NO);
            [peer undo:self];Pump();State([label stringByAppendingString:@"/peer-restores-reopened-delete"],session,@[peer,reopenedEditor],edited,edited,NO);
            [reopened.window close];Pump();Check(app.browserControllers.count==1,@"history cleanup leaves the original browser alive");
        }
        Check(MarkedGlyphCallbacks>0&&SmallChangedBatches>0&&LargeChangedBatches>0,@"histories exercise marked text and both glyph-buffer sizes");
        NSDictionary*result=@{@"history":History,@"markedGlyphCallbacks":@(MarkedGlyphCallbacks),@"glyphCallbacks":@(GlyphCallbacks),@"smallChangedBatches":@(SmallChangedBatches),@"largeChangedBatches":@(LargeChangedBatches),@"wrapLines":@(wrapLines),@"checks":@(Checks)};
        NSData*data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_WRAP_REVIEW_OUTPUT")]atomically:YES],@"closure histories saved");
        [library flushAllNoteChanges];[library closeJournal];NSLog(@"WRAP IME REVIEW PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults]removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];[[NSUserDefaults standardUserDefaults]synchronize];exit(0);
    }@catch(NSException*e){NSLog(@"ROUND3 CLOSURE EXCEPTION %@ %@\n%@",e.name,e.reason,e.callStackSymbols);exit(1);}
}
@end
