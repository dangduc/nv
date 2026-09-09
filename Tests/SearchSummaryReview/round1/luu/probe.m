#import <Cocoa/Cocoa.h>
#import "AppController.h"
#import "NVBrowserSession.h"
#import "DualField.h"
#import "ETScrollView.h"

static NSString *Output;
static NSMutableArray *Observations;
static NSDictionary *State;
static NSUInteger NewContractFailures;

// Only the session's output is substituted. The production affordance method
// controls real AppKit status, button, and scroll views in each compiled variant.
@interface SessionOutput : NSObject
@end
@implementation SessionOutput
- (NSString *)searchString { return State[@"query"]; }
- (NSString *)searchMode { return State[@"mode"]; }
- (BOOL)hasSearchTerms { return [State[@"terms"] boolValue]; }
- (BOOL)searchResultsAreCurrent { return [State[@"current"] boolValue]; }
- (BOOL)searchPending { return [State[@"pending"] boolValue]; }
- (NSUInteger)resultCount { return [State[@"rows"] count]; }
- (NSUInteger)distinctResultNoteCount { return [[NSSet setWithArray:State[@"rows"]] count]; }
- (NSError *)searchError {
    return [State[@"error"] boolValue] ? [NSError errorWithDomain:@"Fixture" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"Search worker unavailable"}] : nil;
}
@end

@interface TableRows : NSObject <NSTableViewDataSource>
@end
@implementation TableRows
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return [State[@"rows"] count]; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return State[@"rows"][row];
}
@end

