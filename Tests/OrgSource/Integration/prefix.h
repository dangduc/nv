#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "NotationDirectoryManager.h"
#import "NVSourceHighlighter.h"
#import <objc/runtime.h>

@interface NVOrgPrefsOwner : NSObject {
@public
    NotationPrefs *prefs;
}
@end
@implementation NVOrgPrefsOwner
- (NotationPrefs *)notationPrefs { return prefs; }
@end

static NSArray *OrgExtensions(NotationPrefs *prefs) {
    Ivar variable = class_getInstanceVariable([NotationPrefs class], "pathExtensions");
    NSMutableArray **arrays = (NSMutableArray **)((char *)(void *)prefs + ivar_getOffset(variable));
    return arrays[PlainTextFormat];
}
static void OrgSetLegacyExtensions(NotationPrefs *prefs, NSArray *extensions, unsigned int selected) {
    Ivar variable = class_getInstanceVariable([NotationPrefs class], "pathExtensions");
    NSMutableArray **arrays = (NSMutableArray **)((char *)(void *)prefs + ivar_getOffset(variable));
    [arrays[PlainTextFormat] release];
    arrays[PlainTextFormat] = [extensions mutableCopy];
    variable = class_getInstanceVariable([NotationPrefs class], "chosenExtIndices");
    unsigned int *indices = (unsigned int *)((char *)(void *)prefs + ivar_getOffset(variable));
    indices[PlainTextFormat] = selected;
    [prefs setValue:@(PlainTextFormat) forKey:@"notesStorageFormat"];
}
static NSData *OrgLegacyArchive(NotationPrefs *prefs) {
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:prefs];
    NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:archive options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
    // Removing only the new key produces the same field set as a pre-Org archive.
    for (id object in plist[@"$objects"])
        if ([object isKindOfClass:[NSMutableDictionary class]]) [object removeObjectForKey:@"orgSourceExtensionAdded"];
    return [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}
static void OrgCollectSyntaxItems(NSMenu *menu, NSMutableArray *items) {
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == @selector(selectSourceSyntax:) && [[item representedObject] isEqual:@"org"]) [items addObject:item];
        if ([item submenu]) OrgCollectSyntaxItems([item submenu], items);
    }
}
static BOOL OrgAwait(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return condition();
}
static BOOL OrgCaptureWindow(NSWindow *window, NSString *path) {
    [[window contentView] layoutSubtreeIfNeeded];
    [window displayIfNeeded];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, (CGWindowID)[window windowNumber], kCGWindowImageDefault);
    if (!image) return NO;
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
    CGImageRelease(image);
    return [[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
}
