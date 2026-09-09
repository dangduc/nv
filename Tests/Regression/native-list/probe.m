#import <Cocoa/Cocoa.h>
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"
#import "NSBezierPath_NV.h"

@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (float)tableFontSize { return 15; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)tableColumnsShowPreview { return YES; }
@end

@interface NativeLabels : NSObject { NSMutableDictionary *labelImages; }
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)selected;
@end
@implementation NativeLabels
#include "label-method.inc"
- (void)dealloc { [labelImages release]; [super dealloc]; }
@end

static unsigned checks;
static void Check(BOOL pass, NSString *message) {
    if (!pass) { fprintf(stderr,"FAIL %s\n",[message UTF8String]); exit(1); }
    checks++;
}
static CGFloat Brightness(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return .2126 * [rgb redComponent] + .7152 * [rgb greenComponent] + .0722 * [rgb blueComponent];
}
static NSBitmapImageRep *Render(NSAppearance *appearance, NSAttributedString *preview, NSImage *label, BOOL selected) {
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:560 pixelsHigh:50 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    [appearance performAsCurrentDrawingAppearance:^{
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
        [(selected ? [NSColor alternateSelectedControlColor] : [NSColor controlBackgroundColor]) setFill];
        NSRectFill(NSMakeRect(0,0,560,50));
        NSMutableAttributedString *drawn = [[preview mutableCopy] autorelease];
        [drawn addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:15] range:NSMakeRange(0,[drawn length])];
        [drawn addAttribute:NSForegroundColorAttributeName value:(selected ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor]) range:NSMakeRange(0,8)];
        if (selected) [drawn addAttribute:NSForegroundColorAttributeName value:[NSColor alternateSelectedControlTextColor] range:NSMakeRange(0,[drawn length])];
        [drawn drawInRect:NSMakeRect(12,16,410,22)];
        [label drawInRect:NSMakeRect(435,18,[label size].width,[label size].height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }];
    return bitmap;
}
static void CheckPixels(NSBitmapImageRep *bitmap, BOOL dark, BOOL selected) {
    CGFloat bg = Brightness([bitmap colorAtX:550 y:2]);
    if (!selected) Check(dark ? bg < .25 : bg > .85, @"rendered background follows appearance");
    NSUInteger titlePixels=0, previewPixels=0, tagPixels=0;
    for (NSInteger y=10;y<44;y++) {
        for (NSInteger x=12;x<420;x++) {
            CGFloat v=Brightness([bitmap colorAtX:x y:y]);
            if (fabs(v-bg) > .18) { if(x<78) titlePixels++; else previewPixels++; }
        }
        for (NSInteger x=435;x<525;x++) if(fabs(Brightness([bitmap colorAtX:x y:y])-bg)>.18) tagPixels++;
    }
    Check(titlePixels>15,@"rendered title has contrasting glyph pixels");
    Check(previewPixels>30,@"cached preview has contrasting glyph pixels");
    Check(tagPixels>30,@"cached tag image has contrasting pixels");
    NSUInteger tagHoles=0;
    for (NSInteger y=17;y<30;y++) for (NSInteger x=438;x<466;x++)
        if (fabs(Brightness([bitmap colorAtX:x y:y])-bg)<.06) tagHoles++;
    Check(tagHoles>15,@"tag glyphs cut visible holes through the pill fill");
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NativeLabels *labels=[[[NativeLabels alloc] init] autorelease];
        NSAttributedString *body=[[[NSAttributedString alloc] initWithString:@"The cached preview follows the appearance."] autorelease];
        NSAttributedString *preview=[@"A sample" attributedSingleLinePreviewFromBodyText:body upToWidth:600];
        NSColor *previewColor=[preview attribute:NSForegroundColorAttributeName atIndex:9 effectiveRange:NULL];
        Check(previewColor != nil,@"production preview supplies a body color");
        __block NSImage *firstTag=nil;
        __block CGFloat firstPreviewBrightness=0;
        for(NSUInteger i=0;i<3;i++) {
            BOOL dark=(i==1);
            NSAppearance *appearance=[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            [appearance performAsCurrentDrawingAppearance:^{
                NSImage *tag=[labels cachedLabelImageForWord:@"work" highlighted:NO];
                if(i==1) Check(tag!=firstTag,@"shared tag cache separates dark and light raster colors");
                if(i==2) Check(tag==firstTag,@"returning to light reuses the matching tag image");
                CGFloat bodyBrightness=Brightness(previewColor);
                if(i==1) Check(bodyBrightness>firstPreviewBrightness+.5,@"same cached attributed preview resolves to light text in dark appearance");
                if(i==2) Check(fabs(bodyBrightness-firstPreviewBrightness)<.01,@"cached preview returns to original light-mode color");
                for(NSUInteger selected=0;selected<2;selected++) {
                    NSImage *image=[labels cachedLabelImageForWord:@"work" highlighted:selected];
                    NSBitmapImageRep *bitmap=Render(appearance,preview,image,selected);
                    CheckPixels(bitmap,dark,selected);
                    NSString *path=[NSString stringWithFormat:@"%s/%lu-%@-%@.png",argv[1],(unsigned long)i,dark?@"dark":@"light",selected?@"selected":@"ordinary"];
                    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"writes rendered fixture");
                }
            }];
            if(i==0) [appearance performAsCurrentDrawingAppearance:^{ firstTag=[labels cachedLabelImageForWord:@"work" highlighted:NO]; firstPreviewBrightness=Brightness(previewColor); }];
        }
        fprintf(stdout,"PASS: %u appearance cache and rendered-pixel checks\n",checks);
    }
    return 0;
}
