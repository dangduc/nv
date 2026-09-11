    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        History=[NSMutableArray array];
        BOOL candidate=strcmp(getenv("NV_WRAP_REVIEW_MODE"),"candidate")==0;
        SEL glyphSelector=@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:);
        Method glyphMethod=class_getInstanceMethod([LinkingEditor class],glyphSelector);
        if (candidate) {
            Check(glyphMethod!=NULL,@"candidate has the production glyph method");
            OriginalGlyphMethod=method_getImplementation(glyphMethod);
            method_setImplementation(glyphMethod,(IMP)ObserveGlyphs);
        }
        [self searchForString:@""]; Pump();
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:12] sender:self];
        NoteObject *other=MakeNote(library,@"Other note",@"other source");
        [app newWindow:self]; Pump();
        AppController *peer=[[app browserControllers] lastObject];
        [peer searchForString:@""]; Pump();
        LinkingEditor *a=[self valueForKey:@"textView"], *b=[peer valueForKey:@"textView"];
        [self.window setContentSize:NSMakeSize(480,600)]; [peer.window setContentSize:NSMakeSize(720,600)];
        NoteObject *wrap=MakeNote(library,@"Geometry control",Spaces(201));
        [self revealNote:wrap options:0]; Pump();
        NSUInteger wrapLines=Lines(a);
        Check(candidate ? wrapLines>1 : wrapLines==1,@"candidate/base geometry control distinguishes the adjustment");
        for (NSString *syntax in @[@"plain",@"markdown"]) {
            for (NSUInteger scenario=0;scenario<4;scenario++) {
                NSString *seed=[[@"HEAD " stringByAppendingString:Spaces(180)] stringByAppendingString:@" TAIL\nANCHOR"];
                NSString *label=[NSString stringWithFormat:@"%@-%lu",syntax,(unsigned long)scenario];
                NoteObject *note=MakeNote(library,label,seed);
                [note setSourceSyntaxIdentifier:syntax];
                [self revealNote:note options:0]; [peer revealNote:note options:0]; Pump();
                NVNoteEditingSession *session=[app editingSessionForNote:note];
                [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:a];
                [note.undoManager removeAllActions];
                [b setSelectedRange:NSMakeRange(seed.length,0)];
                NSString *mark=[@"ê\u0302 " stringByAppendingString:Spaces(96)];
                [a setMarkedText:mark selectedRange:NSMakeRange(mark.length,0) replacementRange:NSMakeRange(0,0)];
                NSString *live=[mark stringByAppendingString:seed];
                State([label stringByAppendingString:@"/marked"],session,@[a,b],live,seed,YES);
                PureRegeneration(@[a,b],session);
                [self.window setContentSize:NSMakeSize(530+scenario*20,600)];
                [peer.window setContentSize:NSMakeSize(740-scenario*30,600)];
                PureRegeneration(@[a,b],session);
                Check(a.hasMarkedText,@"window resize retains marked composition");
                if (scenario==0) {
                    // Replace an IME candidate, defer an external suffix, then merge.
                    NSString *next=[@"Việt " stringByAppendingString:Spaces(128)];
                    [a setMarkedText:next selectedRange:NSMakeRange(next.length,0) replacementRange:a.markedRange];
                    live=[next stringByAppendingString:seed];
                    NSString *remote=[seed stringByAppendingString:@" remote"];
                    [note setContentString:[[[NSAttributedString alloc] initWithString:remote] autorelease]];
                    State([label stringByAppendingString:@"/external-pending"],session,@[a,b],live,remote,YES);
                    PureRegeneration(@[a,b],session);
                    [a unmarkText]; [self finishEditing]; Pump();
                    NSString *merged=[live stringByAppendingString:@" remote"];
                    State([label stringByAppendingString:@"/merged"],session,@[a,b],merged,merged,NO);
                    [b undo:self]; Pump();
                    State([label stringByAppendingString:@"/undo"],session,@[a,b],remote,remote,NO);
                    [b redo:self]; Pump();
                    State([label stringByAppendingString:@"/redo"],session,@[a,b],merged,merged,NO);
                } else if (scenario==1) {
                    // A peer invokes shared history while the original editor composes.
                    [b undo:self]; Pump();
                    State([label stringByAppendingString:@"/peer-undo"],session,@[a,b],seed,seed,NO);
                    PureRegeneration(@[a,b],session);
                    [b redo:self]; Pump();
                    State([label stringByAppendingString:@"/peer-redo"],session,@[a,b],live,live,NO);
                } else if (scenario==2) {
                    // The noncomposing peer detaches and reattaches during composition.
                    NSRange marked=a.markedRange, selection=a.selectedRange;
                    [peer revealNote:other options:0]; Pump();
                    Check(b.textStorage!=a.textStorage,@"peer note switch detaches only its own layout");
                    Check(NSEqualRanges(a.markedRange,marked)&&NSEqualRanges(a.selectedRange,selection),@"peer detach retains native marked range and selection");
                    State([label stringByAppendingString:@"/peer-detached"],session,@[a],live,seed,YES);
                    PureRegeneration(@[a],session);
                    [peer revealNote:note options:0]; Pump();
                    State([label stringByAppendingString:@"/peer-reattached"],session,@[a,b],live,seed,YES);
                    PureRegeneration(@[a,b],session);
                    [a unmarkText]; [self finishEditing]; Pump();
                    State([label stringByAppendingString:@"/committed"],session,@[a,b],live,live,NO);
                } else {
                    // Switching the composition owner commits before it detaches.
                    [self revealNote:other options:0]; Pump();
                    Check(a.textStorage!=b.textStorage,@"composition owner switches to distinct note storage");
                    Check([a.string isEqual:@"other source"],@"composition does not leak into the newly selected note");
                    State([label stringByAppendingString:@"/owner-detached"],session,@[b],live,live,NO);
                    PureRegeneration(@[b],session);
                    [b undo:self]; Pump();
                    State([label stringByAppendingString:@"/detached-undo"],session,@[b],seed,seed,NO);
                    [self revealNote:note options:0]; Pump();
                    [a redo:self]; Pump();
                    State([label stringByAppendingString:@"/reattached-redo"],session,@[a,b],live,live,NO);
                }
            }
        }
        if (candidate) Check(MarkedGlyphCallbacks>0,@"production glyph delegate ran during active native composition");
        NSDictionary *result=@{@"history":History,@"markedGlyphCallbacks":@(MarkedGlyphCallbacks),
            @"glyphCallbacks":@(GlyphCallbacks),@"wrapLines":@(wrapLines),@"checks":@(Checks)};
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_WRAP_REVIEW_OUTPUT")] atomically:YES],@"history evidence saved");
        [peer.window close]; Pump();
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"WRAP IME REVIEW PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch(NSException *exception) {
        NSLog(@"WRAP IME REVIEW EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols); exit(1);
    }
}
@end
