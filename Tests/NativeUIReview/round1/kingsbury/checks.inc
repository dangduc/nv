- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [[app library] retain];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha body") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"beta body") retain];
        NSString *scenario = [NSString stringWithUTF8String:getenv("NV_REVIEW_CASE") ?: "search-new"];
        NSLog(@"CASE %@", scenario);
        if ([scenario isEqual:@"search-new"]) {
            [self searchForString:@"al"]; Pump();
            NSTextView *searchEditor = (id)[field currentEditor];
            Check(searchEditor != nil && [self selectedNoteObject] == alpha, @"setup has a focused search and selected Alpha");
            [searchEditor setMarkedText:@"draft query" selectedRange:NSMakeRange(11, 0) replacementRange:NSMakeRange(0, [[searchEditor string] length])];
            Check([searchEditor hasMarkedText] && [[[self browserSession] searchString] isEqual:@"al"], @"search composition is pending above the old query");
            [self newNote:self]; Pump();
            NoteObject *created = [self selectedNoteObject];
            NSLog(@"OBSERVED query=%@ title=%@ count=%lu titleEditor=%@", [[self browserSession] searchString], created ? titleOfNote(created) : @"<nil>", (unsigned long)[library totalNoteCount], [noteTitleField currentEditor]);
            Check([library totalNoteCount] == 3, @"New Note during composition creates exactly one note");
            Check(created != nil && created != alpha && created != beta && [[[created contentString] string] length] == 0, @"New Note keeps the new blank note selected");
            Check([[[self browserSession] searchString] length] == 0 && [[field stringValue] length] == 0, @"ending the old composition cannot restore its query after New Note");
            Check([noteTitleField currentEditor] != nil, @"New Note transfers focus to its title");
        } else if ([scenario isEqual:@"delete-metadata"]) {
            [self searchForString:@""]; [self revealNote:alpha options:0]; Pump();
            [self renameNote:self];
            NSTextView *titleEditor = (id)[noteTitleField currentEditor];
            [titleEditor setMarkedText:@"Pending Alpha" selectedRange:NSMakeRange(13, 0) replacementRange:NSMakeRange(0, [[titleEditor string] length])];
            Check([titleEditor hasMarkedText], @"title has a pending composition before remote deletion");
            [library removeNote:alpha]; Pump();
            [self revealNote:beta options:0]; Pump();
            [window makeFirstResponder:textView]; Pump();
            NSLog(@"OBSERVED removed=%d alpha=%@ beta=%@ header=%@ marked=%d", ![[library allNotes] containsObject:alpha], titleOfNote(alpha), titleOfNote(beta), [noteTitleField stringValue], [titleEditor hasMarkedText]);
            Check(![[library allNotes] containsObject:alpha], @"committing the stale field never resurrects a deleted note");
            Check([titleOfNote(beta) isEqual:@"Beta"] && [[noteTitleField stringValue] isEqual:@"Beta"], @"stale composition cannot rename the replacement selection");
            Check(![titleEditor hasMarkedText], @"changing selection finishes the old title composition");
        } else if ([scenario isEqual:@"switch-library"]) {
            [app newWindow:self]; Pump();
            AppController *peer = [[app browserControllers] lastObject];
            [peer revealNote:alpha options:0];
            [window makeKeyAndOrderFront:self];
            [self revealNote:alpha options:0]; [self renameNote:self];
            NSTextView *titleEditor = (id)[noteTitleField currentEditor];
            [titleEditor insertText:@"Before library switch" replacementRange:NSMakeRange(0, [[titleEditor string] length])];
            Check([titleOfNote(alpha) isEqual:@"Alpha"], @"metadata is pending before the library switch");
            // Match the preference-driven switch: release the shared journal before opening another library.
            Check([library flushAllNoteChanges], @"old library flushes before another library opens");
            [library closeJournal];
            NSString *otherPath = [TestDirectory stringByAppendingPathComponent:@"OtherNotes"];
            [[NSFileManager defaultManager] createDirectoryAtPath:otherPath withIntermediateDirectories:NO attributes:nil error:NULL];
            FSRef directory; OSStatus err = FSPathMakeRef((const UInt8 *)[otherPath fileSystemRepresentation], &directory, NULL);
            NotationController *other = [[[NotationController alloc] initWithDirectoryRef:&directory error:&err] autorelease];
            Check(other != nil && err == noErr && [[other allNotes] count] == 0, @"second isolated library opens empty");
            [app setLibrary:other]; Pump();
            Check([titleOfNote(alpha) isEqual:@"Before library switch"], @"switching libraries commits pending metadata to the old note");
            Check([self sharedNotationController] == other && [peer sharedNotationController] == other, @"all browser sessions move to the new shared library");
            NoteObject *newNote = MakeNote(other, @"New library note", @"other body");
            [self revealNote:newNote options:0]; Pump();
            [window makeFirstResponder:textView]; Pump();
            Check([titleOfNote(newNote) isEqual:@"New library note"] && [[other allNotes] count] == 1, @"ending the old field session cannot mutate or copy into the new library");
            Check([[noteTitleField stringValue] isEqual:@"New library note"] && [[textView string] isEqual:@"other body"], @"new library header and editor agree");
            [other flushAllNoteChanges]; [other closeJournal];
        } else { Check(NO, @"known scenario"); }
        [library flushAllNoteChanges]; [library closeJournal];
        [alpha release]; [beta release]; [library release];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"KINGSBURY ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
