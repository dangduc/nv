#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "PrefsWindowController.h"
#import "NotationPrefs.h"
#import "NSString_NV.h"

@interface NVApplicationController (WorkflowReviewRouting)
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible;
- (BOOL)applicationOpenUntitledFile:(NSApplication *)application;
@end
@interface NVApplicationController (WorkflowReviewMutation)
- (void)review_omitURLReveal:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
@end
@implementation NVApplicationController (WorkflowReviewMutation)
- (void)review_omitURLReveal:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    [self newWindow:self];
}
@end
