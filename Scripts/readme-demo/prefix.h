#import "NVSourceHighlighter.h"
#import "NVSearchService.h"
#import "NotesTableView.h"
static BOOL CaptureAwait(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    return condition();
}

static NSUInteger HighlightPixels(NSTableView *table, NSUInteger row) {
    NSRect rect = [table rectOfRow:row];
    if (!NSContainsRect([table visibleRect], rect)) return 0;
    NSBitmapImageRep *bitmap = [table bitmapImageRepForCachingDisplayInRect:rect];
    [table cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    NSUInteger highlighted = 0;
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if ([color alphaComponent] > .8 && [color redComponent] > .65 &&
                [color greenComponent] > .55 && [color blueComponent] < .4 &&
                [color redComponent] - [color blueComponent] > .35 &&
                [color greenComponent] - [color blueComponent] > .25) highlighted++;
        }
    }
    return highlighted;
}

static NSMutableArray *DemoWindows;
static NSMutableArray *DemoFrames;
static CGRect DemoBounds;
static NSTimeInterval DemoStart;
static NSString *DemoDirectory;
