#import <Cocoa/Cocoa.h>
#import "LinkingEditor.h"
#import "NVNoteEditingSession.h"
@interface NVNoteEditingSession (PolicyReviewPrivate)
- (BOOL)hasPendingTextChanges;
@end
@interface PolicyEditObserver : NSObject { @public NSUInteger notifications; }
- (void)changed:(NSNotification *)note;
@end
@implementation PolicyEditObserver
- (void)changed:(NSNotification *)note { notifications++; }
@end
static BOOL HasSharedPolicy(NSTextView *editor,NSParagraphStyle *style) {
    __block BOOL valid=YES;
    [editor.textStorage enumerateAttribute:NSParagraphStyleAttributeName inRange:NSMakeRange(0,editor.string.length) options:0
        usingBlock:^(id value,NSRange range,BOOL *stop) { if(value!=style || [value lineBreakMode]!=NSLineBreakByCharWrapping) valid=NO; }];
    return valid;
}
