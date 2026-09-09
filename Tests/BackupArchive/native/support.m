// Test-only UI scaffolding. Archive/model/prefs implementations are linked unchanged.
#import <Cocoa/Cocoa.h>
#import "GlobalPrefs.h"
#import "NoteObject.h"
#import "NotationController.h"
#import "NVApplicationController.h"
#import "SecureTextEntryManager.h"
#import "ODBEditor.h"
#import "EncodingsManager.h"
#import "PassphraseRetriever.h"
NSString *NoteTitleColumnString = @"title", *NoteLabelsColumnString = @"labels", *NotePreviewString = @"preview";
NSString *NotesDatabaseFileName = @"Notes & Settings";
NSString *ShouldHideSecureTextEntryWarningKey = @"NoSecureEntryWarning";
NSString * const NVNoteContentsDidChangeNotification = @"NVNoteContentsDidChangeNotification";
NSAttributedString *AttributedStringForSelection(NSAttributedString *string, BOOL shadow) { abort(); }
long BlockSizeForNotation(NotationController *controller) { abort(); }
NSUInteger diskUUIDIndexForNotation(NotationController *controller) { abort(); }
AppController *NVControllerForView(NSView *view) { abort(); }
@implementation GlobalPrefs
+ (id)defaultPrefs { static id prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (NSDictionary*)noteBodyAttributes { return @{}; }
- (NSFont*)noteBodyFont { return nil; }
- (BOOL)horizontalLayout { return NO; }
@end
@implementation SecureTextEntryManager @end
@implementation ODBEditor @end
@implementation EncodingsManager @end
@implementation PassphraseRetriever
+ (id)retrieverWithNotationPrefs:(id)prefs { return [[[self alloc] init] autorelease]; }
- (int)loadedUserPassphraseData { return 0; }
@end
@interface NSString (NVBackupNativeStrings)
- (const char*)lowercaseUTF8String;
- (char*)copyLowercaseASCIIString;
+ (NSString*)relativeDateStringWithAbsoluteTime:(CFAbsoluteTime)date;
@end
@implementation NSString (NVBackupNativeStrings)
- (const char*)lowercaseUTF8String { return [[self lowercaseString] UTF8String]; }
- (char*)copyLowercaseASCIIString { return strdup([[self lowercaseString] UTF8String]); }
+ (NSString*)relativeDateStringWithAbsoluteTime:(CFAbsoluteTime)date { return @"fixture date label"; }
@end
