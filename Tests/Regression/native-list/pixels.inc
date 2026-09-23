// Capture the containing view to include the scroll-view backing and native selection.
static CGFloat ListColorDistance(NSColor *left, NSColor *right) {
    left = [left colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    right = [right colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return MAX(fabs([left redComponent] - [right redComponent]),
        MAX(fabs([left greenComponent] - [right greenComponent]), fabs([left blueComponent] - [right blueComponent])));
}

static CGFloat ListPixelDistance(NSColor *pixel, NSColor *color, NSColorSpace *space) {
    // colorAtX:y: exposes the captured channel values as calibrated RGB.
    // Compare them with the expected color converted to the bitmap's profile.
    pixel = [pixel colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    color = [color colorUsingColorSpace:space];
    return MAX(fabs([pixel redComponent] - [color redComponent]),
        MAX(fabs([pixel greenComponent] - [color greenComponent]), fabs([pixel blueComponent] - [color blueComponent])));
}

static void CheckNativeListAppearance(NSTableView *table, NSString *appearance) {
    if (@available(macOS 10.14, *)) {
        NSScrollView *scroll = [table enclosingScrollView];
        NSClipView *clip = [scroll contentView];
        Check(scroll != nil && clip != nil, @"list appearance checks include the scroll and clip views");
        NSArray *views = @[table, scroll, clip];
        NSArray *backgrounds = @[[table backgroundColor], [scroll backgroundColor], [clip backgroundColor]];
        NSColor *body = [(AppController *)[table delegate] backgrndColor];
        BOOL dark = [[body colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent] < .5;
        NSString *expectedAppearance = dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
        for (NSUInteger index = 0; index < [views count]; index++) {
            NSView *view = [views objectAtIndex:index];
            NSAppearance *effective = [view effectiveAppearance];
            Check([[effective bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:expectedAppearance],
                @"the table, scroll view, and clip view adapt their native appearance to body brightness");
            NSAppearance *previous = [[NSAppearance currentAppearance] retain];
            @try {
                [NSAppearance setCurrentAppearance:effective];
                NSColor *resolved = [[backgrounds objectAtIndex:index] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
                Check(resolved != nil, @"list backgrounds resolve to measurable colors");
                Check(ListColorDistance(backgrounds[index], body) < .01,
                    @"the table, scroll view, and clip view use the body background");
            } @finally {
                [NSAppearance setCurrentAppearance:previous];
                [previous release];
            }
        }
    }
}

static void CheckNativeListRowPixels(NSTableView *table, NSInteger row, NSInteger titleColumn, NSString *appearance) {
    NSRect tableRow = NSIntersectionRect([table rectOfRow:row], [table visibleRect]);
    Check(![[table selectedRowIndexes] containsIndex:row] && !NSIsEmptyRect(tableRow) &&
        NSHeight(tableRow) >= [table rowHeight], @"list pixel sample contains the visible width and full height of an unselected row");
    NSView *captureView = [[table window] contentView];
    NSRect rect = [table convertRect:tableRow toView:captureView];
    NSRect title = [table convertRect:[table frameOfCellAtColumn:titleColumn row:row] toView:captureView];
    NSBitmapImageRep *bitmap = [captureView bitmapImageRepForCachingDisplayInRect:rect];
    [captureView cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    NSColor *background = [(AppController *)[table delegate] backgrndColor];
    NSColor *foreground = [(AppController *)[table delegate] foregrndColor];
    BOOL dark = [[background colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent] < .5;
    if ([table usesAlternatingRowBackgroundColors] && row % 2)
        background = [background blendedColorWithFraction:.05 ofColor:dark ? [NSColor whiteColor] : [NSColor blackColor]];
    NSUInteger opaque = 0, backgroundPixels = 0, titlePixels = 0, histogram[256] = {0};
    CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if (!pixel || [pixel alphaComponent] < .95) continue;
            CGFloat brightness = .2126 * [pixel redComponent] + .7152 * [pixel greenComponent] + .0722 * [pixel blueComponent];
            histogram[(NSUInteger)round(MAX(0, MIN(1, brightness)) * 255)]++;
            opaque++;
            if (ListPixelDistance(pixel, background, [bitmap colorSpace]) < .025) backgroundPixels++;
            CGFloat localX = x / scale + NSMinX(rect);
            // Exclude row edges and grid lines from the title glyph sample.
            if (localX >= NSMinX(title) + 4 && localX < MIN(NSMaxX(title) - 4, NSMinX(title) + 200) &&
                y >= 2 * scale && y < [bitmap pixelsHigh] - 2 * scale &&
                ListPixelDistance(pixel, foreground, [bitmap colorSpace]) < .15) titlePixels++;
        }
    }
    NSUInteger cumulative = 0, median = 0;
    for (; median < 255; median++) {
        cumulative += histogram[median];
        if (cumulative >= opaque / 2) break;
    }
    NSUInteger total = [bitmap pixelsWide] * [bitmap pixelsHigh];
    CGFloat opaqueFraction = total ? (CGFloat)opaque / total : 0;
    CGFloat backgroundFraction = opaque ? (CGFloat)backgroundPixels / opaque : 0;
    NSLog(@"NATIVE_LIST_PIXELS appearance=%@ row=%ld pixels=%lu opaque_fraction=%.4f median=%.4f background_fraction=%.4f title_pixels=%lu",
        appearance, (long)row, (unsigned long)total, opaqueFraction, median / 255.0, backgroundFraction, (unsigned long)titlePixels);
    const char *artifacts = getenv("NV_UI_ARTIFACTS");
    if (artifacts) {
        NSString *name = [NSString stringWithFormat:@"native-list-%@-row-%ld.png", appearance, (long)row];
        NSString *path = [[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:name];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
            @"native list row bitmap artifact writes successfully");
    }
    Check(total > 1000 && opaqueFraction > .99 && backgroundFraction > .7,
        @"unselected row pixels match the body background and its alternating shade");
    Check(titlePixels > 10, @"note title glyphs use the body foreground color");
}
