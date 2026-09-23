#include "../native-list/pixels.inc"

- (void)nv_checkHeaderColors {
    NSTableHeaderView *header = [notesTableView headerView];
    if (!header) return;
    [header setNeedsDisplay:YES]; [window displayIfNeeded];
    NSView *capture = [window contentView];
    for (NSUInteger index = 0; index < [[notesTableView tableColumns] count]; index++) {
        NSRect frame = NSIntersectionRect([header headerRectOfColumn:index], [header visibleRect]);
        NSRect rect = [header convertRect:frame toView:capture];
        NSBitmapImageRep *bitmap = [capture bitmapImageRepForCachingDisplayInRect:rect];
        [capture cacheDisplayInRect:rect toBitmapImageRep:bitmap];
        NSUInteger backgroundPixels = 0, textPixels = 0, indicatorPixels = 0, total = 0;
        NSTableColumn *column = [[notesTableView tableColumns] objectAtIndex:index];
        NSRect indicator = [[column headerCell] sortIndicatorRectForBounds:frame];
        NSColor *headerBackground = [bitmap colorAtX:[bitmap pixelsWide] / 2 y:2];
        CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
        for (NSInteger y = 2; y < [bitmap pixelsHigh] - 2; y++) {
            for (NSInteger x = 3; x < [bitmap pixelsWide] - 3; x++) {
                NSColor *pixel = [bitmap colorAtX:x y:y];
                total++;
                if (ListPixelDistance(pixel, [self backgrndColor], [bitmap colorSpace]) < .15) backgroundPixels++;
                if (x < MIN([bitmap pixelsWide] - 16 * scale, 110 * scale) &&
                    ListPixelDistance(pixel, [self foregrndColor], [bitmap colorSpace]) < .10) textPixels++;
                NSPoint point = NSMakePoint(NSMinX(frame) + x / scale, NSMinY(frame) + y / scale);
                if (NSPointInRect(point, NSInsetRect(indicator, -1, -1)) && ListColorDistance(pixel, headerBackground) > .15) indicatorPixels++;
            }
        }
        NSLog(@"HEADER_PIXELS column=%lu body_background_fraction=%.3f text_pixels=%lu",
            (unsigned long)index, total ? (double)backgroundPixels / total : 0, (unsigned long)textPixels);
        Check(total > 100 && backgroundPixels > total * .7, @"column header backgrounds follow the body palette");
        Check(textPixels > 10, @"column titles use the body foreground color");
        if (column == [notesTableView highlightedTableColumn])
            Check(indicatorPixels > 3, @"the sorted column retains a visible native sort indicator");
    }
}

