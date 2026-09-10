    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSString *source = @"* TODO Preview boundary\n\nThe *same source* remains editable.\n\n- [ ] Keep source\n";
        NoteObject *note = MakeNote(library, @"Preview boundary review", source);
        [self revealNote:note options:0];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *editor = [self valueForKey:@"textView"], *peerEditor = [peer valueForKey:@"textView"];
        NSTextStorage *storage = [editor textStorage];
        Check(storage == [peerEditor textStorage], @"both browser editors retain one shared source storage");
        Check([[note sourceSyntaxIdentifier] isEqual:@"plain"], @"preview review starts with Plain Text source syntax");
        [editor setSelectedRange:NSMakeRange(10, 4)];
        NSRange selection = [editor selectedRange];
        [[note undoManager] removeAllActions];
        CFAbsoluteTime modified = modifiedDateOfNote(note);
        NSUInteger generation = [[app editingSessionForNote:note] sourceGeneration];
        NSMutableArray *menuItems = [NSMutableArray array];
        CollectViewerItems([NSApp mainMenu], menuItems);
        NSPopUpButton *popup = [self valueForKey:@"viewerTypeControl"];
        NSSet *expected = [NSSet setWithArray:@[@"markdown", @"textile", @"html", @"org"]];
        NSMutableSet *menuChoices = [NSMutableSet set], *popupChoices = [NSMutableSet set];
        for (NSMenuItem *item in menuItems) [menuChoices addObject:[item representedObject]];
        for (NSMenuItem *item in [popup itemArray]) [popupChoices addObject:[item representedObject]];
        Check([menuChoices isEqual:expected] && [popupChoices isEqual:expected], @"menus and popup expose exactly the four renderer choices");
        for (NSString *identifier in @[@"markdown", @"textile", @"html", @"org"]) {
            [self selectPreviewMode:ViewerItem(identifier)];
            PreviewController *preview = [self valueForKey:@"previewController"];
            Check(Await(^BOOL { return Ready(preview, identifier); }, 20), @"each advertised viewer renders through the actual provider");
            Check([[[popup selectedItem] representedObject] isEqual:identifier], @"the popup follows the selected viewer");
            NSUInteger checked = 0;
            for (NSMenuItem *item in menuItems) {
                Check([self validateMenuItem:item], @"each viewer menu item remains enabled");
                if ([item state] == NSControlStateValueOn) {
                    checked++;
                    Check([[item representedObject] isEqual:identifier], @"the checked viewer menu item matches the provider");
                }
            }
            Check(checked == 1, @"exactly one viewer menu choice is checked");
        }
        PreviewController *preview = [self valueForKey:@"previewController"];
        Check([[DOM([preview webView], @"document.querySelector('h1').textContent") description] containsString:@"TODO Preview boundary"], @"the real Org helper produces the visible heading");
        Check(![peer isViewingNote] && [peerEditor textStorage] == storage && [[peerEditor string] isEqual:source], @"viewer selection leaves the peer in Source with the same storage");
        Check([[note sourceSyntaxIdentifier] isEqual:@"plain"] && [[[preview snapshot] contentType] isEqual:@"plain"], @"Org preview does not require or set Org source metadata");
        NSDictionary *windowState = [[self browserWindowState] copy];
        [self selectPreviewMode:ViewerItem(@"html")];
        Check(Await(^BOOL { return Ready(preview, @"html"); }, 20), @"HTML becomes visible before window state restoration");
        [self setViewingNote:NO];
        [self restoreBrowserWindowState:windowState]; [windowState release];
        Check(Await(^BOOL { return [self isViewingNote] && Ready([self valueForKey:@"previewController"], @"org"); }, 20), @"browser state restores Org after another viewer and Source mode");
        preview = [self valueForKey:@"previewController"];

        NSString *helper = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"nv-org-preview"];
        NSString *backup = [helper stringByAppendingString:@".review-original"];
        Check([helper hasPrefix:[TestDirectory stringByAppendingString:@"/"]], @"helper mutation is restricted to the disposable app copy");
        Check([[NSFileManager defaultManager] moveItemAtPath:helper toPath:backup error:NULL], @"temporarily remove only the copied helper");
        for (NSNumber *code in @[@(NVMarkupHelperUnavailable), @(NVMarkupHelperFailed)]) {
            if ([code integerValue] == NVMarkupHelperFailed) {
                NSString *failed = @"#!/bin/sh\nprintf 'review converter failure\\n' >&2\nexit 27\n";
                Check([failed writeToFile:helper atomically:YES encoding:NSUTF8StringEncoding error:NULL] &&
                    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:helper error:NULL], @"install a controlled failing helper in the disposable copy");
            }
            [self selectPreviewMode:ViewerItem(@"org")];
            Check(Await(^BOOL { return ![preview loading] && [preview renderError]; }, 10), @"a real helper failure terminates the provider request");
            Check([[[preview renderError] domain] isEqual:NVMarkupRendererErrorDomain] && [[preview renderError] code] == [code integerValue], @"the provider preserves the renderer failure category");
            NSTextField *status = [preview valueForKey:@"statusField"];
            Check(![status isHidden] && [[status stringValue] length] > 0 && [[preview webView] isHidden], @"the error message is visible and the previous web document is hidden");
            Check([preview renderedHTML] == nil, @"a failed request cannot retain the previous export document");
            if ([code integerValue] == NVMarkupHelperFailed)
                Check([[status stringValue] containsString:@"status 27"] && [[status stringValue] containsString:@"review converter failure"], @"helper status and diagnostic reach the user-visible error");
            for (NSString *selector in @[@"savePreview:", @"printPreview:", @"performFindPanelAction:"]) {
                NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:selector action:NSSelectorFromString(selector) keyEquivalent:@""] autorelease];
                [item setTag:NSFindPanelActionShowFindPanel];
                Check(![self validateMenuItem:item], @"export, print and viewer Find disable while the helper is unavailable");
            }
            Check([[note sourceSyntaxIdentifier] isEqual:@"plain"] && [[storage string] isEqual:source] && [[[note contentString] string] isEqual:source], @"helper failure leaves live source and model source unchanged");
            Check(![peer isViewingNote] && [peerEditor textStorage] == storage && ![peerEditor isHiddenOrHasHiddenAncestor], @"helper failure leaves the peer editor visible and attached");
            [self setViewingNote:NO];
            Check(![self isViewingNote] && NSEqualRanges([editor selectedRange], selection) && [[editor string] isEqual:source], @"returning from a failed preview restores the source and caret");
        }
        Check([[NSFileManager defaultManager] removeItemAtPath:helper error:NULL] &&
            [[NSFileManager defaultManager] moveItemAtPath:backup toPath:helper error:NULL], @"restore the original helper in the disposable copy");
        [self selectPreviewMode:ViewerItem(@"org")];
        Check(Await(^BOOL { return Ready(preview, @"org"); }, 20), @"retry after restoring the helper clears the error and renders Org");
        Check([[DOM([preview webView], @"document.querySelector('h1').textContent") description] containsString:@"TODO Preview boundary"], @"the recovered preview displays the real Org document");
        Check([[app editingSessionForNote:note] sourceGeneration] == generation && modifiedDateOfNote(note) == modified && ![[note undoManager] canUndo], @"all viewer transitions and failures preserve source generation, dates and Undo");
        NSLog(@"ORG PREVIEW OUSTERHOUT ROUND 1 PASSED (%lu checks)", (unsigned long)Checks);
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
