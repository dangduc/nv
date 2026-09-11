// No NSApplication, NSTextView, NSWorkspace, preferences, or user notes are created.
// Production URL methods run with recording collaborators. Encoding helpers are
// fixture implementations; URL escaping correctness is outside these hypotheses.
#import <Cocoa/Cocoa.h>
#import "NVAppIdentity.h"

static NSUInteger Checks;
static NSMutableArray *Routes;
static NSURL *LocalURL, *ExternalURL;
static NSUInteger Flags;
static void Check(BOOL value, NSString *message) {
    Checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
@interface NSData (UXEncoding)
- (NSString *)encodeBase64WithNewlines:(BOOL)value;
@end
@implementation NSData (UXEncoding)
- (NSString *)encodeBase64WithNewlines:(BOOL)value { return [self base64EncodedStringWithOptions:0]; }
@end
@interface NSString (UXEncoding)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (UXEncoding)
- (NSString *)stringWithPercentEscapes { return [self stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]; }
@end
@interface NSDictionary (UXEncoding)
- (NSString *)URLEncodedString;
@end
@implementation NSDictionary (UXEncoding)
- (NSString *)URLEncodedString { return [@"NV=" stringByAppendingString:self[@"NV"]]; }
@end
@interface UXNote : NSObject { CFUUIDBytes uniqueNoteIDBytes; NSString *titleString; }
- (NSURL *)uniqueNoteLink;
@end
@implementation UXNote
- (id)init { if ((self = [super init])) titleString = @"Copied Notes"; return self; }
@NOTE_LINK@
@end

static BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange range);
@interface NSMutableAttributedString (UXWiki)
- (void)_addDoubleBracketedNVLinkAttributesForRange:(NSRange)range;
@end
@implementation NSMutableAttributedString (UXWiki)
@WIKI_LINK@
@end

@interface UXEvent : NSObject
- (NSUInteger)modifierFlags;
@end
@implementation UXEvent
- (NSUInteger)modifierFlags { return Flags; }
@end
@interface UXWindow : NSObject
- (id)currentEvent;
@end
@implementation UXWindow
- (id)currentEvent { return [[[UXEvent alloc] init] autorelease]; }
@end
@interface UXPrefs : NSObject
- (BOOL)URLsAreClickable;
@end
@implementation UXPrefs
- (BOOL)URLsAreClickable { return YES; }
@end
@interface AppController : NSObject
- (BOOL)interpretNVURL:(NSURL *)url;
@end
@implementation AppController
- (BOOL)interpretNVURL:(NSURL *)url { LocalURL = url; return YES; }
@end
static id NVControllerForView(id view) { return [[[AppController alloc] init] autorelease]; }
static BOOL NVSourceLinksAreCurrent(id storage) { return YES; }
@interface UXLinkSuperclass : NSObject
- (void)clickedOnLink:(id)link atIndex:(NSUInteger)index;
@end
@implementation UXLinkSuperclass
- (void)clickedOnLink:(id)link atIndex:(NSUInteger)index { ExternalURL = link; }
@end
@interface UXEditor : UXLinkSuperclass { UXPrefs *prefsController; }
- (id)textStorage;
- (id)window;
- (NSString *)string;
- (void)setSelectedRange:(NSRange)range;
- (id)highlightLinkAtIndex:(NSUInteger)index;
@end
@implementation UXEditor
- (id)init { if ((self = [super init])) prefsController = [[[UXPrefs alloc] init] autorelease]; return self; }
- (id)textStorage { return nil; }
- (id)window { return [[[UXWindow alloc] init] autorelease]; }
- (NSString *)string { return @"fixture"; }
- (void)setSelectedRange:(NSRange)range {}
- (id)highlightLinkAtIndex:(NSUInteger)index { return nil; }
@CLICK_LINK@
@end

static void Route(UXEditor *editor, NSURL *url, BOOL command, BOOL expectLocal, NSString *label) {
    LocalURL = nil; ExternalURL = nil; Flags = command ? NSCommandKeyMask : 0;
    [editor clickedOnLink:url atIndex:0];
    Check((LocalURL != nil) == expectLocal && (ExternalURL != nil) != expectLocal, label);
    if (command && expectLocal) {
        Check([LocalURL.host isEqual:@"make"], @"command-click creates in current app");
        Check([LocalURL.scheme isEqual:NVNoteURLScheme()], @"command-click uses current flavor");
    }
    [Routes addObject:@{@"case":label, @"command":@(command), @"input":url.absoluteString,
                       @"route":LocalURL ? @"local" : @"superclass", @"output":(LocalURL ?: ExternalURL).absoluteString}];
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        BOOL development = !strcmp(argv[1], "development");
        Check(NVIsDevelopmentBuild() == development, @"running bundle controls flavor");
        Routes = [NSMutableArray array];
        UXEditor *editor = [[[UXEditor alloc] init] autorelease];
        NSURL *noteURL = [[[[UXNote alloc] init] autorelease] uniqueNoteLink];
        Check([noteURL.scheme isEqual:NVNoteURLScheme()], @"Copy Note Link uses current flavor");
        NSMutableAttributedString *wiki = [[[NSMutableAttributedString alloc] initWithString:@"[[Copied Notes]]"] autorelease];
        [wiki _addDoubleBracketedNVLinkAttributesForRange:NSMakeRange(0, wiki.length)];
        NSURL *wikiURL = [wiki attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL];
        Check([wikiURL.scheme isEqual:NVNoteURLScheme()], @"wiki generation uses current flavor");
        for (NSNumber *command in @[@NO, @YES]) {
            Route(editor, noteURL, command.boolValue, YES, @"generated note link");
            Route(editor, wikiURL, command.boolValue, YES, @"generated wiki link");
            Route(editor, [NSURL URLWithString:@"nvalt://find/Copied%20Notes"], command.boolValue, YES, @"copied release nvalt link retains local handling");
        }
        // Explicit aliases retain OS dispatch; they are observations, not failures.
        Route(editor, [NSURL URLWithString:@"nv://find/Copied%20Notes"], NO, NO, @"explicit stable alias");
        Route(editor, [NSURL URLWithString:@"nv-dev://find/Copied%20Notes"], NO, NO, @"explicit development alias");
        NSDictionary *result = @{@"flavor":development ? @"development" : @"release", @"checks":@(Checks), @"routes":Routes};
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); putchar('\n');
    }
    return 0;
}
