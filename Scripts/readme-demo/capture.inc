#include "helpers.inc"

- (void)nv_recordFrame:(NSTimer *)timer {
    @autoreleasepool {
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSWindow *candidate in [NSApp orderedWindows])
            if ([DemoWindows containsObject:candidate] && [candidate isVisible]) [ordered addObject:candidate];
        const void *identifiers[2];
        for (NSUInteger i = 0; i < [ordered count]; i++)
            identifiers[i] = (const void *)(uintptr_t)[ordered[i] windowNumber];
        CFArrayRef list = CFArrayCreate(NULL, identifiers, [ordered count], NULL);
        CGImageRef image = CGWindowListCreateImageFromArray(DemoBounds, list, kCGWindowImageNominalResolution);
        CFRelease(list);
        if (!image) { NSLog(@"FAIL: native recording frame"); exit(1); }
        NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
        CGImageRelease(image);
        NSString *name = [NSString stringWithFormat:@"frames/%04lu.png", (unsigned long)[DemoFrames count]];
        BOOL saved = [[bitmap representationUsingType:NSPNGFileType properties:@{}]
            writeToFile:[DemoDirectory stringByAppendingPathComponent:name] atomically:YES];
        if (!saved) { NSLog(@"FAIL: save recording frame"); exit(1); }
        [DemoFrames addObject:@{@"file":name, @"time":@([NSDate timeIntervalSinceReferenceDate] - DemoStart)}];
    }
}

- (void)nv_hold:(NSTimeInterval)seconds {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (void)nv_typeQuery:(NSString *)query {
    [self bringFocusToControlField:self];
    [self nv_hold:.3];
    NSTextView *editor = (id)[field currentEditor];
    Check(editor != nil, @"search uses the native field editor");
    [editor insertText:@"" replacementRange:NSMakeRange(0, [[editor string] length])];
    for (NSUInteger i = 0; i < [query length]; i++) {
        [editor insertText:[query substringWithRange:NSMakeRange(i, 1)] replacementRange:[editor selectedRange]];
        [self nv_hold:.3];
    }
    [self nv_waitForSearch];
    Check([[[self browserSession] searchString] isEqual:query], @"typed text reaches fuzzy search");
    Check([[self browserSession] resultCount] == 0 ||
        ([notesTableView primarySelectedRow] >= 0 && [self selectedNoteObject] != nil),
        @"a completed nonempty fuzzy search has a selected note");
    [self nv_checkVisibleMatches];
}

- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
#include "fixtures.inc"
        [prefsController setAutoCompleteSearches:YES sender:self];
        [prefsController setShouldHighlightSearchTerms:YES sender:self];
        [prefsController setUseETScrollbarsOnLion:YES sender:self];
        Check(![prefsController searchInTitleBar], @"the capture uses the default search row below the title bar");
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [self setUserColorScheme:self];
        NSRect visible = [[NSScreen mainScreen] visibleFrame];
        NSRect area = NSMakeRect(floor(NSMidX(visible) - 510), floor(NSMidY(visible) - 390), 1020, 780);
        Check(NSContainsRect(visible, area), @"display fits the 1020 by 780 recording area");
        DemoBounds = CGRectMake(area.origin.x, NSMaxY([[[NSScreen screens] firstObject] frame]) - NSMaxY(area), 1020, 780);
        [window setFrame:NSMakeRect(area.origin.x + 50, area.origin.y + 110, 840, 620) display:YES];
        [self setNotesListHeight:210];
        [self searchForString:@"" mode:@"fuzzy"];
        [self revealNote:garden options:0];
        [self focusNoteBody];
        [textView setSelectedRange:NSMakeRange(0, 0)];
        [textView scrollRangeToVisible:NSMakeRange(0, 0)];
        Check(CaptureAwait(^BOOL { return NVSourceCapturesAreCurrent([textView layoutManager]); }, 5),
            @"initial Org syntax is ready");
        [self nv_hold:.6];
        DemoWindows = [[NSMutableArray alloc] initWithObjects:window, nil];
        DemoFrames = [[NSMutableArray alloc] init];
        DemoDirectory = [[NSString stringWithUTF8String:getenv("NV_USER_SCHEMES_ARTIFACTS")] copy];
        DemoStart = [NSDate timeIntervalSinceReferenceDate];
        [self nv_recordFrame:nil];
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:.15 target:self selector:@selector(nv_recordFrame:)
            userInfo:nil repeats:YES];
        [self nv_hold:1.5];
        [self nv_typeQuery:@"grdn"];
        [self nv_hold:2];
        Check([[self browserSession] resultCount] > [[self browserSession] distinctResultNoteCount],
            @"the fuzzy list includes separate matching lines from a note");
        [self nv_selectNote:garden matchingLine:@"* TODO Plan the garden"];
        [self nv_hold:2.2];
        [self nv_selectNote:garden matchingLine:@"- [ ] Visit the community garden."];
        [self nv_hold:2.2];
        [app newWindow:self];
        AppController *peer = [[app browserControllers] lastObject];
        [DemoWindows addObject:[peer window]];
        [[peer window] setFrame:NSMakeRect(area.origin.x + 130, area.origin.y + 50, 840, 620) display:YES];
        [[peer window] setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [peer setUserColorScheme:peer];
        [peer setNotesListHeight:165];
        [peer nv_activateBrowser];
        Check(peer != self && [peer sharedNotationController] == library, @"the second window shares the sample library");
        [self nv_hold:.8];
        [peer nv_typeQuery:@"trip"];
        [peer nv_selectNote:trip matchingLine:@"* TODO Get ready for the trip"];
        Check([[[self browserSession] searchString] isEqual:@"grdn"] && [self selectedNoteObject] == garden &&
            [[[peer browserSession] searchString] isEqual:@"trip"] && [peer selectedNoteObject] == trip,
            @"both windows keep independent queries and selected notes");
        [self nv_hold:3];
        [[peer window] performClose:self];
        [self nv_activateBrowser];
        [self nv_hold:1.5];
        [self bringFocusToControlField:self];
        NSTextView *searchEditor = (id)[field currentEditor];
        [searchEditor insertText:@"" replacementRange:NSMakeRange(0, [[searchEditor string] length])];
        [self revealNote:garden options:0];
        [self focusNoteBody];
        [textView setSelectedRange:NSMakeRange(0, 0)];
        [textView scrollRangeToVisible:NSMakeRange(0, 0)];
        Check(CaptureAwait(^BOOL { return [[[self browserSession] searchString] length] == 0 &&
            [[self browserSession] searchResultsAreCurrent] && [self selectedNoteObject] == garden; }, 5),
            @"clearing the query ends with the garden note selected");
        [self nv_hold:1];
        [timer invalidate];
        Check([DemoFrames count] > 80, @"the interaction recording contains more than 80 native frames");
        Check([[NSJSONSerialization dataWithJSONObject:DemoFrames options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[DemoDirectory stringByAppendingPathComponent:@"frames.json"] atomically:YES],
            @"recorded frame timestamps are saved");
        NSLog(@"README_DEMO_CAPTURE_PASS checks=%lu frames=%lu duration=%.2f", (unsigned long)Checks,
            (unsigned long)[DemoFrames count], [NSDate timeIntervalSinceReferenceDate] - DemoStart);
        [DemoWindows release]; [DemoFrames release]; [DemoDirectory release];
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:.1];
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
