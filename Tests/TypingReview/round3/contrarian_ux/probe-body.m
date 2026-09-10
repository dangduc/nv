
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        LinkingEditor *editor = [self valueForKey:@"textView"];
        Activations = [NSMutableArray new];
        method_setImplementation(class_getInstanceMethod([NSWorkspace class], @selector(openURL:)), (IMP)CaptureOpenURL);
        method_setImplementation(class_getInstanceMethod([NSWorkspace class], @selector(openURLs:withApplicationAtURL:configuration:completionHandler:)), (IMP)CaptureModernOpen);
        method_setImplementation(class_getInstanceMethod([NSWorkspace class], @selector(openURLs:withAppBundleIdentifier:options:additionalEventParamDescriptor:launchIdentifiers:)), (IMP)CaptureLegacyOpen);
        [[GlobalPrefs defaultPrefs] setMakeURLsClickable:YES sender:self];
        NoteObject *note = MakeNote(library, @"Menu target", @"https://example.com/old\nlast line");
        [self searchForString:@"" mode:@"fuzzy"]; [self revealNote:note options:0];
        [[self window] makeKeyAndOrderFront:self]; [[self window] makeFirstResponder:editor];
        Check(Await(^BOOL { return LinksCurrent(editor.textStorage); }, 3), @"initial source link analysis completes");
        NSMenu *menu = [[editor menuForEvent:MouseEvent(editor, NSRightMouseDown, 3)] retain];
        DescribeMenu(menu, @"fresh");
        NSMenuItem *open = OpenItem(menu);
        Check(open != nil, @"native current menu contains Open Link");
        NSLog(@"OBSERVE action dispatch=%d firstResponder=%@", [NSApp sendAction:open.action to:open.target from:open], NSStringFromClass([[[self window] firstResponder] class]));
        NSLog(@"OBSERVE fresh menu activation=%@", Activations);
        NSLog(@"LIMITATION programmatic native menu action reaches workspace=%d; no active menu-tracking loop is simulated", [Activations containsObject:@"https://example.com/old"]);
        [Activations removeAllObjects];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer searchForString:@"" mode:@"fuzzy"]; [peer revealNote:note options:0];
        LinkingEditor *other = [peer valueForKey:@"textView"];
        Check(editor.textStorage == other.textStorage, @"peer native editor shares source storage");
        [[self window] makeKeyAndOrderFront:self]; [[self window] makeFirstResponder:editor];
        [menu release]; menu = [[editor menuForEvent:MouseEvent(editor, NSRightMouseDown, 3)] retain]; open = OpenItem(menu);
        [other insertText:@"new" replacementRange:NSMakeRange(20,3)];
        if (HasAnalysis()) Check(!LinksCurrent(editor.textStorage), @"peer character edit invalidates analysis after menu creation");
        [menu update];
        NSLog(@"OBSERVE retained open enabled=%d target=%@ represented=%@ source=%@", open.enabled, NSStringFromClass([open.target class]), open.representedObject, editor.string);
        NSLog(@"OBSERVE action dispatch=%d firstResponder=%@", [NSApp sendAction:open.action to:open.target from:open], NSStringFromClass([[[self window] firstResponder] class]));
        NSLog(@"OBSERVE retained-menu-after-peer-edit activation=%@", Activations);
        [Activations removeAllObjects];
        NSMenu *pending = [editor menuForEvent:MouseEvent(editor, NSRightMouseDown, 3)];
        NSLog(@"OBSERVE pending menu containsOpen=%d current=%d attribute=%@", OpenItem(pending) != nil, LinksCurrent(editor.textStorage), [editor.textStorage attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL]);
        if (HasAnalysis()) Check([editor.textStorage attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL] == nil, @"pending menu removes obsolete source target");
        Check(Await(^BOOL { return LinksCurrent(editor.textStorage); }, 3), @"fresh analysis publishes after pending menu cleanup");
        NSMenu *fresh = [editor menuForEvent:MouseEvent(editor, NSRightMouseDown, 3)];
        NSMenuItem *freshOpen = OpenItem(fresh);
        Check(freshOpen != nil, @"new current menu restores Open Link");
        [NSApp sendAction:freshOpen.action to:freshOpen.target from:freshOpen];
        Check([[[editor.textStorage attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL] description] isEqual:@"https://example.com/new"], @"fresh source attribute holds changed URL target");
        NSLog(@"OBSERVE fresh replacement menu activation=%@", Activations);
        [menu release];
        Check([library flushAllNoteChanges], @"disposable library checkpoint succeeds");
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"TYPING UX PASSED (%lu checks)", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) {
        NSLog(@"TYPING UX EXCEPTION %@ %@", [exception name], [exception reason]); exit(1);
    }
}
@end
