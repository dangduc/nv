// Independent state-ownership review; included inside the disposable AppController category.
- (void)nv_reviewActivate {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ((![window isKeyWindow] || [[NVApplicationController sharedController] activeBrowser] != self) &&
           [deadline timeIntervalSinceNow] > 0) Pump();
    Check([window isKeyWindow] && [[NVApplicationController sharedController] activeBrowser] == self,
        @"the native fixture activates the intended browser");
}

- (void)nv_runTests {
    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha source") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"beta source") retain];
        [app newWindow:self]; Pump();
        AppController *peer = [[[app browserControllers] lastObject] retain];
        Check(peer != self, @"a separate browser shares the library");
        NSRect frame = [window frame]; frame.size.width = MAX(780, frame.size.width);
        [window setFrame:frame display:YES]; [[peer window] setFrame:frame display:YES];
        [self searchForString:@""]; [self revealNote:alpha options:0];
        [peer searchForString:@""]; [peer revealNote:beta options:0];
        [self focusNoteBody]; [peer focusNoteBody];
        for (NSUInteger i = 0; i < 8; i++) Pump();
        [prefsController setShowTitleInTopSection:YES sender:nil];
        [prefsController setShowTagsInTopSection:YES sender:nil];
        [prefsController setShowBodyControlsInTopSection:YES sender:nil];
        Method commitMethod = class_getInstanceMethod([AppController class], @selector(commitNoteMetadata));
        IMP originalCommit = method_getImplementation(commitMethod), mutant = NULL;
        if (getenv("NV_REVIEW_DROP_METADATA_COMMIT")) {
            mutant = imp_implementationWithBlock(^(id object) { });
            method_setImplementation(commitMethod, mutant);
        }

        // Invoke the owning browser's action while the peer's native field editor
        // contains an uncommitted value. Notification delivery visits both owners.
        for (NSUInteger kind = 0; kind < 2; kind++) {
            BOOL title = kind == 0;
            NSString *key = title ? @"noteTitleField" : @"noteTagsField";
            NSTextField *control = [peer valueForKey:key];
            [peer nv_reviewActivate];
            if (title) [peer renameNote:self]; else [peer tagNote:self];
            NSTextView *editor = (id)[control currentEditor];
            Check(editor != nil, @"the peer has its own native metadata editor");
            NSString *changed = title ? @"Beta peer pending" : @"peer-tag, retained";
            [editor insertText:changed replacementRange:NSMakeRange(0, [[editor string] length])];
            Check([peer valueForKey:@"metadataNote"] == beta, @"pending metadata retains the peer's selected note");
            Check(![(title ? titleOfNote(beta) : labelsOfNote(beta)) isEqual:changed],
                @"the input remains uncommitted before the shared preference callback");
            if (title) [self toggleTitleInTopSection:self]; else [self toggleTagsInTopSection:self];
            Check([(title ? titleOfNote(beta) : labelsOfNote(beta)) isEqual:changed],
                @"a shared hide commits the peer field to its original note");
            Check([titleOfNote(alpha) isEqual:@"Alpha"] && [labelsOfNote(alpha) length] == 0,
                @"the initiating browser's note does not receive the peer edit");
            Check([control isHidden] && [[self valueForKey:key] isHidden] && [control currentEditor] == nil &&
                [peer valueForKey:@"metadataNote"] == nil && [peer valueForKey:@"metadataControl"] == nil,
                @"both fields hide and the peer releases its metadata editing state");
            Check([[peer window] firstResponder] == [peer valueForKey:@"textView"],
                @"the peer moves focus to its own source");
            Check([self selectedNoteObject] == alpha && [peer selectedNoteObject] == beta,
                @"the notification preserves both browser selections");
            [[beta undoManager] undo]; Pump();
            Check(title ? [titleOfNote(beta) isEqual:@"Beta"] : [labelsOfNote(beta) length] == 0,
                @"the peer metadata hide is one reversible note edit");
            [[beta undoManager] redo]; Pump();
            Check([(title ? titleOfNote(beta) : labelsOfNote(beta)) isEqual:changed],
                @"redo restores the peer edit without revealing its hidden field");
            if (title) [prefsController setShowTitleInTopSection:YES sender:nil];
            else [prefsController setShowTagsInTopSection:YES sender:nil];
        }

        // Reentrant model notifications while hiding one metadata kind must not
        // finish, replace, or retarget a different metadata editor in the peer.
        [self revealNote:alpha options:0]; [peer revealNote:alpha options:0];
        [self nv_reviewActivate]; [self renameNote:self];
        NSTextView *titleEditor = (id)[noteTitleField currentEditor];
        [titleEditor insertText:@"Alpha title pending" replacementRange:NSMakeRange(0, [[titleEditor string] length])];
        [peer nv_reviewActivate]; [peer tagNote:self];
        NSTextField *peerTags = [peer valueForKey:@"noteTagsField"];
        NSTextView *pendingTagsEditor = (id)[peerTags currentEditor];
        [pendingTagsEditor insertText:@"independent-tag" replacementRange:NSMakeRange(0, [[pendingTagsEditor string] length])];
        Check([noteTitleField currentEditor] != nil && [peerTags currentEditor] != nil,
            @"two windows retain independent native metadata field editors");
        [self toggleTitleInTopSection:self];
        Check([titleOfNote(alpha) isEqual:@"Alpha title pending"], @"hiding Title commits its pending native input");
        Check([peerTags currentEditor] == pendingTagsEditor && [[pendingTagsEditor string] isEqual:@"independent-tag"] &&
            [peer valueForKey:@"metadataNote"] == alpha,
            @"title notification reentry preserves the unrelated pending peer Tags editor");
        Check([labelsOfNote(alpha) length] == 0, @"showing Tags does not prematurely commit its pending editor");
        [peer toggleTagsInTopSection:self];
        Check([labelsOfNote(alpha) isEqual:@"independent-tag"] && [titleOfNote(alpha) isEqual:@"Alpha title pending"],
            @"the second hide commits only the remaining metadata field");

        [prefsController setShowTitleInTopSection:YES sender:nil];
        [prefsController setShowTagsInTopSection:YES sender:nil];
        [self nv_reviewActivate]; [self setViewingNote:YES];
        NSDate *previewDeadline = [NSDate dateWithTimeIntervalSinceNow:8];
        while ([previewController loading] && [previewDeadline timeIntervalSinceNow] > 0) Pump();
        NSLog(@"Preview readiness: loading=%d error=%@ hidden=%d", [previewController loading], [previewController renderError], [[previewController webView] isHiddenOrHasHiddenAncestor]);
        Check(![previewController loading] && ![[previewController webView] isHiddenOrHasHiddenAncestor], @"the viewer is loaded before the focus transition");
        [self renameNote:self];
        titleEditor = (id)[noteTitleField currentEditor];
        Check(titleEditor != nil, @"the untouched Preview title has a native editor");
        [self toggleTitleInTopSection:self];
        for (NSUInteger i = 0; i < 20; i++) Pump();
        NSResponder *bodyResponder = [window firstResponder];
        NSLog(@"Preview focus: responder=%@ webView=%@ viewing=%d", bodyResponder, [previewController webView], [self isViewingNote]);
        Check([self isViewingNote] && [bodyResponder isKindOfClass:[NSView class]] &&
            [(NSView *)bodyResponder isDescendantOf:[previewController webView]],
            @"hiding a Preview title retains presentation and focuses the native viewer");
        Check([titleOfNote(alpha) isEqual:@"Alpha title pending"], @"hiding an untouched Preview title preserves its value");
        Check([[[alpha contentString] string] isEqual:@"alpha source"] && [[[beta contentString] string] isEqual:@"beta source"],
            @"metadata visibility and focus operations preserve exact source strings");
        Check([library totalNoteCount] == 2, @"visibility transitions create no implicit note");
        if (mutant) { method_setImplementation(commitMethod, originalCommit); imp_removeBlock(mutant); }
        [peer release]; [alpha release]; [beta release];
        NSLog(@"OUSTERHOUT REVIEW PASSED: %lu checks", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal]; exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
