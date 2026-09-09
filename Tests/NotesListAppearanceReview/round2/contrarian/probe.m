#import <Cocoa/Cocoa.h>
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"

@implementation GlobalPrefs
+ (id)defaultPrefs { static id value; if (!value) value = [[self alloc] init]; return value; }
- (float)tableFontSize { return 15; }
- (unsigned int)tableColumnsBitmap { return 0; }
- (BOOL)tableColumnsShowPreview { return YES; }
@end
static unsigned checks;
static void Check(BOOL pass, NSString *message) {
    if (!pass) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
    checks++;
}
static CGFloat Brightness(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return .2126 * [rgb redComponent] + .7152 * [rgb greenComponent] + .0722 * [rgb blueComponent];
}
static void DrainEvents(void) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:.08];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event) [NSApp sendEvent:event];
    }
    [NSApp updateWindows];
}

@interface FixtureTable : NSTableView @end
@implementation FixtureTable
- (float)tableFontHeight { return 18; }
- (BOOL)isActiveStyle { return [[self window] isMainWindow] && ([[self window] firstResponder] == self || [self currentEditor]); }
- (BOOL)lastEventActivatedTagEdit { return NO; }
@end

@interface FixtureController : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate> {
@public
    FixtureTable *notesTableView;
    NSWindow *window;
    NSScrollView *scroll;
    NSTextField *otherField;
    NSAttributedString *cachedSingle;
    NSMutableArray *editorObservations;
    NSString *output;
    BOOL baseline;
    NSUInteger commits;
}
@end

static NSBitmapImageRep *Capture(NSView *view, NSRect rect, NSString *path) {
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:rect];
    [view cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    Check(bitmap && [bitmap pixelsWide], @"native capture has pixels");
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"native capture writes");
    return bitmap;
}
static NSUInteger Ink(NSBitmapImageRep *bitmap, NSRect points, CGFloat background, CGFloat threshold, CGFloat scale) {
    NSUInteger count = 0;
    for (NSInteger y = NSMinY(points) * scale; y < MIN(NSMaxY(points) * scale, [bitmap pixelsHigh]); y++)
        for (NSInteger x = NSMinX(points) * scale; x < MIN(NSMaxX(points) * scale, [bitmap pixelsWide]); x++)
            if (fabs(Brightness([bitmap colorAtX:x y:y]) - background) > threshold) count++;
    return count;
}

