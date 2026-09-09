#import <Cocoa/Cocoa.h>
#import "NSBezierPath_NV.h"

static NSUInteger checks, disposedControllers, totalCallbacks, detachedCallbacks;
static void Check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    checks++;
}
static NSColor *RGB(NSColor *color) { return [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; }
static BOOL Same(NSColor *left, NSColor *right) {
    left = RGB(left); right = RGB(right);
    return left && right && fabs(left.redComponent-right.redComponent)<.005 &&
        fabs(left.greenComponent-right.greenComponent)<.005 && fabs(left.blueComponent-right.blueComponent)<.005 &&
        fabs(left.alphaComponent-right.alphaComponent)<.005;
}
static NSColor *Resolved(NSColor *color, NSAppearance *appearance) {
    __block NSColor *result;
    [appearance performAsCurrentDrawingAppearance:^{ result = RGB(color); }];
    return result;
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]]; }

@interface GlobalPrefs : NSObject
+ (id)defaultPrefs;
- (float)tableFontSize;
@end
@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (float)tableFontSize { return 15; }
@end

@interface LabelCache : NSObject { NSMutableDictionary *labelImages; }
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)highlighted;
- (NSUInteger)count;
@end
@implementation LabelCache
#include "label.inc"
- (NSUInteger)count { return [labelImages count]; }
- (void)dealloc { [labelImages release]; [super dealloc]; }
@end

@interface ColorView : NSView
- (void)setBackgroundColor:(NSColor *)color;
@end
@implementation ColorView
- (void)setBackgroundColor:(NSColor *)color {}
@end
@interface DisplayEditor : NSTextView
- (void)updateTextColors;
@end
@implementation DisplayEditor
- (void)updateTextColors {}
@end

@interface SampleTable : NSTableView {
@public
    LabelCache *cache;
    NSImage *lastImage;
    NSColor *drawingFill, *drawingBackground;
    NSUInteger redraws, draws;
}
@end
@implementation SampleTable
- (void)setNeedsDisplay:(BOOL)value { if (value) redraws++; [super setNeedsDisplay:value]; }
- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty]; draws++;
    [drawingFill release]; drawingFill = [RGB([NSColor secondaryLabelColor]) retain];
    [drawingBackground release]; drawingBackground = [RGB([self backgroundColor]) retain];
    lastImage = [cache cachedLabelImageForWord:@"reopened" highlighted:NO];
    [lastImage drawInRect:NSMakeRect(12,12,lastImage.size.width,lastImage.size.height)];
}
- (void)dealloc { [drawingFill release]; [drawingBackground release]; [super dealloc]; }
@end

@interface Browser : NSWindowController {
@public
    NSWindow *window;
    ColorView *mainView;
    SampleTable *notesTableView;
    NSScrollView *notesScrollView;
    NSView *notesSubview, *splitSubview;
    NSSplitViewController *browserSplitController;
    NSSplitView *splitView;
    NSButton *createNoteButton;
    DisplayEditor *textView;
    NSColor *backgrndColor, *foregrndColor;
    BOOL browserHorizontalLayout, awakenedViews;
    NSInteger userScheme;
    NSUInteger callbacks;
}
- (void)setupBrowserContent;
- (void)browserAppearanceChanged;
- (void)updateColorScheme;
- (void)setBackgrndColor:(NSColor *)color;
- (void)setForegrndColor:(NSColor *)color;
@end
#include "view.inc"
@implementation Browser
#include "setup.inc"
#include "controller.inc"
- (void)setBackgrndColor:(NSColor *)color { [color retain]; [backgrndColor release]; backgrndColor=color; }
- (void)setForegrndColor:(NSColor *)color { [color retain]; [foregrndColor release]; foregrndColor=color; }
- (void)dealloc {
    disposedControllers++;
    [window setWindowController:nil];
    [window close];
    [browserSplitController release];
    [createNoteButton release];
    [backgrndColor release]; [foregrndColor release];
    [super dealloc];
}
@end
@interface CountedBrowser : Browser
@end
@implementation CountedBrowser
- (void)browserAppearanceChanged { callbacks++; totalCallbacks++; [super browserAppearanceChanged]; }
@end
@interface DetachedView : NVBrowserContentView
@end
@implementation DetachedView
- (void)viewDidChangeEffectiveAppearance { detachedCallbacks++; [super viewDidChangeEffectiveAppearance]; }
@end

