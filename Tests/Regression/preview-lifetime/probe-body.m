    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        // NV_LIFETIME_INSTRUMENTATION
        NotationController *library = [app library];
        NoteObject *note = MakeNote(library, @"Ownership fixture", @"alpha beta gamma");
        Check([self valueForKey:@"previewController"] == nil, @"initial source window has no viewer provider");
        for (int index = 0; index < 8; index++) {
            NSAutoreleasePool *pool = [NSAutoreleasePool new];
            [app newWindow:self]; Pump();
            AppController *browser = [[app browserControllers] lastObject];
            [browser revealNote:note options:0]; Pump();
            Check(![browser isViewingNote] && [browser valueForKey:@"previewController"] == nil, @"source-only browser does not allocate a viewer");
            LinkingEditor *editor = [browser valueForKey:@"textView"];
            [editor setSelectedRange:NSMakeRange(5, 0)];
            [editor beforeString]; [editor afterString];
            [[browser window] close]; Pump();
            [pool drain]; Pump();
        }
        // Model notifications exercise observer removal after each browser closes.
        for (int index = 0; index < 12; index++) { [note setTitleString:[NSString stringWithFormat:@"Ownership fixture %d", index]]; Pump(); }
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
        while ((editorDeaths < 8 || browserDeaths < 8) && [deadline timeIntervalSinceNow] > 0) Pump();
        NSLog(@"SOURCE LIFETIME browsers=%lu editors=%lu viewerBirths=%lu viewerDeaths=%lu WKBirths=%lu WKDeaths=%lu", (unsigned long)browserDeaths, (unsigned long)editorDeaths, (unsigned long)previewBirths, (unsigned long)previewDeaths, (unsigned long)webBirths, (unsigned long)webDeaths);
        Check(browserDeaths == 8, @"all eight closed source browser controllers deallocate");
        Check(editorDeaths == 8, @"all eight delayed source editor deallocations complete");
        Check(previewBirths == 0 && previewDeaths == 0, @"source-only windows allocate zero viewer providers");
        Check(webBirths == 0 && webDeaths == 0, @"source-only windows allocate zero WKWebViews");
        Check([GlobalPrefs defaultPrefs] != nil && [[GlobalPrefs defaultPrefs] noteBodyFont] != nil, @"shared preferences remain usable after editor deallocation");
        Check([[[note contentString] string] isEqualToString:@"alpha beta gamma"], @"shared note survives browser teardown");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"PREVIEW LIFETIME CHECKS PASSED (%lu)", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
@end
