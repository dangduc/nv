// Included after Check() in the native UI probe. Capture the containing view so
// translucent native row fills composite over the actual scroll-view content.
static void CheckNativeListAppearance(NSTableView *table, NSString *appearance) {
    if (@available(macOS 10.14, *)) {
        NSScrollView *scroll = [table enclosingScrollView];
        NSClipView *clip = [scroll contentView];
        Check(scroll != nil && clip != nil, @"list appearance checks include the scroll and clip views");
        NSArray *views = @[table, scroll, clip];
        NSArray *backgrounds = @[[table backgroundColor], [scroll backgroundColor], [clip backgroundColor]];
        BOOL dark = [appearance isEqual:NSAppearanceNameDarkAqua];
        for (NSUInteger index = 0; index < [views count]; index++) {
            NSView *view = [views objectAtIndex:index];
            NSAppearance *effective = [view effectiveAppearance];
            Check([[effective bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:appearance],
                @"the table, scroll view, and clip view inherit the window appearance");
            NSAppearance *previous = [[NSAppearance currentAppearance] retain];
            CGFloat brightness = 0;
            @try {
                [NSAppearance setCurrentAppearance:effective];
                NSColor *resolved = [[backgrounds objectAtIndex:index] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
                Check(resolved != nil, @"list backgrounds resolve to measurable colors");
                brightness = [resolved whiteComponent];
            } @finally {
                [NSAppearance setCurrentAppearance:previous];
                [previous release];
            }
            Check(dark ? brightness < .3 : brightness > .85,
                @"the table, scroll view, and clip view backgrounds match the window appearance");
        }
    }
}

static void CheckNativeListRowPixels(NSTableView *table, NSInteger row, NSInteger titleColumn, NSString *appearance) {
    NSRect tableRow = [table rectOfRow:row];
    Check(![[table selectedRowIndexes] containsIndex:row] && !NSIsEmptyRect(tableRow) &&
        NSContainsRect([table visibleRect], tableRow), @"list pixel sample contains a complete unselected populated row");
    NSView *captureView = [[table window] contentView];
    NSRect rect = [table convertRect:tableRow toView:captureView];
    NSRect title = [table convertRect:[table frameOfCellAtColumn:titleColumn row:row] toView:captureView];
    NSBitmapImageRep *bitmap = [captureView bitmapImageRepForCachingDisplayInRect:rect];
    [captureView cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    BOOL dark = NO;
    if (@available(macOS 10.14, *)) dark = [appearance isEqual:NSAppearanceNameDarkAqua];
    NSUInteger opaque = 0, backgroundPixels = 0, titlePixels = 0, histogram[256] = {0};
    CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if (!pixel || [pixel alphaComponent] < .95) continue;
            CGFloat brightness = .2126 * [pixel redComponent] + .7152 * [pixel greenComponent] + .0722 * [pixel blueComponent];
            histogram[(NSUInteger)round(MAX(0, MIN(1, brightness)) * 255)]++;
            opaque++;
            if (dark ? brightness < .3 : brightness > .85) backgroundPixels++;
            CGFloat localX = x / scale + NSMinX(rect);
            // Exclude row edges and grid lines from the title glyph sample.
            if (localX >= NSMinX(title) + 4 && localX < MIN(NSMaxX(title) - 4, NSMinX(title) + 200) &&
                y >= 2 * scale && y < [bitmap pixelsHigh] - 2 * scale &&
                (dark ? brightness > .65 : brightness < .3)) titlePixels++;
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
    Check(total > 1000 && opaqueFraction > .99 && (dark ? median / 255.0 < .3 : median / 255.0 > .85) && backgroundFraction > .7,
        @"unselected note rows show light backgrounds in Aqua and dark backgrounds in Dark Aqua");
    Check(titlePixels > 10, @"note rows contain title glyph pixels that contrast with the window appearance");
}
