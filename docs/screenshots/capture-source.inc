// Run with Tests/ViewControlsReview/run-probe.py in a disposable app and library.
- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *fieldNote = MakeNote(library, @"Field notes", @"# Field notes\n\nA small place for ideas, plans, and things worth keeping.\n\n## Today\n\n- Write the source directly.\n- Find a thought with a few remembered characters.\n- Open a read-only preview when the formatting matters.\n\n## A useful reminder\n\nKeep the tools quiet and the text close.\n");
        NoteObject *garden = MakeNote(library, @"Weekend garden", @"# Weekend garden\n\n## Saturday\n\n- Plant rosemary beside the path.\n- Water the seedlings before breakfast.\n- Leave room for the late summer flowers.\n\n## Notes\n\nThe afternoon light reaches the back fence.\n");
        MakeNote(library, @"Reading list", @"# Reading list\n\n- A book about maps\n- An essay on careful observation\n\nLook for the chapter about garden design.\n");
        NoteObject *trip = MakeNote(library, @"Trip checklist", @"# Trip checklist\n\n## Pack light\n\n- Tickets and a notebook\n- A small camera\n- A warm layer for the train\n\n## Before leaving\n\nSave the route and choose a book for the journey.\n");
        for (NoteObject *note in @[fieldNote, garden, trip]) [note setSourceSyntaxIdentifier:@"markdown"];
        [prefsController setAutoCompleteSearches:NO sender:self];
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [self setSystemColorScheme:self];

        NSRect visible = [[window screen] visibleFrame];
        NSRect backdropFrame = NSMakeRect(floor(NSMidX(visible) - 484), floor(NSMidY(visible) - 410), 968, 820);
        Check(NSContainsRect(visible, backdropFrame), @"display fits the app and background margins");
        NSWindow *backdrop = [[NSWindow alloc] initWithContentRect:backdropFrame
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        [backdrop setReleasedWhenClosed:NO];
        [backdrop setOpaque:YES];
        [backdrop setHasShadow:NO];
        [backdrop setBackgroundColor:[NSColor colorWithSRGBRed:0.86 green:0.89 blue:0.93 alpha:1]];
        [backdrop setIgnoresMouseEvents:YES];
        // The native shadow extends farther below the window than above it.
        [window setFrame:NSMakeRect(NSMinX(backdropFrame) + 64, NSMinY(backdropFrame) + 96, 840, 660) display:YES];
        [backdrop orderWindow:NSWindowBelow relativeTo:[window windowNumber]];
        [window makeKeyAndOrderFront:self];
        [self setNotesListHeight:160];
        [self revealNote:fieldNote options:0];
        [self focusNoteBody];
        [textView setSelectedRange:NSMakeRange([[textView string] length], 0)];
        for (NSUInteger i = 0; i < 20; i++) Pump();
        Check([window isKeyWindow] && [window hasShadow], @"sample app window is key and has its native shadow");
        Check(![prefsController showTitleInTopSection] && ![prefsController showTagsInTopSection] && ![prefsController showBodyControlsInTopSection], @"capture uses the hidden-header defaults");
        Check([[prefsController noteBodyFont] isFixedPitch], @"capture uses the monospace default");
        Check([self selectedNoteObject] == fieldNote && ![self isViewingNote], @"capture shows the editable sample source");

        // Only these two windows are captured; other desktop content is excluded.
        const void *identifiers[] = {(const void *)(uintptr_t)[window windowNumber], (const void *)(uintptr_t)[backdrop windowNumber]};
        CFArrayRef windows = CFArrayCreate(NULL, identifiers, 2, NULL);
        CGImageRef capture = CGWindowListCreateImageFromArray(CGRectNull, windows, kCGWindowImageDefault);
        CFRelease(windows);
        Check(capture != NULL, @"WindowServer captures the app, shadow, and native backdrop");
        NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
        CGImageRelease(capture);
        const char *outputPath = getenv("NV_README_SOURCE_SCREENSHOT");
        Check(outputPath != NULL, @"screenshot output path is set");
        Check([[bitmap representationUsingType:NSPNGFileType properties:@{}]
            writeToFile:[NSString stringWithUTF8String:outputPath] atomically:YES], @"source screenshot is saved");
        [backdrop close];
        [backdrop release];
        NSLog(@"README_SOURCE_CAPTURE_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
