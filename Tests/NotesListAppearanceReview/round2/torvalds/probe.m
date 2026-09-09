#import <Cocoa/Cocoa.h>
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
- (id)labelsListDataSource;
- (NSUInteger)cacheCount;
@end
@implementation NativeLabels
#include "labels.inc"
- (id)labelsListDataSource { return self; }
- (NSUInteger)cacheCount { return labelImages.count; }
@end

@interface NativeNote : NSObject {
    NSString *labelString;
    NativeLabels *delegate;
    NSArray *fixtureWords;
}
- (id)initWithLabels:(NativeLabels *)labels;
- (NSArray *)orderedLabelTitles;
- (NSSize)sizeOfLabelBlocks;
- (void)drawLabelBlocksInRect:(NSRect)rect rightAlign:(BOOL)right highlighted:(BOOL)selected;
- (void)_drawLabelBlocksInRect:(NSRect)rect rightAlign:(BOOL)right highlighted:(BOOL)selected getSizeOnly:(NSSize *)size;
@end
@implementation NativeNote
- (id)initWithLabels:(NativeLabels *)labels {
    if ((self = [super init])) {
        delegate = [labels retain];
        fixtureWords = [@[@"MMMM", @"wide", @"été", @"日本語"] retain];
        labelString = [[fixtureWords componentsJoinedByString:@" "] copy];
    }
    return self;
}
- (NSArray *)orderedLabelTitles { return fixtureWords; }
- (void)dealloc { [labelString release]; [fixtureWords release]; [delegate release]; [super dealloc]; }
#include "note.inc"
@end

static unsigned checks, scenarios;
static CGFloat largestError;
static void Check(BOOL condition, const char *description) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", description); exit(1); }
    checks++;
}
static NSBitmapImageRep *Bitmap(NSSize points, unsigned scale) {
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:(NSInteger)(points.width * scale) pixelsHigh:(NSInteger)(points.height * scale)
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    // Explicit CTM and integer dimensions avoid the host display's implicit scale.
    return bitmap;
}
static NSBitmapImageRep *Draw(NativeNote *note, NSSize canvas, unsigned scale,
                              NSColor *row, BOOL right, BOOL selected, BOOL clipped) {
    NSBitmapImageRep *bitmap = Bitmap(canvas, scale);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext setCurrentContext:context];
    CGContextRef cg = context.CGContext;
    CGContextScaleCTM(cg, scale, scale);
    context.imageInterpolation = NSImageInterpolationNone;
    if (row) { [row setFill]; NSRectFill(NSMakeRect(0, 0, canvas.width, canvas.height)); }
    CGContextSaveGState(cg);
    if (clipped) CGContextClipToRect(cg, CGRectMake(canvas.width / 2, 0, canvas.width / 2, canvas.height));
    NSSize tagSize = note.sizeOfLabelBlocks;
    // Right alignment includes the existing four-point final spacing.
    NSRect target = NSMakeRect(8, 8 + tagSize.height, tagSize.width, tagSize.height);
    [note drawLabelBlocksInRect:target rightAlign:right highlighted:selected];
    CGContextRestoreGState(cg);
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}
static void RGBA(NSColor *color, CGFloat result[4]) {
    [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]
        getRed:&result[0] green:&result[1] blue:&result[2] alpha:&result[3]];
}

static void CheckDestination(NativeNote *note, NativeLabels *labels, unsigned scale, BOOL selected) {
    NSSize tags = note.sizeOfLabelBlocks;
    NSSize canvas = NSMakeSize(tags.width + 16, tags.height + 16);
    NSColor *row = selected ? NSColor.alternateSelectedControlColor : NSColor.textBackgroundColor;
    NSBitmapImageRep *transparent = Draw(note, canvas, scale, nil, NO, selected, NO);
    NSBitmapImageRep *opaque = Draw(note, canvas, scale, row, NO, selected, NO);
    NSBitmapImageRep *right = Draw(note, canvas, scale, row, YES, selected, NO);
    NSBitmapImageRep *clipped = Draw(note, canvas, scale, row, NO, selected, YES);
    CGFloat background[4]; RGBA([opaque colorAtX:0 y:0], background);
    Check(background[3] > .999, "the row fixture starts opaque");
    Check(transparent.pixelsWide == (NSInteger)(canvas.width * scale), "the destination has the requested backing pixels");
    NSUInteger entries = labels.cacheCount;
    unsigned colored = 0, transparentInterior = 0;
    NSInteger clipBoundary = (NSInteger)(canvas.width * scale / 2);
    for (NSInteger y = 0; y < opaque.pixelsHigh; y++) {
        for (NSInteger x = 0; x < opaque.pixelsWide; x++) {
            CGFloat source[4], actual[4], aligned[4], limited[4];
            RGBA([transparent colorAtX:x y:y], source);
            RGBA([opaque colorAtX:x y:y], actual);
            RGBA([right colorAtX:x y:y], aligned);
            RGBA([clipped colorAtX:x y:y], limited);
            Check(actual[3] > .995, "tag drawing preserves the opaque row");
            for (unsigned channel = 0; channel < 3; channel++) {
                CGFloat expected = source[channel] * source[3] + background[channel] * (1 - source[3]);
                CGFloat error = fabs(actual[channel] - expected);
                largestError = MAX(largestError, error);
                Check(error < .009, "the destination follows source-over color composition");
                Check(fabs(actual[channel] - aligned[channel]) < .009,
                      "left and right alignment preserve the same tag pixels");
                // Skip the pixel that straddles a half-point clipping edge.
                if (x < clipBoundary - 1) Check(fabs(limited[channel] - background[channel]) < .009,
                    "tag drawing does not modify pixels outside the destination clip");
                else if (x > clipBoundary + 1) Check(fabs(limited[channel] - actual[channel]) < .009,
                    "the destination clip preserves all included tag pixels");
            }
            if (source[3] > .1) colored++;
            if (x > 10 * scale && x < 30 * scale && y > 10 * scale &&
                y < (NSInteger)((8 + tags.height - 2) * scale) && source[3] < .04) transparentInterior++;
        }
    }
    Check(colored > 50, "the consumer draws visible tag fills");
    Check(transparentInterior > 0, "the destination includes transparent tag glyphs");
    Check(labels.cacheCount == entries, "destination composition creates no additional color variants");
    scenarios++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NativeLabels *labels = [[NativeLabels alloc] init];
        NativeNote *note = [[NativeNote alloc] initWithLabels:labels];
        for (NSNumber *font in @[@11, @15, @24]) {
            fixtureFont = font.floatValue;
            [labels invalidateCachedLabelImages];
            for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                    NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
                [[NSAppearance appearanceNamed:name] performAsCurrentDrawingAppearance:^{
                    for (unsigned scale = 1; scale <= 2; scale++) {
                        for (unsigned selected = 0; selected < 2; selected++) {
                            @autoreleasepool { CheckDestination(note, labels, scale, selected); }
                        }
                    }
                }];
                fprintf(stdout, "PASS: font %.0f, %s, both selections, 1x and 2x destinations\n", fixtureFont, name.UTF8String);
            }
        }
        [note release]; [labels release];
        fprintf(stdout, "PASS: %u checks across %u destination scenarios; maximum composition error %.6f\n",
                checks, scenarios, largestError);
    }
    return 0;
}
