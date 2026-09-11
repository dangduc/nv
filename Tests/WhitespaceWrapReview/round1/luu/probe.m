#import <Cocoa/Cocoa.h>
#import <mach/mach_time.h>

// This harness creates fresh, in-memory native NSTextViews. No nvALT preferences
// or notes are loaded. The run script inserts the production method verbatim.
typedef struct {
    uint64_t callbacks, glyphs, maxBatch, allocations, bytes, maxAllocationBytes;
    uint64_t changedBatches, callbackTicks;
} Metrics;
static Metrics M;
static double Milliseconds(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) mach_timebase_info(&timebase);
    return (double)ticks * timebase.numer / timebase.denom / 1e6;
}
static void *TrackMalloc(size_t bytes) {
    M.allocations++; M.bytes += bytes; M.maxAllocationBytes = MAX(M.maxAllocationBytes, bytes);
    return malloc(bytes);
}
@interface ActualDelegate : NSObject <NSLayoutManagerDelegate>
@end
@implementation ActualDelegate
#define malloc TrackMalloc
/* PRODUCTION_METHOD */
#undef malloc
@end

@interface MeasuredDelegate : ActualDelegate { @public BOOL adjusted; }
@end
@implementation MeasuredDelegate
- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:(const CGGlyph *)glyphs
                 properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes
                       font:(NSFont *)font forGlyphRange:(NSRange)range {
    M.callbacks++; M.glyphs += range.length; M.maxBatch = MAX(M.maxBatch, range.length);
    uint64_t before = mach_absolute_time();
    NSUInteger result = adjusted ? [super layoutManager:manager shouldGenerateGlyphs:glyphs
        properties:properties characterIndexes:indexes font:font forGlyphRange:range] : 0;
    M.callbackTicks += mach_absolute_time() - before;
    if (result) M.changedBatches++;
    return result;
}
@end

static NSDictionary *Stats(void) {
    return @{ @"callbacks":@(M.callbacks), @"glyphs":@(M.glyphs), @"maxBatch":@(M.maxBatch),
        @"allocations":@(M.allocations), @"allocatedBytes":@(M.bytes),
        @"maxAllocationBytes":@(M.maxAllocationBytes), @"changedBatches":@(M.changedBatches),
        @"callbackMs":@(Milliseconds(M.callbackTicks)) };
}
static NSString *Repeat(NSString *seed, NSUInteger length) {
    return [@"" stringByPaddingToLength:length withString:seed startingAtIndex:0];
}
static NSUInteger LineCount(NSLayoutManager *layout) {
    __block NSUInteger lines = 0;
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *container, NSRange range, BOOL *stop) { lines++; }];
    return lines;
}
static void Measure(NSMutableArray *rows, NSTextView *view, NSString *mode, NSString *fixture,
                    NSUInteger trial, NSUInteger width, NSString *stage, NSString *expected, void (^work)(void)) {
    memset(&M, 0, sizeof(M));
    uint64_t before = mach_absolute_time(); work(); uint64_t elapsed = mach_absolute_time() - before;
    NSDictionary *stats = Stats();
    [rows addObject:@{@"mode":mode, @"fixture":fixture, @"trial":@(trial), @"width":@(width),
        @"stage":stage, @"ms":@(Milliseconds(elapsed)), @"stats":stats,
        @"lines":@(LineCount(view.layoutManager)), @"unchangedSource":@([view.string isEqual:expected])}];
}

