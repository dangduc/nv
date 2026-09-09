#import <Cocoa/Cocoa.h>
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "NSBezierPath_NV.h"

static unsigned checks;
static void Check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    checks++;
}
static BOOL showList = YES;
@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (float)tableFontSize { return 15; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)tableColumnsShowPreview { return YES; }
- (BOOL)showNotesList { return showList; }
- (NSDictionary *)noteBodyAttributes { return @{NSFontAttributeName:[NSFont systemFontOfSize:14]}; }
@end

@interface ColorView : NSView { NSColor *color; }
- (void)setBackgroundColor:(NSColor *)value;
@end
@implementation ColorView
- (void)setBackgroundColor:(NSColor *)value { [color release]; color = [value retain]; }
- (void)dealloc { [color release]; [super dealloc]; }
@end

@interface RecordingTable : NSTableView { @public NSUInteger redrawRequests; }
@end
@implementation RecordingTable
- (void)setNeedsDisplay:(BOOL)value { if(value) redrawRequests++; [super setNeedsDisplay:value]; }
@end

@class FixtureController;
static FixtureController *NVControllerForView(NSView *view) { return (id)[[view window] windowController]; }
#define AppController FixtureController
#define IsLionOrLater YES
@interface DisplayEditor : NSTextView { @public GlobalPrefs *prefsController; NSUInteger updates; }
- (void)updateTextColors;
- (NSColor *)_insertionPointColorForForegroundColor:(NSColor *)fg backgroundColor:(NSColor *)bg;
- (NSColor *)_selectionColorForForegroundColor:(NSColor *)fg backgroundColor:(NSColor *)bg;
- (NSDictionary *)preferredLinkAttributes;
- (BOOL)textFinderIsVisible;
@end

@interface FixtureController : NSWindowController {
@public
    NSWindow *window;
    ColorView *mainView;
    RecordingTable *notesTableView;
    NSScrollView *notesScrollView;
    NSView *notesSubview, *splitSubview;
    NSSplitViewController *browserSplitController;
    NSSplitView *splitView;
    NSButton *createNoteButton;
    DisplayEditor *textView;
    NSColor *backgrndColor, *foregrndColor;
    GlobalPrefs *prefsController;
    BOOL browserHorizontalLayout, awakenedViews;
    NSInteger userScheme;
    CGFloat pendingListHeight;
    id currentNote;
    NSSearchField *field;
    NSUInteger appearanceCallbacks;
}
- (void)setupBrowserContent;
- (void)browserAppearanceChanged;
- (void)updateColorScheme;
- (void)updateNotesListVisibility;
- (void)setNotesListHeight:(CGFloat)height;
- (CGFloat)notesListHeight;
- (void)restoreNotesListHeight;
- (void)setBackgrndColor:(NSColor *)value;
- (void)setForegrndColor:(NSColor *)value;
- (NSColor *)backgrndColor;
- (NSColor *)foregrndColor;
- (void)focusNoteBody;
@end

@implementation DisplayEditor
#include "editor.inc"
// Cursor, selection, and link computations are fixed collaborators. The display setters are AppKit.
- (NSColor *)_insertionPointColorForForegroundColor:(NSColor *)fg backgroundColor:(NSColor *)bg { return fg; }
- (NSColor *)_selectionColorForForegroundColor:(NSColor *)fg backgroundColor:(NSColor *)bg { return [NSColor selectedTextBackgroundColor]; }
- (NSDictionary *)preferredLinkAttributes { return @{NSForegroundColorAttributeName:[NSColor linkColor]}; }
- (BOOL)textFinderIsVisible { return NO; }
@end

@interface CountedEditor : DisplayEditor
@end
@implementation CountedEditor
- (void)updateTextColors { updates++; [super updateTextColors]; }
@end

#include "appearance-view.inc"
@implementation FixtureController
#include "setup.inc"
#include "controller.inc"
- (void)restoreNotesListHeight { [self setNotesListHeight:pendingListHeight]; }
- (void)setBackgrndColor:(NSColor *)value { [value retain]; [backgrndColor release]; backgrndColor = value; }
- (void)setForegrndColor:(NSColor *)value { [value retain]; [foregrndColor release]; foregrndColor = value; }
- (NSColor *)backgrndColor { return backgrndColor; }
- (NSColor *)foregrndColor { return foregrndColor; }
- (void)focusNoteBody { [window makeFirstResponder:textView]; }
@end
@interface CountedController : FixtureController
@end
@implementation CountedController
- (void)browserAppearanceChanged { appearanceCallbacks++; [super browserAppearanceChanged]; }
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

@interface StorageObserver : NSObject <NSTextStorageDelegate> { @public NSUInteger edits; }
@end
@implementation StorageObserver
- (void)textStorage:(NSTextStorage *)storage didProcessEditing:(NSTextStorageEditActions)actions range:(NSRange)range changeInLength:(NSInteger)delta { edits++; }
@end

