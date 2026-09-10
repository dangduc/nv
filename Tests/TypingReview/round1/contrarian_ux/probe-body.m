    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        LinkingEditor *editor = [self valueForKey:@"textView"];
        [[GlobalPrefs defaultPrefs] setMakeURLsClickable:NO sender:self];
        [[GlobalPrefs defaultPrefs] setShowWordCount:NO];
        NoteObject *note = MakeNote(library, @"Link UX", @"https://example.com\nlast line");
        [self searchForString:@"" mode:@"fuzzy"]; [self revealNote:note options:0];
        [[self window] makeKeyAndOrderFront:self]; [[self window] makeFirstResponder:editor];
        Check(Await(^BOOL { return NVSourceLinksAreCurrent(editor.textStorage); }, 3), @"initial source link analysis completes");
        Check([editor.textStorage attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL] != nil, @"production editor has a URL link attribute");
        Method clickMethod = class_getInstanceMethod([LinkingEditor class], @selector(clickedOnLink:atIndex:));
        OriginalClick = method_setImplementation(clickMethod, (IMP)RecordClick);
        [editor setSelectedRange:NSMakeRange(editor.string.length, 0)];
        Click(editor, 3);
        NSLog(@"OBSERVE fresh-click selection=%@ callbacks=%lu", NSStringFromRange(editor.selectedRange), (unsigned long)LinkClicks);
        Check(editor.selectedRange.location < 18, @"ordinary click inside a current URL places the source caret");
        [editor setSelectedRange:NSMakeRange(editor.string.length, 0)];
        [editor insertText:@"k" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check(!NVSourceLinksAreCurrent(editor.textStorage), @"real character edit marks old link attributes stale");
        NSUInteger end = editor.string.length, callbacks = LinkClicks;
        Click(editor, 3);
        NSLog(@"OBSERVE stale-click selection=%@ end=%lu callbacks=%lu", NSStringFromRange(editor.selectedRange), (unsigned long)end, (unsigned long)(LinkClicks - callbacks));
        BOOL staleClickPlacedCaret = editor.selectedRange.location < 18;

        Check(Await(^BOOL { return NVSourceLinksAreCurrent(editor.textStorage); }, 3), @"link analysis becomes current again");
        [editor setSelectedRange:NSMakeRange(editor.string.length, 0)];
        [editor insertText:@"k" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check([editor highlightLinkAtIndex:3] == nil, @"stale command-link highlight does not select obsolete range");
        NSMenu *staleMenu = [editor menuForEvent:MouseEvent(editor, NSRightMouseDown, 3)];
        Check(staleMenu != nil, @"native source context menu still opens with stale link analysis");
        Check([editor.textStorage attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL] == nil, @"context menu removes obsolete link target before Cocoa builds actions");
        Check(Await(^BOOL { return NVSourceLinksAreCurrent(editor.textStorage); }, 3), @"context-menu cleanup does not prevent the pending fresh link result");
        Check([editor.textStorage attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL] != nil, @"asynchronous result restores URL target after stale menu cleanup");

        // Intercept only Cocoa's final link activation to avoid opening a browser.
        // Source editing, hit testing, and the production stale guard remain intact.
        Method nativeMethod = class_getInstanceMethod([NSTextView class], @selector(clickedOnLink:atIndex:));
        IMP nativeClick = method_setImplementation(nativeMethod, (IMP)RecordNativeActivation);
        [[GlobalPrefs defaultPrefs] setMakeURLsClickable:YES sender:self];
        Check(Await(^BOOL { return NVSourceLinksAreCurrent(editor.textStorage); }, 3), @"link targets are current after clickability preference change");
        id oldURL = [editor.textStorage attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL];
        [editor clickedOnLink:oldURL atIndex:3];
        Check(NativeActivations == 1, @"current clickable URL reaches Cocoa's activation handler");
        [editor setSelectedRange:NSMakeRange(8, 7)];
        [editor insertText:@"changed" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check(!NVSourceLinksAreCurrent(editor.textStorage), @"changing the URL target invalidates link actions");
        [editor clickedOnLink:oldURL atIndex:3];
        Check(NativeActivations == 1, @"clicking changed URL does not activate obsolete target while analysis is pending");
        method_setImplementation(nativeMethod, nativeClick);
        [[GlobalPrefs defaultPrefs] setMakeURLsClickable:NO sender:self];

        id counter = [self valueForKey:@"wordCounter"];
        Check(Await(^BOOL { return [[counter stringValue] length] != 0; }, 3), @"visible word count arrives through production notification path");
        NSString *firstCount = [[counter stringValue] copy];
        NoteObject *second = MakeNote(library, @"Other UX", @"one two three four five six seven");
        [self revealNote:second options:0];
        Check(![[counter stringValue] isEqual:firstCount], @"note switch clears previous note's word count before replacement");
        Check(Await(^BOOL { return [[counter stringValue] isEqual:@"7 words"]; }, 3), @"replacement note asynchronously publishes its own count");
        [firstCount release];
        method_setImplementation(clickMethod, OriginalClick);
        Check([library flushAllNoteChanges], @"disposable library checkpoint succeeds");
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        Check(staleClickPlacedCaret, @"ordinary click inside a stale URL still places the source caret");
        NSLog(@"TYPING UX PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"TYPING UX EXCEPTION %@ %@", [exception name], [exception reason]); exit(1);
    }
}
@end
