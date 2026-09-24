- (void)nv_checkHeaderCornerPixels {
    NSView *header = [notesTableView headerView];
    NSScroller *scroller = [notesScrollView verticalScroller];
    if (!header || [scroller isHidden] || [notesScrollView scrollerStyle] != NSScrollerStyleLegacy) return;
    [window displayIfNeeded]; Pump();
    NSRect headerRect = [header convertRect:[header bounds] toView:nil];
    NSRect scrollerRect = [scroller convertRect:[scroller bounds] toView:nil];
    NSRect corner = NSInsetRect(NSMakeRect(NSMinX(scrollerRect), NSMinY(headerRect),
        NSWidth(scrollerRect), NSHeight(headerRect)), 2, 2);
    CGImageRef full = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
    Check(full != NULL && !NSIsEmptyRect(corner), @"the desktop captures the notes-list header corner");
    CGFloat scale = CGImageGetWidth(full) / NSWidth([window frame]);
    CGImageRef crop = CGImageCreateWithImageInRect(full, CGRectMake(NSMinX(corner) * scale,
        (NSHeight([window frame]) - NSMaxY(corner)) * scale, NSWidth(corner) * scale, NSHeight(corner) * scale));
    Check(crop != NULL, @"the header corner lies inside its browser window");
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:crop] autorelease];
    CGImageRelease(crop); CGImageRelease(full);
    NSUInteger matching = 0, total = [bitmap pixelsWide] * [bitmap pixelsHigh];
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++)
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++)
            if (ListPixelDistance([bitmap colorAtX:x y:y], [self backgrndColor], [bitmap colorSpace]) < .06) matching++;
    NSLog(@"HEADER_CORNER_PIXELS matching=%.3f", total ? (double)matching / total : 0);
    Check(total > 20 && matching > total * .95, @"the corner above the notes scrollbar uses the body background");
}

