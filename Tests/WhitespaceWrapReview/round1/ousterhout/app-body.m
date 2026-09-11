    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = app.library;
        [self searchForString:@""]; Pump();
        NSString *spaces = [@"" stringByPaddingToLength:901 withString:@" " startingAtIndex:0];
        NoteObject *note = MakeNote(library, @"Layout-only review", spaces);
        NoteObject *other = MakeNote(library, @"Other review source", @"separate note body");
        [note setSourceSyntaxIdentifier:@"plain"];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:12] sender:self];
        [self revealNote:note options:0]; Pump();
        [app newWindow:self]; Pump();
        AppController *peer = [app.browserControllers lastObject];
        [peer revealNote:note options:0]; Pump();
        LinkingEditor *a = [self valueForKey:@"textView"];
        LinkingEditor *b = [peer valueForKey:@"textView"];
        [self.window setContentSize:NSMakeSize(480,600)];
        [peer.window setContentSize:NSMakeSize(710,600)];
        Pump(); Pump(); Pump();
        NSTextStorage *storage = a.textStorage;
        Check(storage == b.textStorage, @"both native editors attach to one storage");
        Check(a.layoutManager != b.layoutManager, @"display layout remains per browser");
        Check(a.layoutManager.delegate == a && b.layoutManager.delegate == b, @"existing per-editor delegates remain installed");
        Check(SpaceLineCount(a) > 1 && SpaceLineCount(b) > 1, @"actual production delegate wraps the source spaces");
        [a setSelectedRange:NSMakeRange(101,7)];
        [b setSelectedRange:NSMakeRange(699,3)];
        NSRange selectedA = a.selectedRange, selectedB = b.selectedRange;
        [[note undoManager] removeAllActions];
        NSAttributedString *before = [storage copy];
        NSString *committed = [[[note contentString] string] copy];
        WrapStorageObserver *observer = [[[WrapStorageObserver alloc] init] autorelease];
        [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(observe:)
            name:NSTextStorageDidProcessEditingNotification object:storage];
        NSString *sentinel = @"NVReviewLayoutLocalMarker";
        NSRange markerRange = NSMakeRange(77,144);
        [a.layoutManager addTemporaryAttribute:sentinel value:@"first window" forCharacterRange:markerRange];
        [b.layoutManager addTemporaryAttribute:sentinel value:@"second window" forCharacterRange:markerRange];
        for (NSUInteger pass=0; pass<12; pass++) {
            [self.window setContentSize:NSMakeSize(480 + 31*(pass%5),600)];
            [peer.window setContentSize:NSMakeSize(790 - 27*(pass%7),600)];
            for (LinkingEditor *view in @[a,b]) {
                [view.layoutManager invalidateGlyphsForCharacterRange:NSMakeRange(0,storage.length)
                    changeInLength:0 actualCharacterRange:NULL];
                [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
                [view displayIfNeeded];
                Check(SpaceLineCount(view) > 1, @"regenerated glyphs retain wrapping");
                Check([view didRenderFully], @"existing layout completion callback still runs");
            }
            Check([storage isEqualToAttributedString:before], @"regeneration does not change source attributes or characters");
            Check([[[note contentString] string] isEqual:committed], @"regeneration leaves committed note source unchanged");
            Check(NSEqualRanges(a.selectedRange,selectedA) && NSEqualRanges(b.selectedRange,selectedB), @"layout does not change either editor selection");
            Check(![[note undoManager] canUndo] && ![[note undoManager] canRedo], @"layout does not create note Undo or Redo");
            Check([[a.layoutManager temporaryAttribute:sentinel atCharacterIndex:100 effectiveRange:NULL] isEqual:@"first window"] &&
                [[b.layoutManager temporaryAttribute:sentinel atCharacterIndex:100 effectiveRange:NULL] isEqual:@"second window"],
                @"glyph regeneration preserves independent temporary display attributes");
            Check(observer->edits == 0 && observer->characterEdits == 0, @"layout sends no shared text-storage edit notifications");
        }
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        [a.layoutManager removeTemporaryAttribute:sentinel forCharacterRange:markerRange];
        [b.layoutManager removeTemporaryAttribute:sentinel forCharacterRange:markerRange];
        NSLayoutManager *layoutA = a.layoutManager;
        NSLayoutManager *layoutB = b.layoutManager;
        for (NSUInteger pass=0; pass<5; pass++) {
            [self revealNote:other options:0]; Pump();
            Check(a.textStorage != storage && b.textStorage == storage, @"note switch detaches only its own layout");
            Check(a.layoutManager == layoutA && b.layoutManager == layoutB, @"switch does not replace native layout managers");
            Check(a.layoutManager.delegate == a && b.layoutManager.delegate == b, @"switch preserves delegate ownership");
            Check([b.string isEqual:spaces] && NSEqualRanges(b.selectedRange,selectedB), @"detachment leaves peer source and selection untouched");
            [self revealNote:note options:0]; Pump();
            Check(a.textStorage == storage && b.textStorage == storage, @"reattachment reuses the original shared storage");
            Check(SpaceLineCount(a)>1 && SpaceLineCount(b)>1, @"reused native layouts retain space wrapping");
            Check(![[note undoManager] canUndo], @"note switch and layout retain empty note Undo");
        }
        Check([[[note contentString] string] isEqual:committed], @"note lifecycle leaves committed source intact");
        [before release]; [committed release];
        [peer.window close]; Pump();
        if (getenv("NV_REVIEW_CAPTURE")) {
            NSString *gap = [@"" stringByPaddingToLength:151 withString:@" " startingAtIndex:0];
            NSString *example = [NSString stringWithFormat:@"Ordinary spaces wrap naturally.\n\nStart →%@← End\n\nSource text is unchanged.", gap];
            NoteObject *illustration = MakeNote(library, @"Space wrapping", example);
            [self revealNote:illustration options:0];
            [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
            [self.window setContentSize:NSMakeSize(560,640)];
            [self setNotesListHeight:105];
            [self.window makeKeyAndOrderFront:self];
            [self.window makeFirstResponder:a];
            [a setSelectedRange:NSMakeRange([example rangeOfString:@"←"].location,0)];
            Pump(); Pump();
            [a.layoutManager ensureLayoutForTextContainer:a.textContainer];
            [self.window display];
            NSView *capture = self.window.contentView.superview;
            NSBitmapImageRep *bitmap = [capture bitmapImageRepForCachingDisplayInRect:capture.bounds];
            [capture cacheDisplayInRect:capture.bounds toBitmapImageRep:bitmap];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            Check([png writeToFile:[NSString stringWithUTF8String:getenv("NV_REVIEW_CAPTURE")] atomically:YES], @"save disposable app illustration");
        }
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"OUSTERHOUT WRAP REVIEW PASSED (%lu checks)", (unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"OUSTERHOUT WRAP REVIEW EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
