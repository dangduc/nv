    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        LinkingEditor *editor = [self valueForKey:@"textView"];
        id counter = [self valueForKey:@"wordCounter"];
        [[GlobalPrefs defaultPrefs] setShowWordCount:NO];
        NSMutableArray *notes = [NSMutableArray array];
        NSMutableArray *sources = [NSMutableArray array];
        for (NSUInteger i=0; i<20; i++) {
            NSMutableString *source = [NSMutableString stringWithString:@"alpha beta "];
            if (i==2 || i==3) for (NSUInteger j=0;j<20000;j++) [source appendString:@"seed "];
            [source appendString:(i==1 || i==3) ? @"[[https://example.com/org][Org Label]] [[file:inert]]\n" : @"https://example.com/url [[Wiki Note]]\n"];
            NoteObject *note = MakeNote(library,[NSString stringWithFormat:@"Async %02lu",(unsigned long)i],source);
            if (i==1 || i==3) [note setSourceSyntaxIdentifier:@"org"];
            [notes addObject:note]; [sources addObject:[[source copy] autorelease]];
        }
        Check([[library allNotes] count]==20,@"exactly twenty disposable notes populate actual library");
        InstallObservers();
        NSArray *phases = @[@"short-plain",@"short-org",@"long-plain",@"long-org"];
        for (NSUInteger i=0;i<4;i++) {
            NoteObject *note = notes[i]; NSString *source = sources[i];
            NSString *suffix = @" gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega 😀 é\n";
            NSString *expected = [source stringByAppendingString:suffix];
            NSUInteger beforeCount = OracleCount(source), afterCount = OracleCount(expected);
            [self searchForString:@"" mode:@"fuzzy"]; [self revealNote:note options:0];
            Check(Await(^BOOL { return [self selectedNoteObject]==note && [editor.string isEqual:source] && NVSourceLinksAreCurrent(editor.textStorage) && [[counter stringValue] isEqual:[NSString stringWithFormat:@"%lu words",(unsigned long)beforeCount]]; },8), [phases[i] stringByAppendingString:@": selected native editor and initial count settle"]);
            Check(![counter isHidden], [phases[i] stringByAppendingString:@": native word count is visible"]);
            [[self window] makeKeyAndOrderFront:self]; [[self window] makeFirstResponder:editor];
            Check([[self window] firstResponder]==editor,[phases[i] stringByAppendingString:@": native source editor owns focus"]);
            [ObservationLock lock]; [LiveStoragePointers addObject:[NSValue valueWithPointer:editor.textStorage]]; ObservationPhase=[phases[i] copy]; NSUInteger start=[Observations count]; [ObservationLock unlock];
            [suffix enumerateSubstringsInRange:NSMakeRange(0,suffix.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *part, NSRange r, NSRange enclosing, BOOL *stop) {
                [editor insertText:part replacementRange:NSMakeRange(editor.string.length,0)];
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.012]];
            }];
            Check(Await(^BOOL { return NVSourceLinksAreCurrent(editor.textStorage) && [[counter stringValue] isEqual:[NSString stringWithFormat:@"%lu words",(unsigned long)afterCount]]; },10),[phases[i] stringByAppendingString:@": actual typing publishes complete current links and count"]);
            Check([editor.string isEqual:expected] && [[[note contentString] string] isEqual:expected], [phases[i] stringByAppendingString:@": every source character reaches editor and committed note"]);
            if (i==1 || i==3) {
                Check([[LinkAt(editor,@"Org Label") absoluteString] isEqual:@"https://example.com/org"] && !LinkAt(editor,@"file:inert"),[phases[i] stringByAppendingString:@": Org web target resolves and file target stays inert"]);
            } else {
                Check([[LinkAt(editor,@"https://example.com/url") absoluteString] isEqual:@"https://example.com/url"] && LinkAt(editor,@"Wiki Note")!=nil,[phases[i] stringByAppendingString:@": URL and wiki links survive typed edits"]);
            }
            [ObservationLock lock]; [ObservationPhase release]; ObservationPhase=nil; NSArray *events=[[Observations subarrayWithRange:NSMakeRange(start,Observations.count-start)] copy]; [ObservationLock unlock];
            NSUInteger words=0,links=0; BOOL main=NO,live=NO,wrongQueue=NO,missingHelper=NO;
            for (NSDictionary *event in events) {
                BOOL word=[event[@"selector"] isEqual:@"words"];
                if (word) words++; else links++;
                main |= [event[@"main"] boolValue]; live |= [event[@"live_storage"] boolValue];
                wrongQueue |= ![event[@"queue"] isEqual:@"org.nvalt.source-analysis"];
                missingHelper |= ![event[@"helper_frame"] boolValue] && ![event[@"worker_frame"] boolValue];
            }
            NSLog(@"OBSERVED %@ words=%lu links=%lu main=%d live=%d wrongQueue=%d missingHelper=%d",phases[i],(unsigned long)words,(unsigned long)links,main,live,wrongQueue,missingHelper);
            [[NSJSONSerialization dataWithJSONObject:Observations options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[NSString stringWithUTF8String:getenv("NV_ASYNC_OBSERVATIONS")] atomically:YES];
            Check(words>0 && links>0,[phases[i] stringByAppendingString:@": real app enters both original expensive methods"]);
            Check(!main && !live && !wrongQueue && !missingHelper,[phases[i] stringByAppendingString:@": all expensive calls use private worker objects through production source-analysis worker"]);
            [events release];
        }
        NSData *data=[NSJSONSerialization dataWithJSONObject:Observations options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_ASYNC_OBSERVATIONS")] atomically:YES],@"thread, storage and call-stack observations saved");
        Check([library flushAllNoteChanges],@"disposable library checkpoint succeeds"); [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"TYPING ASYNC PASSED (%lu checks)",(unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"TYPING ASYNC EXCEPTION %@ %@",exception.name,exception.reason); exit(1); }
}
@end
