- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSUInteger phase = strtoul(getenv("NV_REVIEW_PHASE") ?: "1", NULL, 10);
        if (phase == 1) {
            NSMutableString *body = [NSMutableString string];
            for (NSUInteger i=0; i<350; i++) [body appendFormat:@"Paragraph %lu: source remains intact across layout and mode transitions.\n\n", (unsigned long)i];
            NoteObject *note = MakeNote(library, @"Scroll control", body);
            [self revealNote:note options:0];
            NSRect frame = [window frame]; frame.size = NSMakeSize(780,700); [window setFrame:frame display:YES];
            for (NSUInteger i=0; i<6; i++) Pump();
            [self setNotesListHeight:175];
            [[textView layoutManager] ensureLayoutForTextContainer:[textView textContainer]];
            [textView setSelectedRange:NSMakeRange(350,9)];
            [textView scrollPoint:NSMakePoint(0,650)];
            Check(fabs([[textScrollView contentView] bounds].origin.y-650)<1, @"base-compatible control starts at source scroll 650");
            [self setViewingNote:YES];
            PreviewController *preview = [self valueForKey:@"previewController"];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
            while ([preview loading] && [deadline timeIntervalSinceNow]>0) Pump();
            Check(![preview loading] && ![preview renderError], @"base-compatible control renders Preview before checkpoint");
            NSDictionary *state = [self browserWindowState];
            NSLog(@"CONTROL before relaunch editorScroll=%@ bodyState=%@", state[@"editorScroll"], state[@"bodyState"]);
            Check(fabs(NSPointFromString(state[@"editorScroll"]).y-650)<1, @"checkpoint stores source scroll 650 while Preview is visible");
            [app saveWindowStates]; [prefsController synchronize]; [library flushAllNoteChanges]; [library closeJournal];
            NSLog(@"SCROLL CONTROL PHASE 1 PASSED: %lu checks", (unsigned long)Checks); exit(0);
        }
        Check([[self valueForKey:@"viewingNote"] boolValue], @"base-compatible relaunch starts in Preview");
        NSLog(@"CONTROL restored state before returning Source=%@", [self browserWindowState]);
        [self setViewingNote:NO]; Pump();
        CGFloat sourceY = [[textScrollView contentView] bounds].origin.y;
        NSLog(@"CONTROL observed post-relaunch Source scroll=%g; expected=650", sourceY);
        Check(NSEqualRanges([textView selectedRange],NSMakeRange(350,9)), @"base-compatible relaunch preserves selection");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"SCROLL CONTROL PHASE 2 COMPLETED: %lu checks", (unsigned long)Checks); exit(0);
    } @catch(NSException *exception) { NSLog(@"FAIL exception: %@",exception); exit(1); }
}