- (void)nv_checkSelectedListPixels {
    [notesTableView setNeedsDisplay:YES]; [window displayIfNeeded];
    NSRect rowRect = NSIntersectionRect([notesTableView rectOfRow:0], [notesTableView visibleRect]);
    NSView *capture = [window contentView];
    NSRect rect = [notesTableView convertRect:rowRect toView:capture];
    NSBitmapImageRep *bitmap = [capture bitmapImageRepForCachingDisplayInRect:rect];
    [capture cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    NSColor *background = [bitmap colorAtX:4 y:[bitmap pixelsHigh] / 2];
    Check(ListPixelDistance(background, [self backgrndColor], [bitmap colorSpace]) > .05,
        @"native selection remains visible against the body palette");
    CGFloat foreground = [[[self foregrndColor] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent];
    __block NSColor *text = nil;
    if (@available(macOS 11.0, *)) {
        [[notesTableView effectiveAppearance] performAsCurrentDrawingAppearance:^{
            NSTextFieldCell *cell = (NSTextFieldCell *)[notesTableView preparedCellAtColumn:0 row:0];
            text = [[[cell textColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace] retain];
        }];
    }
    NSUInteger glyphs = 0;
    for (NSInteger y = 2; y < MIN([bitmap pixelsHigh] - 2, 18); y++)
        for (NSInteger x = 5; x < MIN([bitmap pixelsWide], 90); x++)
            if (ListPixelDistance([bitmap colorAtX:x y:y], text, [bitmap colorSpace]) < .15 &&
                ListColorDistance([bitmap colorAtX:x y:y], background) > .25) glyphs++;
    NSLog(@"SELECTED_LIST_PIXELS body_foreground=%.3f selection=%@ text=%@ glyphs=%lu",
        foreground, background, text, (unsigned long)glyphs);
    Check(glyphs > 10, @"selected title glyphs contrast with the native selection in both layouts");
    [text release];
}

- (void)nv_checkListColorsWithPeer:(AppController *)peer alpha:(NoteObject *)alpha beta:(NoteObject *)beta {
    if (@available(macOS 11.0, *)) {
        NSRect oldFrame = [window frame];
        NSAppearance *oldAppearance = [[window appearance] retain];
        NSAppearance *oldPeerAppearance = [[[peer window] appearance] retain];
        NSColor *oldLightBG = [[prefsController backgroundTextColor] retain];
        NSColor *oldDarkBG = [[prefsController darkBackgroundTextColor] retain];
        NSColor *oldLightFG = [[prefsController foregroundTextColor] retain];
        NSColor *oldDarkFG = [[prefsController darkForegroundTextColor] retain];
        BOOL oldAlternating = [prefsController alternatingRows];
        NSAttributedString *source = [[alpha contentString] copy];
        // Deliberately oppose the window themes, including the default peach paper.
        NSColor *ink = [NSColor colorWithSRGBRed:.10 green:.16 blue:.22 alpha:1];
        NSColor *paper = [NSColor colorWithSRGBRed:253/255.0 green:233/255.0 blue:217/255.0 alpha:1];
        [prefsController setBackgroundTextColor:ink sender:nil];
        [prefsController setForegroundTextColor:[NSColor colorWithSRGBRed:.88 green:.94 blue:1 alpha:1] sender:nil];
        [prefsController setDarkBackgroundTextColor:paper sender:nil];
        [prefsController setDarkForegroundTextColor:[NSColor colorWithSRGBRed:.18 green:.08 blue:.03 alpha:1] sender:nil];
        [self setUserColorScheme:self]; [peer setUserColorScheme:peer];
        BOOL allowsEmptySelection = [notesTableView allowsEmptySelection];
        [notesTableView setAllowsEmptySelection:YES];
        NSRect frame = oldFrame; frame.size = NSMakeSize(950, 620); [window setFrame:frame display:YES];
        [self searchForString:@""]; Pump();
        for (NSString *appearance in @[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]) {
            [window setAppearance:[NSAppearance appearanceNamed:appearance]];
            [[peer window] setAppearance:[NSAppearance appearanceNamed:[appearance isEqual:NSAppearanceNameAqua] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
            Pump(); [self nv_activateBrowser];
            NSColor *peerBackground = [[[peer valueForKey:@"notesTableView"] backgroundColor] retain];
            for (NSNumber *side in @[@NO, @YES]) {
                [self searchForString:@""]; Pump();
                [self setHorizontalLayout:[side boolValue]]; [self setNotesListHeight:[side boolValue] ? 320 : 180];
                for (NSNumber *alternate in @[@YES, @NO]) {
                    [prefsController setAlternatingRows:[alternate boolValue] sender:nil];
                    [notesTableView deselectAll:self]; Pump();
                    CheckNativeListAppearance(notesTableView, appearance);
                    [self nv_checkHeaderColors];
                    NSInteger titleColumn = [notesTableView columnWithIdentifier:NoteTitleColumnString];
                    for (NSInteger row = 0; row < 2; row++) CheckNativeListRowPixels(notesTableView, row, titleColumn, appearance);
                }
                [prefsController setAlternatingRows:YES sender:nil];
                [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                [window makeFirstResponder:notesTableView]; Pump();
                [self nv_checkSelectedListPixels];
                [self focusNoteBody]; Pump();
                [self nv_checkSelectedListPixels];
                [peer nv_activateBrowser]; Pump();
                [self nv_checkSelectedListPixels];
                [self nv_activateBrowser];
                Check(ListColorDistance([[peer valueForKey:@"notesTableView"] backgroundColor], peerBackground) < .01 &&
                    ListColorDistance(peerBackground, [self backgrndColor]) > .5,
                    @"opposite browser appearances retain independent list palettes");
                [self searchForString:@"alpha" mode:@"fuzzy"];
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
                while (![[self browserSession] searchResultsAreCurrent] && [deadline timeIntervalSinceNow] > 0) Pump();
                Check([[self browserSession] resultCount] == 2, @"custom list colors retain separate fuzzy title and body matches");
                for (NSUInteger row = 0; row < 2; row++) {
                    __block BOOL highlighted = NO;
                    deadline = [NSDate dateWithTimeIntervalSinceNow:5];
                    do {
                        NSAttributedString *preview = [[self browserSession] previewForRow:row inTable:notesTableView];
                        [preview enumerateAttribute:NSBackgroundColorAttributeName inRange:NSMakeRange(0, [preview length])
                            options:0 usingBlock:^(id color, NSRange range, BOOL *stop) { if (color) highlighted = YES; }];
                        if (!highlighted) Pump();
                    } while (!highlighted && [deadline timeIntervalSinceNow] > 0);
                    Check(highlighted, @"fuzzy row highlights survive custom palettes in both layouts");
                }
                [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
                [self focusNoteBody]; Pump();
                [self nv_captureViewControls:[NSString stringWithFormat:@"adaptive-list-%@-%@.png",
                    [appearance isEqual:NSAppearanceNameAqua] ? @"dark-body" : @"light-body", [side boolValue] ? @"side" : @"stacked"]];
            }
            [peerBackground release];
        }
        Check([[alpha contentString] isEqual:source], @"list color and layout changes preserve the shared note source");
        [source release];
        [prefsController setBackgroundTextColor:oldLightBG sender:nil]; [oldLightBG release];
        [prefsController setDarkBackgroundTextColor:oldDarkBG sender:nil]; [oldDarkBG release];
        [prefsController setForegroundTextColor:oldLightFG sender:nil]; [oldLightFG release];
        [prefsController setDarkForegroundTextColor:oldDarkFG sender:nil]; [oldDarkFG release];
        [prefsController setAlternatingRows:oldAlternating sender:nil];
        [window setAppearance:oldAppearance]; [oldAppearance release];
        [[peer window] setAppearance:oldPeerAppearance]; [oldPeerAppearance release];
        [self setSystemColorScheme:self]; [peer setSystemColorScheme:peer];
        [notesTableView setAllowsEmptySelection:allowsEmptySelection];
        [self setHorizontalLayout:NO]; [window setFrame:oldFrame display:YES];
        [self searchForString:@"al" mode:@"exact"]; [self revealNote:alpha options:0];
        [peer searchForString:@"Beta"]; [peer revealNote:beta options:0]; Pump();
    }
}
