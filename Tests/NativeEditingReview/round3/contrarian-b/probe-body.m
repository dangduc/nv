    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        AppController *first = self;
        LinkingEditor *firstEditor = [first valueForKey:@"textView"];

        NoteObject *firstNote = MakeNote(library, @"First Find target", @"first-window-only needle");
        [first revealNote:firstNote options:0]; Pump();
        [[first window] makeKeyAndOrderFront:self];
        [[first window] makeFirstResponder:firstEditor];

        [app newWindow:self]; Pump();
        AppController *second = [[app browserControllers] lastObject];
        LinkingEditor *secondEditor = [second valueForKey:@"textView"];
        NoteObject *secondNote = MakeNote(library, @"Second Find target", @"second-window-only needle");
        [second revealNote:secondNote options:0]; Pump();
        [[second window] makeKeyAndOrderFront:self];
        [[second window] makeFirstResponder:secondEditor]; Pump();

        Check([app activeBrowser] == second && [[second window] firstResponder] == secondEditor,
              @"second browser source editor is active first responder");

        __block NSMenuItem *findItem = nil;
        __block void (^WalkMenu)(NSMenu *);
        WalkMenu = [^(NSMenu *menu) {
            for (NSMenuItem *item in [menu itemArray]) {
                if ([item action] == @selector(performFindPanelAction:) && [item tag] == 1) {
                    findItem = item;
                    return;
                }
                if ([item submenu]) WalkMenu([item submenu]);
                if (findItem) return;
            }
        } copy];
        WalkMenu([NSApp mainMenu]);
        [WalkMenu release];

        Check(findItem != nil, @"main menu exposes the Find command");
        Check([findItem target] == app,
              @"legacy nib Find target is replaced by the application router");
        id (*ForwardTarget)(id, SEL) = (id (*)(id, SEL))
            [app methodForSelector:@selector(forwardTargetForSelector:)];
        Check(ForwardTarget(app, @selector(performFindPanelAction:)) == second,
              @"Find router resolves the active second browser");
        Check([NSApp targetForAction:@selector(selectAll:) to:nil from:nil] == secondEditor,
              @"ordinary native Text actions resolve through the active responder chain");

        [firstEditor hideTextFinderIfNecessary:
            [NSNotification notificationWithName:@"TextFinderShouldHide" object:first]];
        [secondEditor hideTextFinderIfNecessary:
            [NSNotification notificationWithName:@"TextFinderShouldHide" object:second]];
        Pump();
        Check(![firstEditor textFinderIsVisible] && ![secondEditor textFinderIsVisible],
              @"both source find bars begin hidden");

        [NSApp sendAction:[findItem action] to:[findItem target] from:findItem]; Pump();
        Check(![firstEditor textFinderIsVisible],
              @"Find invoked from the second window leaves the first editor untouched");
        Check([secondEditor textFinderIsVisible],
              @"Find opens the active second editor's find bar");
        id secondResponder = [[second window] firstResponder];
        id firstResponder = [[first window] firstResponder];
        Check([secondResponder window] == [second window] &&
              [firstResponder window] != [second window],
              @"Find moves focus only within the active second window");

        [secondEditor hideTextFinderIfNecessary:
            [NSNotification notificationWithName:@"TextFinderShouldHide" object:second]];
        [[second window] makeFirstResponder:secondEditor]; Pump();
        NSString *sourceBeforeComposition = [[secondEditor string] copy];
        NSTextView *reference = [[[NSTextView alloc]
            initWithFrame:NSMakeRect(0, 0, 480, 300)] autorelease];
        [reference setRichText:NO];
        [reference setImportsGraphics:NO];
        [reference setString:sourceBeforeComposition];
        [secondEditor setSelectedRange:NSMakeRange(0, 0)];
        [reference setSelectedRange:NSMakeRange(0, 0)];
        NSAttributedString *marked = [[[NSAttributedString alloc]
            initWithString:@"かな"] autorelease];
        [secondEditor setMarkedText:marked selectedRange:NSMakeRange(2, 0)
                   replacementRange:NSMakeRange(NSNotFound, 0)];
        [reference setMarkedText:marked selectedRange:NSMakeRange(2, 0)
                replacementRange:NSMakeRange(NSNotFound, 0)];
        Pump();
        Check([[secondEditor string] isEqual:[reference string]] &&
              NSEqualRanges([secondEditor selectedRange], [reference selectedRange]) &&
              NSEqualRanges([secondEditor markedRange], [reference markedRange]),
              @"IME marked-text insertion matches NSTextView");
        Check([[[secondNote contentString] string] isEqual:sourceBeforeComposition],
              @"marked text remains uncommitted in the note model");

        [secondEditor insertText:@"仮名" replacementRange:NSMakeRange(NSNotFound, 0)];
        [reference insertText:@"仮名" replacementRange:NSMakeRange(NSNotFound, 0)];
        Pump();
        Check([[secondEditor string] isEqual:[reference string]] &&
              NSEqualRanges([secondEditor selectedRange], [reference selectedRange]) &&
              ![secondEditor hasMarkedText] && ![reference hasMarkedText],
              @"IME commit matches NSTextView and clears marked state");
        Check([[[secondNote contentString] string] isEqual:[secondEditor string]],
              @"committed input reaches the note model");

        Check([[secondEditor accessibilityAttributeValue:NSAccessibilityRoleAttribute]
                  isEqual:[reference accessibilityAttributeValue:NSAccessibilityRoleAttribute]],
              @"source editor exposes the native accessibility role");
        Check([[secondEditor accessibilityAttributeValue:NSAccessibilityValueAttribute]
                  isEqual:[reference accessibilityAttributeValue:NSAccessibilityValueAttribute]],
              @"source editor exposes the native accessibility text value");
        Check([[secondEditor accessibilityAttributeValue:NSAccessibilitySelectedTextRangeAttribute]
                  isEqual:[reference accessibilityAttributeValue:NSAccessibilitySelectedTextRangeAttribute]],
              @"source editor exposes the native accessibility selection");
        [sourceBeforeComposition release];

        NSLog(@"CONTRARIAN B ROUND 3 EVIDENCE PASSED (%lu checks)",
              (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults]
            removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"CONTRARIAN B ROUND 3 EXCEPTION %@ %@\n%@", [exception name],
              [exception reason], [exception callStackSymbols]);
        exit(1);
    }
}
@end
