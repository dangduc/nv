    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=[app library];
        NoteObject *alpha=[MakeNote(library,@"Alpha",@"alpha body") retain];
        [self revealNote:alpha options:0]; Pump();
        [[library undoManager] removeAllActions]; [[alpha undoManager] removeAllActions];
        [self renameNote:self];
        NSTextField *title=[self valueForKey:@"noteTitleField"];
        NSTextView *editor=(id)[title currentEditor];
        Check(editor!=nil,@"rename focuses a native field editor");
        [editor insertText:@"Renamed Alpha" replacementRange:NSMakeRange(0,[[editor string] length])];
        [self control:title textView:editor doCommandBySelector:@selector(insertNewline:)]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Renamed Alpha"],@"Return commits the title");
        Check([[self window] firstResponder]==textView,@"Return moves focus to the body");
        NSLog(@"UNDO BEFORE library=%d note=%d windowIsLibrary=%d windowIsNote=%d target=%@",
            [[library undoManager] canUndo],[[alpha undoManager] canUndo],
            [[self window] undoManager]==[library undoManager],[[self window] undoManager]==[alpha undoManager],
            [NSApp targetForAction:@selector(undo:)]);
        BOOL dispatched=[NSApp sendAction:@selector(undo:) to:nil from:self]; Pump();
        NSLog(@"UNDO RESULT sent=%d title=%@ expected=Alpha",dispatched,titleOfNote(alpha));
        BOOL undoWorks=[titleOfNote(alpha) isEqual:@"Alpha"];
        // Demonstrate that the missing effect is routing, not missing registration.
        if (!undoWorks) { [[library undoManager] undo]; Pump(); }
        Check([titleOfNote(alpha) isEqual:@"Alpha"],@"library undo directly restores the title");

        __block NSUInteger browserDeaths=0, editorDeaths=0;
        IMP oldBrowser=class_getMethodImplementation([AppController class],@selector(dealloc));
        IMP oldEditor=class_getMethodImplementation([LinkingEditor class],@selector(dealloc));
        method_setImplementation(class_getInstanceMethod([AppController class],@selector(dealloc)),imp_implementationWithBlock(^(id object) {
            browserDeaths++; ((void(*)(id,SEL))oldBrowser)(object,@selector(dealloc));
        }));
        method_setImplementation(class_getInstanceMethod([LinkingEditor class],@selector(dealloc)),imp_implementationWithBlock(^(id object) {
            editorDeaths++; ((void(*)(id,SEL))oldEditor)(object,@selector(dealloc));
        }));
        NSAutoreleasePool *peerPool=[NSAutoreleasePool new];
        [app newWindow:self]; Pump();
        AppController *peer=[[app browserControllers] lastObject];
        [peer revealNote:alpha options:0]; Pump();
        [peer renameNote:self];
        title=[peer valueForKey:@"noteTitleField"]; editor=(id)[title currentEditor];
        [editor insertText:@"Committed on close" replacementRange:NSMakeRange(0,[[editor string] length])];
        [[peer window] close]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Committed on close"],@"closing a browser commits its pending metadata");
        [[self window] makeKeyAndOrderFront:self]; Pump();
        [[library undoManager] undo]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Alpha"],@"metadata undo target survives the editing browser closing");
        [peerPool drain]; Pump();
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];
        while (editorDeaths<1 && [deadline timeIntervalSinceNow]>0) {
            NSAutoreleasePool *drain=[NSAutoreleasePool new]; Pump(); [drain drain];
        }
        NSLog(@"METADATA LIFETIME browserDeaths=%lu editorDeaths=%lu",(unsigned long)browserDeaths,(unsigned long)editorDeaths);
        Check(browserDeaths==1 && editorDeaths==1,@"pending metadata and its undo entry do not retain the closed browser/editor");

        [self renameNote:self];
        title=[self valueForKey:@"noteTitleField"]; editor=(id)[title currentEditor];
        // A peer or external sync changes the model while the untouched local header is editing.
        [alpha setTitleString:@"External Alpha"]; Pump();
        [[self window] makeFirstResponder:textView]; Pump();
        Check([titleOfNote(alpha) isEqual:@"External Alpha"],@"an untouched active title field does not roll back an external rename");
        Check([[title stringValue] isEqual:@"External Alpha"],@"the metadata header refreshes after editing ends");
        NSLog(@"OUSTERHOUT ROUND1 RESULT routedRenameUndo=%d checks=%lu",undoWorks,(unsigned long)Checks);
        [alpha release]; [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        _exit(0);
    } @catch(NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
@end
