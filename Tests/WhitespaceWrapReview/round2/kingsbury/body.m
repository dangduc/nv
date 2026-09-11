    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        History=[NSMutableArray array];
        BOOL candidate=strcmp(getenv("NV_WRAP_REVIEW_MODE"),"candidate")==0;
        SEL glyphSelector=@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:);
        if(candidate){Method method=class_getInstanceMethod([LinkingEditor class],glyphSelector);Check(method!=NULL,@"frozen candidate has the glyph method");OriginalGlyphMethod=method_getImplementation(method);method_setImplementation(method,(IMP)ObserveGlyphs);}
        [self searchForString:@""];Pump();
        [[GlobalPrefs defaultPrefs]setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular"size:18]sender:self];
        NoteObject *other=MakeNote(library,@"Other source",@"untouched other note");
        [app newWindow:self];Pump();
        AppController *peer=[[app browserControllers]lastObject];[peer searchForString:@""];Pump();
        LinkingEditor *a=[self valueForKey:@"textView"],*b=[peer valueForKey:@"textView"];
        [self.window setContentSize:NSMakeSize(560,620)];[peer.window setContentSize:NSMakeSize(840,620)];
        NoteObject *geometry=MakeNote(library,@"Wrapping control",Spaces(201));[self revealNote:geometry options:0];Pump();
        NSUInteger wrapLines=Lines(a);Check(candidate?wrapLines>1:wrapLines==1,@"baseline geometry distinguishes the correction");
        for(NSString*syntax in @[@"plain",@"markdown"]){
            for(NSUInteger scenario=0;scenario<4;scenario++){
                NSString*label=[NSString stringWithFormat:@"%@-%lu",syntax,(unsigned long)scenario];
                NSString*seed=[[@"HEADER\nalpha beta" stringByAppendingString:Spaces(120)]stringByAppendingString:@" Việt e\u0302 END"];
                NoteObject*note=MakeNote(library,label,seed);[note setSourceSyntaxIdentifier:syntax];
                [self revealNote:note options:0];[peer revealNote:note options:0];Pump();
                NVNoteEditingSession*session=[app editingSessionForNote:note];
                [self.window makeKeyAndOrderFront:self];[self.window makeFirstResponder:a];
                [note.undoManager removeAllActions];[b setSelectedRange:NSMakeRange(7,5)];
                NSRange replacement=NSMakeRange(seed.length-3,3);
                NSString*prefix=[seed substringToIndex:replacement.location];
                NSString*mark=nil,*live=nil;
                for(NSString*stem in @[@"e\u0302",@"Việt",@"👩🏽‍💻"]){
                    mark=[[stem stringByAppendingString:Spaces(80)]stringByAppendingString:@"👩🏽‍💻"];
                    [a setMarkedText:mark selectedRange:NSMakeRange(mark.length,0) replacementRange:a.hasMarkedText?a.markedRange:replacement];
                    live=[prefix stringByAppendingString:mark];
                    State([label stringByAppendingFormat:@"/candidate-%@",stem],session,@[a,b],live,seed,YES);
                    PureRegeneration(@[a,b],session);
                    NSParagraphStyle*style=[session.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
                    Check(style.lineBreakMode==(candidate?NSLineBreakByCharWrapping:NSLineBreakByWordWrapping),@"composition retains the expected source paragraph policy");
                }
                NSString*remote=seed;
                if(scenario==1||scenario==3){
                    remote=[@"remote →\n"stringByAppendingString:seed];
                    [note setContentString:[[[NSAttributedString alloc]initWithString:remote]autorelease]];
                    State([label stringByAppendingString:@"/external-prefix-pending"],session,@[a,b],live,remote,YES);
                    PureRegeneration(@[a,b],session);
                }
                if(scenario==2){
                    NSRange marked=a.markedRange,selection=a.selectedRange;
                    [peer revealNote:other options:0];Pump();
                    Check(b.textStorage!=a.textStorage&&[b.string isEqual:@"untouched other note"],@"peer note switch keeps the other source untouched");
                    Check(NSEqualRanges(marked,a.markedRange)&&NSEqualRanges(selection,a.selectedRange),@"peer detach retains the Unicode candidate range");
                    PureRegeneration(@[a],session);
                    [peer revealNote:note options:0];Pump();
                    State([label stringByAppendingString:@"/peer-restored"],session,@[a,b],live,seed,YES);
                }
                NSString*committed=(scenario==1||scenario==3)?[@"remote →\n"stringByAppendingString:live]:live;
                if(scenario==3){
                    // Undo from the peer first resolves the pending external prefix.
                    [b undo:self];Pump();
                    State([label stringByAppendingString:@"/pending-peer-undo"],session,@[a,b],remote,remote,NO);
                    [b redo:self];Pump();
                    State([label stringByAppendingString:@"/pending-peer-redo"],session,@[a,b],committed,committed,NO);
                }else{
                    // Commit through NSTextInputClient's insertion path, rather than unmarkText alone.
                    [a insertText:mark replacementRange:a.markedRange];[self finishEditing];Pump();
                    State([label stringByAppendingString:@"/insert-committed"],session,@[a,b],committed,committed,NO);
                }
                // Backspace deletes one extended grapheme; shared history restores it.
                [self.window makeKeyAndOrderFront:self];[self.window makeFirstResponder:a];
                [a setSelectedRange:NSMakeRange(committed.length,0)];
                NSRange cluster=[committed rangeOfComposedCharacterSequenceAtIndex:committed.length-1];
                Check(cluster.length>1,@"delete fixture ends in an extended Unicode grapheme");
                NSString*deleted=[committed substringToIndex:cluster.location];
                [note.undoManager removeAllActions];
                [a deleteBackward:self];Pump();
                State([label stringByAppendingString:@"/deleted-grapheme"],session,@[a,b],deleted,deleted,NO);
                Check(NSEqualRanges(a.selectedRange,NSMakeRange(deleted.length,0)),@"Backspace caret follows the whole deleted grapheme");
                PureRegeneration(@[a,b],session);
                [b undo:self];Pump();
                State([label stringByAppendingString:@"/peer-restores-grapheme"],session,@[a,b],committed,committed,NO);
                [b redo:self];Pump();
                State([label stringByAppendingString:@"/peer-redoes-delete"],session,@[a,b],deleted,deleted,NO);
                [self revealNote:other options:0];Pump();
                [b undo:self];Pump();
                State([label stringByAppendingString:@"/owner-detached-history"],session,@[b],committed,committed,NO);
            }
        }
        if(candidate)Check(MarkedGlyphCallbacks>0,@"final production delegate ran during Unicode marked text");
        NSDictionary*result=@{@"history":History,@"markedGlyphCallbacks":@(MarkedGlyphCallbacks),@"glyphCallbacks":@(GlyphCallbacks),@"wrapLines":@(wrapLines),@"checks":@(Checks)};
        NSData*data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_WRAP_REVIEW_OUTPUT")]atomically:YES],@"round-two history evidence saved");
        [peer.window close];Pump();[library flushAllNoteChanges];[library closeJournal];
        NSLog(@"WRAP IME REVIEW PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults]removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];[[NSUserDefaults standardUserDefaults]synchronize];exit(0);
    }@catch(NSException*e){NSLog(@"ROUND2 IME EXCEPTION %@ %@\n%@",e.name,e.reason,e.callStackSymbols);exit(1);}
}
@end
