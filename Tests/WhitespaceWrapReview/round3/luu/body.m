    @try{
        NVApplicationController*app=[NVApplicationController sharedController];NotationController*library=app.library;
        LinkingEditor*editor=[self valueForKey:@"textView"];
        BOOL sample=strcmp(getenv("NV_R3_SAMPLE"),"1")==0;
        if(sample){SEL selector=@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:);Method method=class_getInstanceMethod(LinkingEditor.class,selector);OriginalGlyphs=(GlyphFunction)method_getImplementation(method);method_setImplementation(method,(IMP)ObserveGlyphs);}
        NSString*seed=@"A short note with a few words. ";
        NoteObject*note=MakeNote(library,@"Active short note",seed);[note setSourceSyntaxIdentifier:@"plain"];
        for(NSUInteger i=1;i<20;i++)MakeNote(library,[NSString stringWithFormat:@"Reference %02lu",(unsigned long)i],@"A different short reference note.");
        Check(library.allNotes.count==20,@"disposable corpus contains exactly 20 notes");
        [self searchForString:@""];[self revealNote:note options:0];Pump();
        [self.window setContentSize:NSMakeSize(480,600)];[self.window makeKeyAndOrderFront:self];[self.window makeFirstResponder:editor];Pump();
        NSMutableArray*results=[NSMutableArray array];
        NSArray*fonts=sample?@[@[@"Menlo-Regular",@12]]:@[@[@"Menlo-Regular",@12],@[@"Helvetica",@18]];
        for(NSArray*font in fonts){
            [[GlobalPrefs defaultPrefs]setNoteBodyFont:[NSFont fontWithName:font[0]size:[font[1]doubleValue]]sender:self];
            for(NSUInteger trial=0;trial<(sample?1:3);trial++){
                [note setContentString:[[[NSAttributedString alloc]initWithString:seed]autorelease]];Pump();
                [editor setSelectedRange:NSMakeRange(seed.length,0)];
                Check(self.window.firstResponder==editor&&self.browserSession.searchString.length==0,@"actual editor has focus and search is empty");
                NSMutableString*expected=[[seed mutableCopy]autorelease];
                Mallocs=Frees=GlyphCalls=ChangedSmall=ChangedLarge=MaximumBatch=0;MallocBytes=0;
                uint64_t ticks=0;double startCPU=CPU();NSUInteger count=sample?64:128;
                for(NSUInteger i=0;i<count;i++){
                    NSString*key=(i%64)<16?@"k":@" ";
                    NSEvent*event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil characters:key charactersIgnoringModifiers:key isARepeat:i>0 keyCode:[key isEqual:@" "]?49:40];
                    uint64_t start=mach_absolute_time();[NSApp sendEvent:event];ticks+=mach_absolute_time()-start;
                    [expected appendString:key];
                    Check([editor.string isEqual:expected]&&[[note.contentString string]isEqual:expected],@"native key preserves exact source and committed note");
                    Check(NSEqualRanges(editor.selectedRange,NSMakeRange(expected.length,0)),@"native key advances logical caret once");
                    [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.012]];
                }
                Pump();double cpu=CPU()-startCPU;
                Check(library.allNotes.count==20&&self.browserSession.searchString.length==0,@"typing preserves corpus count and empty query");
                [results addObject:@{@"font":font[0],@"size":font[1],@"trial":@(trial),@"keys":@(count),@"dispatchMs":@(Ms(ticks)),@"cpuMs":@(cpu),
                    @"glyphCalls":@(GlyphCalls),@"changedSmall":@(ChangedSmall),@"changedLarge":@(ChangedLarge),@"maximumBatch":@(MaximumBatch),
                    @"mallocs":@(Mallocs),@"frees":@(Frees),@"mallocBytes":@(MallocBytes)}];
            }
        }
        NSData*data=[NSJSONSerialization dataWithJSONObject:@{@"trials":results,@"checks":@(Checks)}options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_R3_OUTPUT")]atomically:YES],@"final typing evidence saved");
        [library flushAllNoteChanges];[library closeJournal];NSLog(@"SHORT NOTE REVIEW PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults]removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];[[NSUserDefaults standardUserDefaults]synchronize];exit(0);
    }@catch(NSException*e){NSLog(@"FINAL TYPING EXCEPTION %@ %@\n%@",e.name,e.reason,e.callStackSymbols);exit(1);}
}
@end
