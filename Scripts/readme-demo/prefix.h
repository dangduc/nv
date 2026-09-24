#import "NVSourceHighlighter.h"
#import "NVSearchService.h"
#import "NotesTableView.h"
static BOOL CaptureAwait(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    return condition();
}

static NSUInteger HighlightPixels(NSTableView *table, NSUInteger row, NSColor *expected) {
    NSRect rect = [table rectOfRow:row];
    if (!NSContainsRect([table visibleRect], rect)) return 0;
    NSBitmapImageRep *bitmap = [table bitmapImageRepForCachingDisplayInRect:rect];
    [table cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    expected = [expected colorUsingColorSpace:[bitmap colorSpace]];
    if (!expected) return 0;
    NSUInteger highlighted = 0;
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            // colorAtX:y: exposes captured channel values as calibrated RGB.
            NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if ([color alphaComponent] > .8 &&
                fabs([color redComponent] - [expected redComponent]) < .04 &&
                fabs([color greenComponent] - [expected greenComponent]) < .04 &&
                fabs([color blueComponent] - [expected blueComponent]) < .04) highlighted++;
        }
    }
    return highlighted;
}

static NSMutableArray *DemoWindows;
static NSMutableArray *DemoFrames;
static CGRect DemoBounds;
static NSTimeInterval DemoStart;
static NSString *DemoDirectory;
