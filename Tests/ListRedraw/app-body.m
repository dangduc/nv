
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        for (NSUInteger i = 0; i < 24; i++)
            MakeNote(library, [NSString stringWithFormat:@"Note %02lu — repeated redraw", (unsigned long)i], @"plain source");
        [self searchForString:@""]; Pump();
        [[GlobalPrefs defaultPrefs] setShowNotesList:YES sender:nil];
        [self.window setContentSize:NSMakeSize(520, 620)];
        [notesTableView deselectAll:self];
        [self.window makeFirstResponder:field];
        Check(notesScrollView.drawsBackground && notesScrollView.contentView.drawsBackground,
            @"the production scroll and clip views paint their background");
        if (getenv("NV_LIST_OPAQUE_NEGATIVE")) {
            Check(class_addMethod([NotesTableView class], @selector(isOpaque), (IMP)OpaqueForNegativeControl,
                method_getTypeEncoding(class_getInstanceMethod([NSTableView class], @selector(isOpaque)))),
                @"negative control installs a local opacity override");
        }
        NSString *output = [[NSString stringWithUTF8String:getenv("NV_REVIEW_CAPTURE")] stringByDeletingLastPathComponent];
        if (@available(macOS 10.14, *)) {
            for (NSString *appearance in @[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]) {
                [self.window setAppearance:[NSAppearance appearanceNamed:appearance]];
                [NSAppearance setCurrentAppearance:self.window.effectiveAppearance];
                for (NSNumber *alternating in @[@YES, @NO]) {
                    [[GlobalPrefs defaultPrefs] setAlternatingRows:alternating.boolValue sender:nil];
                    [self setNotesListHeight:350]; Pump();
                    [self.window display];
                    NSRect rect = NSMakeRect(0, 0, NSWidth(notesTableView.bounds), 280);
                    NSView *capture = [notesTableView opaqueAncestor];
                    Check(capture != nil, @"native drawing has an opaque ancestor");
                    NSRect captureRect = [notesTableView convertRect:rect toView:capture];
                    NSBitmapImageRep *bitmap = [capture bitmapImageRepForCachingDisplayInRect:captureRect];
                    [capture cacheDisplayInRect:captureRect toBitmapImageRep:bitmap];
                    NSData *first = [[Pixels(bitmap) copy] autorelease];
                    for (NSUInteger i = 1; i <= 100; i++) {
                        [self setNotesListHeight:i % 2 ? 320 : 350];
                        [notesTableView setNeedsDisplay:YES];
                        [self.window displayIfNeeded];
                        [capture cacheDisplayInRect:captureRect toBitmapImageRep:bitmap];
                    }
                    NSString *name = [NSString stringWithFormat:@"%@-%@.png", appearance, alternating.boolValue ? @"alternating" : @"plain"];
                    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                        writeToFile:[output stringByAppendingPathComponent:name] atomically:YES], @"save the final native list capture");
                    NSLog(@"LIST REDRAW appearance=%@ alternating=%@ ancestor=%@", appearance, alternating, NSStringFromClass(capture.class));
                    Check([first isEqual:Pixels(bitmap)], @"repeated redraw preserves every captured pixel");
                    CGFloat scale = bitmap.pixelsWide / NSWidth(rect);
                    for (NSInteger row = 1; row <= 2; row++) {
                        NSColor *color = [[bitmap colorAtX:4 y:(NSInteger)(NSMidY([notesTableView rectOfRow:row]) * scale)]
                            colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                        CGFloat brightness = .2126 * color.redComponent + .7152 * color.greenComponent + .0722 * color.blueComponent;
                        Check(color.alphaComponent > .99, @"row backgrounds remain opaque");
                        Check([appearance isEqual:NSAppearanceNameDarkAqua] ? brightness < .3 : brightness > .85,
                            @"row backgrounds retain their system appearance");
                    }
                }
            }
        } else {
            NSLog(@"SKIP: Dark Aqua requires macOS 10.14 or later");
        }
        NSLog(@"LIST REDRAW TESTS PASSED (%lu)", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@", exception); exit(1); }
}
@end
