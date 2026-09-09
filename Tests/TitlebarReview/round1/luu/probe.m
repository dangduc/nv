#import <Cocoa/Cocoa.h>
#import "AppController.h"
#import "DualField.h"

static NSString *Output;
static NSMutableArray *Samples;
static NSUInteger GeometryFailures;
static void Pump(void) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:.08];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast]
            inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    }
}

// Only the unrelated routing collaborator is substituted. DualField itself and
// all toolbar construction/focus/delegate methods are compiled from production.
AppController *NVControllerForView(NSView *view) { return [(id)view delegate]; }

@interface AppController (Measurements)
- (void)measure;
@end
@implementation AppController
#include "production.inc"
- (void)measure {
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 100, 780, 320)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setContentMinSize:NSMakeSize(480, 320)];
    [window setTitle:@"Disposable layout measurement"];
    [window setWindowController:self];
    NSSearchField *archiveField = [[[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)] autorelease];
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:archiveField];
    NSKeyedUnarchiver *decoder = [[[NSKeyedUnarchiver alloc] initForReadingWithData:archive] autorelease];
    [decoder setClass:[DualField class] forClassName:@"NSSearchField"];
    field = [[decoder decodeObjectForKey:NSKeyedArchiveRootObjectKey] retain];
    [decoder finishDecoding];
    NSView *wrapper = [[[NSView alloc] initWithFrame:[field frame]] autorelease];
    [[window contentView] addSubview:wrapper]; [wrapper addSubview:field];
    [self setDualFieldInToolbar];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES]; Pump();

    NSArray *widths = @[@480, @780, @1200, @1600, @1200, @780, @480];
    for (NSString *scenario in @[@"empty", @"long_query", @"editing"]) {
        [field setStringValue:[scenario isEqual:@"empty"] ? @"" : [@"q" stringByPaddingToLength:1024 withString:@"query " startingAtIndex:0]];
        if ([scenario isEqual:@"editing"]) [self selectSearchField];
        else [window makeFirstResponder:nil];
        Pump();
        for (NSNumber *width in widths) {
            NSRect frame = [window frame]; frame.size.width = [width doubleValue];
            [window setFrame:frame display:YES];
            NSRect before = [field convertRect:[field bounds] toView:nil];
            // This is exactly the synchronous layout call used by production
            // selectSearchField. No run-loop drain occurs before assertions.
            [[[window contentView] superview] layoutSubtreeIfNeeded];
            NSRect after = [field convertRect:[field bounds] toView:nil];
            CGFloat actualWidth = NSWidth([window frame]);
            BOOL valid = NSWidth(after) >= actualWidth - 130 && NSMinX(after) < 130 &&
                actualWidth - NSMaxX(after) >= 0 && actualWidth - NSMaxX(after) <= 30 &&
                ![field isHiddenOrHasHiddenAncestor] && [field window] == window;
            if (!valid) GeometryFailures++;
            [Samples addObject:@{@"scenario": scenario, @"windowWidth": @(actualWidth),
                @"immediateFieldWidth": @(NSWidth(before)), @"laidOutFieldWidth": @(NSWidth(after)),
                @"fieldX": @(NSMinX(after)), @"trailingMargin": @(actualWidth - NSMaxX(after)),
                @"valid": @(valid), @"editing": @([field currentEditor] != nil)}];
        }
    }

    // A bounded main-thread timing sample, not an application benchmark. Blank
    // content excludes notes table/source/preview costs and actual mouse events.
    NSMutableArray *durations = [NSMutableArray array];
    for (NSUInteger i = 0; i < 220; i++) {
        @autoreleasepool {
            NSRect frame = [window frame]; frame.size.width = 480 + ((i * 137) % 1121);
            NSTimeInterval begin = [NSDate timeIntervalSinceReferenceDate];
            [window setFrame:frame display:YES];
            [[[window contentView] superview] layoutSubtreeIfNeeded];
            NSTimeInterval milliseconds = ([NSDate timeIntervalSinceReferenceDate] - begin) * 1000;
            if (i >= 20) [durations addObject:@(milliseconds)];
        }
    }
    NSDictionary *result = @{@"geometryFailures": @(GeometryFailures), @"geometry": Samples,
        @"resizePlusLayoutMilliseconds": durations, @"warmupIterations": @20,
        @"os": [[NSProcessInfo processInfo] operatingSystemVersionString],
        @"limits": @"Real AppKit NSWindow, production DualField and extracted toolbar methods. Programmatic resize plus synchronous layout; no mouse drag, note library, app lifecycle, or source/preview rendering. Timings exclude compositor presentation."};
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&error];
    if (!data || ![data writeToFile:Output atomically:YES]) { NSLog(@"write failed %@", error); exit(2); }
    [window orderOut:nil];
    exit(0);
}
@end

@interface MeasurementDelegate : NSObject <NSApplicationDelegate>
@end
@implementation MeasurementDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    @try { AppController *controller = [[AppController alloc] init]; [controller measure]; }
    @catch (NSException *exception) { NSLog(@"%@\n%@", exception, [exception callStackSymbols]); exit(2); }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        Output = [[NSString stringWithUTF8String:argv[1]] copy];
        Samples = [[NSMutableArray alloc] init];
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        MeasurementDelegate *delegate = [[MeasurementDelegate alloc] init]; [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
