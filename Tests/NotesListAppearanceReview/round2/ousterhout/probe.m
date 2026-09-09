#import <Cocoa/Cocoa.h>
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "NSBezierPath_NV.h"

static NSUInteger checks;
static void Check(BOOL result, const char *message) {
    if (!result) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    checks++;
}
static NSColor *RGB(NSColor *color) { return [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; }
static BOOL Same(NSColor *a, NSColor *b, CGFloat tolerance) {
    a = RGB(a); b = RGB(b);
    return a && b && fabs(a.redComponent-b.redComponent)<tolerance && fabs(a.greenComponent-b.greenComponent)<tolerance &&
        fabs(a.blueComponent-b.blueComponent)<tolerance && fabs(a.alphaComponent-b.alphaComponent)<tolerance;
}
static NSColor *Resolved(NSColor *color, NSAppearance *appearance) {
    __block NSColor *result;
    [appearance performAsCurrentDrawingAppearance:^{ result = RGB(color); }];
    return result;
}
static CGFloat Brightness(NSColor *color) {
    color = RGB(color);
    return .2126*color.redComponent + .7152*color.greenComponent + .0722*color.blueComponent;
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]]; }

@implementation GlobalPrefs
+ (id)defaultPrefs { static id value; if (!value) value = [[self alloc] init]; return value; }
- (float)tableFontSize { return 15; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)tableColumnsShowPreview { return YES; }
@end

@interface ColorView : NSView { NSColor *color; }
- (void)setBackgroundColor:(NSColor *)value;
@end
@implementation ColorView
- (void)setBackgroundColor:(NSColor *)value { [value retain]; [color release]; color = value; }
- (void)dealloc { [color release]; [super dealloc]; }
@end
@interface DisplayEditor : NSTextView { @public NSUInteger updates; }
- (void)updateTextColors;
@end
@implementation DisplayEditor
- (void)updateTextColors { updates++; }
@end
@interface CountedTable : NSTableView { @public NSUInteger redraws; }
@end
@implementation CountedTable
- (void)setNeedsDisplay:(BOOL)value { if (value) redraws++; [super setNeedsDisplay:value]; }
@end
@interface Browser : NSWindowController {
@public
    NSWindow *window;
    ColorView *mainView;
    CountedTable *notesTableView;
    NSScrollView *notesScrollView;
    NSView *notesSubview, *splitSubview;
    NSSplitViewController *browserSplitController;
    NSSplitView *splitView;
    NSButton *createNoteButton;
    DisplayEditor *textView;
    NSColor *backgrndColor, *foregrndColor;
    BOOL browserHorizontalLayout, awakenedViews;
    NSInteger userScheme;
    NSUInteger deliveries;
}
- (void)setupBrowserContent;
- (void)browserAppearanceChanged;
- (void)updateColorScheme;
- (void)setBackgrndColor:(NSColor *)color;
- (void)setForegrndColor:(NSColor *)color;
@end
#include "appearance-view.inc"
@implementation Browser
#include "setup.inc"
#include "controller.inc"
- (void)setBackgrndColor:(NSColor *)value { [value retain]; [backgrndColor release]; backgrndColor = value; }
- (void)setForegrndColor:(NSColor *)value { [value retain]; [foregrndColor release]; foregrndColor = value; }
@end
@interface CountedBrowser : Browser
@end
@implementation CountedBrowser
- (void)browserAppearanceChanged { deliveries++; [super browserAppearanceChanged]; }
@end

@interface LabelCache : NSObject { NSMutableDictionary *labelImages; }
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)highlighted;
- (NSUInteger)count;
@end
@implementation LabelCache
#include "labels.inc"
- (NSUInteger)count { return [labelImages count]; }
- (void)dealloc { [labelImages release]; [super dealloc]; }
@end
@interface RecordingCache : LabelCache { @public NSImage *lastImage; NSUInteger requests; }
@end
@implementation RecordingCache
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)highlighted {
    requests++;
    lastImage = [super cachedLabelImageForWord:word highlighted:highlighted];
    return lastImage;
}
@end
@interface LibraryStub : NSObject { @public RecordingCache *cache; }
- (id)labelsListDataSource;
@end
@implementation LibraryStub
- (id)labelsListDataSource { return cache; }
@end
@interface NoteFixture : NSObject { @public NSString *labelString; LibraryStub *delegate; }
- (NSArray *)orderedLabelTitles;
- (NSSize)sizeOfLabelBlocks;
- (void)drawLabelBlocksInRect:(NSRect)rect rightAlign:(BOOL)right highlighted:(BOOL)highlighted;
- (void)_drawLabelBlocksInRect:(NSRect)rect rightAlign:(BOOL)right highlighted:(BOOL)highlighted getSizeOnly:(NSSize *)size;
@end
@implementation NoteFixture
- (NSArray *)orderedLabelTitles { return @[labelString]; }
#include "note-drawing.inc"
@end

