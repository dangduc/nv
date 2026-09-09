#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NSBezierPath_NV.h"

static float fixtureFont = 15;
@interface GlobalPrefs : NSObject
+ (id)defaultPrefs;
- (float)tableFontSize;
@end
@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (float)tableFontSize { return fixtureFont; }
@end

@interface NativeLabels : NSObject {
    NSMutableDictionary *labelImages;
    NSCountedSet *allLabels, *filteredLabels;
}
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)highlighted;
- (void)invalidateCachedLabelImages;
- (NSUInteger)cacheCount;
@end
@implementation NativeLabels
#include "production.inc"
- (NSUInteger)cacheCount { return labelImages.count; }
@end

static unsigned checks, releasedImages;
static char witnessKey;
@interface ReleaseWitness : NSObject @end
@implementation ReleaseWitness
- (void)dealloc { releasedImages++; [super dealloc]; }
@end
static void ObserveRelease(id object) {
    ReleaseWitness *witness = [[ReleaseWitness alloc] init];
    objc_setAssociatedObject(object, &witnessKey, witness, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [witness release];
}
static void Check(BOOL result, const char *description) {
    if (!result) { fprintf(stderr, "FAIL: %s\n", description); exit(1); }
    checks++;
}
static NSBitmapImageRep *Bitmap(NSSize size) {
    return [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:(NSInteger)size.width pixelsHigh:(NSInteger)size.height
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
}
static NSColor *fixtureColor;
static NSColor *InjectedColor(id receiver, SEL command) { return fixtureColor; }

static void CheckGlyphRemoval(NSImage *image, NSString *word, CGFloat expectedAlpha) {
    NSSize size = image.size;
    // lockFocus follows the display backing scale. Build the independent opaque
    // glyph mask on that same surface before comparing native bitmap pixels.
    NSImage *maskImage = [[[NSImage alloc] initWithSize:size] autorelease];
    [maskImage lockFocus];
    [word drawWithRect:NSMakeRect(2, 3, size.width, size.height)
        options:NSStringDrawingUsesFontLeading attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:fixtureFont - 1],
            NSForegroundColorAttributeName: [NSColor blackColor]}];
    [maskImage unlockFocus];
    NSImageRep *sourceRep = [[image representations] objectAtIndex:0];
    NSImageRep *maskRep = [[maskImage representations] objectAtIndex:0];
    Check(sourceRep.pixelsWide == maskRep.pixelsWide && sourceRep.pixelsHigh == maskRep.pixelsHigh,
          "the independent glyph mask matches the source backing scale");
    fprintf(stdout, "Glyph surface: %.0fx%.0f points, %ldx%ld backing pixels, fill alpha %.2f\n",
            size.width, size.height, (long)sourceRep.pixelsWide, (long)sourceRep.pixelsHigh, expectedAlpha);
    // Compare native backing pixels. Downsampling can introduce interpolation
    // overshoot, which does not preserve a per-pixel alpha identity.
    NSSize pixelSize = NSMakeSize(sourceRep.pixelsWide, sourceRep.pixelsHigh);
    NSRect pixelRect = NSMakeRect(0, 0, pixelSize.width, pixelSize.height);
    NSBitmapImageRep *pill = Bitmap(pixelSize), *glyphMask = Bitmap(pixelSize);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:pill]];
    [image drawInRect:pixelRect fromRect:NSZeroRect
        operation:NSCompositingOperationCopy fraction:1];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:glyphMask]];
    [maskImage drawInRect:pixelRect fromRect:NSZeroRect
        operation:NSCompositingOperationCopy fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    unsigned holes = 0, fill = 0;
    CGFloat glyphCoverage = 0;
    NSInteger margin = (NSInteger)ceil(2 * pixelSize.width / size.width);
    for (NSInteger y = margin; y < pixelSize.height - margin; y++) {
        for (NSInteger x = margin; x < pixelSize.width - margin; x++) {
            CGFloat mask = [[glyphMask colorAtX:x y:y] alphaComponent];
            CGFloat alpha = [[pill colorAtX:x y:y] alphaComponent];
            if (mask > .05) {
                Check(fabs(alpha - expectedAlpha * (1 - mask)) < .04,
                      "glyph coverage removes the expected translucent fill");
                glyphCoverage += mask;
                if (mask > .99) {
                    Check(alpha < .04, "opaque glyph pixels remove the translucent fill");
                    holes++;
                }
            } else if (mask < .01) {
                if (fabs(alpha - expectedAlpha) >= .04) fprintf(stderr,
                    "Unexpected fill at (%ld,%ld): mask %.4f, alpha %.4f, expected %.4f\n",
                    (long)x, (long)y, mask, alpha, expectedAlpha);
                Check(fabs(alpha - expectedAlpha) < .04, "the non-glyph interior preserves system color alpha");
                fill++;
            }
        }
    }
    fprintf(stdout, "Glyph mask: %.2f covered pixels, %u opaque pixels, %u fill pixels\n",
            glyphCoverage, holes, fill);
    Check(glyphCoverage > 20 && fill > 20, "the mask covers both glyphs and fill");
}

