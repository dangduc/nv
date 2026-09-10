#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include "freshness.inc"

static NSUInteger checks, nativeActivations, noteActivations;
static void Check(BOOL condition, NSString *label) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); }
    checks++; printf("PASS: %s\n", label.UTF8String);
}

@interface ReviewPrefs : NSObject { @public BOOL clickable; }
- (BOOL)URLsAreClickable;
@end
@implementation ReviewPrefs
- (BOOL)URLsAreClickable { return clickable; }
@end
@interface ReviewEvent : NSObject { @public NSUInteger flags; }
- (NSUInteger)modifierFlags;
@end
@implementation ReviewEvent
- (NSUInteger)modifierFlags { return flags; }
@end
@interface ReviewWindow : NSObject { @public ReviewEvent *event; }
- (NSEvent *)currentEvent;
@end
@implementation ReviewWindow
- (NSEvent *)currentEvent { return (id)event; }
@end
@interface AppController : NSObject
- (void)interpretNVURL:(id)url;
@end
@implementation AppController
- (void)interpretNVURL:(id)url { noteActivations++; }
@end
static AppController *browser;
static id NVControllerForView(id view) { return browser; }

@interface ReviewBase : NSObject
- (void)clickedOnLink:(id)url atIndex:(NSUInteger)index;
@end
@implementation ReviewBase
- (void)clickedOnLink:(id)url atIndex:(NSUInteger)index { nativeActivations++; }
@end
@interface ReviewEditor : ReviewBase {
@public
    NSTextStorage *storage;
    ReviewPrefs *prefsController;
    ReviewWindow *window;
    NSRange selection;
    NSUInteger linkHighlights;
}
- (NSTextStorage *)textStorage;
- (NSString *)string;
- (id)window;
- (void)setSelectedRange:(NSRange)range;
- (id)highlightLinkAtIndex:(NSUInteger)index;
@end
@implementation ReviewEditor
- (NSTextStorage *)textStorage { return storage; }
- (NSString *)string { return storage.string; }
- (id)window { return window; }
- (void)setSelectedRange:(NSRange)range {
    if (range.location > storage.length || range.length > storage.length - range.location)
        [NSException raise:NSRangeException format:@"invalid fixture selection"];
    selection = range;
}
- (id)highlightLinkAtIndex:(NSUInteger)index { linkHighlights++; return nil; }
#include "click.inc"
@end

int main(void) { @autoreleasepool {
    ReviewEditor *editor = [[[ReviewEditor alloc] init] autorelease];
    editor->storage = [[[NSTextStorage alloc] initWithString:@"https://example.com tail"] autorelease];
    editor->prefsController = [[[ReviewPrefs alloc] init] autorelease];
    editor->window = [[[ReviewWindow alloc] init] autorelease];
    editor->window->event = [[[ReviewEvent alloc] init] autorelease];
    browser = [[[AppController alloc] init] autorelease];
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSURL *note = [NSURL URLWithString:@"nvalt://find/obsolete"];
    for (NSNumber *clickable in @[@NO, @YES]) {
        editor->prefsController->clickable = clickable.boolValue;
        for (NSNumber *command in @[@NO, @YES]) {
            editor->window->event->flags = command.boolValue ? NSCommandKeyMask : 0;
            NVSetSourceLinksCurrent(editor->storage, NO);
            editor->selection = NSMakeRange(editor->storage.length, 0);
            [editor clickedOnLink:url atIndex:3];
            Check(NSEqualRanges(editor->selection, NSMakeRange(3, 0)),
                [NSString stringWithFormat:@"stale URL places caret: clickable=%@ command=%@", clickable, command]);
            [editor clickedOnLink:note atIndex:4];
            Check(NSEqualRanges(editor->selection, NSMakeRange(4, 0)),
                [NSString stringWithFormat:@"stale note link places caret: clickable=%@ command=%@", clickable, command]);
        }
    }
    Check(nativeActivations == 0 && noteActivations == 0 && editor->linkHighlights == 0,
          @"stale targets never activate or select obsolete whole-link ranges");
    [editor clickedOnLink:url atIndex:NSNotFound];
    Check(editor->selection.location == editor->storage.length, @"out-of-bounds stale index clamps to source end");
    [editor->storage replaceCharactersInRange:NSMakeRange(0, editor->storage.length) withString:@""];
    [editor clickedOnLink:note atIndex:NSUIntegerMax];
    Check(NSEqualRanges(editor->selection, NSMakeRange(0, 0)), @"empty source clamps stale selection to zero");

    [editor->storage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"https://example.com tail"];
    NVSetSourceLinksCurrent(editor->storage, YES);
    editor->window->event->flags = 0;
    editor->prefsController->clickable = NO;
    [editor clickedOnLink:url atIndex:3];
    Check(editor->selection.location == 3 && nativeActivations == 0,
          @"current URL with clicking disabled retains ordinary caret behavior");
    editor->prefsController->clickable = YES;
    [editor clickedOnLink:url atIndex:3];
    [editor clickedOnLink:note atIndex:3];
    Check(nativeActivations == 1 && noteActivations == 1, @"current targets retain native and note navigation");
    printf("PASS: %lu headless production-callback checks\n", (unsigned long)checks);
} return 0; }
