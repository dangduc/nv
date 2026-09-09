#import <Cocoa/Cocoa.h>
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "NSBezierPath_NV.h"

static float fontSize = 15;
@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (float)tableFontSize { return fontSize; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)tableColumnsShowPreview { return YES; }
@end

@interface ReviewLabels : NSObject { NSMutableDictionary *labelImages; }
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)selected;
- (void)invalidateCachedLabelImages;
- (NSUInteger)cacheCount;
@end
@implementation ReviewLabels
#include "labels.inc"
#include "invalidate.inc"
- (NSUInteger)cacheCount { return [labelImages count]; }
- (void)dealloc { [labelImages release]; [super dealloc]; }
@end

@interface ReviewView : NSView { NSColor *color; }
@property (retain) NSColor *backgroundColor;
@end
@implementation ReviewView
@synthesize backgroundColor = color;
- (void)dealloc { [color release]; [super dealloc]; }
@end
@interface ReviewEditor : NSTextView { @public NSUInteger refreshes; }
- (void)updateTextColors;
@end
@implementation ReviewEditor
- (void)updateTextColors { refreshes++; }
@end
@interface ReviewBrowser : NSObject {
@public
    ReviewView *mainView;
    NSTableView *notesTableView;
    ReviewEditor *textView;
    NSView *splitView;
    NSColor *backgrndColor;
}
- (void)updateColorScheme;
@end
@implementation ReviewBrowser
#include "colors.inc"
- (id)init {
    if ((self = [super init])) {
        mainView = [[ReviewView alloc] initWithFrame:NSMakeRect(0,0,500,500)];
        notesTableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,500,180)];
        textView = [[ReviewEditor alloc] initWithFrame:NSMakeRect(0,0,500,200)];
        splitView = [[NSView alloc] initWithFrame:NSMakeRect(0,0,500,500)];
        backgrndColor = [[NSColor colorWithCalibratedRed:.15 green:.65 blue:.2 alpha:1] retain];
    }
    return self;
}
- (void)dealloc {
    [mainView release]; [notesTableView release]; [textView release];
    [splitView release]; [backgrndColor release]; [super dealloc];
}
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr,"FAIL %s\n", [message UTF8String]); exit(1); }
    checks++;
}
static NSColor *RGB(NSColor *color) { return [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; }
static BOOL SameColor(NSColor *a, NSColor *b) {
    a=RGB(a); b=RGB(b);
    return a && b && fabs(a.redComponent-b.redComponent)<.0001 && fabs(a.greenComponent-b.greenComponent)<.0001 &&
        fabs(a.blueComponent-b.blueComponent)<.0001 && fabs(a.alphaComponent-b.alphaComponent)<.0001;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        ReviewLabels *labels=[[[ReviewLabels alloc] init] autorelease];
        ReviewBrowser *browser=[[[ReviewBrowser alloc] init] autorelease];
        NSMutableAttributedString *source=[[[NSMutableAttributedString alloc] initWithString:@"A source body with custom red attributes." attributes:@{NSForegroundColorAttributeName:NSColor.redColor}] autorelease];
        NSAttributedString *original=[[source copy] autorelease];
        NSAttributedString *single=[@"Title" attributedSingleLinePreviewFromBodyText:source upToWidth:600];
        NSAttributedString *multi=[@"Title" attributedMultiLinePreviewFromBodyText:source upToWidth:600 intrusionWidth:44];
        Check(single && multi, @"both production preview formats exist");
        Check([[single string] hasPrefix:@"Title"] && [[multi string] hasPrefix:@"Title\n"], @"preview formats preserve title placement");
        Check([single attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]==nil && [multi attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]==nil,
            @"preview formatters leave title colors to their cells");
        NSArray *appearances=@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua,NSAppearanceNameAccessibilityHighContrastAqua,NSAppearanceNameAccessibilityHighContrastDarkAqua];
        NSMutableDictionary *imagesByColor=[NSMutableDictionary dictionary];
        NSMutableSet *distinctOrdinaryColors=[NSMutableSet set];
        // Interleave eight virtual draws through one library-owned image cache.
        // Revisit the same appearances without rebuilding either attributed preview.
        for (NSUInteger pass=0;pass<2;pass++) {
            for (NSString *name in appearances) {
                NSAppearance *appearance=[NSAppearance appearanceNamed:name];
                Check(appearance!=nil,@"the requested system appearance exists");
                [appearance performAsCurrentDrawingAppearance:^{
                    NSColor *expected=NSColor.secondaryLabelColor;
                    Check(SameColor([single attribute:NSForegroundColorAttributeName atIndex:6 effectiveRange:NULL], expected), @"the cached single-line preview resolves its system body color");
                    Check(SameColor([multi attribute:NSForegroundColorAttributeName atIndex:6 effectiveRange:NULL], expected), @"the cached multiline preview resolves its system body color");
                    [distinctOrdinaryColors addObject:RGB(expected)];
                    for (NSUInteger selected=0;selected<2;selected++) {
                        NSColor *fill=RGB(selected ? NSColor.alternateSelectedControlTextColor : expected);
                        NSArray *key=@[@(selected),fill];
                        NSImage *img=[labels cachedLabelImageForWord:@"work" highlighted:selected];
                        Check(img!=nil && img.size.width>10 && img.size.height>8,@"tag cache returns a nonempty raster image");
                        NSImage *previous=[imagesByColor objectForKey:key];
                        if (previous) Check(previous==img,@"equal resolved colors reuse the existing shared raster");
                        else {
                            for (NSImage *other in [imagesByColor allValues]) Check(other!=img,@"different resolved colors cannot reuse the same cached raster");
                            [imagesByColor setObject:img forKey:key];
                        }
                    }
                    [browser updateColorScheme];
                    Check(SameColor(browser->notesTableView.backgroundColor,NSColor.textBackgroundColor),@"list background ignores the custom editor color");
                    Check(SameColor(browser->textView.backgroundColor,browser->backgrndColor),@"editor background keeps the selected custom color");
                    Check(SameColor(browser->mainView.backgroundColor,NSColor.windowBackgroundColor),@"the containing view keeps its semantic window color");
                }];
            }
        }
        Check(distinctOrdinaryColors.count>=2,@"the appearance matrix exercises distinct light and dark cache colors");
        Check(labels.cacheCount==imagesByColor.count,@"repeated appearances add no redundant tag cache entries");
        Check([source isEqualToAttributedString:original],@"preview formatting and appearance changes preserve the source attributes");
        Check(browser->textView->refreshes==8,@"color updates refresh the editor once per request");
        NSImage *before=[[labels cachedLabelImageForWord:@"work" highlighted:NO] retain];
        fontSize=22;
        [labels invalidateCachedLabelImages];
        Check(labels.cacheCount==0,@"font invalidation clears all appearance variants together");
        NSImage *after=[labels cachedLabelImageForWord:@"work" highlighted:NO];
        Check(after!=before && after.size.height>before.size.height,@"font invalidation replaces the raster with the new font size");
        [before release];
        printf("PASS: %lu ownership and cache assertions\n",(unsigned long)checks);
    }
    return 0;
}