static NSArray *MeasureVisibleLayouts(void) {
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *modes = @[@"native", @"adjusted", @"adjusted-charwrap"];
    for (NSUInteger trial=0; trial<3; trial++) {
        for (NSNumber *lengthNumber in @[@201,@4096,@8192,@16384,@32768]) {
            for (NSNumber *widthNumber in @[@160,@480]) {
                for (NSUInteger m=0; m<3; m++) { @autoreleasepool {
                    NSString *mode = modes[(m+trial)%3];
                    NSUInteger length = lengthNumber.unsignedIntegerValue, width = widthNumber.unsignedIntegerValue;
                    NSTextStorage *storage = [[[NSTextStorage alloc] init] autorelease];
                    NSLayoutManager *layout = [[[NSLayoutManager alloc] init] autorelease];
                    layout.backgroundLayoutEnabled = NO;
                    NSTextContainer *container = [[[NSTextContainer alloc] initWithSize:NSMakeSize(width,10000000)] autorelease];
                    [storage addLayoutManager:layout]; [layout addTextContainer:container];
                    NSTextView *view = [[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,width,400) textContainer:container] autorelease];
                    view.richText = NO;
                    view.horizontallyResizable = NO; view.verticallyResizable = YES;
                    container.widthTracksTextView = NO;
                    MeasuredDelegate *delegate = [[[MeasuredDelegate alloc] init] autorelease];
                    delegate->adjusted = YES;
                    if (![mode isEqual:@"native"]) layout.delegate = delegate;
                    NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
                    if ([mode isEqual:@"adjusted-charwrap"]) style.lineBreakMode = NSLineBreakByCharWrapping;
                    NSDictionary *attrs = @{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:12],
                        NSParagraphStyleAttributeName:style};
                    NSString *source = Repeat(@" ",length);
                    NSUInteger currentWidth = width;
                    for (NSString *stage in @[@"visible-initial",@"visible-resize",@"layout-to-caret-at-end"]) {
                        memset(&M,0,sizeof(M));
                        uint64_t before = mach_absolute_time();
                        if ([stage isEqual:@"visible-initial"]) {
                            [storage setAttributedString:[[[NSAttributedString alloc] initWithString:source attributes:attrs] autorelease]];
                        } else if ([stage isEqual:@"visible-resize"]) {
                            currentWidth = width == 160 ? 480 : 160;
                            container.containerSize = NSMakeSize(currentWidth,10000000);
                        }
                        if ([stage isEqual:@"layout-to-caret-at-end"])
                            [layout ensureLayoutForCharacterRange:NSMakeRange(length-1,1)];
                        else [layout ensureLayoutForBoundingRect:NSMakeRect(0,0,currentWidth,400) inTextContainer:container];
                        uint64_t elapsed = mach_absolute_time()-before;
                        [rows addObject:@{@"mode":mode,@"length":@(length),@"initialWidth":@(width),
                            @"width":@(currentWidth),@"trial":@(trial),@"stage":stage,
                            @"ms":@(Milliseconds(elapsed)),@"laidCharacters":@([layout firstUnlaidCharacterIndex]),
                            @"stats":Stats(),@"unchangedSource":@([source isEqual:storage.string])}];
                    }
                    layout.delegate = nil;
                }}
            }
        }
    }
    return rows;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSDictionary *fixtures = @{
            @"short-prose":Repeat(@"alpha beta gamma delta epsilon.\n", 1024),
            @"prose-100k":Repeat(@"alpha beta gamma delta epsilon.\n", 100000),
            @"no-space-100k":Repeat(@"abcdefghijklmnopqrstuvwxyz\n", 100000),
            @"tabs-100k":Repeat(@"\talpha\tbeta\tgamma\n", 100000),
            @"spaces-201":Repeat(@" ",201), @"spaces-4k":Repeat(@" ",4096),
            @"spaces-32k":Repeat(@" ",32768),
            // Same glyph count and Menlo advance, with ordinary native wrapping.
            @"letters-201":Repeat(@"x",201), @"letters-4k":Repeat(@"x",4096),
            @"letters-32k":Repeat(@"x",32768) };
        NSArray *modes = @[@"native", @"noop", @"adjusted"];
        NSMutableArray *rows = [NSMutableArray array];
        NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:12];
        // Warm CoreText/font caches before collecting measurements.
        [@"warm up glyphs" sizeWithAttributes:@{NSFontAttributeName:font}];
        for (NSUInteger trial=0; trial<3; trial++) {
            for (NSString *fixture in [[fixtures allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
                for (NSNumber *widthNumber in @[@160, @480]) {
                    NSUInteger width = widthNumber.unsignedIntegerValue;
                    for (NSUInteger m=0; m<3; m++) { @autoreleasepool {
                        NSString *mode = modes[(m + trial) % modes.count];
                        NSTextStorage *storage = [[[NSTextStorage alloc] init] autorelease];
                        NSLayoutManager *layout = [[[NSLayoutManager alloc] init] autorelease];
                        layout.backgroundLayoutEnabled = NO;
                        NSTextContainer *container = [[[NSTextContainer alloc] initWithSize:NSMakeSize(width, 10000000)] autorelease];
                        [storage addLayoutManager:layout]; [layout addTextContainer:container];
                        NSTextView *view = [[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,width,400)
                            textContainer:container] autorelease];
                        view.richText = NO; view.font = font;
                        view.horizontallyResizable = NO; view.verticallyResizable = YES;
                        container.widthTracksTextView = NO;
                        MeasuredDelegate *delegate = [[[MeasuredDelegate alloc] init] autorelease];
                        delegate->adjusted = [mode isEqual:@"adjusted"];
                        if (![mode isEqual:@"native"]) layout.delegate = delegate;
                        NSString *source = fixtures[fixture];
                        NSDictionary *attrs = @{NSFontAttributeName:font};
                        Measure(rows, view, mode, fixture, trial, width, @"initial", source, ^{
                            [storage setAttributedString:[[[NSAttributedString alloc] initWithString:source attributes:attrs] autorelease]];
                            [layout ensureLayoutForTextContainer:container];
                        });
                        NSString *after = [source stringByAppendingString:Repeat(@" ",30)];
                        Measure(rows, view, mode, fixture, trial, width, @"30-appends", after, ^{
                            for (NSUInteger n=0; n<30; n++) {
                                [storage replaceCharactersInRange:NSMakeRange(storage.length,0) withString:@" "];
                                [layout ensureLayoutForTextContainer:container];
                            }
                        });
                        Measure(rows, view, mode, fixture, trial, width, @"resize", after, ^{
                            container.containerSize = NSMakeSize(width + 81, 10000000);
                            [layout ensureLayoutForTextContainer:container];
                        });
                        layout.delegate = nil;
                    }}
                }
            }
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:NULL];
        if (![data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES]) return 2;
        printf("Native TextKit timing: %lu stages\n", (unsigned long)rows.count);
        NSArray *visibleRows = MeasureVisibleLayouts();
        NSData *visibleData = [NSJSONSerialization dataWithJSONObject:visibleRows options:NSJSONWritingPrettyPrinted error:NULL];
        NSString *visiblePath = [[NSString stringWithUTF8String:argv[1]] stringByAppendingString:@".visible.json"];
        if (![visibleData writeToFile:visiblePath atomically:YES]) return 3;
        printf("Visible-layout scaling: %lu stages\n",(unsigned long)visibleRows.count);
    }
    return 0;
}
