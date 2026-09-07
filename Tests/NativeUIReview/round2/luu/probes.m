// Injected only into the temporary app created by run.py.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"
#import "NSFileManager_NV.h"
#import "ODBEditor.h"

static NSString *TestDirectory;
static NSUInteger Checks;
static void Check(BOOL result, NSString *description) {
    if (!result) { NSLog(@"FAIL: %@", description); exit(1); }
    NSLog(@"PASS: %@", description); Checks++;
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static void Swap(Class cls, SEL first, SEL second) {
    method_exchangeImplementations(class_getInstanceMethod(cls, first), class_getInstanceMethod(cls, second));
}
static CGFloat Distance(NSColor *first, NSColor *second) {
    first = [first colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    second = [second colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!first || !second) return CGFLOAT_MAX;
    return MAX(fabs([first redComponent] - [second redComponent]),
        MAX(fabs([first greenComponent] - [second greenComponent]), fabs([first blueComponent] - [second blueComponent])));
}
static NSBitmapImageRep *CaptureRun(LinkingEditor *editor, NSRange characters) {
    NSLayoutManager *layout = [editor layoutManager];
    [layout ensureLayoutForTextContainer:[editor textContainer]];
    NSRange glyphs = [layout glyphRangeForCharacterRange:characters actualCharacterRange:NULL];
    NSRect rect = [layout boundingRectForGlyphRange:glyphs inTextContainer:[editor textContainer]];
    NSPoint origin = [editor textContainerOrigin];
    rect = NSIntegralRect(NSOffsetRect(rect, origin.x, origin.y));
    Check(!NSIsEmptyRect(rect) && NSContainsRect([editor visibleRect], rect), @"the selected run is visible in the bitmap capture");
    NSBitmapImageRep *bitmap = [editor bitmapImageRepForCachingDisplayInRect:rect];
    [editor cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    return bitmap;
}
static void CheckSelectedRun(LinkingEditor *editor, NSRange characters, NSColor *foreground, NSString *name) {
    NSColor *background = [[editor selectedTextAttributes] objectForKey:NSBackgroundColorAttributeName];
    Check(background != nil && Distance(background, [editor backgroundColor]) > .2,
        @"selection has a distinct background before capture");
    NSBitmapImageRep *bitmap = CaptureRun(editor, characters);
    NSUInteger foregroundPixels = 0, selectionPixels = 0;
    CGFloat closestSelection = CGFLOAT_MAX, closestForeground = CGFLOAT_MAX;
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            closestSelection = MIN(closestSelection, Distance(pixel, background));
            closestForeground = MIN(closestForeground, Distance(pixel, foreground));
            // Match the established rendering suite's tolerance for foreground
            // conversion. Require selection pixels to differ from editor fill.
            if (Distance(pixel, foreground) < .25 && Distance(pixel, background) > .25) foregroundPixels++;
            if (Distance(pixel, background) < .10 && Distance(pixel, [editor backgroundColor]) > .12) selectionPixels++;
        }
    }
    NSString *filename = [[[name stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
        stringByReplacingOccurrencesOfString:@":" withString:@"_"] stringByAppendingString:@".png"];
    NSString *path = [[NSString stringWithUTF8String:getenv("NV_LUU_ARTIFACTS")] stringByAppendingPathComponent:filename];
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
        @"selected text bitmap writes successfully");
    NSLog(@"SELECTED_BITMAP %@ foreground_pixels=%lu selection_pixels=%lu closest_foreground_distance=%.3f closest_selection_distance=%.3f expected_foreground=%@ expected_selection=%@ corner=%@", name,
        (unsigned long)foregroundPixels, (unsigned long)selectionPixels, closestForeground, closestSelection, foreground, background, [bitmap colorAtX:0 y:0]);
    Check(selectionPixels > 100, @"capture contains the active selection background");
    Check(foregroundPixels > 10, @"selected text contains visible glyphs in the expected foreground");
}

@interface NSFileManager (NVLuuPaths)
- (NSString *)nv_luuSupport;
@end
@implementation NSFileManager (NVLuuPaths)
- (NSString *)nv_luuSupport { return [TestDirectory stringByAppendingPathComponent:@"Support"]; }
@end
@interface ODBEditor (NVLuuIsolation)
- (void)nv_luuSkipExternal:(id)prefs;
@end
@implementation ODBEditor (NVLuuIsolation)
- (void)nv_luuSkipExternal:(id)prefs { }
@end
@interface AppController (NVLuuSelection)
- (void)nv_luuLaunch:(NSNotification *)notification;
- (void)nv_luuDelayed;
- (void)nv_luuRun;
@end
@implementation AppController (NVLuuSelection)
+ (void)load {
    const char *directory = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!directory) return;
    TestDirectory = [[NSString stringWithUTF8String:directory] copy];
    Swap(self, @selector(applicationDidFinishLaunching:), @selector(nv_luuLaunch:));
    Swap(self, @selector(runDelayedUIActionsAfterLaunch), @selector(nv_luuDelayed));
    Swap([NSFileManager class], @selector(applicationSupportDirectory), @selector(nv_luuSupport));
    Swap([ODBEditor class], @selector(initializeDatabase:), @selector(nv_luuSkipExternal:));
}
- (void)nv_luuDelayed { }
- (void)nv_luuLaunch:(NSNotification *)notification {
    [self setupViewsAfterAppAwakened];
    FSRef directory;
    OSStatus err = FSPathMakeRef((const UInt8 *)[[TestDirectory stringByAppendingPathComponent:@"Notes"] fileSystemRepresentation], &directory, NULL);
    Check(err == noErr, @"temporary library directory exists");
    NotationController *library = [[[NotationController alloc] initWithDirectoryRef:&directory error:&err] autorelease];
    Check(library != nil && err == noErr, @"temporary library opens");
    [self setNotationController:library];
    [self prepareAdditionalWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [[self window] makeKeyAndOrderFront:self];
    [self performSelector:@selector(nv_luuRun) withObject:nil afterDelay:0.3];
}
- (void)nv_luuRun {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        LinkingEditor *editor = [self valueForKey:@"textView"];
        [NSApp activateIgnoringOtherApps:YES];
        [[self window] makeKeyAndOrderFront:self];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while ((![[self window] isKeyWindow] || ![NSApp isActive] || [app activeBrowser] != self) && [deadline timeIntervalSinceNow] > 0) Pump();
        Check([NSApp isActive] && [[self window] isKeyWindow] && [app activeBrowser] == self,
            @"native activation makes the fixture key and active");
        [[self window] setContentSize:NSMakeSize(1000, 650)];
        if ([self respondsToSelector:@selector(setNotesListHeight:)]) [self setNotesListHeight:120];
        [self setUserColorScheme:self];
        Check([[self valueForKey:@"userScheme"] integerValue] == 2, @"explicit color scheme is established before custom colors");
        NSString *body = @"Bold selected\nItalic selected\nStruck selected\nhttps://example.invalid/path";
        NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:body] autorelease]
            title:@"Rich selected rendering" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
        [library addNewNote:note]; Pump();
        [self revealNote:note options:0]; Pump();
        Check([self selectedNoteObject] == note, @"fixture selects the expected note");
        Check([[self window] makeFirstResponder:editor] && [[self window] firstResponder] == editor,
            @"body editor owns keyboard input");
        [editor insertText:body replacementRange:NSMakeRange(0, [[editor string] length])];
        NSRange bold = [body rangeOfString:@"Bold selected"], italic = [body rangeOfString:@"Italic selected"];
        NSRange struck = [body rangeOfString:@"Struck selected"], url = [body rangeOfString:@"https://example.invalid/path"];
        [editor setSelectedRange:bold]; [editor bold:self];
        [editor setSelectedRange:italic]; [editor italic:self];
        [editor setSelectedRange:struck]; [editor strikethroughNV:self];
        [self finishEditing]; Pump();
        NSTextStorage *storage = [editor textStorage];
        NSDictionary *boldAttrs = [storage attributesAtIndex:bold.location effectiveRange:NULL];
        NSDictionary *italicAttrs = [storage attributesAtIndex:italic.location effectiveRange:NULL];
        Check(([[NSFontManager sharedFontManager] traitsOfFont:boldAttrs[NSFontAttributeName]] & NSBoldFontMask) ||
            [boldAttrs[NSStrokeWidthAttributeName] doubleValue] < 0, @"the body Bold action creates a bold run");
        Check(([[NSFontManager sharedFontManager] traitsOfFont:italicAttrs[NSFontAttributeName]] & NSItalicFontMask) ||
            [italicAttrs[NSObliquenessAttributeName] doubleValue] > 0, @"the body Italic action creates an italic run");
        Check([[storage attribute:NSStrikethroughStyleAttributeName atIndex:struck.location effectiveRange:NULL] integerValue] != 0,
            @"the body Strikethrough action creates a struck run");
        Check([storage attribute:NSLinkAttributeName atIndex:url.location effectiveRange:NULL] != nil,
            @"typing the body creates the URL attribute");
        NSAttributedString *before = [[storage copy] autorelease];
        for (NSNumber *dark in @[@NO, @YES]) {
            [self setForegrndColor:[dark boolValue] ? [NSColor whiteColor] : [NSColor blackColor]];
            [self setBackgrndColor:[dark boolValue] ? [NSColor blackColor] : [NSColor whiteColor]];
            [self updateColorScheme];
            for (NSNumber *clickable in @[@NO, @YES]) {
                [[GlobalPrefs defaultPrefs] setMakeURLsClickable:[clickable boolValue] sender:self];
                [self updateColorScheme];
                [editor removeHighlightedTerms];
                [[self window] makeFirstResponder:editor];
                [editor setSelectedRange:NSMakeRange(0, [body length])]; Pump();
                Check([[self window] isKeyWindow] && [[self window] firstResponder] == editor && [editor selectedRange].length == [body length],
                    @"full rich body remains actively selected before capture");
                for (NSString *word in @[@"Bold selected", @"Italic selected", @"Struck selected", @"https://example.invalid/path"]) {
                    NSColor *foreground = [word hasPrefix:@"https:"] && [clickable boolValue] ?
                        [[editor preferredLinkAttributes] objectForKey:NSForegroundColorAttributeName] : [self foregrndColor];
                    CheckSelectedRun(editor, [body rangeOfString:word], foreground,
                        [NSString stringWithFormat:@"dark-%@-clickable-%@-%@", dark, clickable, [word componentsSeparatedByString:@" "][0]]);
                }
                if ([editor respondsToSelector:@selector(layoutManager:shouldUseTemporaryAttributes:forDrawingToScreen:atCharacterIndex:effectiveRange:)]) {
                    Check([storage isEqualToAttributedString:before], @"selection and appearance preserve every rich text attribute");
                } else {
                    NSMutableAttributedString *oldStyles = [[before mutableCopy] autorelease];
                    NSMutableAttributedString *newStyles = [[storage mutableCopy] autorelease];
                    [oldStyles removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [oldStyles length])];
                    [newStyles removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [newStyles length])];
                    Check([oldStyles isEqualToAttributedString:newStyles], @"baseline appearance preserves rich attributes apart from its stored foreground");
                }
            }
        }
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND2 LUU SELECTION PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