static Browser *MakeBrowser(LabelCache *cache) {
    Browser *c = [[CountedBrowser alloc] init];
    c->window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,500)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    [c->window setReleasedWhenClosed:NO];
    [c setWindow:c->window];
    c->mainView = [[[ColorView alloc] initWithFrame:NSMakeRect(0,0,640,500)] autorelease];
    [c->window setContentView:c->mainView];
    c->notesScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,640,180)] autorelease];
    c->notesTableView = [[[SampleTable alloc] initWithFrame:NSMakeRect(0,0,640,180)] autorelease];
    c->notesTableView->cache = cache;
    [c->notesScrollView setDocumentView:c->notesTableView];
    c->textView = [[[DisplayEditor alloc] initWithFrame:NSMakeRect(0,0,640,280)] autorelease];
    [c setupBrowserContent];
    [c->splitSubview addSubview:c->textView];
    c->awakenedViews = YES;
    c->userScheme = 3;
    // Initial setup occurs once. No test calls viewDidChangeEffectiveAppearance or browserAppearanceChanged.
    [c setBackgrndColor:[NSColor textBackgroundColor]];
    [c updateColorScheme];
    [c->mainView layoutSubtreeIfNeeded];
    [c->splitSubview effectiveAppearance];
    // Register the window with AppKit without exposing or activating the fixture.
    [c->window setAlphaValue:0];
    [c->window orderFront:nil];
    [c->window orderOut:nil];
    return c;
}
static void Draw(Browser *c) {
    [c->mainView layoutSubtreeIfNeeded];
    NSRect bounds = c->notesTableView.bounds;
    NSBitmapImageRep *bitmap = [c->notesTableView bitmapImageRepForCachingDisplayInRect:bounds];
    [c->notesTableView cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
    Check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0 && c->notesTableView->draws > 0,
          "hidden native table receives an AppKit drawing context");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        NSArray *appearances = @[[NSAppearance appearanceNamed:NSAppearanceNameAqua],
            [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],
            [NSAppearance appearanceNamed:NSAppearanceNameAccessibilityHighContrastAqua],
            [NSAppearance appearanceNamed:NSAppearanceNameAccessibilityHighContrastDarkAqua]];
        LabelCache *cache = [[[LabelCache alloc] init] autorelease];
        NSMutableDictionary *imagesByColor = [NSMutableDictionary dictionary];
        NSUInteger callbacksBeforeResolution=0, callbacksAfterResolution=0;
        for (NSUInteger generation=0; generation<24; generation++) {
            NSAutoreleasePool *generationPool = [[NSAutoreleasePool alloc] init];
                [NSApp setAppearance:appearances[generation % 4]];
                Browser *c = MakeBrowser(cache);
                Check([c->window appearance] == nil && ![c->window isVisible], "fixture window inherits the application and stays ordered out");
                Draw(c);
                Check([[[c->notesSubview effectiveAppearance] name] isEqual:[appearances[generation % 4] name]],
                      "new hidden list starts with the current application appearance");
                Check(Same(c->notesTableView->drawingBackground, Resolved([NSColor textBackgroundColor], appearances[generation % 4])),
                      "new hidden list draws its current background before an appearance transition");
                NSImage *reused = [imagesByColor objectForKey:c->notesTableView->drawingFill];
                Check(!reused || reused == c->notesTableView->lastImage,
                      "new hidden list reuses its current image before an appearance transition");
                for (NSUInteger turn=0; turn<4; turn++) {
                    NSAppearance *appearance = appearances[(generation + turn + 1) % 4];
                    NSUInteger prior = c->callbacks, redraws = c->notesTableView->redraws;
                    [NSApp setAppearance:appearance];
                    Pump();
                    callbacksBeforeResolution += c->callbacks - prior;
                    [c->splitSubview effectiveAppearance];
                    [c->notesSubview effectiveAppearance];
                    [c->notesTableView effectiveAppearance];
                    Draw(c);
                    callbacksAfterResolution += c->callbacks - prior;
                    if(c->callbacks <= prior) fprintf(stderr, "TRACE generation=%lu turn=%lu app=%s window=%s split=%s table=%s callbacks=%lu prior=%lu\n", generation, turn,
                        NSApp.effectiveAppearance.name.UTF8String, c->window.effectiveAppearance.name.UTF8String,
                        c->splitSubview.effectiveAppearance.name.UTF8String, c->notesTableView.effectiveAppearance.name.UTF8String, c->callbacks, prior);
                    Check(c->callbacks > prior, "hidden application appearance reaches its controller automatically");
                    Check(c->notesTableView->redraws > redraws, "automatic callback requests a hidden list redraw");
                    Check([[[c->notesSubview effectiveAppearance] name] isEqual:appearance.name], "hidden list inherits the application appearance");
                    Check(Same(c->notesTableView->drawingBackground, Resolved([NSColor textBackgroundColor], appearance)),
                          "first hidden draw uses the current background");
                    Check(Same(c->notesTableView->drawingFill, Resolved([NSColor secondaryLabelColor], appearance)),
                          "first hidden tag draw uses the current drawing appearance");
                    NSImage *image = c->notesTableView->lastImage;
                    NSColor *color = c->notesTableView->drawingFill;
                    NSImage *priorImage = [imagesByColor objectForKey:color];
                    Check(!priorImage || priorImage == image, "recreated controller reuses each retained color image");
                    for (NSColor *other in imagesByColor) {
                        if (![other isEqual:color]) Check([imagesByColor objectForKey:other] != image,
                            "retained cache gives different colors different images");
                    }
                    [imagesByColor setObject:image forKey:color];
                    Check(![c->window isVisible], "appearance delivery does not order out windows in");
                }
                // Retain the former production content view after its controller is destroyed.
                NSView *stale = [c->splitSubview retain];
                [stale removeFromSuperview];
                NSUInteger disposed = disposedControllers;
                [c->window close];
                [c release];
                [generationPool drain];
                Check(disposedControllers == disposed + 1, "fixture controller is destroyed before the next generation");
                Check(stale.window == nil, "retained former content view has no window after teardown");
                NSUInteger callbacks = totalCallbacks;
                [stale setAppearance:appearances[(generation + 1) % 4]];
                [stale effectiveAppearance];
                Pump();
                Check(totalCallbacks == callbacks, "detached automatic appearance delivery reaches no destroyed controller");
                [stale release];
                Check([cache count] == [imagesByColor count], "controller recreation adds no duplicate cache colors");
        }
        // An observed subclass establishes that AppKit actually delivered a detached callback.
        DetachedView *detached = [[[DetachedView alloc] initWithFrame:NSMakeRect(0,0,10,10)] autorelease];
        [detached setAppearance:appearances[0]]; [detached effectiveAppearance];
        NSUInteger callbacks = totalCallbacks, before = detachedCallbacks;
        [detached setAppearance:appearances[1]]; [detached effectiveAppearance];
        Check(detachedCallbacks > before && totalCallbacks == callbacks,
              "AppKit detached callback executes the production nil-window route safely");
        Check(disposedControllers == 24, "all fixture controller generations were destroyed");
        fprintf(stdout,"PASS: %lu checks; 24 controller generations; 96 hidden application transitions; %lu retained colors; "
            "callbacks before resolution %lu, after resolution %lu; detached callbacks %lu\n",
            checks, [cache count], callbacksBeforeResolution, callbacksAfterResolution, detachedCallbacks);
        [NSApp setAppearance:nil];
    }
    return 0;
}
