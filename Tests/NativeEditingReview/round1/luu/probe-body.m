    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];

        MakeNote(library, @"Alpha Completion Candidate", @"candidate body");
        NoteObject *target = MakeNote(library, @"Completion Target", @"Al");
        [browser revealNote:target options:0]; Pump();
        [[browser window] makeKeyAndOrderFront:self];
        [[browser window] makeFirstResponder:editor];
        [editor setSelectedRange:NSMakeRange(2, 0)];

        Check([[browser window] firstResponder] == editor && [editor delegate] == (id)browser,
              @"source editor is active and AppController remains its completion delegate");

        NSInteger selected = -1;
        NSArray *provided = [browser textView:editor
                                  completions:@[@"NSTextView fallback"]
                           forPartialWordRange:NSMakeRange(0, 2)
                        indexOfSelectedItem:&selected];
        Check([provided containsObject:@"Alpha Completion Candidate"],
              @"source editor delegate still exposes note-title completion");
        Check(![provided containsObject:@"NSTextView fallback"],
              @"source editor replaces AppKit completion candidates with nv note titles");

        [editor insertText:@"p" replacementRange:[editor selectedRange]]; Pump();
        Check([[editor string] isEqualToString:@"Alp"],
              @"ordinary typing does not trigger completion, explaining the production-suite pass");

        NSLog(@"LUU NATIVE EDITING REVIEW REPRODUCED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"LUU NATIVE EDITING REVIEW EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
