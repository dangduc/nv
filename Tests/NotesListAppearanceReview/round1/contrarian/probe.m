#import <Cocoa/Cocoa.h>
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "ETOverlayScroller.h"

@implementation GlobalPrefs
+ (id)defaultPrefs { static id value; if (!value) value = [[self alloc] init]; return value; }
- (float)tableFontSize { return 15; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)tableColumnsShowPreview { return YES; }
@end

static unsigned assertions;
static void Check(BOOL pass, NSString *message) {
    if (!pass) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
    assertions++;
}
static CGFloat Brightness(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return .2126 * [rgb redComponent] + .7152 * [rgb greenComponent] + .0722 * [rgb blueComponent];
}

#define STATUS_STRING_FONT_SIZE 16.0f
@interface FixtureTable : NSTableView {
    NSString *loadStatusString;
    NSDictionary *loadStatusAttributes;
    CGFloat loadStatusStringWidth;
}
@end
@implementation FixtureTable
- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
#include "status-init.inc"
    }
    return self;
}
#include "table-drawing.inc"
- (void)dealloc { [loadStatusAttributes release]; [super dealloc]; }
@end

@interface FixtureController : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public
    FixtureTable *notesTableView;
    NSWindow *window;
    BOOL preview;
    NSInteger rows;
    NSAttributedString *cachedPreview;
}
@end
@implementation FixtureController
- (id)init {
    if ((self = [super init])) {
        rows = 3;
        NSAttributedString *body = [[[NSAttributedString alloc] initWithString:@"Body preview text has its own system color."] autorelease];
        cachedPreview = [[@"Title" attributedSingleLinePreviewFromBodyText:body upToWidth:560] retain];
    }
    return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return rows; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    // Match the production ordinary-list dereferencer: active selection returns
    // plain text. All other rows retain the cached preview attributes.
    BOOL active = [window isMainWindow] && ([window firstResponder] == table || [table currentEditor]);
    return !preview ? @"Title" : ([table isRowSelected:row] && active ? [cachedPreview string] : cachedPreview);
}
#include "delegate.inc"
- (void)dealloc { [cachedPreview release]; [super dealloc]; }
@end

static NSBitmapImageRep *Capture(NSView *view, NSRect rect, NSString *path) {
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:rect];
    [view cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    Check(bitmap != nil && [bitmap pixelsWide] > 0, @"native view capture has pixels");
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"native capture writes");
    return bitmap;
}
static NSUInteger Contrasting(NSBitmapImageRep *bitmap, NSInteger minX, NSInteger maxX, CGFloat background, CGFloat threshold) {
    NSUInteger count = 0;
    for (NSInteger y = 2; y < [bitmap pixelsHigh] - 2; y++)
        for (NSInteger x = minX; x < MIN(maxX, [bitmap pixelsWide]); x++)
            if (fabs(Brightness([bitmap colorAtX:x y:y]) - background) > threshold) count++;
    return count;
}

@interface FixtureScroller : ETOverlayScroller
- (void)loadImages:(NSString *)root;
@end
@implementation FixtureScroller
- (void)loadImages:(NSString *)root {
    [knobTop release]; [knobVerticalFill release]; [knobBottom release];
    [slotTop release]; [slotVerticalFill release]; [slotBottom release];
    knobTop = [[NSImage alloc] initWithContentsOfFile:[root stringByAppendingPathComponent:@"TransparentScrollerKnobTop.tif"]];
    knobVerticalFill = [[NSImage alloc] initWithContentsOfFile:[root stringByAppendingPathComponent:@"TransparentScrollerKnobVerticalFill.tif"]];
    knobBottom = [[NSImage alloc] initWithContentsOfFile:[root stringByAppendingPathComponent:@"TransparentScrollerKnobBottom.tif"]];
    slotTop = [[NSImage alloc] initWithContentsOfFile:[root stringByAppendingPathComponent:@"TransparentScrollerSlotTop.tif"]];
    slotVerticalFill = [[NSImage alloc] initWithContentsOfFile:[root stringByAppendingPathComponent:@"TransparentScrollerSlotVerticalFill.tif"]];
    slotBottom = [[NSImage alloc] initWithContentsOfFile:[root stringByAppendingPathComponent:@"TransparentScrollerSlotBottom.tif"]];
    Check(knobTop && knobVerticalFill && knobBottom && slotTop && slotVerticalFill && slotBottom, @"production scroller resources load");
}
@end

