    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *browser = self;
        Check(![browser isViewingNote] && ![browser valueForKey:@"previewController"], @"source-only browser has no viewer controller");
        NoteObject *note = MakeNote(library, @"Deletion review", @"# Source default\n\nOriginal body.");
        [browser revealNote:note options:0];
        Check(![browser valueForKey:@"previewController"], @"selecting a source note does not create a viewer");
        Check([[note sourceSyntaxIdentifier] isEqualToString:@"plain"], @"Markdown-looking source still defaults to explicit Plain Text");
        [browser selectSourceSyntax:SourceItem(@"markdown", @selector(selectSourceSyntax:))];
        Check(![browser valueForKey:@"previewController"] && ![browser isViewingNote], @"syntax selection does not allocate an unused provider");
        NSMutableArray *menus = [NSMutableArray arrayWithObjects:[NSApp mainMenu], [browser statBarMenu], nil];
        NSSet *removed = [NSSet setWithObjects:@"lockPreview:", @"shareNote:", @"openCustomPreviewFolder:", @"defaultStyle:", @"previewNoteWithMarked:", nil];
        NSUInteger viewerItems = 0, syntaxItems = 0;
        [app configureMenus]; [app configureMenus];
        for (NSUInteger index = 0; index < [menus count]; index++) {
            for (NSMenuItem *item in [[menus objectAtIndex:index] itemArray]) {
                if ([item submenu]) [menus addObject:[item submenu]];
                Check(![removed containsObject:NSStringFromSelector([item action]) ?: @""], @"live menu contains no removed workflow action");
                if ([item action] == @selector(selectPreviewMode:)) viewerItems++;
                if ([item action] == @selector(selectSourceSyntax:)) syntaxItems++;
            }
        }
        Check(viewerItems == 3 && syntaxItems == 5, @"repeated menu configuration does not duplicate viewer or syntax choices");
        LinkingEditor *editor = [browser valueForKey:@"textView"];
        [[browser window] makeKeyAndOrderFront:self]; [[browser window] makeFirstResponder:editor];
        [editor insertText:@"Undo marker.\n" replacementRange:NSMakeRange(0,0)]; [browser finishEditing];
        Check([[note undoManager] canUndo], @"source edit establishes an Undo history");
        NSString *source = [[[note contentString] string] copy];
        ChangeMode(browser, YES);
        Check(Await(^BOOL { return PreviewShows(browser, @"Undo marker."); }, 15), @"preview renders before responder-chain probe");
        NSMenuItem *undo = [[[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"] autorelease];
        id target = [NSApp targetForAction:@selector(undo:) to:nil from:undo];
        BOOL enabled = [target respondsToSelector:@selector(validateMenuItem:)] ? [target validateMenuItem:undo] : NO;
        NSLog(@"Preview Undo responder=%@ enabled=%d", [target class], enabled);
        [NSApp sendAction:@selector(undo:) to:nil from:undo]; Pump();
        Check([[[note contentString] string] isEqual:source], @"actual responder-chain Undo leaves hidden source unchanged");
        NSMenuItem *format = SourceItem(@"html", @selector(selectPreviewMode:));
        [format setTarget:app];
        [NSApp sendAction:[format action] to:[format target] from:format];
        Check([[browser selectedViewerIdentifier] isEqual:@"html"] && [[note sourceSyntaxIdentifier] isEqual:@"markdown"], @"application-routed preview menu does not change insertion syntax");
        ChangeMode(browser, NO);
        [editor undo:self]; Pump();
        Check([[[note contentString] string] isEqual:@"# Source default\n\nOriginal body."], @"source Undo remains intact after viewer commands");
        [source release];
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"CONTRARIAN MINIMAL CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
@end
