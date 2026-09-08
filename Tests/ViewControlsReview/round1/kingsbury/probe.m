- (void)nv_kingsburyCheckHidden:(NSArray *)controllers {
    for (AppController *browser in controllers) {
        NSSplitViewItem *item = [[browser valueForKey:@"browserSplitController"] splitViewItems][0];
        Check([item isCollapsed] && [[browser valueForKey:@"notesSubview"] isHiddenOrHasHiddenAncestor],
            @"the actual list is collapsed in each browser");
        Check([[browser valueForKey:@"noteTitleField"] isHidden] && [[browser valueForKey:@"noteTagsField"] isHidden] &&
            [[browser valueForKey:@"bodyModeControl"] isHidden], @"all three header preferences reach each browser");
        Check(fabs(NSHeight([[browser valueForKey:@"splitSubview"] bounds]) -
            NSHeight([[browser valueForKey:@"textScrollView"] frame])) < 1,
            @"the hidden header and word count leave no reserved header area");
    }
}
- (void)nv_kingsburyHide {
    [prefsController setShowWordCount:YES];
    [prefsController setShowTitleInTopSection:NO sender:nil];
    [prefsController setShowTagsInTopSection:NO sender:nil];
    [prefsController setShowBodyControlsInTopSection:NO sender:nil];
    [prefsController setShowNotesList:NO sender:nil];
    Pump();
}
- (void)nv_runTests {
    @try {
        NSUInteger phase = strtoul(getenv("NV_REVIEW_PHASE") ?: "1", NULL, 10);
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSString *markerPath = [TestDirectory stringByAppendingPathComponent:@"relaunch.plist"];
        if (phase == 1) {
            NoteObject *alpha = MakeNote(library, @"Persist Alpha", @"source alpha");
            NoteObject *beta = MakeNote(library, @"Persist Beta", @"source beta");
            [app newWindow:self]; Pump();
            AppController *peer = [[app browserControllers] lastObject];
            [self searchForString:@""]; [self revealNote:alpha options:0];
            [peer searchForString:@""]; [peer revealNote:beta options:0];
            for (AppController *browser in [app browserControllers]) {
                NSRect frame = [[browser window] frame]; frame.size = NSMakeSize(780, 700);
                [[browser window] setFrame:frame display:YES];
            }
            for (NSUInteger i = 0; i < 6; i++) Pump();
            [self setNotesListHeight:120]; [peer setNotesListHeight:180]; Pump();
            NSArray *heights = @[@([self notesListHeight]), @([peer notesListHeight])];
            Check(fabs([heights[0] doubleValue] - 120) < 1 && fabs([heights[1] doubleValue] - 180) < 1,
                @"the two windows begin with distinct expanded divider heights");
            [self nv_kingsburyHide];
            [self nv_kingsburyCheckHidden:[app browserControllers]];
            NSRect previous = [[peer window] frame], small = previous;
            small.size.height = 440;
            [[peer window] setFrame:small display:YES]; Pump();
            Check(fabs([peer notesListHeight] - [heights[1] doubleValue]) < 1,
                @"a collapsed resize retains the peer's expanded height");
            [[peer window] setFrame:previous display:YES]; Pump();
            Check(fabs([peer notesListHeight] - [heights[1] doubleValue]) < 1,
                @"a collapsed shrink and expansion preserve the original divider height");
            Check([@{@"heights": heights, @"titles": @[@"Persist Alpha", @"Persist Beta"]}
                writeToFile:markerPath atomically:YES], @"the independent expected state persists for the next process");
            // Negative control: model the faulty implementation that serializes
            // zero physical height instead of the saved expanded height.
            if (getenv("NV_REVIEW_ZERO_COLLAPSED_HEIGHT")) {
                Method method = class_getInstanceMethod([AppController class], @selector(notesListHeight));
                IMP original = method_getImplementation(method);
                IMP replacement = imp_implementationWithBlock(^CGFloat(id browser) {
                    NSSplitViewItem *item = [[browser valueForKey:@"browserSplitController"] splitViewItems][0];
                    return [item isCollapsed] ? 0 : ((CGFloat (*)(id, SEL))original)(browser, @selector(notesListHeight));
                });
                method_setImplementation(method, replacement);
                [app saveWindowStates];
                method_setImplementation(method, original); imp_removeBlock(replacement);
            } else [app saveWindowStates];
            [prefsController synchronize];
            Check([[[NSUserDefaults standardUserDefaults] arrayForKey:@"NVBrowserWindows"] count] == 2,
                @"the native coordinator stores exactly two windows for relaunch");
            [library flushAllNoteChanges]; [library closeJournal];
            NSLog(@"KINGSBURY PHASE 1 PASSED: %lu checks", (unsigned long)Checks); exit(0);
        }
        NSDictionary *marker = [NSDictionary dictionaryWithContentsOfFile:markerPath];
        Check(marker != nil, @"the second process reads the first process's expected state");
        NSArray *controllers = [app browserControllers], *heights = marker[@"heights"];
        Check([controllers count] == 2, @"normal startup restores both persisted browser windows");
        Check(![prefsController showNotesList] && ![prefsController showTitleInTopSection] &&
            ![prefsController showTagsInTopSection] && ![prefsController showBodyControlsInTopSection],
            @"a new process restores all four hidden preferences from its defaults");
        [self nv_kingsburyCheckHidden:controllers];
        for (NSUInteger i = 0; i < 2; i++) {
            AppController *browser = controllers[i];
            Check(fabs([browser notesListHeight] - [heights[i] doubleValue]) < 1,
                @"relaunch preserves each window's saved expanded height while collapsed");
            Check([titleOfNote([browser selectedNoteObject]) isEqual:marker[@"titles"][i]],
                @"relaunch retains each selected note while its list is hidden");
        }
        Check([library totalNoteCount] == 2, @"the source library survives the real process boundary");
        [prefsController setShowNotesList:YES sender:nil]; Pump();
        for (NSUInteger i = 0; i < 2; i++) {
            AppController *browser = controllers[i];
            NSSplitViewItem *item = [[browser valueForKey:@"browserSplitController"] splitViewItems][0];
            Check(![item isCollapsed] && fabs(NSHeight([[browser valueForKey:@"notesSubview"] frame]) -
                [heights[i] doubleValue]) < 1, @"Show restores the physical divider to its separate saved height");
        }
        AppController *peer = controllers[1];
        for (NSUInteger history = 0; history < 20; history++) {
            [prefsController setShowNotesList:NO sender:nil];
            [prefsController setShowTitleInTopSection:(history & 1) sender:nil];
            [app newWindow:self];
            AppController *closing = [[app browserControllers] lastObject];
            Check([[[closing valueForKey:@"browserSplitController"] splitViewItems][0] isCollapsed],
                @"a window created within a toggle history inherits physical collapse");
            [[closing window] close];
            [prefsController setShowTagsInTopSection:(history & 1) sender:nil];
            [prefsController setShowNotesList:YES sender:nil];
            if (history % 4 == 0) Pump();
            Check([[app browserControllers] count] == 2, @"closing an interleaved browser preserves the original owners");
            Check(fabs([self notesListHeight] - [heights[0] doubleValue]) < 1 &&
                fabs([peer notesListHeight] - [heights[1] doubleValue]) < 1,
                @"interleaved creation and closure preserve both expanded divider heights");
        }
        [self nv_kingsburyHide];
        NSMutableDictionary *legacy = [[[peer browserWindowState] mutableCopy] autorelease];
        [legacy setObject:@YES forKey:@"horizontalLayout"];
        [legacy setObject:@1 forKey:@"layoutVersion"];
        [legacy setObject:@500 forKey:@"divider"];
        [peer restoreBrowserWindowState:legacy]; Pump();
        NSSplitView *peerSplit = [peer valueForKey:@"splitView"];
        Check(![peerSplit isVertical], @"legacy side-by-side state restores the required list-above-editor layout");
        Check(fabs([peer notesListHeight] - NSHeight([peerSplit bounds]) / 3) < 1,
            @"legacy width becomes a list height without revealing the hidden list");
        [self nv_kingsburyCheckHidden:controllers];
        NSString *replacementDirectory = [TestDirectory stringByAppendingPathComponent:@"Replacement"];
        Check([[NSFileManager defaultManager] createDirectoryAtPath:replacementDirectory
            withIntermediateDirectories:YES attributes:nil error:nil], @"a disposable replacement library directory exists");
        FSRef ref; OSStatus error = FSPathMakeRef((const UInt8 *)[replacementDirectory fileSystemRepresentation], &ref, NULL);
        Check(error == noErr, @"the replacement library has a valid native directory reference");
        // Both libraries use this disposable bundle cache. Finish the original
        // journal before the replacement constructor opens its journal.
        [library flushAllNoteChanges]; [library closeJournal];
        NotationController *replacementLibrary = [[[NotationController alloc] initWithDirectoryRef:&ref error:&error] autorelease];
        Check(replacementLibrary != nil && error == noErr, @"the replacement library opens");
        [app setLibrary:replacementLibrary];
        NoteObject *replacementNote = MakeNote(replacementLibrary, @"Replacement note", @"replacement source");
        for (AppController *browser in controllers) {
            [browser searchForString:@""]; [browser revealNote:replacementNote options:0];
            Check([browser sharedNotationController] == replacementLibrary,
                @"library replacement retains one shared library for every existing browser");
        }
        [self nv_kingsburyCheckHidden:controllers];
        [prefsController setShowNotesList:YES sender:nil];
        Check(fabs([self notesListHeight] - [heights[0] doubleValue]) < 1,
            @"library replacement preserves the browser's independent list height");
        Check([replacementLibrary totalNoteCount] == 1, @"visibility callbacks do not create notes during library replacement");
        [replacementLibrary flushAllNoteChanges]; [replacementLibrary closeJournal];
        NSLog(@"KINGSBURY PHASE 2 PASSED: %lu checks", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
