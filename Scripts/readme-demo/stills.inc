#include "helpers.inc"

- (void)nv_captureWindows:(NSArray *)windows name:(NSString *)name {
    for (NSWindow *captureWindow in windows) {
        [[captureWindow contentView] layoutSubtreeIfNeeded];
        [captureWindow display];
    }
    for (NSUInteger i = 0; i < 6; i++) Pump();
    const void *identifiers[2];
    Check([windows count] > 0 && [windows count] <= 2, @"the capture contains one or two sample windows");
    for (NSUInteger i = 0; i < [windows count]; i++)
        identifiers[i] = (const void *)(uintptr_t)[windows[i] windowNumber];
    CFArrayRef list = CFArrayCreate(NULL, identifiers, [windows count], NULL);
    CGImageRef capture = CGWindowListCreateImageFromArray(CGRectNull, list, kCGWindowImageDefault);
    CFRelease(list);
    Check(capture != NULL, @"WindowServer captures only the sample windows");
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:capture] autorelease];
    CGImageRelease(capture);
    NSString *directory = [NSString stringWithUTF8String:getenv("NV_USER_SCHEMES_ARTIFACTS")];
    Check([[bitmap representationUsingType:NSPNGFileType properties:@{}]
        writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES], @"the native screenshot is saved");
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
        [self setHorizontalLayout:NO];
        [self setUserColorScheme:self];
        NSRect visible = [[window screen] visibleFrame];
        NSRect frame = NSMakeRect(floor(NSMidX(visible) - 450), floor(NSMidY(visible) - 370), 900, 740);
        Check(NSContainsRect(visible, frame), @"the sample window fits entirely on screen");
        [window setFrame:frame display:YES];
        [self setNotesListHeight:170];
        for (NSNumber *dark in @[@NO, @YES]) {
            if (@available(macOS 10.14, *))
                [window setAppearance:[NSAppearance appearanceNamed:[dark boolValue] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
            else Check(NO, @"dark appearance screenshots require macOS 10.14 or later");
            [self searchForString:@"ideas" mode:@"fuzzy"];
            [self nv_waitForSearch];
            [self nv_selectNote:fieldNote matchingLine:@"A small place for ideas, plans, and things worth keeping."];
            [textView setSelectedRange:NSMakeRange(0, 0)];
            [textView scrollRangeToVisible:NSMakeRange(0, 0)];
            [self nv_checkVisibleMatches];
            Check([self usesDarkUserColorScheme] == [dark boolValue], @"the User Scheme follows the sample window appearance");
            NSRange range = [[textView string] rangeOfString:@"TODO"];
            NSLayoutManager *layout = [textView layoutManager];
            NSDictionary *temporary = [layout temporaryAttributesAtCharacterIndex:range.location effectiveRange:NULL];
            NSDictionary *drawing = [textView layoutManager:layout shouldUseTemporaryAttributes:temporary
                forDrawingToScreen:YES atCharacterIndex:range.location effectiveRange:&range];
            Check(drawing[NSForegroundColorAttributeName] && ![drawing[NSForegroundColorAttributeName] isEqual:[self foregrndColor]],
                @"the Org TODO keyword draws with a syntax color");
            [self nv_captureWindows:@[window] name:[dark boolValue] ? @"readme-dark.png" : @"readme-source.png"];
        }

        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [self setNotesListHeight:220];
        [self searchForString:@"grdn" mode:@"fuzzy"];
        [self nv_waitForSearch];
        [self nv_selectNote:garden matchingLine:@"* TODO Plan the garden"];
        [textView scrollRangeToVisible:NSMakeRange(0, 0)];
        [self nv_checkVisibleMatches];
        Check([[self browserSession] resultCount] > [[self browserSession] distinctResultNoteCount],
            @"the fuzzy list contains separate matching lines from a note");
        [self nv_captureWindows:@[window] name:@"readme-search.png"];

        [app newWindow:self];
        AppController *peer = [[app browserControllers] lastObject];
        [peer nv_activateBrowser];
        [[peer window] setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [peer setUserColorScheme:peer];
        CGFloat width = MIN(760, floor((NSWidth(visible) - 96) / 2));
        CGFloat left = floor(NSMidX(visible) - width - 16);
        [window setFrame:NSMakeRect(left, frame.origin.y, width, frame.size.height) display:YES];
        [[peer window] setFrame:NSMakeRect(left + width + 32, frame.origin.y, width, frame.size.height) display:YES];
        [peer setHorizontalLayout:YES];
        [peer setNotesListHeight:250];
        [peer searchForString:@"trip" mode:@"fuzzy"];
        [peer nv_waitForSearch];
        [peer nv_selectNote:trip matchingLine:@"* TODO Get ready for the trip"];
        [[peer valueForKey:@"textView"] scrollRangeToVisible:NSMakeRange(0, 0)];
        [self nv_checkVisibleMatches]; [peer nv_checkVisibleMatches];
        Check(peer != self && [peer sharedNotationController] == library &&
            [[[self browserSession] searchString] isEqual:@"grdn"] && [self selectedNoteObject] == garden &&
            [[[peer browserSession] searchString] isEqual:@"trip"] && [peer selectedNoteObject] == trip,
            @"the sample windows keep independent queries and notes in one library");
        Check(NSContainsRect(visible, [window frame]) && NSContainsRect(visible, [[peer window] frame]),
            @"both sample windows fit entirely on screen");
        [self nv_captureWindows:@[[peer window], window] name:@"readme-windows.png"];
        [[peer window] performClose:self];

        [self nv_activateBrowser];
        [window setFrame:frame display:YES];
        [self setNotesListHeight:130];
        [self searchForString:@"" mode:@"fuzzy"];
        NoteObject *previewNote = MakeNote(library, @"A useful reminder",
            @"# A useful reminder\n\nA small place for **ideas**, plans, and things worth keeping.\n\n"
             "## Today\n\n- Write the source directly.\n- Find a thought with a few remembered characters.\n"
             "- Open a read-only preview when the formatting matters.\n\n"
             "## Keep it simple\n\n> Keep the tools quiet and the text close.\n\n"
             "The Markdown source stays editable in **Source**. This preview keeps the formatting close at hand.\n");
        [previewNote setSourceSyntaxIdentifier:@"markdown"];
        [self revealNote:previewNote options:0];
        [prefsController setShowBodyControlsInTopSection:YES sender:self];
        NSMenuItem *markdown = [[[NSMenuItem alloc] initWithTitle:@"Markdown" action:@selector(selectPreviewMode:) keyEquivalent:@""] autorelease];
        [markdown setRepresentedObject:@"markdown"];
        [self selectPreviewMode:markdown];
        [self setViewingNote:YES];
        PreviewController *preview = [self valueForKey:@"previewController"];
        Check(CaptureAwait(^BOOL { return [self isViewingNote] && ![preview loading] &&
            ![preview renderError] && [[preview renderedHTML] containsString:@"Keep it simple"]; }, 15),
            @"the Markdown preview finishes rendering the sample note");
        __block BOOL complete = NO, readOnly = NO;
        [[preview webView] evaluateJavaScript:@"document.body.innerText.includes('Keep it simple') && !document.body.isContentEditable"
            completionHandler:^(id value, NSError *error) { readOnly = !error && [value boolValue]; complete = YES; }];
        Check(CaptureAwait(^BOOL { return complete; }, 5) && readOnly, @"WebKit displays the read-only Markdown sample");
        [self nv_captureWindows:@[window] name:@"readme-preview.png"];
        NSLog(@"README_STILLS_CAPTURE_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:.1];
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
