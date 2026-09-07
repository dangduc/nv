// Included after Check() in the native UI probe. Capture the containing view so
// translucent native row fills composite over the actual scroll-view content.
static void CheckNativeListRowPixels(NSTableView *table, NSInteger row, NSInteger titleColumn, NSString *appearance) {
    NSRect tableRow = [table rectOfRow:row];
    Check(![[table selectedRowIndexes] containsIndex:row] && !NSIsEmptyRect(tableRow) &&
        NSContainsRect([table visibleRect], tableRow), @"list pixel sample contains a complete unselected populated row");
    NSView *captureView = [[table window] contentView];
    NSRect rect = [table convertRect:tableRow toView:captureView];
    NSRect title = [table convertRect:[table frameOfCellAtColumn:titleColumn row:row] toView:captureView];
    NSBitmapImageRep *bitmap = [captureView bitmapImageRepForCachingDisplayInRect:rect];
    [captureView cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    NSUInteger opaque = 0, pale = 0, darkTitlePixels = 0, histogram[256] = {0};
    CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if (!pixel || [pixel alphaComponent] < .95) continue;
            CGFloat brightness = .2126 * [pixel redComponent] + .7152 * [pixel greenComponent] + .0722 * [pixel blueComponent];
            histogram[(NSUInteger)round(MAX(0, MIN(1, brightness)) * 255)]++;
            opaque++;
            if (brightness > .85) pale++;
            CGFloat localX = x / scale + NSMinX(rect);
            // Exclude row edges and grid lines from the title glyph sample.
            if (localX >= NSMinX(title) + 4 && localX < MIN(NSMaxX(title) - 4, NSMinX(title) + 200) &&
                y >= 2 * scale && y < [bitmap pixelsHigh] - 2 * scale && brightness < .3) darkTitlePixels++;
        }
    }
    NSUInteger cumulative = 0, median = 0;
    for (; median < 255; median++) {
        cumulative += histogram[median];
        if (cumulative >= opaque / 2) break;
    }
    NSUInteger total = [bitmap pixelsWide] * [bitmap pixelsHigh];
    CGFloat opaqueFraction = total ? (CGFloat)opaque / total : 0;
    CGFloat paleFraction = opaque ? (CGFloat)pale / opaque : 0;
    NSLog(@"NATIVE_LIST_PIXELS appearance=%@ row=%ld pixels=%lu opaque_fraction=%.4f median=%.4f pale_fraction=%.4f dark_title_pixels=%lu",
        appearance, (long)row, (unsigned long)total, opaqueFraction, median / 255.0, paleFraction, (unsigned long)darkTitlePixels);
    const char *artifacts = getenv("NV_UI_ARTIFACTS");
    if (artifacts) {
        NSString *name = [NSString stringWithFormat:@"native-list-%@-row-%ld.png", appearance, (long)row];
        NSString *path = [[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:name];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
            @"native list row bitmap artifact writes successfully");
    }
    Check(total > 1000 && opaqueFraction > .99 && median / 255.0 > .85 && paleFraction > .7,
        @"unselected alternating note rows retain a pale rendered background under the window appearance");
    Check(darkTitlePixels > 10, @"the pale note rows contain visible dark title glyph pixels");
}