@implementation AppController
@synthesize isEditing;
#include "production.inc"
- (NVBrowserSession *)browserSession {
    static SessionOutput *session;
    if (!session) session = [[SessionOutput alloc] init];
    return (NVBrowserSession *)session;
}
- (void)measure {
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 100, 780, 180)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setTitle:@"Disposable search affordance measurement"];
    notesSubview = [window contentView];
    notesScrollView = (ETScrollView *)[[NSScrollView alloc] initWithFrame:[notesSubview bounds]];
    [notesScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [notesScrollView setHasVerticalScroller:YES];
    [notesScrollView setHasHorizontalScroller:NO];
    [notesScrollView setBorderType:NSNoBorder];
    [notesSubview addSubview:notesScrollView];
    NSTableView *table = [[[NSTableView alloc] initWithFrame:[notesScrollView bounds]] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"title"] autorelease];
    [column setWidth:450]; [table addTableColumn:column];
    [table setHeaderView:nil]; [table setRowHeight:20]; [table setIntercellSpacing:NSZeroSize];
    TableRows *rows = [[[TableRows alloc] init] autorelease]; [table setDataSource:rows];
    [notesScrollView setDocumentView:table];
    field = (DualField *)[[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    searchStatusField = [[NSTextField alloc] initWithFrame:NSMakeRect(8, NSHeight([notesSubview bounds]) - 22,
        NSWidth([notesSubview bounds]) - 16, 18)];
    [searchStatusField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [searchStatusField setEditable:NO]; [searchStatusField setSelectable:NO];
    [searchStatusField setBezeled:NO]; [searchStatusField setDrawsBackground:NO];
    [notesSubview addSubview:searchStatusField];
    createNoteButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 60, 456, 32)];
    [createNoteButton setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
    [notesSubview addSubview:createNoteButton];
    [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];

    NSArray *cases = @[
        @{@"name": @"fuzzy-empty", @"query": @"", @"mode": @"fuzzy", @"terms": @NO, @"current": @YES,
          @"rows": @[@"Alpha", @"Beta", @"Gamma"]},
        @{@"name": @"exact-empty", @"query": @"", @"mode": @"exact", @"terms": @NO, @"current": @YES,
          @"rows": @[@"Alpha", @"Beta", @"Gamma"]},
        @{@"name": @"fuzzy-duplicate-results", @"query": @"al", @"mode": @"fuzzy", @"terms": @YES, @"current": @YES,
          @"rows": @[@"Alpha", @"Alpine", @"Alpha", @"Alpine", @"Malta", @"Palace"]},
        @{@"name": @"exact-results", @"query": @"al", @"mode": @"exact", @"terms": @YES, @"current": @YES,
          @"rows": @[@"Alpha", @"Alpine", @"Malta", @"Palace"]},
        @{@"name": @"fuzzy-zero", @"query": @"unmatched", @"mode": @"fuzzy", @"terms": @YES, @"current": @YES, @"rows": @[]},
        @{@"name": @"exact-zero", @"query": @"unmatched", @"mode": @"exact", @"terms": @YES, @"current": @YES, @"rows": @[]},
        @{@"name": @"fuzzy-before-delay", @"query": @"al", @"mode": @"fuzzy", @"terms": @YES,
          @"pending": @YES, @"delayed": @NO, @"rows": @[]},
        @{@"name": @"fuzzy-after-delay", @"query": @"al", @"mode": @"fuzzy", @"terms": @YES,
          @"pending": @YES, @"delayed": @YES, @"rows": @[]},
        @{@"name": @"fuzzy-completion", @"query": @"al", @"mode": @"fuzzy", @"terms": @YES,
          @"current": @YES, @"delayed": @YES, @"rows": @[@"Alpha", @"Alpha"]},
        @{@"name": @"fuzzy-error", @"query": @"al", @"mode": @"fuzzy", @"terms": @YES,
          @"error": @YES, @"rows": @[]}
    ];
    NSArray *sizes = @[[NSValue valueWithSize:NSMakeSize(480, 84)], [NSValue valueWithSize:NSMakeSize(780, 180)],
        [NSValue valueWithSize:NSMakeSize(1200, 320)], [NSValue valueWithSize:NSMakeSize(480, 84)]];
    for (NSDictionary *scenario in cases) {
        State = scenario;
        [table reloadData];
        if ([table numberOfRows] > 1) [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        NSIndexSet *selected = [[table selectedRowIndexes] copy];
        searchStatusDelayElapsed = [scenario[@"delayed"] boolValue];
        for (NSValue *size in sizes) {
            [window setContentSize:[size sizeValue]];
            [self updateSearchAffordance];
            [[window contentView] layoutSubtreeIfNeeded];
            BOOL expectedStatus = [scenario[@"error"] boolValue] ||
                ([scenario[@"pending"] boolValue] && [scenario[@"delayed"] boolValue]);
            CGFloat gap = NSHeight([notesSubview bounds]) - NSHeight([notesScrollView frame]);
            NSString *expectedText = [scenario[@"error"] boolValue] ? @"Search worker unavailable" :
                expectedStatus ? @"Searching…" : @"";
            BOOL geometry = fabs(gap - (expectedStatus ? 24 : 0)) < .01 &&
                NSWidth([notesScrollView frame]) == NSWidth([notesSubview bounds]);
            BOOL text = [searchStatusField isHidden] == !expectedStatus &&
                [[searchStatusField stringValue] isEqual:expectedText] &&
                [[field toolTip] ?: @"" isEqual:expectedText];
            BOOL creates = [scenario[@"current"] boolValue] && [scenario[@"query"] length] && ![scenario[@"rows"] count];
            BOOL error = [scenario[@"error"] boolValue];
            BOOL button = [createNoteButton isHidden] == !(creates || error) &&
                [createNoteButton action] == (error ? @selector(retrySearch:) : @selector(createNoteFromSearch:));
            if (error) button = button && [[createNoteButton title] isEqual:@"Retry Search"];
            BOOL preserved = [table numberOfRows] == [scenario[@"rows"] count] &&
                [[table selectedRowIndexes] isEqual:selected];
            BOOL separated = !expectedStatus || NSMaxY([notesScrollView frame]) <= NSMinY([searchStatusField frame]);
            BOOL valid = geometry && text && button && preserved && separated;
            if (!valid) NewContractFailures++;
            NSDictionary *row = @{@"case": scenario[@"name"], @"width": @(NSWidth([notesSubview bounds])),
                @"height": @(NSHeight([notesSubview bounds])), @"listHeight": @(NSHeight([notesScrollView frame])),
                @"reservedHeight": @(gap), @"clipHeight": @(NSHeight([[notesScrollView contentView] bounds])),
                @"statusHidden": @([searchStatusField isHidden]), @"status": [searchStatusField stringValue],
                @"buttonHidden": @([createNoteButton isHidden]), @"rowCount": @([table numberOfRows]),
                @"distinctNotes": @([[NSSet setWithArray:scenario[@"rows"]] count]),
                @"geometryPass": @(geometry), @"statusPass": @(text), @"buttonPass": @(button),
                @"rowSelectionPass": @(preserved), @"newContractPass": @(valid)};
            [Observations addObject:row]; NSLog(@"MEASURE %@", row);
        }
        [selected release];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"observations": Observations,
        @"newContractFailures": @(NewContractFailures)} options:NSJSONWritingPrettyPrinted error:NULL];
    if (![data writeToFile:Output atomically:YES]) exit(2);
    [window orderOut:nil]; exit(0);
}
@end

@interface ProbeDelegate : NSObject <NSApplicationDelegate>
@end
@implementation ProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    @try { [[[AppController alloc] init] measure]; }
    @catch (NSException *exception) { NSLog(@"HARNESS ERROR %@\n%@", exception, [exception callStackSymbols]); exit(2); }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        Output = [[NSString stringWithUTF8String:argv[1]] copy]; Observations = [[NSMutableArray alloc] init];
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp setDelegate:[[ProbeDelegate alloc] init]]; [NSApp run];
    }
    return 0;
}
