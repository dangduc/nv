#import <AppKit/AppKit.h>

// Ask the same system service used for Finder icons, without launching the app.
static NSData *RenderIcon(NSString *path, NSString *output) {
    NSImage *image = [[NSWorkspace sharedWorkspace] iconForFile:path];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:512 pixelsHigh:512
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
    [[NSColor clearColor] set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, 512, 512), NSCompositingOperationCopy);
    [image drawInRect:NSMakeRect(0, 0, 512, 512) fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:output atomically:YES];
    return [NSData dataWithBytes:[bitmap bitmapData] length:[bitmap bytesPerRow] * [bitmap pixelsHigh]];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NSMutableDictionary *images = [NSMutableDictionary dictionary];
        for (NSString *name in @[@"Hybrid", @"Classic", @"Modern"]) {
            NSString *path = [directory stringByAppendingPathComponent:[name stringByAppendingString:@".app"]];
            NSString *output = [directory stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
            images[name] = RenderIcon(path, output);
        }
        NSInteger major = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        NSString *expected = major >= 26 ? @"Modern" : @"Classic";
        if ([images[@"Classic"] isEqual:images[@"Modern"]]) {
            fprintf(stderr, "FAIL: control icons are identical; the probe cannot distinguish designs.\n");
            return 1;
        }
        if (![images[@"Hybrid"] isEqual:images[expected]]) {
            fprintf(stderr, "FAIL: macOS %ld did not select %s.\n", (long)major, [expected UTF8String]);
            return 1;
        }
        printf("PASS: macOS %ld selects %s through NSWorkspace.\n", (long)major, [expected UTF8String]);
    }
    return 0;
}
