    @try {
        NVApplicationController*app=[NVApplicationController sharedController];
        NotationController*library=app.library;
        LinkingEditor*editor=[self valueForKey:@"textView"];
        StyleIdentities=[NSMutableSet new];
        Method method=class_getInstanceMethod(GlobalPrefs.class,@selector(noteBodyAttributes));
        OriginalAttributes=method_getImplementation(method);method_setImplementation(method,(IMP)ObserveAttributes);
        [self searchForString:@""];Pump();
        [[GlobalPrefs defaultPrefs]setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular"size:12]sender:self];
        NSMutableArray*trials=[NSMutableArray array];
        for(NSString*name in @[@"single-paragraph",@"many-paragraphs"]){
            NSMutableString*seed=[NSMutableString string];
            NSString*unit=[name isEqual:@"single-paragraph"]?@"alpha\tbeta   Việt 👩🏽‍💻 中文   ":@"alpha\tbeta   Việt 👩🏽‍💻 中文   \n";
            for(NSUInteger i=0;i<1024;i++)[seed appendString:unit];
            [seed appendString:[@""stringByPaddingToLength:200 withString:@" "startingAtIndex:0]];
            NoteObject*note=MakeNote(library,name,seed);[note setSourceSyntaxIdentifier:@"plain"];
            [self revealNote:note options:0];[self.window setContentSize:NSMakeSize(860,640)];
            [self.window makeKeyAndOrderFront:self];[self.window makeFirstResponder:editor];Pump();
            for(NSUInteger trial=0;trial<3;trial++){
                [note setContentString:[[[NSAttributedString alloc]initWithString:seed]autorelease]];
                [editor setSelectedRange:NSMakeRange(seed.length,0)];Pump();
                Check(self.window.firstResponder==editor,@"actual mixed-source editor has key focus");
                NSMutableString*expected=[[seed mutableCopy]autorelease];
                uint64_t dispatch=0;double resizeTotal=0,resizeMax=0,cpuStart=CPU();
                NSMutableArray*widths=[NSMutableArray array];
                for(NSUInteger i=0;i<64;i++){
                    NSString*key=i%3?@"k":@" ";
                    NSEvent*event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil characters:key charactersIgnoringModifiers:key isARepeat:i>0 keyCode:i%3?40:49];
                    uint64_t before=mach_absolute_time();[NSApp sendEvent:event];dispatch+=mach_absolute_time()-before;
                    [expected appendString:key];
                    Check([editor.string isEqual:expected]&&[[note.contentString string]isEqual:expected],@"mixed-source event preserves exact Unicode source and committed model");
                    Check(NSEqualRanges(editor.selectedRange,NSMakeRange(expected.length,0)),@"mixed-source event advances logical caret once");
                    if(i%8==7){
                        NSRange selection=editor.selectedRange;
                        uint64_t start=mach_absolute_time();
                        [self.window setContentSize:NSMakeSize((i/8)%2?860:520,640)];
                        // Flush visible window work; do not force whole-document layout here.
                        [self.window displayIfNeeded];
                        double elapsed=Ms(mach_absolute_time()-start);resizeTotal+=elapsed;resizeMax=MAX(resizeMax,elapsed);
                        [widths addObject:@(editor.textContainer.size.width)];
                        Check([editor.string isEqual:expected]&&NSEqualRanges(editor.selectedRange,selection),@"visible resize preserves current edit and caret");
                    }
                    [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.012]];
                }
                Pump();
                double cpuElapsed=CPU()-cpuStart;
                // Geometry context is collected after the timed visible-work phase.
                [editor.layoutManager ensureLayoutForTextContainer:editor.textContainer];
                __block NSUInteger finalLines=0;
                [editor.layoutManager enumerateLineFragmentsForGlyphRange:NSMakeRange(0,editor.layoutManager.numberOfGlyphs)
                    usingBlock:^(NSRect a,NSRect b,NSTextContainer*c,NSRange r,BOOL*stop){finalLines++;}];
                [trials addObject:@{@"case":name,@"trial":@(trial),@"initialUTF16":@(seed.length),@"keys":@64,
                    @"dispatchMs":@(Ms(dispatch)),@"cpuMs":@(cpuElapsed),@"resizeTotalMs":@(resizeTotal),@"resizeMaxMs":@(resizeMax),@"containerWidths":widths,@"finalLines":@(finalLines)}];
            }
        }
        BOOL candidate=strcmp(getenv("NV_R2_MODE"),"candidate")==0;
        Check(!candidate||StyleIdentities.count==1,@"actual candidate edits reuse one immutable source paragraph style");
        NSDictionary*results=@{@"trials":trials,@"styleCalls":@(StyleCalls),@"styleCount":@(StyleIdentities.count),
            @"styleObjectBytes":@(StyleBytes),@"styleOffMainCalls":@(StyleOffMainCalls),@"checks":@(Checks)};
        NSData*data=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_R2_OUTPUT")]atomically:YES],@"mixed-source evidence saved");
        [library flushAllNoteChanges];[library closeJournal];
        NSLog(@"MIXED SOURCE REVIEW PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults]removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
        [[NSUserDefaults standardUserDefaults]synchronize];exit(0);
    }@catch(NSException*e){NSLog(@"MIXED SOURCE REVIEW EXCEPTION %@ %@\n%@",e.name,e.reason,e.callStackSymbols);exit(1);}
}
@end
