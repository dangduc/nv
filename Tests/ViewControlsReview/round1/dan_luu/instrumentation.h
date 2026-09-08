// Loaded only by native-controls/run.py into a disposable app copy.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "LabelsListController.h"
#import "NoteAttributeColumn.h"
#import "LinkingEditor.h"
#import "DualField.h"
#import "GlobalPrefs.h"
#import "NSFileManager_NV.h"
#import "ODBEditor.h"
#import "PreviewController.h"
#import "ETNoteScrollView.h"


static NSUInteger CountCalls, LayoutCalls, DisplayCalls, JSCalls;
static double CountMilliseconds;
@interface PreviewController (NVCounter)
- (void)nv_displaySnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier;
@end
@implementation PreviewController (NVCounter)
- (void)nv_displaySnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier { DisplayCalls++; [self nv_displaySnapshot:snapshot viewerIdentifier:identifier]; }
@end
@interface WKWebView (NVCounter)
- (void)nv_evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion;
@end
@implementation WKWebView (NVCounter)
- (void)nv_evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion { JSCalls++; [self nv_evaluateJavaScript:script completionHandler:completion]; }
@end


@interface AppController (NVLuuCounters)
- (void)nv_countWords:(BOOL)count;
- (void)nv_layoutHeader;
@end
@implementation AppController (NVLuuCounters)
+ (void)load {
 if (!getenv("NV_WINDOW_TEST_DIRECTORY")) return;
 method_exchangeImplementations(class_getInstanceMethod(self,@selector(updateWordCount:)), class_getInstanceMethod(self,@selector(nv_countWords:)));
 method_exchangeImplementations(class_getInstanceMethod(self,@selector(layoutNoteHeader)), class_getInstanceMethod(self,@selector(nv_layoutHeader)));
 method_exchangeImplementations(class_getInstanceMethod([PreviewController class],@selector(displaySnapshot:viewerIdentifier:)), class_getInstanceMethod([PreviewController class],@selector(nv_displaySnapshot:viewerIdentifier:)));
 method_exchangeImplementations(class_getInstanceMethod([WKWebView class],@selector(evaluateJavaScript:completionHandler:)), class_getInstanceMethod([WKWebView class],@selector(nv_evaluateJavaScript:completionHandler:)));
}
- (void)nv_countWords:(BOOL)count {
 double start=[NSDate timeIntervalSinceReferenceDate];
 [self nv_countWords:count];
 if(count) { CountCalls++; CountMilliseconds+=([NSDate timeIntervalSinceReferenceDate]-start)*1000; }
}
- (void)nv_layoutHeader { LayoutCalls++; [self nv_layoutHeader]; }
@end
