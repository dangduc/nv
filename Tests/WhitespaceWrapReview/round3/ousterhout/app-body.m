    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        GlobalPrefs *prefs=[GlobalPrefs defaultPrefs];
        NSParagraphStyle *style=[[prefs noteBodyAttributes] objectForKey:NSParagraphStyleAttributeName];
        SEL selector=@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:);
        Method method=class_getInstanceMethod([LinkingEditor class],selector);
        OriginalGlyphMethod=(ProductionGlyphMethod)method_getImplementation(method);
        method_setImplementation(method,(IMP)ReviewGlyphMethod);
        NSString *shortSource=@"alpha beta      end";
        NSString *longSource=[[@"long " stringByAppendingString:[@"" stringByPaddingToLength:601 withString:@" " startingAtIndex:0]] stringByAppendingString:@" marker\nlast"];
        NSString *mixedSource=@"first\tsecond   Việt 中文\nthird   line";
        NSArray *texts=@[shortSource,longSource,mixedSource];
        NSArray *notes=@[MakeNote(library,@"Buffer short",shortSource),MakeNote(library,@"Buffer long",longSource),MakeNote(library,@"Buffer mixed",mixedSource)];
        NSArray *fonts=@[[NSFont fontWithName:@"Menlo" size:12],[NSFont fontWithName:@"Menlo" size:22],[NSFont fontWithName:@"Helvetica" size:16]];
        [self searchForString:@""]; Pump();
        LinkingEditor *a=[self valueForKey:@"textView"];
        for(NSUInteger lifetime=0;lifetime<3;lifetime++) {
            [app newWindow:self]; Pump();
            AppController *peer=[app.browserControllers lastObject];
            Check(peer!=self,@"new peer browser owns a distinct editor lifecycle");
            LinkingEditor *b=[peer valueForKey:@"textView"];
            for(NSUInteger pass=0;pass<3;pass++) {
                NSUInteger index=(lifetime+pass)%notes.count;
                NoteObject *note=notes[index],*other=notes[(index+1)%notes.count];
                [self revealNote:note options:0]; [peer revealNote:note options:0]; Pump();
                NVNoteEditingSession *session=[app editingSessionForNote:note];
                Check(a.textStorage==b.textStorage && a.textStorage==session.textStorage,@"reattached peers use one shared note storage");
                Check(a.layoutManager!=b.layoutManager && a.layoutManager.delegate==a && b.layoutManager.delegate==b,@"glyph callback ownership remains local to each editor");
                [prefs setNoteBodyFont:fonts[(lifetime+pass)%fonts.count] sender:self];
                [prefs setForegroundTextColor:(pass%2 ? [NSColor purpleColor] : [NSColor brownColor]) sender:self];
                [a updateTextColors]; [b updateTextColors]; Pump();
                // Note reattachment applies the existing cached-font refresh before the layout-only snapshot.
                [self revealNote:other options:0]; [peer revealNote:other options:0];
                [self revealNote:note options:0]; [peer revealNote:note options:0]; Pump();
                Check([[[a.textStorage attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSFontAttributeName] isEqual:fonts[(lifetime+pass)%fonts.count]],@"the current preference font is installed before the layout-only snapshot");
                [self.window setContentSize:NSMakeSize(490+pass*70,640)];
                [peer.window setContentSize:NSMakeSize(710-pass*45,640)];
                [a setSelectedRange:NSMakeRange(MIN((NSUInteger)7,a.string.length),0)];
                [b setSelectedRange:NSMakeRange(b.string.length,0)];
                NSRange selectionA=a.selectedRange,selectionB=b.selectedRange;
                NSAttributedString *attributes=[a.textStorage copy];
                uint64_t generation=session.sourceGeneration;
                CFAbsoluteTime date=modifiedDateOfNote(note);
                BOOL undo=[[note undoManager] canUndo],redo=[[note undoManager] canRedo];
                NSArray *before=[GlyphSnapshot(a,YES) copy];
                GlyphSnapshot(b,YES);
                Check([before isEqual:GlyphSnapshot(a,NO)],@"a second layout cannot overwrite native glyph arrays from a completed callback");
                Check([before isEqual:GlyphSnapshot(a,YES)],@"regenerating the same source reproduces copied glyph IDs, properties, and indexes");
                [before release];
                Check([a.textStorage isEqualToAttributedString:attributes] && HasSharedPolicy(a,style),@"buffer operations preserve source attributes and shared immutable paragraph policy");
                Check(session.sourceGeneration==generation && modifiedDateOfNote(note)==date && ![session hasPendingTextChanges],@"layout-only work cannot dirty source or advance its modified date");
                Check([[note undoManager] canUndo]==undo && [[note undoManager] canRedo]==redo,@"regeneration does not add or remove Undo and Redo actions");
                Check(NSEqualRanges(a.selectedRange,selectionA) && NSEqualRanges(b.selectedRange,selectionB),@"peer glyph generation preserves independent selections");
                [peer revealNote:other options:0]; Pump();
                GlyphSnapshot(b,YES);
                Check(a.textStorage!=b.textStorage && [a.string isEqual:texts[index]],@"detaching the peer leaves the original source attached and unchanged");
                if (![a.textStorage isEqualToAttributedString:attributes]) {
                    NSLog(@"ATTRIBUTE_DIFF pass=%lu index=%lu before=%@ after=%@",(unsigned long)pass,(unsigned long)index,[attributes attributesAtIndex:0 effectiveRange:NULL],[a.textStorage attributesAtIndex:0 effectiveRange:NULL]);
                }
                Check([a.textStorage isEqualToAttributedString:attributes],@"an unrelated note's short or large buffer cannot change old source attributes");
                [peer revealNote:note options:0]; Pump();
                Check(a.textStorage==b.textStorage && HasSharedPolicy(b,style),@"reattachment retains the same session and source policy");
                [attributes release];
            }
            NSTextStorage *survivingStorage=a.textStorage;
            NSString *survivingSource=[a.string copy];
            [peer.window close]; Pump();
            GlyphSnapshot(a,YES);
            Check(a.textStorage==survivingStorage && [a.string isEqual:survivingSource],@"closing the peer cannot invalidate surviving storage or its glyph callback");
            [survivingSource release];
        }
        Check(SmallChangedBatches>0 && LargeChangedBatches>0 && UnchangedBatches>0,@"the real callback exercised stack, heap, and native-return paths");
        NSLog(@"BUFFER_METRICS {\"small_changed_batches\":%lu,\"large_changed_batches\":%lu,\"unchanged_batches\":%lu}",(unsigned long)SmallChangedBatches,(unsigned long)LargeChangedBatches,(unsigned long)UnchangedBatches);
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND3 OUSTERHOUT PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch(NSException *exception) {
        NSLog(@"ROUND3 OUSTERHOUT EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols); exit(1);
    }
}
@end
