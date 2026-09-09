#import <Cocoa/Cocoa.h>
#import <time.h>
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "NSBezierPath_NV.h"

@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (float)tableFontSize { return 15; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)tableColumnsShowPreview { return YES; }
@end

@interface NSCharacterSet (FixtureSeparators)
+ (NSCharacterSet *)labelSeparatorCharacterSet;
@end
@implementation NSCharacterSet (FixtureSeparators)
#include "separators.inc"
@end
@interface NSString (FixtureWords)
- (NSArray *)labelCompatibleWords;
@end
@implementation NSString (FixtureWords)
#include "words.inc"
@end

// This dictionary adapter counts work only in the assertion phase.
// Timed runs use ordinary NSMutableDictionary objects.
@interface CountingCache : NSObject {
    NSMutableDictionary *storage;
@public
    NSUInteger lookups, writes;
}
@end
@implementation CountingCache
- (id)init { if ((self = [super init])) storage = [[NSMutableDictionary alloc] init]; return self; }
- (id)objectForKey:(id)key { lookups++; return [storage objectForKey:key]; }
- (void)setObject:(id)value forKey:(id)key { writes++; [storage setObject:value forKey:key]; }
- (NSUInteger)count { return [storage count]; }
- (void)dealloc { [storage release]; [super dealloc]; }
@end

@interface Cache : NSObject { @public id labelImages; }
- (id)initWithCounting:(BOOL)counting;
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)highlighted;
@end
@implementation Cache
- (id)initWithCounting:(BOOL)counting {
    if ((self = [super init])) labelImages = counting ? [[CountingCache alloc] init] : [[NSMutableDictionary alloc] init];
    return self;
}
- (void)dealloc { [labelImages release]; [super dealloc]; }
@end
@interface CurrentCache : Cache @end
@implementation CurrentCache
#include "current.inc"
@end
@interface BaseCache : Cache @end
@implementation BaseCache
#include "base.inc"
@end

@interface FixtureDelegate : NSObject { @public Cache *cache; }
- (Cache *)labelsListDataSource;
@end
@implementation FixtureDelegate
- (Cache *)labelsListDataSource { return cache; }
@end

@interface FixtureNote : NSObject { NSString *labelString; FixtureDelegate *delegate; }
- (id)initWithWords:(NSArray *)words delegate:(FixtureDelegate *)owner;
- (NSArray *)orderedLabelTitles;
- (void)drawLabelBlocksInRect:(NSRect)rect rightAlign:(BOOL)right highlighted:(BOOL)selected;
- (void)_drawLabelBlocksInRect:(NSRect)rect rightAlign:(BOOL)right highlighted:(BOOL)selected getSizeOnly:(NSSize *)size;
@end
@implementation FixtureNote
- (id)initWithWords:(NSArray *)words delegate:(FixtureDelegate *)owner {
    if ((self = [super init])) { labelString = [[words componentsJoinedByString:@","] copy]; delegate = owner; }
    return self;
}
#include "note.inc"
- (void)dealloc { [labelString release]; [super dealloc]; }
@end

