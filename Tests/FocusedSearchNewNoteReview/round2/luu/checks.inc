- (NoteObject *)nv_luuCommandNExpecting:(NSString *)expected label:(NSString *)label {
    NotationController *library = [[NVApplicationController sharedController] library];
    NSUInteger before = [library totalNoteCount];
    NoteObject *previous = [self selectedNoteObject];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
        context:nil characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:kVK_ANSI_N];
    Check([[NSApp mainMenu] performKeyEquivalent:event], [label stringByAppendingString:@": menu handles Command-N"]);
    NoteObject *created = [self selectedNoteObject];
    Check(created && created != previous && [library totalNoteCount] == before + 1 &&
        [titleOfNote(created) isEqual:expected],
        [label stringByAppendingString:@": one distinct note has the expected title before another run-loop turn"]);
    Check([prefsController showTitleInTopSection] ? [noteTitleField currentEditor] != nil : [window firstResponder] == textView,
        [label stringByAppendingString:@": the configured title or source editor has focus"]);
    return created;
}

- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        NotationController *library = [[NVApplicationController sharedController] library];
        NSString *untitled = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
        NSMutableArray *createdNotes = [NSMutableArray array];
        for (NSNumber *visible in @[@NO, @YES]) {
            NSString *mode = [visible boolValue] ? @"visible title" : @"hidden title";
            [prefsController setShowTitleInTopSection:[visible boolValue] sender:nil];
            [self searchForString:@"Previously nonempty query" mode:@"exact"];
            NSTextView *editor = (id)[field currentEditor];
            [editor selectAll:nil];
            [editor deleteBackward:nil];
            Check([self searchFieldHasFocus] && [[editor string] length] == 0,
                [mode stringByAppendingString:@": native select-all and Delete leave empty focused Search"]);
            Check([[[self browserSession] searchString] length] == 0,
                [mode stringByAppendingString:@": native deletion publishes the empty search"]);
            [createdNotes addObject:[self nv_luuCommandNExpecting:untitled label:[mode stringByAppendingString:@" after deletion"]]];
            // No Pump between commands: each command must establish its complete
            // postcondition before the next key equivalent arrives.
            [createdNotes addObject:[self nv_luuCommandNExpecting:untitled label:[mode stringByAppendingString:@" repeat one"]]];
            [createdNotes addObject:[self nv_luuCommandNExpecting:untitled label:[mode stringByAppendingString:@" repeat two"]]];
            Pump();

            [self searchForString:@"Live original title" mode:@"fuzzy"];
            NoteObject *first = [self nv_luuCommandNExpecting:@"Live original title"
                label:[mode stringByAppendingString:@" populated Search"]];
            [createdNotes addObject:first];
            if ([visible boolValue]) {
                NSTextView *titleEditor = (id)[noteTitleField currentEditor];
                [titleEditor insertText:@"Renamed before next Command-N"
                    replacementRange:NSMakeRange(0, [[titleEditor string] length])];
                Check([[titleEditor string] isEqual:@"Renamed before next Command-N"] && ![self searchFieldHasFocus],
                    @"visible title: pending title edit owns focus before the next command");
            } else {
                [textView insertText:@"Body before next Command-N" replacementRange:NSMakeRange(0, 0)];
                Check([[textView string] isEqual:@"Body before next Command-N"] && ![self searchFieldHasFocus],
                    @"hidden title: pending source edit owns focus before the next command");
            }
            NoteObject *second = [self nv_luuCommandNExpecting:untitled label:[mode stringByAppendingString:@" after edit"]];
            [createdNotes addObject:second];
            Pump();
            if ([visible boolValue]) {
                Check([titleOfNote(first) isEqual:@"Renamed before next Command-N"] && [[first contentString] length] == 0,
                    @"visible title: the next command commits the preceding title without copying it to the new note");
            } else {
                Check([titleOfNote(first) isEqual:@"Live original title"] &&
                    [[[first contentString] string] isEqual:@"Body before next Command-N"],
                    @"hidden title: the next command preserves the preceding title and source edit");
            }
            Check([[second contentString] length] == 0 && [[field stringValue] length] == 0 &&
                [[[self browserSession] searchString] length] == 0,
                [mode stringByAppendingString:@": the new source stays empty and Search stays cleared"]);
        }
        for (NSUInteger i = 0; i < 4; i++) Pump();
        Check([library totalNoteCount] == 10 && [[NSSet setWithArray:createdNotes] count] == 10,
            @"ten commands created ten distinct notes after delayed callbacks");
        for (NoteObject *note in createdNotes) [library removeNote:note];
        Check([library totalNoteCount] == 0, @"the disposable library has no remaining notes");
        NSLog(@"DAN LUU-INSPIRED ROUND 2 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