@interface ContentProbe : NSView {
@public
    NSAttributedString *single, *multi;
    NoteFixture *note;
    NSColor *observedBody, *observedBackground;
    NSUInteger draws;
    NSImage *drawnTag;
    BOOL rightAligned;
}
@end
@implementation ContentProbe
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    draws++;
    [observedBackground release]; observedBackground = [RGB(NSColor.textBackgroundColor) retain];
    [observedBody release]; observedBody = [RGB([single attribute:NSForegroundColorAttributeName atIndex:6 effectiveRange:NULL]) retain];
    [NSColor.textBackgroundColor setFill]; NSRectFill(self.bounds);
    [single drawInRect:NSMakeRect(10,10,280,30)];
    [multi drawInRect:NSMakeRect(10,55,280,70)];
    [note drawLabelBlocksInRect:NSMakeRect(300,43,150,20) rightAlign:rightAligned highlighted:NO];
    drawnTag = note->delegate->cache->lastImage;
}
- (void)dealloc { [single release]; [multi release]; [observedBody release]; [observedBackground release]; [super dealloc]; }
@end

static Browser *MakeBrowser(NSAppearance *appearance) {
    Browser *c = [[[CountedBrowser alloc] init] autorelease];
    c->window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    [c setWindow:c->window]; [c->window setReleasedWhenClosed:NO]; [c->window setAppearance:appearance];
    c->mainView = [[[ColorView alloc] initWithFrame:NSMakeRect(0,0,640,500)] autorelease];
    [c->window setContentView:c->mainView];
    c->notesScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,640,180)] autorelease];
    c->notesTableView = [[[CountedTable alloc] initWithFrame:NSMakeRect(0,0,640,180)] autorelease];
    [c->notesScrollView setDocumentView:c->notesTableView];
    c->textView = [[[DisplayEditor alloc] initWithFrame:NSMakeRect(0,0,640,280)] autorelease];
    [c setupBrowserContent];
    [c->splitSubview addSubview:c->textView];
    c->userScheme = 2; // A custom editor scheme must not own the list appearance.
    [c setBackgrndColor:NSColor.greenColor]; [c setForegrndColor:NSColor.redColor];
    [c updateColorScheme];
    c->awakenedViews = YES;
    [c->mainView layoutSubtreeIfNeeded];
    Pump();
    return c;
}
static NSColor *TagFill(NSImage *image) {
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation] autorelease];
    CGFloat sx = bitmap.pixelsWide / image.size.width, sy = bitmap.pixelsHigh / image.size.height;
    return [bitmap colorAtX:(NSInteger)(3*sx) y:(NSInteger)(2*sy)];
}
static NSUInteger GlyphPixels(NSBitmapImageRep *bitmap, NSRect rect, CGFloat scale, CGFloat background) {
    NSUInteger count = 0;
    for (NSInteger y=NSMinY(rect)*scale; y<NSMaxY(rect)*scale; y++)
        for (NSInteger x=NSMinX(rect)*scale; x<NSMaxX(rect)*scale; x++)
            if (fabs(Brightness([bitmap colorAtX:x y:y])-background) > .12) count++;
    return count;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *output = [NSString stringWithUTF8String:argv[1]];
        NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        NSAppearance *dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        Browser *a = MakeBrowser(light), *b = MakeBrowser(dark);
        NSArray *owners = @[a,b];
        RecordingCache *cache = [[[RecordingCache alloc] init] autorelease];
        LibraryStub *library = [[[LibraryStub alloc] init] autorelease]; library->cache = cache;
        NoteFixture *note = [[[NoteFixture alloc] init] autorelease]; note->delegate = library; note->labelString = @"shared";
        ContentProbe *view = [[[ContentProbe alloc] initWithFrame:NSMakeRect(0,0,600,150)] autorelease]; view->note = note;
        NSAttributedString *body = [[[NSAttributedString alloc] initWithString:@"Cached source across native attachments."] autorelease];
        view->single = [[@"Title" attributedSingleLinePreviewFromBodyText:body upToWidth:280] retain];
        view->multi = [[@"Title" attributedMultiLinePreviewFromBodyText:body upToWidth:280 intrusionWidth:0] retain];
        NSAttributedString *singleIdentity = view->single, *multiIdentity = view->multi;
        NSMutableDictionary *tagIdentities = [NSMutableDictionary dictionary];
        for (NSUInteger turn=0; turn<16; turn++) {
            Browser *c = owners[turn%2], *peer = owners[1-turn%2];
            NSAppearance *desired = [[c->window.effectiveAppearance name] isEqualToString:dark.name] ? light : dark;
            NSAppearance *foreign = desired == dark ? light : dark;
            NSUInteger deliveries = c->deliveries, peerDeliveries = peer->deliveries;
            NSUInteger redraws = c->notesTableView->redraws;
            [c->window setAppearance:desired];
            [c->mainView layoutSubtreeIfNeeded];
            Pump();
            (void)[c->splitSubview effectiveAppearance];
            // Native view movement supplies inheritance. No explicit appearance block encloses capture.
            [view removeFromSuperview];
            [c->notesSubview addSubview:view];
            Check([view appearance] == nil, "the shared content view retains native appearance inheritance");
            Check([[[c->notesSubview effectiveAppearance] name] isEqualToString:desired.name], "attached list inherits the destination appearance");
            Check([[view.effectiveAppearance name] isEqualToString:desired.name], "reattached content inherits its destination appearance");
            [NSAppearance setCurrentAppearance:foreign];
            NSUInteger requests = cache->requests;
            NSSize measured = [note sizeOfLabelBlocks];
            Check(measured.width > 20 && measured.height > 10 && cache->requests == requests+1, "production size measurement requests a cached raster outside drawing");
            NSColor *foreignFill = Resolved(NSColor.secondaryLabelColor, foreign);
            Check(Same(TagFill(cache->lastImage), foreignFill, .02), "the preflight measurement uses its caller appearance");
            view->rightAligned = turn%2;
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            Pump();
            Check(bitmap != nil && bitmap.pixelsWide>0 && view->draws>turn, "native display captures the moved content");
            Check(c->deliveries>deliveries, "automatic native appearance callback reaches the owner");
            Check(peer->deliveries==peerDeliveries, "automatic delivery does not notify the peer owner");
            Check(c->notesTableView->redraws>redraws, "the native callback requests a new list redraw");
            Check(Same(view->observedBody, Resolved(NSColor.secondaryLabelColor, desired), .001), "cached preview color resolves inside its native destination draw");
            Check(Same(view->observedBackground, Resolved(NSColor.textBackgroundColor, desired), .001), "the native drawing context supplies the destination background");
            NSColor *desiredFill = Resolved(NSColor.secondaryLabelColor, desired);
            Check(Same(TagFill(view->drawnTag), desiredFill, .02), "native tag draw uses its destination color after a foreign measurement");
            NSImage *previous = [tagIdentities objectForKey:desired.name];
            if (previous) Check(previous==view->drawnTag, "returning to an appearance reuses its raster across owners");
            else [tagIdentities setObject:view->drawnTag forKey:desired.name];
            Check([NSAppearance currentAppearance]==foreign, "native drawing restores the foreign caller appearance");
            Check(view->single==singleIdentity && view->multi==multiIdentity, "view movement does not rebuild either preview object");
            Check(Same(c->textView.backgroundColor, NSColor.greenColor, .001), "automatic list appearance retains the custom editor background");
            CGFloat scale = bitmap.pixelsWide / NSWidth(view.bounds);
            if (turn==0) printf("Native capture scale: %.0fx (%ld by %ld pixels)\n", scale, (long)bitmap.pixelsWide, (long)bitmap.pixelsHigh);
            CGFloat background = Brightness([bitmap colorAtX:590*scale y:120*scale]);
            Check(desired==dark ? background<.3 : background>.85, "captured background matches destination light or dark mode");
            CGFloat tagX = view->rightAligned ? 450-view->drawnTag.size.width-4 : 300;
            NSColor *tagPixel = [bitmap colorAtX:(tagX+3)*scale y:27*scale];
            CGFloat expectedFill = Brightness(desiredFill)*desiredFill.alphaComponent + Brightness(view->observedBackground)*(1-desiredFill.alphaComponent);
            Check(fabs(Brightness(tagPixel)-expectedFill)<.04, "the production left or right tag path draws its destination fill into the native view");
            Check(GlyphPixels(bitmap, NSMakeRect(60,10,200,28), scale, background)>50, "the unchanged single-line preview draws contrasting glyphs");
            Check(GlyphPixels(bitmap, NSMakeRect(10,76,270,32), scale, background)>50, "the unchanged multiline preview draws contrasting glyphs");
            if (turn<4) {
                NSString *path = [output stringByAppendingPathComponent:[NSString stringWithFormat:@"attachment-%lu.png", (unsigned long)turn]];
                Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], "native attachment capture writes");
            }
            [NSAppearance setCurrentAppearance:nil];
        }
        Check(cache.count==2, "measurement and drawing retain exactly two shared tag rasters");
        printf("PASS: %lu checks across 16 native window changes and content attachments\n", (unsigned long)checks);
        [a->window orderOut:nil]; [b->window orderOut:nil];
    }
    return 0;
}
