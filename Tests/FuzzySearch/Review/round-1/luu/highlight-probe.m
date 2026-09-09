#import <Cocoa/Cocoa.h>
#import "NVSearchQuery.h"
#include <mach/mach_time.h>

static void Check(BOOL condition, const char *message) { if (!condition) { fprintf(stderr, "FAIL %s\n", message); exit(1); } }
static double Now(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6; }
@interface Prefs : NSObject
@end
@implementation Prefs
- (BOOL)highlightSearchTerms { return YES; }
- (NSDictionary *)searchTermHighlightAttributes { return @{NSBackgroundColorAttributeName: [NSColor yellowColor]}; }
@end

// The editor double supplies storage and a real native TextKit layout manager.
// Attribute mutation methods below are extracted unchanged from LinkingEditor.
@interface Editor : NSObject {
@public NSTextStorage *storage; NSLayoutManager *layout; Prefs *prefsController;
}
- (NSString *)string;
- (NSLayoutManager *)layoutManager;
- (void)removeHighlightedTerms;
- (void)setSearchHighlightRanges:(NSArray *)ranges;
@end
@implementation Editor
- (id)init { if ((self = [super init])) { storage = [[NSTextStorage alloc] init]; layout = [[NSLayoutManager alloc] init]; [storage addLayoutManager:layout]; prefsController = [[Prefs alloc] init]; } return self; }
- (NSString *)string { return [storage string]; }
- (NSLayoutManager *)layoutManager { return layout; }
#include "editor.inc"
- (void)dealloc { [storage removeLayoutManager:layout]; [storage release]; [layout release]; [prefsController release]; [super dealloc]; }
@end
@interface Note : NSObject { @public NSAttributedString *content; }
@end
@implementation Note
- (NSAttributedString *)contentString { return content; }
- (void)dealloc { [content release]; [super dealloc]; }
@end
@interface NVBrowserSession : NSObject { @public NSString *query; }
- (BOOL)searchResultsAreCurrent;
- (NSString *)matchKindAtIndex:(NSInteger)row;
- (NSString *)searchString;
- (NSString *)rowKeyAtIndex:(NSInteger)row;
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(void (^)(NSArray *, NSString *))completion;
@end
@implementation NVBrowserSession
- (BOOL)searchResultsAreCurrent { return YES; }
- (NSString *)matchKindAtIndex:(NSInteger)row { (void)row; return @"title"; }
- (NSString *)searchString { return query; }
- (NSString *)rowKeyAtIndex:(NSInteger)row { (void)row; return @"title:fixture"; }
- (void)requestSourceHighlightsForRow:(NSInteger)row completion:(void (^)(NSArray *, NSString *))completion { (void)row; (void)completion; abort(); }
@end
@interface Table : NSObject
@end
@implementation Table
- (NSInteger)primarySelectedRow { return 0; }
@end
@interface Controller : NSObject {
@public NSUInteger searchHighlightGeneration; Editor *textView; Note *currentNote; Prefs *prefsController; BOOL searchHasPendingComposition; Table *notesTableView; NVBrowserSession *browser;
}
- (NVBrowserSession *)browserSession;
- (void)refreshSearchHighlights;
@end
@implementation Controller
- (NVBrowserSession *)browserSession { return browser; }
#include "refresh.inc"
@end

static NSString *Source(NSUInteger bytes) {
    NSString *line = @"meeting notes: a clear goal and a small task to finish today.\n";
    NSMutableString *string = [NSMutableString stringWithCapacity:bytes];
    while ([string length] < bytes) [string appendString:line];
    return [string substringToIndex:bytes];
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check([NSThread isMainThread], "highlight measurements execute on main");
        NSUInteger cap = argc > 1 ? strtoull(argv[1], NULL, 10) : 1048576;
        Prefs *prefs = [[[Prefs alloc] init] autorelease];
        Controller *controller = [[[Controller alloc] init] autorelease];
        controller->prefsController = prefs;
        controller->textView = [[[Editor alloc] init] autorelease];
        controller->notesTableView = [[[Table alloc] init] autorelease];
        controller->currentNote = [[[Note alloc] init] autorelease];
        controller->browser = [[[NVBrowserSession alloc] init] autorelease];
        printf("source_bytes,query,trial,ranges,range_scan_ms,apply_ms,refresh_ms,clear_ms,fresh_refresh_ms\n"); fflush(stdout);
        NSUInteger sizes[] = {16384, 65536, 262144, 1048576, 4194304, 8388608};
        for (NSUInteger i = 0; i < sizeof(sizes)/sizeof(*sizes); i++) {
            NSUInteger bytes = sizes[i];
            if (bytes > cap) continue;
            for (NSString *term in @[@"a", @"meeting", @"absent"]) {
                @autoreleasepool {
                    NSString *source = Source(bytes);
                    [controller->currentNote->content release];
                    controller->currentNote->content = [[NSAttributedString alloc] initWithString:source];
                    [controller->textView->storage setAttributedString:controller->currentNote->content];
                    controller->browser->query = term;
                    NVSearchQuery *query = [[[NVSearchQuery alloc] initWithString:term] autorelease];
                    for (NSUInteger trial = 0; trial < 3; trial++) {
                        double start = Now(); NSArray *ranges = [query literalRangesInString:source]; double scan = Now() - start;
                        start = Now(); [controller->textView setSearchHighlightRanges:ranges]; double apply = Now() - start;
                        start = Now(); [controller refreshSearchHighlights]; double refresh = Now() - start;
                        Check([[controller->textView string] isEqualToString:source], "highlighting preserves source");
                        if ([ranges count]) {
                            for (NSValue *value in @[[ranges firstObject], [ranges lastObject]]) {
                                Check([controller->textView->layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:[value rangeValue].location effectiveRange:NULL] != nil, "first and last literal ranges receive real TextKit attributes");
                            }
                        }
                        start = Now(); [controller->textView removeHighlightedTerms]; double clear = Now() - start;
                        if ([ranges count]) Check([controller->textView->layout temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:[[ranges firstObject] rangeValue].location effectiveRange:NULL] == nil, "invalidation removes real temporary attributes");
                        Editor *existing = controller->textView;
                        Editor *fresh = [[Editor alloc] init];
                        [fresh->storage setAttributedString:controller->currentNote->content];
                        controller->textView = fresh;
                        start = Now(); [controller refreshSearchHighlights]; double cleanRefresh = Now() - start;
                        controller->textView = existing;
                        [fresh release];
                        printf("%lu,%s,%lu,%lu,%.3f,%.3f,%.3f,%.3f,%.3f\n", bytes, [term UTF8String], trial, [ranges count], scan, apply, refresh, clear, cleanRefresh); fflush(stdout);
                    }
                }
            }
        }
    }
    fprintf(stderr, "PASS: native highlight method and source preservation checks\n");
    return 0;
}
