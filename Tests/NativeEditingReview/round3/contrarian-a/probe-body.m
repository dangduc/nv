#import <Cocoa/Cocoa.h>

static NSUInteger checks = 0;
static void Check(BOOL condition, NSString *message) {
    checks++;
    printf("%s: %s\n", condition ? "PASS" : "FAIL", [message UTF8String]);
    if (!condition) exit(2);
}

@interface ColorSender : NSObject
@property(retain) NSColor *color;
@end
@implementation ColorSender
@synthesize color;
- (void)dealloc { [color release]; [super dealloc]; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTextView *defaultView = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)] autorelease];
        Check([defaultView usesFontPanel] == YES, @"fresh NSTextView uses the font panel by default");
        NSTextView *plain = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)] autorelease];
        [plain setRichText:NO];
        [plain setUsesFontPanel:NO];
        [plain setString:@"source"];
        [plain setSelectedRange:NSMakeRange(0, 6)];

        ColorSender *sender = [[[ColorSender alloc] init] autorelease];
        sender.color = [NSColor redColor];
        NSDictionary *before = [[[plain textStorage] attributesAtIndex:0 effectiveRange:NULL] copy];
        [plain changeColor:sender];
        NSDictionary *after = [[plain textStorage] attributesAtIndex:0 effectiveRange:NULL];

        Check([plain isRichText] == NO, @"reference is a plain-text NSTextView");
        Check([plain usesFontPanel] == NO, @"reference disables the font panel like LinkingEditor");
        Check(![[after objectForKey:NSForegroundColorAttributeName] isEqual:[NSColor redColor]],
              @"NSTextView changeColor does not apply color to selected plain text");
        Check([before isEqual:after], @"native color action leaves plain source attributes unchanged");
        [before release];

        NSTextView *typing = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)] autorelease];
        [typing setRichText:NO];
        [typing setUsesFontPanel:NO];
        [typing setString:@"source"];
        [typing setSelectedRange:NSMakeRange(6, 0)];
        NSDictionary *typingBefore = [[[typing typingAttributes] copy] autorelease];
        [typing changeColor:sender];
        Check([[typing typingAttributes] isEqual:typingBefore],
              @"NSTextView changeColor leaves plain insertion attributes unchanged");

        printf("checks=%lu\n", (unsigned long)checks);
    }
    return 0;
}