static void ColorKeysAndLifetime(void) {
    Method secondary = class_getClassMethod([NSColor class], @selector(secondaryLabelColor));
    IMP original = method_setImplementation(secondary, (IMP)InjectedColor);
    NativeLabels *labels = [[NativeLabels alloc] init];
    __block NSImage *first = nil;
    const unsigned baseline = releasedImages;
    @try {
        @autoreleasepool {
            fixtureColor = [NSColor colorWithCalibratedRed:.2 green:.4 blue:.6 alpha:.35];
            first = [labels cachedLabelImageForWord:@"MMMM" highlighted:NO];
            ObserveRelease(first);
            CheckGlyphRemoval(first, @"MMMM", .35);
        }
        Check(releasedImages == baseline, "the cache owns its image after autorelease pool drainage");
        @autoreleasepool {
            fixtureColor = [NSColor colorWithCalibratedRed:.2 green:.4 blue:.6 alpha:.35];
            Check([labels cachedLabelImageForWord:@"MMMM" highlighted:NO] == first,
                  "equal color values reuse the surviving cached image");
            fixtureColor = [NSColor colorWithCalibratedRed:.2 green:.4 blue:.6 alpha:.7];
            NSImage *second = [labels cachedLabelImageForWord:@"MMMM" highlighted:NO];
            Check(second != first, "distinct alpha values require distinct cached images");
            ObserveRelease(second);
            CheckGlyphRemoval(second, @"MMMM", .7);
            Check(labels.cacheCount == 2, "alpha changes retain exactly two image variants");
        }
        [labels invalidateCachedLabelImages];
        Check(labels.cacheCount == 0, "font invalidation clears the full image cache");
        Check(releasedImages == baseline + 2, "invalidating the cache releases its images");
        NSImage *held;
        @autoreleasepool {
            fixtureColor = [NSColor colorWithCalibratedWhite:.5 alpha:.5];
            held = [[labels cachedLabelImageForWord:@"keep" highlighted:NO] retain];
            ObserveRelease(held);
        }
        [labels release]; labels = nil;
        Check(releasedImages == baseline + 2, "caller retention keeps an image alive after controller disposal");
        Check(held.size.width > 0, "the retained image remains usable after controller disposal");
        [held release];
        Check(releasedImages == baseline + 3, "caller release disposes the last retained image");
    } @finally {
        method_setImplementation(secondary, original);
        fixtureColor = nil;
        [labels release];
    }
}

static void SystemAppearancesAndGraphicsState(void) {
    NativeLabels *labels = [[NativeLabels alloc] init];
    NSArray *names = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
        NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua];
    NSMutableDictionary *firstImages = [NSMutableDictionary dictionary];
    NSUInteger variants = 0;
    for (unsigned pass = 0; pass < 24; pass++) {
        @autoreleasepool {
            for (NSString *name in names) {
                NSAppearance *appearance = [NSAppearance appearanceNamed:name];
                Check(appearance != nil, "the host supplies the requested system appearance");
                [appearance performAsCurrentDrawingAppearance:^{
                    for (unsigned selected = 0; selected < 2; selected++) {
                        NSColor *color = [(selected ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor)
                            colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                        Check(color != nil, "the system label color resolves to calibrated RGB");
                        NSBitmapImageRep *target = Bitmap(NSMakeSize(80, 20));
                        [NSGraphicsContext saveGraphicsState];
                        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:target];
                        [NSGraphicsContext setCurrentContext:context];
                        context.compositingOperation = NSCompositingOperationSourceAtop;
                        NSImage *image = [labels cachedLabelImageForWord:@"native" highlighted:selected];
                        Check(NSGraphicsContext.currentContext == context,
                              "tag image creation preserves the caller graphics context");
                        Check(context.compositingOperation == NSCompositingOperationSourceAtop,
                              "tag image creation preserves the caller compositing operation");
                        [NSGraphicsContext restoreGraphicsState];
                        NSString *scenario = [NSString stringWithFormat:@"%@/%u", name, selected];
                        NSValue *old = firstImages[scenario];
                        if (old) Check(old.pointerValue == image, "repeated appearances reuse cached images after pool drainage");
                        else firstImages[scenario] = [NSValue valueWithPointer:image];
                    }
                }];
            }
        }
        if (pass == 0) variants = labels.cacheCount;
        Check(labels.cacheCount == variants, "repeated appearance cycles do not add cache entries");
    }
    Check(variants >= 3 && variants <= 8, "four appearances and selection produce a bounded set of color variants");
    NSSize oldSize;
    @autoreleasepool {
        oldSize = [labels cachedLabelImageForWord:@"fontchange" highlighted:NO].size;
    }
    fixtureFont = 22;
    [labels invalidateCachedLabelImages];
    NSSize newSize = [labels cachedLabelImageForWord:@"fontchange" highlighted:NO].size;
    Check(newSize.width > oldSize.width && newSize.height > oldSize.height,
          "font invalidation regenerates image geometry");
    fixtureFont = 15;
    [labels release];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            fprintf(stdout, "Glyph appearance: %s\n", [name UTF8String]);
            [[NSAppearance appearanceNamed:name] performAsCurrentDrawingAppearance:^{ ColorKeysAndLifetime(); }];
        }
        SystemAppearancesAndGraphicsState();
        fprintf(stdout, "PASS: %u native cache ownership, alpha, appearance, and graphics-state checks\n", checks);
    }
    return 0;
}