static NSColor *Resolved(NSColor *color, NSAppearance *appearance) {
    __block NSColor *result = nil;
    [appearance performAsCurrentDrawingAppearance:^{ result = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; }];
    return result;
}
static BOOL SameColor(NSColor *left, NSColor *right) {
    CGFloat r1,g1,b1,a1,r2,g2,b2,a2;
    [[left colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [[right colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return fabs(r1-r2)<.005 && fabs(g1-g2)<.005 && fabs(b1-b2)<.005 && fabs(a1-a2)<.005;
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
}
static FixtureController *MakeController(NSTextStorage *storage, NSAppearance *appearance) {
    FixtureController *c = [[CountedController alloc] init];
    c->window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [c setWindow:c->window];
    [c->window setReleasedWhenClosed:NO];
    [c->window setAppearance:appearance];
    c->mainView = [[ColorView alloc] initWithFrame:NSMakeRect(0,0,640,500)];
    [c->window setContentView:c->mainView];
    c->notesScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,640,180)];
    c->notesTableView = [[RecordingTable alloc] initWithFrame:NSMakeRect(0,0,640,180)];
    [c->notesScrollView setDocumentView:c->notesTableView];
    c->prefsController = [GlobalPrefs defaultPrefs];
    c->pendingListHeight = 180;
    [c setupBrowserContent];
    NSLayoutManager *layout = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(640,10000)] autorelease];
    [storage addLayoutManager:layout];
    [layout addTextContainer:container];
    c->textView = [[CountedEditor alloc] initWithFrame:NSMakeRect(0,0,640,280) textContainer:container];
    c->textView->prefsController = c->prefsController;
    [c->textView setAllowsUndo:YES];
    [c->splitSubview addSubview:c->textView];
    c->awakenedViews = YES;
    c->userScheme = 3;
    [c browserAppearanceChanged];
    [c->mainView layoutSubtreeIfNeeded];
    return c;
}
static NSColor *TagPixel(NSImage *image) {
    // Sample an opaque part of the translucent rounded rectangle, outside glyphs.
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]] autorelease];
    return [bitmap colorAtX:3 y:2];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSArray *appearances = @[[NSAppearance appearanceNamed:NSAppearanceNameAqua],
            [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],
            [NSAppearance appearanceNamed:NSAppearanceNameAccessibilityHighContrastAqua],
            [NSAppearance appearanceNamed:NSAppearanceNameAccessibilityHighContrastDarkAqua]];
        NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:@"Source α\r\n# Markdown and {\"json\":true}\n"] autorelease];
        FixtureController *a = MakeController(storage, appearances[0]);
        FixtureController *b = MakeController(storage, appearances[1]);
        NSArray *controllers = @[a,b];
        NSAttributedString *sourceSnapshot = [[storage copy] autorelease];
        StorageObserver *observer = [[[StorageObserver alloc] init] autorelease];
        [storage setDelegate:observer];
        NSUndoManager *undoA = [a->textView undoManager];
        NSUndoManager *undoB = [b->textView undoManager];
        [undoA removeAllActions]; [undoB removeAllActions];
        Check(undoA != nil && undoB != nil, "fixture supplies real AppKit Undo managers");
        LabelCache *cache = [[[LabelCache alloc] init] autorelease];
        NSAttributedString *single = [@"Title" attributedSingleLinePreviewFromBodyText:storage upToWidth:600];
        NSAttributedString *multi = [@"Title" attributedMultiLinePreviewFromBodyText:storage upToWidth:600 intrusionWidth:30];
        NSMutableDictionary *imagesByColor = [NSMutableDictionary dictionary];
        // Shared cache, opposing windows, custom editor colors, collapsed lists, and reordered callbacks.
        for (NSUInteger turn=0; turn<128; turn++) {
            FixtureController *c = controllers[(turn ^ (turn>>1)) & 1];
            FixtureController *peer = controllers[1 - ((turn ^ (turn>>1)) & 1)];
            NSAppearance *appearance = appearances[(turn/2 + turn%2) % [appearances count]];
            NSAppearance *peerBefore = [[peer->window effectiveAppearance] retain];
            NSColor *peerEditorBefore = [[peer backgrndColor] retain];
            BOOL custom = (turn % 3) == 0;
            c->userScheme = custom ? 2 : 3;
            NSColor *customColor = [NSColor colorWithCalibratedRed:.82 green:.61 blue:.2 alpha:1];
            if(custom) { [c setBackgrndColor:customColor]; [c setForegrndColor:[NSColor blackColor]]; [c updateColorScheme]; }
            showList = (turn % 4) < 2;
            [c updateNotesListVisibility];
            [c->window setAppearance:appearance];
            [c->splitSubview effectiveAppearance];
            [c->notesSubview effectiveAppearance];
            Pump();
            // A delayed callback must use the receiver's effective appearance even while another window draws.
            NSUInteger callbacksBefore = c->appearanceCallbacks;
            NSUInteger peerCallbacksBefore = peer->appearanceCallbacks;
            NSUInteger redrawsBefore = c->notesTableView->redrawRequests;
            [[peer->window effectiveAppearance] performAsCurrentDrawingAppearance:^{ [c->splitSubview viewDidChangeEffectiveAppearance]; }];
            Check(c->appearanceCallbacks == callbacksBefore + 1, "native view callback reaches the owning controller");
            Check(peer->appearanceCallbacks == peerCallbacksBefore, "native view callback does not reach the peer controller");
            Check(c->notesTableView->redrawRequests > redrawsBefore, "native view callback requests a list redraw");
            [c->mainView layoutSubtreeIfNeeded];
            Check([[[c->notesSubview effectiveAppearance] name] isEqual:[appearance name]], "list inherits its own window appearance");
            Check([[[c->notesTableView effectiveAppearance] name] isEqual:[appearance name]], "table inherits its own window appearance");
            Check([[[c->browserSplitController splitViewItems] firstObject] isCollapsed] == !showList, "production visibility method matches the requested state");
            Check(SameColor(Resolved([c->notesTableView backgroundColor], appearance), Resolved([NSColor textBackgroundColor], appearance)), "list background matches its own appearance");
            Check(SameColor(Resolved([c->notesScrollView backgroundColor], appearance), Resolved([NSColor textBackgroundColor], appearance)), "scroll background matches its own appearance");
            Check(SameColor(Resolved([[c->notesScrollView contentView] backgroundColor], appearance), Resolved([NSColor textBackgroundColor], appearance)), "clip background matches its own appearance");
            Check(SameColor([c backgrndColor], custom ? customColor : Resolved([NSColor textBackgroundColor], appearance)), "editor honors its independent color mode");
            Check([[[peer->window effectiveAppearance] name] isEqual:[peerBefore name]] && SameColor([peer backgrndColor], peerEditorBefore), "other window retains its appearance and editor colors");
            [peerBefore release]; [peerEditorBefore release];
            [appearance performAsCurrentDrawingAppearance:^{
                for (NSAttributedString *preview in @[single,multi]) {
                    NSUInteger bodyIndex = 6;
                    NSColor *bodyColor = [preview attribute:NSForegroundColorAttributeName atIndex:bodyIndex effectiveRange:NULL];
                    Check(SameColor(Resolved(bodyColor, appearance), Resolved([NSColor secondaryLabelColor], appearance)), "cached preview follows its drawing appearance");
                }
                for (NSUInteger selected=0; selected<2; selected++) {
                    NSColor *expected = Resolved(selected ? [NSColor alternateSelectedControlTextColor] : [NSColor secondaryLabelColor], appearance);
                    NSImage *image = [cache cachedLabelImageForWord:@"state" highlighted:selected];
                    NSColor *pixel = TagPixel(image);
                    Check(fabs([pixel alphaComponent] - [expected alphaComponent]) < .02, "tag image follows its own appearance alpha");
                    Check(SameColor(pixel, expected), "tag image follows its own appearance color");
                    NSArray *key = @[@(selected),expected];
                    NSImage *prior = [imagesByColor objectForKey:key];
                    Check(!prior || prior == image, "shared tag cache reuses each resolved color");
                    [imagesByColor setObject:image forKey:key];
                }
            }];
            Check([storage isEqualToAttributedString:sourceSnapshot] && observer->edits == 0, "appearance and list visibility preserve shared source and attributes");
            Check(![undoA canUndo] && ![undoB canUndo] && ![undoA canRedo] && ![undoB canRedo], "appearance and list visibility preserve Undo state");
        }
        Check([cache count] == [imagesByColor count], "tag cache contains only observed drawing colors");
        Check(a->appearanceCallbacks > 64 && b->appearanceCallbacks > 64, "both native content views forward explicitly delivered appearance callbacks");
        Check(a->notesTableView->redrawRequests > 64 && b->notesTableView->redrawRequests > 64, "appearance callbacks request redraws in both windows");
        Check(a->textView->updates > 32 && b->textView->updates > 32, "system appearance executes production editor display updates");
        fprintf(stdout,"PASS: %u checks; 128 ordered transitions; callbacks %lu/%lu; %lu cached colors; source edits %lu\n", checks,
            (unsigned long)a->appearanceCallbacks, (unsigned long)b->appearanceCallbacks,
            (unsigned long)[cache count], (unsigned long)observer->edits);
        [a->window close]; [b->window close];
    }
    return 0;
}
