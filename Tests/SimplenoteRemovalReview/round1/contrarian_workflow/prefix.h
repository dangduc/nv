#import "PrefsWindowController.h"
#import "NotationPrefs.h"
#import "AppController.h"
@interface AppController (NVWorkflowPrivate)
- (BOOL)interpretNVURL:(NSURL *)url;
@end

#import "NVApplicationController.h"
@interface NVApplicationController (NVWorkflowRouting)
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
@end

@implementation NVApplicationController (NVWorkflowMutation)
- (NSApplicationTerminateReply)nv_workflowPrematureTermination:(NSApplication *)sender { return NSTerminateNow; }
@end
