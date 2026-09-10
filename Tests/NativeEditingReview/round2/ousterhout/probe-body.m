    @try {
        NVApplicationController *application = [NVApplicationController sharedController];
        NotationController *library = [application library];
        AppController *first = self;
        [first searchForString:@""]; Pump();

        NoteObject *note = MakeNote(library, @"Ousterhout round 2", @"alpha beta");
        [first revealNote:note options:0]; Pump();
        [application newWindow:self]; Pump();
        Check([[application browserControllers] count] == 2,
              @"a second browser opens over the shared library");
        AppController *second = [[application browserControllers] lastObject];
        [second revealNote:note options:0]; Pump();

        LinkingEditor *firstEditor = [first valueForKey:@"textView"];
        LinkingEditor *secondEditor = [second valueForKey:@"textView"];
        Check([firstEditor textStorage] == [secondEditor textStorage],
              @"both editors use the editing session's single text storage");
        Check([firstEditor layoutManager] != [secondEditor layoutManager],
              @"each editor owns a separate layout manager");

        NSArray *inputSelectors = @[
            NSStringFromSelector(@selector(keyDown:)),
            NSStringFromSelector(@selector(deleteBackward:)),
            NSStringFromSelector(@selector(insertNewline:)),
            NSStringFromSelector(@selector(insertTab:)),
            NSStringFromSelector(@selector(insertText:replacementRange:)),
            NSStringFromSelector(@selector(complete:)),
            NSStringFromSelector(@selector(selectionRangeForProposedRange:granularity:))
        ];
        for (NSString *name in inputSelectors) {
            SEL selector = NSSelectorFromString(name);
            Check(class_getMethodImplementation([LinkingEditor class], selector) ==
                  class_getMethodImplementation([NSTextView class], selector),
                  [NSString stringWithFormat:@"%@ remains owned by NSTextView", name]);
        }
        Check(![[firstEditor delegate] respondsToSelector:
              @selector(textView:completions:forPartialWordRange:indexOfSelectedItem:)],
              @"the body delegate has no source-specific completion policy");

        [[first window] makeKeyAndOrderFront:self];
        [[first window] makeFirstResponder:firstEditor];
        [firstEditor setSelectedRange:NSMakeRange([[firstEditor string] length], 0)];
        [firstEditor insertText:@" one" replacementRange:[firstEditor selectedRange]]; Pump();
        Check([[secondEditor string] isEqualToString:@"alpha beta one"] &&
              [[[note contentString] string] isEqualToString:[secondEditor string]],
              @"native input reaches the shared editor and note model");
        [[second window] makeKeyAndOrderFront:self];
        [[second window] makeFirstResponder:secondEditor];
        [secondEditor undo:self]; Pump();
        Check([[firstEditor string] isEqualToString:@"alpha beta"] &&
              [[secondEditor string] isEqualToString:[firstEditor string]] &&
              [[[note contentString] string] isEqualToString:[firstEditor string]],
              @"shared-session Undo updates both native views and the model");

        Method iBeamMethod = class_getClassMethod([NSCursor class], @selector(IBeamCursor));
        [firstEditor setBackgroundColor:[NSColor blackColor]];
        [firstEditor setMouseInside:NO];
        IMP ordinaryIBeam = method_getImplementation(iBeamMethod);
        [firstEditor setMouseInside:YES];
        IMP editorDarkIBeam = method_getImplementation(iBeamMethod);
        Check(editorDarkIBeam != ordinaryIBeam,
              @"hovering one dark source editor replaces NSCursor's class implementation");

        NSTextView *unrelated = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 40)] autorelease];
        [unrelated setString:@"unrelated field"];
        Check(method_getImplementation(class_getClassMethod([NSCursor class], @selector(IBeamCursor))) == editorDarkIBeam,
              @"the replacement remains process-wide for unrelated text views");

        [firstEditor setMouseInside:NO];
        Check(method_getImplementation(class_getClassMethod([NSCursor class], @selector(IBeamCursor))) == ordinaryIBeam,
              @"another source-editor event is required to restore the global cursor method");

        NSLog(@"OUSTERHOUT ROUND 2 EVIDENCE PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"OUSTERHOUT ROUND 2 EXCEPTION %@ %@\n%@", [exception name], [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
