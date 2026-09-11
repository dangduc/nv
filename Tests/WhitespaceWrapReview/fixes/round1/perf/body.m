    @try {
        NVApplicationController*app=[NVApplicationController sharedController];
        NotationController*library=app.library;
        LinkingEditor*editor=[self valueForKey:@"textView"];
        BOOL fixed=strcmp(getenv("NV_WRAP_PERF_MODE"),"fixed")==0;
        [self searchForString:@""];Pump();
        [[GlobalPrefs defaultPrefs]setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular"size:12]sender:self];
        NSMutableArray*reflows=[NSMutableArray array],*typing=[NSMutableArray array];
        for(NSNumber*number in @[@4096,@8192,@16384,@32768]) {
            NSString*source=Spaces(number.unsignedIntegerValue);
            NoteObject*note=MakeNote(library,[NSString stringWithFormat:@"spaces %@",number],source);
            [note setSourceSyntaxIdentifier:@"plain"];
            [self revealNote:note options:0];Pump();
            NSParagraphStyle*style=[editor.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
            Check(style.lineBreakMode==(fixed?NSLineBreakByCharWrapping:NSLineBreakByWordWrapping),@"actual source storage uses the expected paragraph wrapping policy");
            for(NSUInteger trial=0;trial<3;trial++) {
                [self.window setContentSize:NSMakeSize(720,600)];
                [editor.layoutManager ensureLayoutForTextContainer:editor.textContainer];Pump();
                CGFloat oldWidth=editor.textContainer.size.width;
                NSRange selection=editor.selectedRange;
                uint64_t before=mach_absolute_time();
                [self.window setContentSize:NSMakeSize(176,600)];
                [editor.layoutManager ensureLayoutForTextContainer:editor.textContainer];
                double ms=Milliseconds(mach_absolute_time()-before);
                CGFloat width=editor.textContainer.size.width;
                Check(width<oldWidth,@"window resize reduces the actual text container width");
                Check([editor.string isEqual:source]&&[[note.contentString string]isEqual:source],@"resize preserves source and committed model");
                Check(NSEqualRanges(selection,editor.selectedRange),@"resize preserves source selection");
                [reflows addObject:@{@"length":number,@"trial":@(trial),@"oldWidth":@(oldWidth),@"width":@(width),@"ms":@(ms),@"lines":@(Lines(editor))}];
            }
        }
        NSString*seed=@"A short plain text note for repeated key events.";
        NoteObject*shortNote=MakeNote(library,@"short typing",seed);
        [shortNote setSourceSyntaxIdentifier:@"plain"];[self revealNote:shortNote options:0];
        [self.window setContentSize:NSMakeSize(720,600)];
        [self.window makeKeyAndOrderFront:self];[self.window makeFirstResponder:editor];Pump();
        for(NSUInteger trial=0;trial<3;trial++) {
            [shortNote setContentString:[[[NSAttributedString alloc]initWithString:seed]autorelease]];Pump();
            [editor setSelectedRange:NSMakeRange(seed.length,0)];
            Check(self.window.firstResponder==editor,@"short note editor receives real key events");
            NSMutableString*expected=[[seed mutableCopy]autorelease];
            double cpuStart=MainCPU();uint64_t dispatchTicks=0;
            for(NSUInteger i=0;i<90;i++) {
                NSString*key=i%7?@"k":@" ";
                NSEvent*event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil characters:key charactersIgnoringModifiers:key isARepeat:i>0 keyCode:i%7?40:49];
                uint64_t start=mach_absolute_time();[NSApp sendEvent:event];dispatchTicks+=mach_absolute_time()-start;
                [expected appendString:key];
                Check([editor.string isEqual:expected]&&[[shortNote.contentString string]isEqual:expected],@"each native key preserves the exact live and committed source");
                Check(NSEqualRanges(editor.selectedRange,NSMakeRange(expected.length,0)),@"each native key advances the logical caret by one");
                [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.012]];
            }
            Pump();
            [typing addObject:@{@"trial":@(trial),@"keys":@90,@"dispatchMs":@(Milliseconds(dispatchTicks)),@"cpuMs":@(MainCPU()-cpuStart)}];
        }
        NSDictionary*results=@{@"reflows":reflows,@"typing":typing,@"checks":@(Checks)};
        NSData*data=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_WRAP_PERF_OUTPUT")]atomically:YES],@"performance evidence saved");
        [library flushAllNoteChanges];[library closeJournal];
        NSLog(@"WRAP PERF PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults]removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
        [[NSUserDefaults standardUserDefaults]synchronize];exit(0);
    }@catch(NSException*e){NSLog(@"WRAP PERF EXCEPTION %@ %@\n%@",e.name,e.reason,e.callStackSymbols);exit(1);}
}
@end