@interface DrawingBatch : NSObject {
@public
    NSUInteger rowCount, tagCount;
    FixtureDelegate *owner;
    NSMutableArray *notes, *cells;
    NSBitmapImageRep *bitmap;
    NSGraphicsContext *context;
    NSView *view;
}
- (id)initWithRows:(NSUInteger)rows tags:(NSUInteger)tags;
@end
@implementation DrawingBatch
- (id)initWithRows:(NSUInteger)rows tags:(NSUInteger)tags {
    if ((self = [super init])) {
        rowCount = rows; tagCount = tags;
        owner = [[FixtureDelegate alloc] init];
        notes = [[NSMutableArray alloc] init]; cells = [[NSMutableArray alloc] init];
        view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, rows * 52)];
        bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:720 pixelsHigh:rows * 52
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
            bytesPerRow:0 bitsPerPixel:0];
        context = [[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap] retain];
        for (NSUInteger row = 0; row < rows; row++) {
            NSMutableArray *words = [NSMutableArray array];
            for (NSUInteger tag = 0; tag < tags; tag++)
                [words addObject:[NSString stringWithFormat:@"tag-%02lu", (row + tag) % 16]];
            [notes addObject:[[[FixtureNote alloc] initWithWords:words delegate:owner] autorelease]];
            NSString *title = [NSString stringWithFormat:@"Note %03lu", row];
            NSAttributedString *body = [[[NSAttributedString alloc] initWithString:
                @"A cached source preview with a stable layout and enough text to occupy a line."] autorelease];
            NSAttributedString *preview = [title attributedMultiLinePreviewFromBodyText:body upToWidth:720 intrusionWidth:tags * 55];
            NSTextFieldCell *cell = [[[NSTextFieldCell alloc] init] autorelease];
            [cell setFont:[NSFont systemFontOfSize:15]];
            [cell setTextColor:[NSColor labelColor]];
            [cell setBordered:NO]; [cell setTruncatesLastVisibleLine:YES];
            [cell setWraps:YES]; [cell setScrollable:NO]; [cell setControlView:view];
            [cell setUsesSingleLineMode:NO];
            [cell setAttributedStringValue:preview];
            [cells addObject:cell];
        }
    }
    return self;
}
- (void)dealloc {
    [owner release]; [notes release]; [cells release]; [context release]; [bitmap release]; [view release];
    [super dealloc];
}
@end

