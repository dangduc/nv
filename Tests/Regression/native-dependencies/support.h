#import <WebKit/WebKit.h>
#import "PreviewController.h"
#import "AppController_Importing.h"
#import "AlienNoteImporter.h"
#import "AttributedPlainText.h"
#import "PrefsWindowController.h"
#import "NotationPrefsViewController.h"
static NSTabView *NVFindPreferencesTabs(NSView *view) {
    if ([view isKindOfClass:[NSTabView class]]) return (NSTabView *)view;
    for (NSView *child in [view subviews]) { NSTabView *tabs = NVFindPreferencesTabs(child); if (tabs) return tabs; }
    return nil;
}
