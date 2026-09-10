#import <Cocoa/Cocoa.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTextView *view = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 320, 200)] autorelease];
        NSParagraphStyle *typingStyle = [[view typingAttributes] objectForKey:NSParagraphStyleAttributeName];
        NSParagraphStyle *defaultStyle = [NSParagraphStyle defaultParagraphStyle];
        NSFont *font = [NSFont userFixedPitchFontOfSize:12.0];
        CGFloat fourSpaces = [@"    " sizeWithAttributes:@{NSFontAttributeName: font}].width;

        printf("nativeTypingParagraphStyle=%s\n", typingStyle ? "present" : "absent");
        printf("nativeDefaultTabInterval=%.3f\n", [defaultStyle defaultTabInterval]);
        printf("legacyFourSpaceOverride=%.3f\n", fourSpaces);

        if (typingStyle != nil) return 2;
        if ([defaultStyle defaultTabInterval] != 0.0) return 3;
        if (fourSpaces <= 0.0) return 4;
    }
    return 0;
}