static NSUInteger checks;
static void Check(BOOL pass, const char *message) {
    if (!pass) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    checks++;
}
static double Now(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
static void Draw(DrawingBatch *batch, Cache *cache, BOOL rightAlign) {
    batch->owner->cache = cache;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:batch->context];
    for (NSUInteger row = 0; row < batch->rowCount; row++) {
        BOOL selected = row % 7 == 0;
        NSRect frame = NSMakeRect(0, row * 52, 720, 52);
        [(selected ? [NSColor alternateSelectedControlColor] : [NSColor controlBackgroundColor]) setFill];
        NSRectFill(frame);
        NSTextFieldCell *cell = batch->cells[row];
        [cell setHighlighted:selected];
        [cell drawWithFrame:NSInsetRect(frame, 4, 0) inView:batch->view];
        [NSGraphicsContext saveGraphicsState];
        NSRectClip(frame);
        [batch->notes[row] drawLabelBlocksInRect:NSMakeRect(4, frame.origin.y + 20, 712, 18)
            rightAlign:rightAlign highlighted:selected];
        [NSGraphicsContext restoreGraphicsState];
    }
    CGContextFlush([batch->context CGContext]);
    [NSGraphicsContext restoreGraphicsState];
}
static double TimedDraws(DrawingBatch *batch, Cache *cache, NSAppearance *appearance, NSUInteger repeats) {
    __block double elapsed;
    [batch->view setAppearance:appearance];
    [appearance performAsCurrentDrawingAppearance:^{
        double start = Now();
        for (NSUInteger draw = 0; draw < repeats; draw++) {
            @autoreleasepool { Draw(batch, cache, draw % 2); }
        }
        elapsed = (Now() - start) * 1000.0 / repeats;
    }];
    return elapsed;
}
static NSUInteger InkCount(DrawingBatch *batch, BOOL bodyOnly) {
    NSUInteger ink = 0;
    // Row 1 is ordinary. Count pixels that differ from its row background.
    NSColor *background = [batch->bitmap colorAtX:718 y:batch->rowCount * 52 - 53];
    NSInteger rowTop = batch->rowCount * 52 - 104;
    for (NSInteger y = rowTop + (bodyOnly ? 19 : 0); y < rowTop + (bodyOnly ? 34 : 52); y++) {
        for (NSInteger x = 3; x < (bodyOnly ? 500 : 716); x++) {
            NSColor *color = [batch->bitmap colorAtX:x y:y];
            if (fabs([color redComponent] - [background redComponent]) > .08 ||
                fabs([color greenComponent] - [background greenComponent]) > .08 ||
                fabs([color blueComponent] - [background blueComponent]) > .08) ink++;
        }
    }
    return ink;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSArray *appearances = @[[NSAppearance appearanceNamed:NSAppearanceNameAqua],
            [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        for (NSUInteger rows = 10; rows <= 80; rows *= 2) for (NSUInteger tags = 0; tags <= 3; tags += 3) {
            @autoreleasepool {
                DrawingBatch *batch = [[[DrawingBatch alloc] initWithRows:rows tags:tags] autorelease];
                CurrentCache *cache = [[[CurrentCache alloc] initWithCounting:YES] autorelease];
                CountingCache *counts = cache->labelImages;
                for (NSAppearance *appearance in appearances) {
                    [batch->view setAppearance:appearance];
                    [appearance performAsCurrentDrawingAppearance:^{ Draw(batch, cache, YES); }];
                    NSUInteger ink = InkCount(batch, NO);
                    if (ink <= 150) {
                        [[batch->bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                            writeToFile:@"build/NotesListAppearanceReview/round2/luu/failed-draw.png" atomically:YES];
                        fprintf(stderr, "rows=%lu tags=%lu appearance=%s ink=%lu\n", rows, tags,
                            [[appearance name] UTF8String], ink);
                    }
                    Check(ink > 150, "native bitmap contains drawn cell/tag pixels");
                    Check(InkCount(batch, YES) > 50, "native bitmap contains drawn preview body text");
                    if (rows == 40 && tags == 3) {
                        NSString *path = [NSString stringWithFormat:
                            @"build/NotesListAppearanceReview/round2/luu/%@.png", [appearance name]];
                        Check([[batch->bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                            writeToFile:path atomically:YES], "writes the representative native drawing fixture");
                    }
                }
                NSUInteger writes = counts->writes, entries = [counts count];
                for (NSUInteger redraw = 0; redraw < 24; redraw++) {
                    NSUInteger prior = counts->lookups;
                    [batch->view setAppearance:appearances[redraw % 2]];
                    [appearances[redraw % 2] performAsCurrentDrawingAppearance:^{ Draw(batch, cache, redraw % 2); }];
                    Check(counts->writes == writes, "warm redraw does not replace cached images");
                    Check(counts->lookups - prior == rows * tags, "redraw performs one cache lookup per visible tag");
                    Check([counts count] == entries, "redraw leaves cache cardinality unchanged");
                }
            }
        }
        NSMutableArray *measurements = [NSMutableArray array];
        for (NSNumber *rows in @[@10, @40, @80]) for (NSNumber *tags in @[@0, @3]) {
            @autoreleasepool {
                DrawingBatch *batch = [[[DrawingBatch alloc] initWithRows:[rows unsignedIntegerValue] tags:[tags unsignedIntegerValue]] autorelease];
                CurrentCache *current = [[[CurrentCache alloc] initWithCounting:NO] autorelease];
                BaseCache *base = [[[BaseCache alloc] initWithCounting:NO] autorelease];
                for (NSAppearance *appearance in appearances) {
                    TimedDraws(batch, current, appearance, 3); TimedDraws(batch, base, appearance, 3);
                }
                NSMutableArray *currentMS = [NSMutableArray array], *baseMS = [NSMutableArray array];
                for (NSUInteger sample = 0; sample < 7; sample++) {
                    double currentTime = 0, baseTime = 0;
                    for (NSAppearance *appearance in appearances) {
                        if (sample % 2) {
                            currentTime += TimedDraws(batch, current, appearance, 5);
                            baseTime += TimedDraws(batch, base, appearance, 5);
                        } else {
                            baseTime += TimedDraws(batch, base, appearance, 5);
                            currentTime += TimedDraws(batch, current, appearance, 5);
                        }
                    }
                    [currentMS addObject:@(currentTime / 2)]; [baseMS addObject:@(baseTime / 2)];
                }
                [measurements addObject:@{@"rows": rows, @"tags_per_row": tags,
                    @"current_ms_per_draw": currentMS, @"base_ms_per_draw": baseMS}];
            }
        }
        NSDictionary *report = @{@"assertions": @(checks), @"redraws_per_assertion_case": @24,
            @"samples": @7, @"draws_per_sample_and_implementation": @10, @"measurements": measurements};
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
        printf("PASS: %lu native drawing and redraw-work assertions\n%s\n", checks,
            [[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease] UTF8String]);
    }
    return 0;
}
