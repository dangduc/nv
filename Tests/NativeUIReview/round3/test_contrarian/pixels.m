#import <Cocoa/Cocoa.h>

NSDictionary *NVMeasureRowPixels(NSTableView *table, NSInteger row, NSInteger titleColumn, NSString *name) {
    NSRect rect = [table rectOfRow:row];
    NSRect cell = [table frameOfCellAtColumn:titleColumn row:row];
    if (NSIsEmptyRect(rect) || !NSContainsRect([table visibleRect], rect)) {
        NSLog(@"FAIL: pixel capture requires a complete visible note row"); exit(1);
    }
    NSBitmapImageRep *bitmap = [table bitmapImageRepForCachingDisplayInRect:rect];
    [table cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    NSUInteger opaque = 0, pale = 0, darkInk = 0, lightInk = 0;
    NSUInteger histogram[256] = {0};
    CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if (!pixel || [pixel alphaComponent] < .95) continue;
            CGFloat luminance = .2126 * [pixel redComponent] + .7152 * [pixel greenComponent] + .0722 * [pixel blueComponent];
            histogram[(NSUInteger)round(MAX(0, MIN(1, luminance)) * 255)]++;
            opaque++;
            if (luminance > .85) pale++;
            CGFloat localX = x / scale + NSMinX(rect);
            if (localX >= NSMinX(cell) + 4 && localX < MIN(NSMaxX(cell) - 4, NSMinX(cell) + 180)) {
                if (luminance < .3) darkInk++;
                if (luminance > .7) lightInk++;
            }
        }
    }
    NSUInteger cumulative = 0, median = 0;
    for (; median < 255; median++) {
        cumulative += histogram[median];
        if (cumulative >= opaque / 2) break;
    }
    const char *artifacts = getenv("NV_R3_ARTIFACTS");
    if (artifacts) {
        NSString *path = [[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
        if (![[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]) {
            NSLog(@"FAIL: row bitmap artifact writes successfully"); exit(1);
        }
    }
    NSDictionary *result = @{@"opaque": @(opaque), @"paleFraction": @(opaque ? (double)pale / opaque : 0),
        @"medianBrightness": @(median / 255.0), @"darkTitlePixels": @(darkInk), @"lightTitlePixels": @(lightInk)};
    NSLog(@"ROW_PIXELS %@ %@", name, result);
    return result;
}