- (void)nv_checkScrollbarPixels:(NSScrollView *)scroll {
    NSScroller *scroller = [scroll verticalScroller];
    Check([scroller isKindOfClass:[ETTransparentScroller class]] && ![scroller isHidden] &&
        [scroller isEnabled] && [scroller knobProportion] > 0 && [scroller knobProportion] < 1,
        @"the palette fixture has a visible custom scrollbar with a scrollable document");
    NSRect knob = [scroller rectForPart:NSScrollerKnob];
    NSPoint knobPoint = [scroller convertPoint:NSMakePoint(NSMidX(knob), NSMidY(knob)) toView:nil];
    Check([scroller testPart:knobPoint] == NSScrollerKnob, @"the painted scrollbar thumb retains its native hit target");
    // Capture the displayed window, without asking the scroller to repaint into a cache.
    // This also checks that palette changes invalidate AppKit's cached scrollbar parts.
    [window displayIfNeeded]; Pump();
    NSRect rect = [scroller convertRect:[scroller bounds] toView:nil];
    CGImageRef full = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
    Check(full != NULL, @"the desktop captures the displayed scrollbar");
    CGFloat windowScale = CGImageGetWidth(full) / NSWidth([window frame]);
    CGRect crop = CGRectMake(NSMinX(rect) * windowScale, (NSHeight([window frame]) - NSMaxY(rect)) * windowScale,
        NSWidth(rect) * windowScale, NSHeight(rect) * windowScale);
    CGImageRef strip = CGImageCreateWithImageInRect(full, crop);
    Check(strip != NULL, @"the scrollbar crop lies inside its browser window");
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:strip] autorelease];
    CGImageRelease(strip); CGImageRelease(full);
    NSColor *body = [self backgrndColor];
    NSColor *expected = [body colorUsingColorSpace:[bitmap colorSpace]];
    CGFloat bodyWhite = [[body colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent];
    CGFloat expectedRed = [expected redComponent];
    NSUInteger gutter = 0, matchingGutter = 0, knobPixels = 0;
    CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
    NSInteger center = MIN([bitmap pixelsWide] - 1, lround(NSMidX(knob) * scale));
    for (NSInteger y = 10; y < [bitmap pixelsHigh] - 10; y++) {
        NSColor *margin = [bitmap colorAtX:1 y:y];
        gutter++;
        if (ListPixelDistance(margin, body, [bitmap colorSpace]) < .06) matchingGutter++;
        NSColor *pixel = [[bitmap colorAtX:center y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        CGFloat contrast = bodyWhite < .5 ? [pixel redComponent] - expectedRed : expectedRed - [pixel redComponent];
        if (contrast > .20) knobPixels++;
    }
    NSLog(@"SCROLLBAR_PIXELS view=%@ style=%ld body=%@ matching_gutter=%.3f knob_pixels=%lu",
        NSStringFromClass([scroll class]), (long)[scroll scrollerStyle], body,
        gutter ? (double)matchingGutter / gutter : 0, (unsigned long)knobPixels);
    if ([scroll scrollerStyle] == NSScrollerStyleLegacy)
        Check(gutter > 20 && matchingGutter > gutter * .90, @"custom scrollbar gutters use the exact body background");
    else
        Check(![scroller isOpaque], @"overlay custom scrollbars keep their backing transparent");
    Check(knobPixels > 10, @"custom scrollbar thumbs contrast with the body independently of the window theme");
}

- (void)nv_checkNativeScrollbarPair {
    // Overlay scrollers blend with their content; compare them over the same paper.
    BOOL alternating = [prefsController alternatingRows];
    [prefsController setAlternatingRows:NO sender:nil];
    NSScrollView *reference = [[[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 80, 140)] autorelease];
    [reference setBorderType:NSNoBorder];
    [reference setHasVerticalScroller:YES];
    [reference setBackgroundColor:[self backgrndColor]];
    [reference setDrawsBackground:YES];
    [reference setDocumentView:[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 60, 1600)] autorelease]];
    [reference setScrollerStyle:[notesScrollView scrollerStyle]];
    [[window contentView] addSubview:reference];
    [reference tile]; [reference reflectScrolledClipView:[reference contentView]];
    [reference flashScrollers];
    for (NSUInteger tick = 0; tick < 6; tick++) Pump();
    [window displayIfNeeded]; Pump();
    CGImageRef full = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
    Check(full != NULL, @"the desktop captures both native scrollbars");
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:full] autorelease];
    CGImageRelease(full);
    CGFloat scale = [bitmap pixelsWide] / NSWidth([window frame]);
    NSMutableArray *thumbs = [NSMutableArray array], *tracks = [NSMutableArray array];
    BOOL darkWindow = NO;
    for (NSScrollView *scroll in @[notesScrollView, textScrollView, reference]) {
        NSScroller *scroller = [scroll verticalScroller];
        Check([scroller class] == [NSScroller class] && ![scroller isHidden] && [scroller isEnabled] &&
            [scroller knobProportion] > 0 && [scroller knobProportion] < 1,
            @"both views have visible native scrollbars with scrollable content");
        if (@available(macOS 10.14, *)) {
            NSArray *names = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua];
            NSString *windowAppearance = [[window effectiveAppearance] bestMatchFromAppearancesWithNames:names];
            darkWindow = [windowAppearance isEqual:NSAppearanceNameDarkAqua];
            if ([scroll scrollerStyle] == NSScrollerStyleLegacy)
                Check([[[scroller effectiveAppearance] bestMatchFromAppearancesWithNames:names] isEqual:windowAppearance],
                    @"native legacy scrollbars follow the window appearance independently of the body palette");
        }
        NSRect knob = [scroller rectForPart:NSScrollerKnob];
        NSPoint thumb = [scroller convertPoint:NSMakePoint(NSMidX(knob), NSMidY(knob)) toView:nil];
        NSPoint track = [scroller convertPoint:NSMakePoint(2, NSMidY(knob)) toView:nil];
        [thumbs addObject:[bitmap colorAtX:floor(thumb.x * scale) y:floor((NSHeight([window frame]) - thumb.y) * scale)]];
        [tracks addObject:[bitmap colorAtX:floor(track.x * scale) y:floor((NSHeight([window frame]) - track.y) * scale)]];
    }
    NSLog(@"NATIVE_SCROLLBAR_PIXELS style=%ld thumbs=%@ tracks=%@", (long)[notesScrollView scrollerStyle], thumbs, tracks);
    if ([notesScrollView scrollerStyle] == NSScrollerStyleLegacy) {
        for (NSUInteger index = 0; index < 2; index++) {
            Check(ListColorDistance([thumbs objectAtIndex:index], [thumbs objectAtIndex:2]) < .04,
                @"native scrollbar thumbs match a standard macOS scroll view");
            Check(ListColorDistance([tracks objectAtIndex:index], [tracks objectAtIndex:2]) < .04,
                @"native scrollbar tracks match a standard macOS scroll view");
        }
    } else {
        // AppKit animates each overlay thumb's opacity independently.
        for (NSUInteger index = 0; index < [thumbs count]; index++) {
            NSColor *thumb = [[thumbs objectAtIndex:index] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            NSColor *track = [[tracks objectAtIndex:index] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            CGFloat delta = darkWindow ? MAX([thumb redComponent] - [track redComponent], [thumb blueComponent] - [track blueComponent]) :
                MAX([track redComponent] - [thumb redComponent], [track blueComponent] - [thumb blueComponent]);
            Check(delta > .02, @"native overlay thumbs use the window's macOS shade, including the reference control");
        }
    }
    Check(ListColorDistance([tracks objectAtIndex:0], [tracks objectAtIndex:1]) < .04,
        @"native scrollbar tracks have matching colors in the notes list and body");
    [reference removeFromSuperview];
    [prefsController setAlternatingRows:alternating sender:nil];
}

- (void)nv_checkScrollbarsWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    if (@available(macOS 11.0, *)) {
        BOOL oldCustom = [prefsController useETScrollbarsOnLion];
        NSRect oldFrame = [window frame];
        NSAppearance *oldAppearance = [[window appearance] retain];
        NSAppearance *oldPeerAppearance = [[[peer window] appearance] retain];
        NSColor *oldLightBG = [[prefsController backgroundTextColor] retain];
        NSColor *oldDarkBG = [[prefsController darkBackgroundTextColor] retain];
        NSColor *oldLightFG = [[prefsController foregroundTextColor] retain];
        NSColor *oldDarkFG = [[prefsController darkForegroundTextColor] retain];
        NSString *source = [[[alpha contentString] string] copy];
        NotationController *library = [[NVApplicationController sharedController] library];
        NSMutableArray *filler = [NSMutableArray array];
        for (NSUInteger index = 0; index < 40; index++)
            [filler addObject:MakeNote(library, [NSString stringWithFormat:@"Notebook %02lu", (unsigned long)index], @"A sample note for scrolling.")];
        [self setViewingNote:NO]; [peer setViewingNote:NO];
        [self searchForString:@""]; [self revealNote:alpha options:0];
        [peer searchForString:@""]; [peer revealNote:alpha options:0];
        NSMutableString *longBody = [NSMutableString stringWithString:@"Custom scrollbars follow the paper; native scrollbars follow macOS.\n\n"];
        for (NSUInteger line = 0; line < 80; line++)
            [longBody appendFormat:@"Line %02lu — Notes, ideas, and things worth keeping.\n", (unsigned long)line + 1];
        [textView insertText:longBody replacementRange:NSMakeRange(0, [[textView string] length])]; Pump();
        NSRect frame = oldFrame; frame.size = NSMakeSize(920, 620); [window setFrame:frame display:YES];
        NSColor *ink = [NSColor colorWithSRGBRed:.10 green:.16 blue:.22 alpha:1];
        NSColor *paper = [NSColor colorWithSRGBRed:253/255.0 green:233/255.0 blue:217/255.0 alpha:1];
        [prefsController setBackgroundTextColor:ink sender:nil];
        [prefsController setForegroundTextColor:[NSColor whiteColor] sender:nil];
        [prefsController setDarkBackgroundTextColor:paper sender:nil];
        [prefsController setDarkForegroundTextColor:[NSColor blackColor] sender:nil];
        [self setUserColorScheme:self]; [peer setUserColorScheme:peer];
        [self showPreferencesWindow:self]; Pump();
        NSButton *toggle = [prefsWindowController valueForKey:@"useETScrollbarsOnLionButton"];
        [toggle setState:NSControlStateValueOn];
        Check([toggle sendAction:[toggle action] to:[toggle target]], @"Settings dispatches Use Neo Notational V Scrollbars");
        [[prefsWindowController valueForKey:@"window"] orderOut:self];
        Check([prefsController useETScrollbarsOnLion], @"Settings enables custom scrollbars");
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            [window setAppearance:[NSAppearance appearanceNamed:appearance]];
            [[peer window] setAppearance:[NSAppearance appearanceNamed:[appearance isEqual:NSAppearanceNameAqua] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
            Pump(); [self nv_activateBrowser];
            for (NSNumber *side in @[@NO, @YES]) {
                [self setHorizontalLayout:[side boolValue]];
                [self setNotesListHeight:[side boolValue] ? 320 : 180];
                for (NSScrollView *scroll in @[notesScrollView, textScrollView]) {
                    [scroll setScrollerStyle:NSScrollerStyleLegacy];
                    [[scroll documentView] scrollPoint:NSMakePoint(0, 40)];
                    [scroll tile]; [scroll reflectScrolledClipView:[scroll contentView]];
                }
                Pump();
                [self nv_checkScrollbarPixels:notesScrollView];
                [self nv_checkScrollbarPixels:textScrollView];
                [self nv_checkHeaderCornerPixels];
                [self nv_captureViewControls:[NSString stringWithFormat:@"adaptive-scrollbars-%@-%@.png",
                    [appearance isEqual:NSAppearanceNameAqua] ? @"dark-body" : @"light-body", [side boolValue] ? @"side" : @"stacked"]];
                // The notes list supports native overlay behavior; the source scrollbar retains its legacy style.
                [notesScrollView setScrollerStyle:NSScrollerStyleOverlay];
                [notesScrollView flashScrollers];
                for (NSUInteger tick = 0; tick < 6; tick++) Pump();
                [self nv_checkScrollbarPixels:notesScrollView];
                [notesScrollView setScrollerStyle:NSScrollerStyleLegacy];
                [prefsController setUseETScrollbarsOnLion:NO sender:nil];
                for (NSNumber *style in @[@(NSScrollerStyleLegacy), @(NSScrollerStyleOverlay)]) {
                    for (NSScrollView *scroll in @[notesScrollView, textScrollView]) {
                        [scroll setScrollerStyle:[style integerValue]];
                        [scroll tile]; [scroll reflectScrolledClipView:[scroll contentView]];
                        [scroll flashScrollers];
                    }
                    for (NSUInteger tick = 0; tick < 6; tick++) Pump();
                    [self nv_checkNativeScrollbarPair];
                    if ([style integerValue] == NSScrollerStyleLegacy)
                        [self nv_captureViewControls:[NSString stringWithFormat:@"native-scrollbars-%@-%@.png",
                            [appearance isEqual:NSAppearanceNameAqua] ? @"dark-body" : @"light-body", [side boolValue] ? @"side" : @"stacked"]];
                }
                [prefsController setUseETScrollbarsOnLion:YES sender:nil];
            }
            [peer nv_activateBrowser];
            for (NSScrollView *scroll in @[[peer valueForKey:@"notesScrollView"], [peer valueForKey:@"textScrollView"]]) {
                [scroll setScrollerStyle:NSScrollerStyleLegacy];
                [scroll tile]; [scroll reflectScrolledClipView:[scroll contentView]];
                [peer nv_checkScrollbarPixels:scroll];
            }
            [peer nv_checkHeaderCornerPixels];
            [prefsController setUseETScrollbarsOnLion:NO sender:nil];
            for (NSScrollView *scroll in @[[peer valueForKey:@"notesScrollView"], [peer valueForKey:@"textScrollView"]]) {
                [scroll setScrollerStyle:NSScrollerStyleLegacy]; [scroll tile];
            }
            [peer nv_checkNativeScrollbarPair];
            [prefsController setUseETScrollbarsOnLion:YES sender:nil];
            [self nv_activateBrowser];
        }
        NSScroller *existing = [[textScrollView verticalScroller] retain];
        [prefsController setDarkBackgroundTextColor:ink sender:nil];
        Check([textScrollView verticalScroller] == existing,
            @"live palette changes preserve the existing scrollbar");
        Pump(); [self nv_checkScrollbarPixels:textScrollView]; [existing release];
        [self setHorizontalLayout:NO];
        [self nv_checkHeaderCornerPixels];
        [toggle setState:NSControlStateValueOff]; [toggle sendAction:[toggle action] to:[toggle target]];
        for (AppController *browser in @[self, peer]) {
            for (NSString *key in @[@"notesScrollView", @"textScrollView"])
                Check([[[browser valueForKey:key] verticalScroller] class] == [NSScroller class],
                    @"disabling custom scrollbars restores standard macOS scrollers in every browser");
            for (NSString *key in @[@"notesScrollView", @"textScrollView"]) {
                NSScrollView *scroll = [browser valueForKey:key];
                [scroll setScrollerStyle:NSScrollerStyleLegacy]; [scroll tile];
            }
            [browser nv_activateBrowser];
            [browser nv_checkHeaderCornerPixels];
            [browser nv_checkNativeScrollbarPair];
        }
        [self nv_activateBrowser];
        NSScroller *nativeScroller = [[textScrollView verticalScroller] retain];
        [prefsController setDarkBackgroundTextColor:paper sender:nil];
        Check([textScrollView verticalScroller] == nativeScroller,
            @"live palette changes preserve the existing native scrollbar");
        [self nv_checkNativeScrollbarPair];
        NSScroller *nativeListScroller = [[notesScrollView verticalScroller] retain];
        for (NSNumber *style in @[@(NSScrollerStyleLegacy), @(NSScrollerStyleOverlay)]) {
            for (NSScrollView *scroll in @[notesScrollView, textScrollView])
                [scroll setScrollerStyle:[style integerValue]];
            for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                [window setAppearance:[NSAppearance appearanceNamed:appearance]];
                Pump();
                Check([notesScrollView verticalScroller] == nativeListScroller && [textScrollView verticalScroller] == nativeScroller,
                    @"live window appearance changes preserve both native scrollbars");
                [notesScrollView flashScrollers]; [textScrollView flashScrollers];
                for (NSUInteger tick = 0; tick < 6; tick++) Pump();
                [self nv_checkNativeScrollbarPair];
            }
        }
        [nativeListScroller release]; [nativeScroller release];
        [prefsController setUseETScrollbarsOnLion:YES sender:nil];
        [self nv_checkScrollbarPixels:textScrollView];
        Check([[textView string] isEqual:longBody] && [[[peer valueForKey:@"textView"] string] isEqual:longBody],
            @"palette and scrollbar changes preserve the shared source");
        [textView insertText:source replacementRange:NSMakeRange(0, [[textView string] length])]; [source release];
        [library removeNotes:filler];
        [prefsController setUseETScrollbarsOnLion:oldCustom sender:nil];
        [prefsController setBackgroundTextColor:oldLightBG sender:nil]; [oldLightBG release];
        [prefsController setDarkBackgroundTextColor:oldDarkBG sender:nil]; [oldDarkBG release];
        [prefsController setForegroundTextColor:oldLightFG sender:nil]; [oldLightFG release];
        [prefsController setDarkForegroundTextColor:oldDarkFG sender:nil]; [oldDarkFG release];
        [window setAppearance:oldAppearance]; [oldAppearance release];
        [[peer window] setAppearance:oldPeerAppearance]; [oldPeerAppearance release];
        [self setSystemColorScheme:self]; [peer setSystemColorScheme:peer];
        [self setHorizontalLayout:NO]; [window setFrame:oldFrame display:YES];
        [self searchForString:@"al" mode:@"exact"]; [self revealNote:alpha options:0];
        [peer searchForString:@"Beta"]; [peer revealNote:beta options:0]; Pump();
    }
}
