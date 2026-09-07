- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *alpha = [MakeNote(library, @"Alpha", @"alpha body") retain];
        NoteObject *beta = [MakeNote(library, @"Beta", @"beta body") retain];
        NSWindow *browserWindow = [self window];
        NSSplitView *split = [self valueForKey:@"splitView"];
        Check([split isKindOfClass:[NSSplitView class]] && ![split isVertical], @"browser uses a native horizontal divider");
        Check([field isKindOfClass:[NSSearchField class]] && [field isEditable], @"search is an editable native search control");
        Check([[browserWindow toolbar] allowsUserCustomization], @"toolbar supports standard customization");
        NSMenu *noteMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
        NSMenuItem *newNoteItem = [noteMenu itemAtIndex:[noteMenu indexOfItemWithTarget:app andAction:@selector(newNote:)]];
        Check([[newNoteItem keyEquivalent] isEqual:@"n"], @"Note menu exposes Command-N for New Note");
        if (@available(macOS 11.0, *)) {
            Check([browserWindow toolbarStyle] == NSWindowToolbarStyleUnifiedCompact, @"window uses the compact unified toolbar");
            Check([dualFieldItem isKindOfClass:[NSSearchToolbarItem class]], @"search uses the native adaptive toolbar item");
        }
        [self searchForString:@"al"]; Pump();
        Check([[field stringValue] isEqual:@"al"] && [self selectedNoteObject] == alpha,
            @"search suggests a matching note without replacing the query");
        Check([field currentEditor] != nil, @"search command focuses the native field editor");
        NSTextView *searchEditor = (id)[field currentEditor];
        [searchEditor setMarkedText:@"beta" selectedRange:NSMakeRange(4, 0) replacementRange:NSMakeRange(0, [[searchEditor string] length])];
        Check([searchEditor hasMarkedText] && [[[self browserSession] searchString] isEqual:@"al"],
            @"uncommitted search composition does not replace the active query");
        [searchEditor unmarkText]; [browserWindow makeFirstResponder:notesTableView]; Pump();
        Check([[[self browserSession] searchString] isEqual:@"beta"], @"leaving search commits composed query text");
        [self searchForString:@"al"]; Pump();
        [self revealNote:alpha options:0]; Pump();
        Check([[field stringValue] isEqual:@"al"] && [[noteTitleField stringValue] isEqual:@"Alpha"],
            @"selection keeps the query and displays a separate title");
        NSSearchFieldCell *searchCell = (id)[field cell];
        [[searchCell cancelButtonCell] performClick:field]; Pump();
        Check([[field stringValue] length] == 0 && [[[self browserSession] searchString] length] == 0 && [library totalNoteCount] == 2,
            @"native clear button clears the query without creating a note");
        [self searchForString:@"No matching note"]; Pump();
        Check([library totalNoteCount] == 2 && ![createNoteButton isHidden], @"typing an unmatched query only offers creation");
        [createNoteButton performClick:self]; Pump();
        Check([library totalNoteCount] == 3 && [titleOfNote([self selectedNoteObject]) isEqual:@"No matching note"],
            @"explicit Create action uses the query as the title");
        NoteObject *created = [[self selectedNoteObject] retain];
        [self newNote:self]; Pump();
        Check([library totalNoteCount] == 4 && [noteTitleField currentEditor] != nil,
            @"New Note creates a blank note and focuses its title");
        Check([[[[self selectedNoteObject] contentString] string] length] == 0, @"New Note never copies the previous body");
        [self searchForString:@""]; [self revealNote:alpha options:0]; Pump();
        [[library undoManager] removeAllActions];
        [self renameNote:self];
        NSTextView *titleEditor = (id)[noteTitleField currentEditor];
        [titleEditor insertText:@"Renamed Alpha" replacementRange:NSMakeRange(0, [[titleEditor string] length])];
        [browserWindow makeFirstResponder:textView]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Renamed Alpha"] && [[field stringValue] isEqual:@""],
            @"title edits commit through the model and leave search unchanged");
        [[library undoManager] undo]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Alpha"], @"metadata undo restores the original title");
        [[library undoManager] redo]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Renamed Alpha"], @"metadata redo restores the edited title");
        Check([(NSView *)wordCounter window] == browserWindow, @"word count remains attached to its browser header");
        [self tagNote:self];
        NSTextView *tagsEditor = (id)[noteTagsField currentEditor];
        [tagsEditor insertText:@"work, ideas" replacementRange:NSMakeRange(0, [[tagsEditor string] length])];
        [browserWindow makeFirstResponder:textView]; Pump();
        Check([labelsOfNote(alpha) containsString:@"work"] && [labelsOfNote(alpha) containsString:@"ideas"],
            @"tags edited in the header reach the note model");
        [self renameNote:self];
        titleEditor = (id)[noteTitleField currentEditor];
        [titleEditor insertText:@"Discard this" replacementRange:NSMakeRange(0, [[titleEditor string] length])];
        [self control:noteTitleField textView:titleEditor doCommandBySelector:@selector(cancelOperation:)]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Renamed Alpha"] && [[noteTitleField stringValue] isEqual:titleOfNote(alpha)],
            @"Escape cancels a title edit without renaming");
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:alpha options:0]; Pump();
        [alpha setLabelString:@"updated elsewhere"]; Pump();
        Check([[[peer valueForKey:@"noteTagsField"] stringValue] isEqual:@"updated elsewhere"],
            @"peer metadata refreshes after a model change");
        [browserWindow makeKeyAndOrderFront:self];
        [self renameNote:self];
        titleEditor = (id)[noteTitleField currentEditor];
        [titleEditor insertText:@"Commit to Alpha" replacementRange:NSMakeRange(0, [[titleEditor string] length])];
        [self revealNote:beta options:0]; Pump();
        Check([titleOfNote(alpha) isEqual:@"Commit to Alpha"] && [titleOfNote(beta) isEqual:@"Beta"],
            @"changing selection commits metadata to its original note");
        [self searchForString:@"beta"]; Pump();
        [self setDualFieldIsVisible:NO];
        [self bringFocusToControlField:self]; Pump();
        Check([self dualFieldIsVisible] && [field currentEditor] != nil && [[field stringValue] isEqual:@"beta"],
            @"Search command restores a hidden toolbar without losing the query");
        CGFloat peerHeight = [peer notesListHeight];
        [self setNotesListHeight:110]; Pump();
        Check(fabs([self notesListHeight] - 110) < 2 && fabs([peer notesListHeight] - peerHeight) < 1,
            @"native divider positions are independent between windows");
        NSDictionary *state = [self browserWindowState];
        [self setNotesListHeight:190]; [self restoreBrowserWindowState:state]; Pump();
        Check(fabs([self notesListHeight] - 110) < 2, @"native divider height survives state restoration");
        if (getenv("NV_UI_FULL_SCREEN")) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [NSApp activateIgnoringOtherApps:YES];
            [browserWindow makeKeyAndOrderFront:self];
            for (NSUInteger i = 0; i < 10; i++) Pump();
            Check([NSApp isActive], @"full-screen test requires the foreground app in an unlocked desktop session");
            [self switchFullScreen:self];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while (![self isInFullScreen] && [deadline timeIntervalSinceNow] > 0) Pump();
            for (NSUInteger i = 0; i < 30; i++) Pump();
            Check([self isInFullScreen] && ![split isVertical], @"native full screen retains the stacked layout");
            [self switchFullScreen:self];
            deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while ([self isInFullScreen] && [deadline timeIntervalSinceNow] > 0) Pump();
            for (NSUInteger i = 0; i < 30; i++) Pump();
            Check(![self isInFullScreen] && ![split isVertical], @"leaving full screen retains the stacked layout");
        }
        NSMutableDictionary *legacy = [[state mutableCopy] autorelease];
        legacy[@"horizontalLayout"] = @YES; legacy[@"divider"] = @1000;
        [self restoreBrowserWindowState:legacy]; Pump();
        Check(![split isVertical] && [self notesListHeight] < 1000, @"legacy side-by-side geometry migrates to the vertical stack");
        for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(480, 320)], [NSValue valueWithSize:NSMakeSize(800, 650)]]) {
            [browserWindow setContentSize:[size sizeValue]]; Pump();
            [split layoutSubtreeIfNeeded];
            Check(fabs(NSWidth([[browserWindow contentView] bounds]) - [size sizeValue].width) < 2,
                @"window retains its requested width after native layout");
            NSRect listFrame = [notesSubview convertRect:[notesSubview bounds] toView:[browserWindow contentView]];
            NSRect bodyFrame = [textScrollView convertRect:[textScrollView bounds] toView:[browserWindow contentView]];
            Check(NSMinY(listFrame) >= NSMaxY(bodyFrame) && NSHeight(bodyFrame) >= 100,
                @"small and large windows keep the note list above a usable editor");
            Check(fabs(NSWidth(listFrame) - NSWidth([[browserWindow contentView] bounds])) < 2 &&
                fabs(NSWidth(bodyFrame) - NSWidth(listFrame)) < 2,
                @"both panes fill the window width after resizing");
        }
        if (@available(macOS 10.14, *)) {
            [self setSystemColorScheme:self];
            for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                [browserWindow setAppearance:[NSAppearance appearanceNamed:appearance]]; Pump();
                [self browserAppearanceChanged];
                CGFloat brightness = [[[self backgrndColor] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent];
                Check([appearance isEqual:NSAppearanceNameAqua] ? brightness > .8 : brightness < .3,
                    @"system editor background follows the window appearance");
                NSRange renderedRange = NSMakeRange(0, [[textView string] length]);
                NSDictionary *rendered = [textView layoutManager:[textView layoutManager] shouldUseTemporaryAttributes:@{}
                    forDrawingToScreen:YES atCharacterIndex:0 effectiveRange:&renderedRange];
                CGFloat foreground = [[[rendered objectForKey:NSForegroundColorAttributeName] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent];
                Check(fabs(foreground - brightness) > .5, @"displayed body text contrasts with the editor background");
                const char *destination = getenv("NV_UI_ARTIFACTS");
                if (destination) {
                    NSView *frame = [[browserWindow contentView] superview];
                    NSBitmapImageRep *bitmap = [frame bitmapImageRepForCachingDisplayInRect:[frame bounds]];
                    [frame cacheDisplayInRect:[frame bounds] toBitmapImageRep:bitmap];
                    NSString *path = [[NSString stringWithUTF8String:destination] stringByAppendingPathComponent:[appearance stringByAppendingString:@".png"]];
                    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
                }
            }
            [self setUserColorScheme:self];
            NSColor *custom = [[self backgrndColor] retain];
            [browserWindow setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]]; Pump();
            Check([[self backgrndColor] isEqual:custom], @"explicit editor colors survive appearance changes");
            [custom release];
        }
        [created release]; [alpha release]; [beta release];
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"NATIVE UI TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
