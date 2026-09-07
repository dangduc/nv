    @try {
        NSAutoreleasePool *scope = [NSAutoreleasePool new];
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        void (^activate)(AppController *) = ^(AppController *browser) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [NSApp activateIgnoringOtherApps:YES];
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [[browser window] makeKeyAndOrderFront:browser];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
            while ((![[browser window] isKeyWindow] || ![[browser window] isMainWindow] || ![NSApp isActive]) &&
                   [deadline timeIntervalSinceNow] > 0) Pump();
            NSLog(@"NATIVE READY active=%d key=%d main=%d window=%@ keyWindow=%@ mainWindow=%@",
                  [NSApp isActive], [[browser window] isKeyWindow], [[browser window] isMainWindow],
                  [browser window], [NSApp keyWindow], [NSApp mainWindow]);
            Check([NSApp isActive] && [[browser window] isKeyWindow] && [[browser window] isMainWindow] &&
                  [app activeBrowser] == browser, @"native activation supplies the actual key and main browser");
        };
        void (^commitField)(AppController *, BOOL, NSString *) = ^(AppController *browser, BOOL title, NSString *value) {
            activate(browser);
            if (title) [browser renameNote:browser]; else [browser tagNote:browser];
            NSTextField *control = [browser valueForKey:title ? @"noteTitleField" : @"noteTagsField"];
            NSTextView *editor = (id)[control currentEditor];
            Check(editor != nil, @"metadata command opens its native field editor");
            [editor insertText:value replacementRange:NSMakeRange(0, [[editor string] length])];
            [editor doCommandBySelector:@selector(insertNewline:)]; Pump();
            Check([[browser window] firstResponder] == [browser valueForKey:@"textView"],
                  @"Return commits metadata and restores body focus");
        };
        void (^dispatch)(AppController *, SEL) = ^(AppController *browser, SEL action) {
            activate(browser);
            [[browser window] makeFirstResponder:[browser valueForKey:@"textView"]];
            Check([NSApp sendAction:action to:nil from:browser], @"AppKit dispatches the history action through the responder chain");
            Pump();
        };
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"original body") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"other body") retain];
        [self revealNote:alpha options:0]; Pump();
        [[alpha undoManager] removeAllActions];
        commitField(self, YES, @"Renamed Alpha");
        commitField(self, NO, @"tag one");
        dispatch(self, @selector(undo:));
        Check([labelsOfNote(alpha) length] == 0 && [titleOfNote(alpha) isEqual:@"Renamed Alpha"],
              @"tag Undo preserves the preceding title edit");
        [self revealNote:beta options:0]; Pump();
        NVNoteEditingSession *oldSession = [app editingSessionForNote:alpha];
        Check([[[oldSession textStorage] layoutManagers] count] == 0, @"the history note has no attached editor");
        [alpha setContentString:[[[NSAttributedString alloc] initWithString:@"external body without editors"] autorelease]]; Pump();
        Check([oldSession canRedo], @"an external body snapshot preserves metadata Redo without an attached editor");

        [[self window] close]; Pump();
        Check([[app browserControllers] count] == 0, @"closing the last browser leaves the application without browsers");
        [app newWindow:self]; Pump();
        Check([[app browserControllers] count] == 1, @"New Window reopens a browser after the last one closes");
        AppController *reopened = [[app browserControllers] lastObject];
        activate(reopened);
        [reopened revealNote:alpha options:0]; Pump();
        dispatch(reopened, @selector(redo:));
        Check([labelsOfNote(alpha) isEqual:@"tag one"] && [titleOfNote(alpha) isEqual:@"Renamed Alpha"] &&
              [[[alpha contentString] string] isEqual:@"external body without editors"],
              @"the reopened browser redoes metadata and preserves the external body snapshot");
        dispatch(reopened, @selector(undo:));
        commitField(reopened, YES, @"Renamed Alpha");
        Check([oldSession canRedo], @"an unchanged title commit preserves pending metadata Redo");
        dispatch(reopened, @selector(redo:));
        Check([labelsOfNote(alpha) isEqual:@"tag one"], @"metadata Redo remains reachable after the unchanged title commit");

        NSUndoManager *oldUndo = [[alpha undoManager] retain];
        __block NSUInteger sessionDeaths = 0, targetDeaths = 0;
        void *sessionAddress = oldSession;
        void *targetAddress = [oldSession valueForKey:@"metadataUndoTarget"];
        Method sessionDealloc = class_getInstanceMethod([NVNoteEditingSession class], @selector(dealloc));
        // The target inherits dealloc, so add an override instead of replacing NSObject.dealloc.
        Class targetClass = NSClassFromString(@"NVNoteMetadataUndoTarget");
        IMP originalSession = method_getImplementation(sessionDealloc);
        IMP originalTarget = class_getMethodImplementation(targetClass, @selector(dealloc));
        IMP trackSession = imp_implementationWithBlock(^(id object) {
            if ((void *)object == sessionAddress) sessionDeaths++;
            ((void (*)(id, SEL))originalSession)(object, @selector(dealloc));
        });
        IMP trackTarget = imp_implementationWithBlock(^(id object) {
            if ((void *)object == targetAddress) targetDeaths++;
            ((void (*)(id, SEL))originalTarget)(object, @selector(dealloc));
        });
        method_setImplementation(sessionDealloc, trackSession);
        Check(class_addMethod(targetClass, @selector(dealloc), trackTarget, "v@:"), @"the lifetime probe instruments only the metadata target class");

        activate(reopened);
        [reopened renameNote:reopened];
        NSTextField *title = [reopened valueForKey:@"noteTitleField"];
        NSTextView *editor = (id)[title currentEditor];
        Check(editor != nil, @"the replacement fixture has an active title editor");
        [editor insertText:@"Committed during replacement" replacementRange:NSMakeRange(0, [[editor string] length])];
        [library flushAllNoteChanges]; [library closeJournal];
        NSString *path = [TestDirectory stringByAppendingPathComponent:@"Replacement Notes"];
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
        FSRef ref; OSStatus error = FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], &ref, NULL);
        NotationController *replacement = [[NotationController alloc] initWithDirectoryRef:&ref error:&error];
        Check(replacement != nil && error == noErr, @"the replacement library uses another temporary directory");
        [app setLibrary:replacement]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Committed during replacement"], @"library replacement commits the pending title to its original note");
        Check(![oldUndo canUndo] && ![oldUndo canRedo], @"library replacement clears both directions of the old note history");
        Check([reopened sharedNotationController] == replacement && [reopened selectedNoteObject] == nil &&
              ![title isEnabled] && [[title stringValue] length] == 0,
              @"the browser switches to the empty replacement library and clears its metadata header");
        [alpha release]; [beta release];
        [scope drain];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
        while ((!sessionDeaths || !targetDeaths) && [deadline timeIntervalSinceNow] > 0) {
            NSAutoreleasePool *pool = [NSAutoreleasePool new]; Pump(); [pool drain];
        }
        NSLog(@"R2 OWNERSHIP sessionDeaths=%lu targetDeaths=%lu oldUndo=%d oldRedo=%d",
              (unsigned long)sessionDeaths, (unsigned long)targetDeaths, [oldUndo canUndo], [oldUndo canRedo]);
        Check(sessionDeaths == 1 && targetDeaths == 1, @"normal library replacement releases the old session and its borrowed-session undo target");
        method_setImplementation(sessionDealloc, originalSession);
        method_setImplementation(class_getInstanceMethod(targetClass, @selector(dealloc)), originalTarget);
        imp_removeBlock(trackSession); imp_removeBlock(trackTarget);
        [oldUndo release];
        NoteObject *fresh = MakeNote(replacement, @"Fresh", @"fresh body");
        [reopened revealNote:fresh options:0]; Pump();
        commitField(reopened, YES, @"Fresh renamed");
        dispatch(reopened, @selector(undo:));
        Check([titleOfNote(fresh) isEqual:@"Fresh"] && [[[fresh contentString] string] isEqual:@"fresh body"],
              @"the replacement library owns a separate working metadata history");
        [replacement flushAllNoteChanges]; [replacement closeJournal]; [replacement release];
        NSLog(@"OUSTERHOUT ROUND2 PASSED (%lu checks)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        _exit(0);
    } @catch(NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
@end
