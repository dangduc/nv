        {
            NoteObject *history = [MakeNote(library, @"Metadata history", @"body") retain];
            [self revealNote:history options:0]; [peer revealNote:history options:0]; Pump();
            [browserWindow makeKeyAndOrderFront:self]; [browserWindow makeFirstResponder:textView];
            [[history undoManager] removeAllActions];
            [textView insertText:@" before" replacementRange:NSMakeRange(4, 0)]; Pump();
            [self renameNote:self];
            NSTextView *editor = (id)[noteTitleField currentEditor];
            [editor insertText:@"History renamed" replacementRange:NSMakeRange(0, [[editor string] length])];
            [self control:noteTitleField textView:editor doCommandBySelector:@selector(insertNewline:)]; Pump();
            [textView insertText:@" after" replacementRange:NSMakeRange([[textView string] length], 0)]; Pump();
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([titleOfNote(history) isEqual:@"History renamed"] && [[textView string] isEqual:@"body before"],
                @"Undo removes the body edit after a rename first");
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([titleOfNote(history) isEqual:@"Metadata history"] && [[textView string] isEqual:@"body before"],
                @"Undo restores the title before the earlier body edit");
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([[textView string] isEqual:@"body"], @"Undo then removes the body edit before the rename");
            [NSApp sendAction:@selector(redo:) to:nil from:redoItem]; Pump();
            Check([[textView string] isEqual:@"body before"] && [titleOfNote(history) isEqual:@"Metadata history"],
                @"Redo restores the earlier body edit first");
            [NSApp sendAction:@selector(redo:) to:nil from:redoItem]; Pump();
            Check([titleOfNote(history) isEqual:@"History renamed"] && [[textView string] isEqual:@"body before"],
                @"Redo restores the rename in edit order");
            [NSApp sendAction:@selector(redo:) to:nil from:redoItem]; Pump();
            Check([[textView string] isEqual:@"body before after"], @"Redo restores the later body edit last");

            // An external body snapshot clears unsafe body history only.
            [history setContentString:[[[NSAttributedString alloc] initWithString:@"external body"] autorelease]]; Pump();
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([titleOfNote(history) isEqual:@"Metadata history"] && [[textView string] isEqual:@"external body"],
                @"metadata Undo survives an external body update without replacing its text");
            [NSApp sendAction:@selector(redo:) to:nil from:redoItem]; Pump();
            Check([titleOfNote(history) isEqual:@"History renamed"] && [[textView string] isEqual:@"external body"],
                @"metadata Redo retains the external body text");

            // Pending composition in another browser precedes the metadata commit.
            LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
            [peerEditor setMarkedText:@" draft" selectedRange:NSMakeRange(6, 0)
                replacementRange:NSMakeRange([[peerEditor string] length], 0)];
            [self tagNote:self];
            editor = (id)[noteTagsField currentEditor];
            [editor insertText:@"ordered" replacementRange:NSMakeRange(0, [[editor string] length])];
            [self control:noteTagsField textView:editor doCommandBySelector:@selector(insertNewline:)]; Pump();
            Check(![peerEditor hasMarkedText] && [[textView string] isEqual:@"external body draft"],
                @"metadata commit finishes pending body composition in the peer browser");
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([labelsOfNote(history) length] == 0 && [[textView string] isEqual:@"external body draft"],
                @"Undo removes metadata before the composition that preceded it");
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([[textView string] isEqual:@"external body"], @"the next Undo removes the earlier peer composition");

            // Deletion remains library history; restoring the note retains its metadata history.
            [[library undoManager] removeAllActions];
            [library removeNote:history]; Pump();
            Check(![[library allNotes] containsObject:history], @"the history note leaves the library on deletion");
            [app setNote:history metadataValue:@"deleted edit" isTitle:YES];
            Check([titleOfNote(history) isEqual:@"History renamed"], @"metadata commits ignore a deleted note");
            [[library undoManager] undo]; Pump();
            [self revealNote:history options:0]; [browserWindow makeFirstResponder:textView]; Pump();
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([[library allNotes] containsObject:history] && [titleOfNote(history) isEqual:@"Metadata history"] &&
                [[textView string] isEqual:@"external body"], @"restoring a deleted note retains its earlier metadata Undo");
            [NSApp sendAction:@selector(redo:) to:nil from:redoItem]; Pump();

            __block NSUInteger browserDeaths = 0, editorDeaths = 0;
            __block void *closedBrowser = NULL, *closedEditor = NULL;
            Method browserDealloc = class_getInstanceMethod([AppController class], @selector(dealloc));
            Method editorDealloc = class_getInstanceMethod([LinkingEditor class], @selector(dealloc));
            IMP originalBrowserDealloc = method_getImplementation(browserDealloc);
            IMP originalEditorDealloc = method_getImplementation(editorDealloc);
            IMP trackBrowser = imp_implementationWithBlock(^(id object) {
                if ((void *)object == closedBrowser) browserDeaths++;
                ((void (*)(id, SEL))originalBrowserDealloc)(object, @selector(dealloc));
            });
            IMP trackEditor = imp_implementationWithBlock(^(id object) {
                if ((void *)object == closedEditor) editorDeaths++;
                ((void (*)(id, SEL))originalEditorDealloc)(object, @selector(dealloc));
            });
            method_setImplementation(browserDealloc, trackBrowser);
            method_setImplementation(editorDealloc, trackEditor);
            NSAutoreleasePool *closingPool = [NSAutoreleasePool new];
            [app newWindow:self]; Pump();
            AppController *closing = [[app browserControllers] lastObject];
            closedBrowser = closing; closedEditor = [closing valueForKey:@"textView"];
            [closing revealNote:history options:0]; Pump();
            [closing renameNote:self];
            NSTextField *closingTitle = [closing valueForKey:@"noteTitleField"];
            editor = (id)[closingTitle currentEditor];
            [editor insertText:@"Committed on close" replacementRange:NSMakeRange(0, [[editor string] length])];
            [[closing window] close]; Pump();
            Check([titleOfNote(history) isEqual:@"Committed on close"], @"closing a browser commits its pending metadata");
            [closingPool drain];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
            while ((!browserDeaths || !editorDeaths) && [deadline timeIntervalSinceNow] > 0) {
                NSAutoreleasePool *drain = [NSAutoreleasePool new]; Pump(); [drain drain];
            }
            Check(browserDeaths == 1 && editorDeaths == 1, @"metadata history does not retain a closed browser or its editor");
            method_setImplementation(browserDealloc, originalBrowserDealloc);
            method_setImplementation(editorDealloc, originalEditorDealloc);
            imp_removeBlock(trackBrowser); imp_removeBlock(trackEditor);

            [self revealNote:beta options:0]; [peer revealNote:alpha options:0]; Pump();
            [app newWindow:self]; Pump();
            AppController *reopened = [[app browserControllers] lastObject];
            [reopened revealNote:history options:0];
            [[reopened window] makeFirstResponder:[reopened valueForKey:@"textView"]]; Pump();
            [NSApp sendAction:@selector(undo:) to:nil from:undoItem]; Pump();
            Check([titleOfNote(history) isEqual:@"History renamed"], @"a reopened browser can Undo metadata from the closed browser");
            [NSApp sendAction:@selector(redo:) to:nil from:redoItem]; Pump();
            Check([titleOfNote(history) isEqual:@"Committed on close"], @"a reopened browser can Redo metadata from the closed browser");
            [[reopened window] close]; Pump();
            [browserWindow makeKeyAndOrderFront:self]; [browserWindow makeFirstResponder:textView]; Pump();
            [history release];
        }
        for (NSNumber *explicitClose in @[@YES, @NO]) {
            NSAutoreleasePool *lifetimePool = [NSAutoreleasePool new];
            NoteObject *lifetimeNote = [MakeNote(library, @"Metadata lifetime", @"body") retain];
            NVNoteEditingSession *lifetimeSession = [app editingSessionForNote:lifetimeNote];
            NSUndoManager *lifetimeUndo = [[lifetimeNote undoManager] retain];
            [app setNote:lifetimeNote metadataValue:@"Lifetime renamed" isTitle:YES];
            [[lifetimeSession textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:@" edit"] autorelease]];
            [lifetimeSession commitTextChanges];
            Check([lifetimeUndo canUndo], @"lifetime control contains body and metadata history");
            [self revealNote:beta options:0]; Pump();
            [library removeNote:lifetimeNote]; Pump();
            [[library undoManager] removeAllActions];

            __block NSUInteger noteDeaths = 0, sessionDeaths = 0;
            void *noteAddress = lifetimeNote, *sessionAddress = lifetimeSession;
            Method noteDealloc = class_getInstanceMethod([NoteObject class], @selector(dealloc));
            Method sessionDealloc = class_getInstanceMethod([NVNoteEditingSession class], @selector(dealloc));
            IMP originalNoteDealloc = method_getImplementation(noteDealloc);
            IMP originalSessionDealloc = method_getImplementation(sessionDealloc);
            IMP trackNote = imp_implementationWithBlock(^(id object) {
                if ((void *)object == noteAddress) noteDeaths++;
                ((void (*)(id, SEL))originalNoteDealloc)(object, @selector(dealloc));
            });
            IMP trackSession = imp_implementationWithBlock(^(id object) {
                if ((void *)object == sessionAddress) sessionDeaths++;
                ((void (*)(id, SEL))originalSessionDealloc)(object, @selector(dealloc));
            });
            method_setImplementation(noteDealloc, trackNote);
            method_setImplementation(sessionDealloc, trackSession);
            if ([explicitClose boolValue]) [lifetimeSession close];
            NSMutableDictionary *sessions = [app valueForKey:@"editingSessions"];
            [sessions removeObjectsForKeys:[sessions allKeysForObject:lifetimeSession]];
            [lifetimeNote release]; [lifetimePool drain];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
            while ((!noteDeaths || !sessionDeaths) && [deadline timeIntervalSinceNow] > 0) {
                NSAutoreleasePool *drain = [NSAutoreleasePool new]; Pump(); [drain drain];
            }
            Check(noteDeaths == 1 && sessionDeaths == 1,
                [explicitClose boolValue] ? @"session close releases its note and metadata history" :
                    @"session deallocation releases its note without an explicit close");
            Check(![lifetimeUndo canUndo] && ![lifetimeUndo canRedo], @"session teardown leaves no body or metadata undo targets");
            method_setImplementation(noteDealloc, originalNoteDealloc);
            method_setImplementation(sessionDealloc, originalSessionDealloc);
            imp_removeBlock(trackNote); imp_removeBlock(trackSession);
            [lifetimeUndo release];
        }