@implementation FixtureController
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return 3; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    BOOL selected = [table isRowSelected:row] && [(FixtureTable *)table isActiveStyle];
    // Match the production ordinary-list dereferencer selection policy.
    return selected ? (id)[cachedSingle string] : cachedSingle;
}
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    commits++;
}
#include "delegate.inc"
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80,80,560,235)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"nvALT disposable selection review"];
    [window setReleasedWhenClosed:NO];
    scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,45,560,190)];
    [scroll setBorderType:NSNoBorder];
    [scroll setBackgroundColor:[NSColor textBackgroundColor]];
    [[scroll contentView] setBackgroundColor:[NSColor textBackgroundColor]];
    notesTableView = [[FixtureTable alloc] initWithFrame:NSMakeRect(0,0,560,190)];
    [notesTableView setBackgroundColor:[NSColor textBackgroundColor]];
    [notesTableView setHeaderView:nil];
    [notesTableView setStyle:NSTableViewStyleFullWidth];
    [notesTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [notesTableView setIntercellSpacing:NSMakeSize(10,3)];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"Title"] autorelease];
    [column setWidth:550]; [column setEditable:YES];
    [notesTableView addTableColumn:column];
    [notesTableView setDataSource:self]; [notesTableView setDelegate:self];
    [scroll setDocumentView:notesTableView]; [[window contentView] addSubview:scroll];
    otherField = [[NSTextField alloc] initWithFrame:NSMakeRect(15,10,400,24)];
    [otherField setStringValue:@"Separate editor focus"];
    [[window contentView] addSubview:otherField];
    NSAttributedString *body = [[[NSAttributedString alloc] initWithString:@"Body preview text has a readable system color."] autorelease];
    cachedSingle = [[@"Title" attributedSingleLinePreviewFromBodyText:body upToWidth:550] retain];
    editorObservations = [[NSMutableArray alloc] init];
    [window makeKeyAndOrderFront:nil]; [window makeMainWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [self performSelector:@selector(runChecks) withObject:nil afterDelay:.3];
}
- (void)runChecks {
    Check([NSApp isActive], @"real fixture application is active");
    Check([window isKeyWindow] && [window isMainWindow], @"real fixture window is key and main");
    fprintf(stdout, "NATIVE active=%d key=%d main=%d\n", [NSApp isActive], [window isKeyWindow], [window isMainWindow]);
    {
        NSTableColumn *column = [[notesTableView tableColumns] objectAtIndex:0];
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] init] autorelease];
        [cell setEditable:YES]; [cell setFont:[NSFont systemFontOfSize:15]];
        [cell setWraps:NO]; [cell setScrollable:YES];
        [column setDataCell:cell]; [notesTableView setRowHeight:22];
        for (NSUInteger dark = 0; dark < (baseline ? 1 : 2); dark++) {
            [window setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
            for (NSUInteger alternating = 0; alternating < 2; alternating++) {
                [notesTableView setUsesAlternatingRowBackgroundColors:alternating];
                [notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
                Check([window makeFirstResponder:notesTableView], @"native table accepts keyboard focus");
                DrainEvents();
                Check([NSApp isActive] && [window isKeyWindow] && [window isMainWindow], @"native active window state persists");
                Check([window firstResponder] == notesTableView, @"native first responder is the table");
                [notesTableView reloadData];
                [self inspectRowsWithName:[NSString stringWithFormat:@"d%lu-a%lu-active",dark,alternating] dark:dark editing:NO];
                [notesTableView editColumn:0 row:1 withEvent:nil select:YES];
                DrainEvents();
                NSTextView *editor = (NSTextView *)[notesTableView currentEditor];
                Check(editor != nil && [window firstResponder] == editor && [notesTableView editedRow] == 1, @"native field editor owns row one");
                [editor setString:@"Title"]; [editor setSelectedRange:NSMakeRange(0,0)];
                [self inspectRowsWithName:[NSString stringWithFormat:@"d%lu-a%lu-editing",dark,alternating] dark:dark editing:YES];
                NSUInteger before = commits;
                Check([window makeFirstResponder:otherField], @"separate field accepts focus after row edit");
                DrainEvents();
                Check([notesTableView currentEditor] == nil && [notesTableView editedRow] == -1, @"native table editor closes");
                Check(commits == before + 1, @"native row edit commits exactly once");
                [notesTableView reloadData];
                [self inspectRowsWithName:[NSString stringWithFormat:@"d%lu-a%lu-inactive",dark,alternating] dark:dark editing:NO];
            }
        }
    }
    Check([[NSJSONSerialization dataWithJSONObject:editorObservations options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[output stringByAppendingPathComponent:@"editors.json"] atomically:YES], @"editor observations write");
    fprintf(stdout, "PASS: %u native active-selection and inline-editing checks\n", checks);
    [window orderOut:nil];
    [NSApp stop:nil];
}
- (void)inspectRowsWithName:(NSString *)name dark:(BOOL)dark editing:(BOOL)editing {
    for (NSInteger row = 0; row < 3; row++) {
        NSRect rect = [notesTableView convertRect:[notesTableView rectOfRow:row] toView:[window contentView]];
        NSBitmapImageRep *bitmap = Capture([window contentView], rect,
            [output stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-r%ld.png",name,row]]);
        CGFloat scale = [bitmap pixelsWide] / NSWidth(rect);
        CGFloat bg = Brightness([bitmap colorAtX:[bitmap pixelsWide]-10 y:10]);
        // The editor has its own background. Sample inside it, away from the
        // glyphs, caret, focus ring, and the table's selection animation.
        if (editing && row == 1) bg = Brightness([bitmap colorAtX:100*scale y:10*scale]);
        if (row != 1) Check(dark ? bg < .3 : bg > .85, @"ordinary row background follows appearance");
        NSUInteger titleInk = Ink(bitmap, NSMakeRect(10,4,32,13), bg, .2, scale);
        fprintf(stdout, "ROW %s r=%ld bg=%.4f title=%lu\n", [name UTF8String], row, bg, titleInk);
        if (editing && row == 1) {
            NSTextView *editor = (NSTextView *)[notesTableView currentEditor];
            __block CGFloat foreground, background;
            [[editor effectiveAppearance] performAsCurrentDrawingAppearance:^{
                foreground = Brightness([editor textColor]);
                background = Brightness([editor backgroundColor]);
            }];
            [editorObservations addObject:@{@"name":name, @"dark":@(dark), @"glyphsContrast":@(titleInk > 15),
                @"foreground":@(foreground), @"background":@(background)}];
            if (dark) Check(titleInk > 15, @"dark native field-editor title glyphs contrast");
        } else {
            Check(titleInk > 15, row == 1 ? @"selected title glyphs contrast" : @"unselected title glyphs contrast");
            Check(Ink(bitmap, NSMakeRect(75,2,345,19), bg, .13, scale) > 30, @"native preview glyphs contrast");
        }
    }
}
- (void)dealloc {
    [window release]; [scroll release]; [notesTableView release]; [otherField release];
    [cachedSingle release]; [editorObservations release]; [output release]; [super dealloc];
}
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        FixtureController *controller = [[FixtureController alloc] init];
        controller->baseline = argc > 2;
        controller->output = [[NSString stringWithUTF8String:argv[1]] copy];
        [NSApp setDelegate:controller];
        [NSApp run];
        [NSApp setDelegate:nil]; [controller release];
    }
    return 0;
}