static void InspectScroller(NSAppearance *appearance, NSString *root, NSString *output, BOOL dark) {
    FixtureScroller *scroller = [[[FixtureScroller alloc] initWithFrame:NSMakeRect(0, 0, 15, 200)] autorelease];
    [scroller loadImages:root];
    [scroller setScrollerStyle:NSScrollerStyleLegacy];
    [scroller setEnabled:YES];
    [scroller setKnobProportion:.25];
    [scroller setDoubleValue:.5];
    NSRect knob = [scroller rectForPart:NSScrollerKnob];
    Check(!NSIsEmptyRect(knob), @"production scroller supplies a knob rectangle");
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:15 pixelsHigh:200 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    [appearance performAsCurrentDrawingAppearance:^{
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
        [[NSColor textBackgroundColor] setFill]; NSRectFill(NSMakeRect(0, 0, 15, 200));
        [scroller drawKnobSlotInRect:[scroller rectForPart:NSScrollerKnobSlot] highlight:NO];
        [scroller drawKnob];
        [NSGraphicsContext restoreGraphicsState];
    }];
    CGFloat background = Brightness([bitmap colorAtX:0 y:100]);
    CGFloat center = Brightness([bitmap colorAtX:8 y:100]);
    CGFloat difference = fabs(center - background);
    fprintf(stdout, "SCROLLER dark=%d background=%.4f center=%.4f delta=%.4f\n", dark, background, center, difference);
    NSString *path = [output stringByAppendingPathComponent:dark ? @"scroller-dark.png" : @"scroller-light.png"];
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"scroller capture writes");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *output = [NSString stringWithUTF8String:argv[1]];
        FixtureController *controller = [[[FixtureController alloc] init] autorelease];
        NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,560,180) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
        [window setReleasedWhenClosed:NO];
        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,560,180)] autorelease];
        [scroll setBorderType:NSNoBorder];
        [scroll setBackgroundColor:[NSColor textBackgroundColor]];
        [[scroll contentView] setBackgroundColor:[NSColor textBackgroundColor]];
        FixtureTable *table = [[[FixtureTable alloc] initWithFrame:NSMakeRect(0,0,560,180)] autorelease];
        [table setBackgroundColor:[NSColor textBackgroundColor]];
        [table setHeaderView:nil];
        [table setStyle:NSTableViewStyleFullWidth];
        [table setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
        [table setRowHeight:22];
        [table setIntercellSpacing:NSMakeSize(10,3)];
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"Title"] autorelease];
        [column setWidth:550]; [[column dataCell] setFont:[NSFont systemFontOfSize:15]];
        [table addTableColumn:column];
        [table setDataSource:controller]; [table setDelegate:controller];
        [scroll setDocumentView:table]; [[window contentView] addSubview:scroll];
        controller->notesTableView = table; controller->window = window;
        for (NSUInteger dark = 0; dark < 2; dark++) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            [window setAppearance:appearance];
            for (NSUInteger alternating = 0; alternating < 2; alternating++) {
                [table setUsesAlternatingRowBackgroundColors:alternating];
                for (NSUInteger preview = 0; preview < 2; preview++) {
                    controller->preview = preview;
                    for (NSUInteger selected = 0; selected < 2; selected++) {
                        [table deselectAll:nil];
                        if (selected) [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
                        [table reloadData];
                        for (NSInteger row = 0; row < 3; row++) {
                            NSRect rect = [table convertRect:[table rectOfRow:row] toView:[window contentView]];
                            NSString *path = [output stringByAppendingPathComponent:[NSString stringWithFormat:@"d%lu-a%lu-p%lu-s%lu-r%ld.png", dark, alternating, preview, selected, row]];
                            NSBitmapImageRep *bitmap = Capture([window contentView], rect, path);
                            CGFloat background = Brightness([bitmap colorAtX:[bitmap pixelsWide]-10 y:10]);
                            BOOL rowSelected = selected && row == 1;
                            if (!rowSelected) Check(dark ? background < .3 : background > .85, @"native row background follows appearance");
                            CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
                            Check(Contrasting(bitmap, 6*scale, 38*scale, background, .2) > 15, @"native title glyphs contrast");
                            if (preview) Check(Contrasting(bitmap, 65*scale, 410*scale, background, .13) > 30, @"native preview glyphs contrast");
                        }
                    }
                }
                [table setDataSource:nil]; [table deselectAll:nil]; [table reloadData];
                NSString *path = [output stringByAppendingPathComponent:[NSString stringWithFormat:@"loading-d%lu-a%lu.png",dark,alternating]];
                NSBitmapImageRep *loading = Capture([window contentView], [scroll frame], path);
                CGFloat bg = Brightness([loading colorAtX:10 y:80]);
                Check(dark ? bg < .3 : bg > .85, @"native loading background follows appearance");
                Check(Contrasting(loading, 180, 750, bg, .15) > 40, @"loading glyphs contrast");
                [table setDataSource:controller]; controller->rows = 0; [table reloadData];
                NSBitmapImageRep *empty = Capture([window contentView], [scroll frame], [output stringByAppendingPathComponent:[NSString stringWithFormat:@"empty-d%lu-a%lu.png",dark,alternating]]);
                CGFloat emptyBG = Brightness([empty colorAtX:10 y:80]);
                Check(dark ? emptyBG < .3 : emptyBG > .85, @"native empty background follows appearance");
                controller->rows = 3; [table reloadData];
            }
            InspectScroller(appearance, [NSString stringWithUTF8String:argv[2]], output, dark);
        }
        fprintf(stdout, "PASS: %u native table, loading, empty, and scroller checks\n", assertions);
        [window orderOut:nil];
    }
    return 0;
}
