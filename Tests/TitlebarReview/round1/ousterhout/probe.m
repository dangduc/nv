#import <Cocoa/Cocoa.h>
#import "AppController.h"
#import "DualField.h"
#import "NVBrowserSession.h"
#import "LinkingEditor.h"

static NSUInteger Checks, FieldDeaths, WrapperDeaths;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", [message UTF8String]); exit(1); }
    Checks++; fprintf(stdout, "PASS %s\n", [message UTF8String]); fflush(stdout);
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
}
AppController *NVControllerForView(NSView *view) { return [(id)view delegate]; }

@interface TrackedField : DualField @end
@implementation TrackedField
- (void)dealloc { FieldDeaths++; [super dealloc]; }
@end
@interface TrackedWrapper : NSView @end
@implementation TrackedWrapper
- (void)dealloc { WrapperDeaths++; [super dealloc]; }
@end

@interface AppController (OwnershipFixture)
- (void)fixtureSetup;
- (void)fixtureInspect;
- (void)fixtureDetach;
@end
@implementation AppController
// Unmodified production setup, toolbar delegate, focus, and dealloc methods.
#include "production.inc"
// Unrelated production-dealloc collaborators have no state in this fixture.
- (void)cancelMultiTagEditing { }
- (void)discardViewer { }
- (void)fixtureSetup {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 780, 100)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    [super setWindow:window]; [window release];
    [window setTitle:@"Semantic title"];
    NSSearchField *encodedField = [[[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)] autorelease];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:encodedField];
    NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [decoder setClass:[TrackedField class] forClassName:@"NSSearchField"];
    field = [[decoder decodeObjectForKey:NSKeyedArchiveRootObjectKey] retain];
    [decoder finishDecoding]; [decoder release];
    NSView *wrapper = [[TrackedWrapper alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    [[window contentView] addSubview:wrapper]; [wrapper addSubview:field];
    [wrapper release]; [field release];
    [pool drain];
    NSUInteger fieldsBefore = FieldDeaths;
    [self setDualFieldInToolbar];
    Check([[[window contentView] subviews] count] == 0, @"migration removes the legacy wrapper from content");
    Check(FieldDeaths == fieldsBefore && [field isKindOfClass:[TrackedField class]], @"migration keeps the borrowed nib field alive");
    [window makeKeyAndOrderFront:nil];
}
- (void)fixtureInspect {
    Pump();
    Check([field superview] == [dualFieldItem view], @"the toolbar item owns the field through one container");
    Check([[field superview] superview] != nil && [field window] == window, @"AppKit attaches that container to the owning window");
    Check([field delegate] == self && [toolbar delegate] == self, @"delegates point to the owning browser");
    Check([field target] == nil && [field action] == NULL, @"native typing and clear cannot invoke an implicit note action");
    Check([[window title] isEqual:@"Semantic title"] && [window titleVisibility] == NSWindowTitleHidden,
        @"the visual title is hidden while its semantic value remains intact");
    [window setTitle:@"Renamed semantic title"];
    Check([[window title] isEqual:@"Renamed semantic title"] && [window titleVisibility] == NSWindowTitleHidden,
        @"ordinary title updates preserve hidden presentation");
    Check([[[toolbar items] valueForKey:@"itemIdentifier"] isEqual:@[@"Search"]], @"the toolbar exposes one item");
    Check([self toolbar:toolbar itemForItemIdentifier:@"NewNote" willBeInsertedIntoToolbar:YES] == nil,
        @"removed action identifiers cannot create legacy buttons");
    [field setStringValue:@"independent query"];
    [self selectSearchField];
    Check([field currentEditor] != nil, @"selectSearchField establishes the editor synchronously");
    NSTextView *body = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)] autorelease];
    [[window contentView] addSubview:body];
    Check([window makeFirstResponder:body], @"a later source focus request succeeds");
    Pump(); Pump();
    Check([window firstResponder] == body && [[field stringValue] isEqual:@"independent query"],
        @"draining events preserves later source focus and the query");
}
- (void)fixtureDetach {
    [window makeFirstResponder:nil]; [window orderOut:nil];
    // AppKit may keep an ordered window alive beyond NSWindowController. Detach
    // its toolbar explicitly so the probe isolates the controller/item/view graph.
    [window setInitialFirstResponder:nil]; [window setToolbar:nil];
}
@end

@interface FixtureDelegate : NSObject <NSApplicationDelegate> @end
@implementation FixtureDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    @try {
        for (NSUInteger iteration = 0; iteration < 8; iteration++) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSUInteger before = FieldDeaths;
            AppController *owner = [[AppController alloc] initWithWindow:nil];
            [owner fixtureSetup]; [owner fixtureInspect]; [owner fixtureDetach]; [owner release];
            [pool drain];
            Pump();
            Check(FieldDeaths == before + 1, @"controller teardown releases exactly one migrated field");
            Check(WrapperDeaths == iteration + 1, @"the removed legacy wrapper releases after the pool drains");
        }
        fprintf(stdout, "RESULT passes=%lu field_deallocations=%lu wrapper_deallocations=%lu\n",
            (unsigned long)Checks, (unsigned long)FieldDeaths, (unsigned long)WrapperDeaths);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL exception: %@", exception); exit(1); }
}
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        FixtureDelegate *delegate = [[FixtureDelegate alloc] init]; [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 1;
}
