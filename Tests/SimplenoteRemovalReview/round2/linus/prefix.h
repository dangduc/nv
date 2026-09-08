#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NoteObject.h"
#import "NotationController.h"
#import "NotationPrefs.h"
#import "NotationDirectoryManager.h"
#import "FrozenNotation.h"
@interface NoteObject (NVLocalExternalReview)
- (void)nv_reviewDropODB:(id)editor didModifyFile:(NSString *)path newFileLocation:(NSString *)newPath context:(NSDictionary *)context;
@end
@implementation NoteObject (NVLocalExternalReview)
- (void)nv_reviewDropODB:(id)editor didModifyFile:(NSString *)path newFileLocation:(NSString *)newPath context:(NSDictionary *)context { }
@end
