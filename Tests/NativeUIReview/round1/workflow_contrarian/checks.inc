- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"Alpha original body") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"Beta original body") retain];
        NSString *probe = [NSString stringWithUTF8String:getenv("NV_WORKFLOW_PROBE") ?: "tab"];
        if ([probe isEqual:@"tab"]) {
            [self searchForString:@"al"]; Pump();
            [self revealNote:alpha options:0]; Pump();
            NSTextView *editor = (id)[field currentEditor];
            Check(editor != nil, @"nonempty search has its field editor");
            [editor doCommandBySelector:@selector(insertTab:)]; Pump();
            NSLog(@"TAB_NONEMPTY expected=body actual=%@ field=%@", [window firstResponder] == textView ? @"body" : NSStringFromClass([[window firstResponder] class]), [field stringValue]);
            Check([window firstResponder] == textView, @"Tab moves from a nonempty search to the selected note body");
            [self searchForString:@""]; Pump();
            [self revealNote:alpha options:0]; Pump();
            [self bringFocusToControlField:self]; for (NSUInteger i=0;i<5;i++) Pump();
            editor = (id)[field currentEditor];
            Check([self selectedNoteObject] == alpha && editor != nil, @"empty-query note selection and search focus are established");
            NSLog(@"TAB_EMPTY before selected=%@ query=%@ field=%@", titleOfNote([self selectedNoteObject]), [[self browserSession] searchString], [field stringValue]);
            [editor doCommandBySelector:@selector(insertTab:)]; Pump();
            NSLog(@"TAB_EMPTY expected=body actual=%@ currentEditor=%p", [window firstResponder] == textView ? @"body" : NSStringFromClass([[window firstResponder] class]), [field currentEditor]);
            Check([window firstResponder] == textView, @"Tab moves from search to a selected note even when the persistent query is empty");
        } else if ([probe isEqual:@"paste"]) {
            [self searchForString:getenv("NV_WORKFLOW_FILTERED") ? @"Alpha" : @""]; Pump();
            [app newWindow:self]; Pump();
            AppController *peer = [[app browserControllers] lastObject];
            [peer searchForString:@"Beta"]; Pump();
            [peer revealNote:beta options:0]; Pump();
            NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
            [pasteboard declareTypes:@[NSStringPboardType] owner:nil];
            [pasteboard setString:@"Pasted heading\nPasted body with no services" forType:NSStringPboardType];
            [window makeKeyAndOrderFront:self]; Pump();
            BOOL imported = [self addNotesFromPasteboard:pasteboard]; Pump();
            NoteObject *created = [self selectedNoteObject];
            NSLog(@"PASTE expected=count3,bodypreserved,originselected,peerBeta actual=count%lu title=%@ body=%@ peer=%@", (unsigned long)[library totalNoteCount], created ? titleOfNote(created) : @"nil", [[created contentString] string], titleOfNote([peer selectedNoteObject]));
            Check(imported && [library totalNoteCount] == 3, @"plain-text clipboard import creates one note in the shared library");
            Check(created != alpha && created != beta && [[[created contentString] string] isEqual:@"Pasted heading\nPasted body with no services"], @"clipboard body survives and new note is selected in the originating browser");
            Check([peer selectedNoteObject] == beta && [[[[peer browserSession] searchString] lowercaseString] isEqual:@"beta"], @"clipboard import preserves the other browser query and selection");
            [pasteboard releaseGlobally];
        } else if ([probe isEqual:@"tags"]) {
            [alpha setLabelString:@"workflow"]; Pump();
            [self searchForString:@""]; [self revealNote:beta options:0]; Pump();
            [self tagNote:self]; Pump();
            NSTextView *editor = (id)[window firstResponder];
            Check([editor isKindOfClass:[NSTextView class]], @"Tag Note opens a text field editor");
            [editor insertText:@"wor" replacementRange:NSMakeRange(0, [[editor string] length])]; Pump();
            [editor complete:nil]; Pump();
            NSLog(@"TAGS expected=workflow actual=%@ delegate=%@", [editor string], NSStringFromClass([[editor delegate] class]));
            Check([[editor string] isEqual:@"workflow"], @"single-note tag editing completes an existing tag prefix");
        }
        [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"WORKFLOW PROBES PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
