    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        AppController *browser = self;
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [browser searchForString:@""]; Pump();

        NSArray *nativeCommands = @[
            NSStringFromSelector(@selector(deleteBackward:)),
            NSStringFromSelector(@selector(insertNewline:)),
            NSStringFromSelector(@selector(insertTab:)),
            NSStringFromSelector(@selector(insertBacktab:)),
            NSStringFromSelector(@selector(insertText:replacementRange:)),
            NSStringFromSelector(@selector(performKeyEquivalent:)),
            NSStringFromSelector(@selector(selectionRangeForProposedRange:granularity:))
        ];
        for (NSString *name in nativeCommands) {
            SEL selector = NSSelectorFromString(name);
            Check(class_getMethodImplementation([LinkingEditor class], selector) ==
                  class_getMethodImplementation([NSTextView class], selector),
                  [NSString stringWithFormat:@"%@ stays behind the NSTextView abstraction", name]);
        }

        NSString *candidateTitle = @"OusterhoutCompletionBoundaryUnique";
        MakeNote(library, candidateTitle, @"completion target");
        NoteObject *source = MakeNote(library, @"Ousterhout completion source", @"OusterhoutComp");
        [browser revealNote:source options:0]; Pump();
        [[browser window] makeKeyAndOrderFront:self];
        [[browser window] makeFirstResponder:editor];

        id delegate = [editor delegate];
        Check(delegate == browser, @"browser remains the source editor delegate");
        Check([delegate respondsToSelector:@selector(textView:completions:forPartialWordRange:indexOfSelectedItem:)],
              @"source editor delegate still implements the completion hook");

        NSInteger selected = -1;
        NSRange partial = NSMakeRange(0, [[editor string] length]);
        NSArray *completions = [delegate textView:editor completions:@[]
                                forPartialWordRange:partial indexOfSelectedItem:&selected];
        Check([completions containsObject:candidateTitle],
              @"source completion hook returns a note title from the library");

        Check(class_getMethodImplementation([LinkingEditor class], @selector(complete:)) ==
              class_getMethodImplementation([NSTextView class], @selector(complete:)),
              @"native complete command remains connected to delegate completion");

        NSLog(@"OUSTERHOUT ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"OUSTERHOUT ROUND 1 EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
