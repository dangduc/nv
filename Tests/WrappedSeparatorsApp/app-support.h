#import <Cocoa/Cocoa.h>
#import "LinkingEditor.h"
#import "NVNoteEditingSession.h"

@interface NVNoteEditingSession (WordWrappingTests)
- (BOOL)hasPendingTextChanges;
@end

static NSArray *WordWrapLines(NSTextView *view) {
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForTextContainer:view.textContainer];
    NSMutableArray *lines = [NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *container, NSRange glyphs, BOOL *stop) {
            NSRange characters = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
            [lines addObject:@{@"range":NSStringFromRange(characters), @"y":@(NSMinY(rect)),
                @"text":[view.string substringWithRange:characters]}];
        }];
    return lines;
}

static BOOL WordWrapLetter(unichar character) {
    return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z');
}

// The prose fixtures contain no word wider than the narrowest tested line.
static BOOL WordWrapPreservesWords(NSTextView *view) {
    for (NSDictionary *line in WordWrapLines(view)) {
        NSRange range = NSRangeFromString(line[@"range"]);
        NSUInteger end = NSMaxRange(range);
        if (end && end < view.string.length && WordWrapLetter([view.string characterAtIndex:end-1]) &&
            WordWrapLetter([view.string characterAtIndex:end])) {
            NSLog(@"WORD SPLIT at %lu: %@", (unsigned long)end, line);
            return NO;
        }
    }
    return YES;
}

static NSArray *WordWrapPositions(NSTextView *view, NSRange characters) {
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForTextContainer:view.textContainer];
    NSMutableArray *positions = [NSMutableArray array];
    for (NSUInteger index = characters.location; index < NSMaxRange(characters); index++) {
        NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:index];
        NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
        NSPoint location = [layout locationForGlyphAtIndex:glyph];
        [positions addObject:NSStringFromPoint(NSMakePoint(NSMinX(fragment)+location.x,NSMinY(fragment)+location.y))];
    }
    return positions;
}

static NSRect WordWrapCaret(NSTextView *view) {
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    NSRect rect = [view firstRectForCharacterRange:view.selectedRange actualRange:NULL];
    return [view convertRect:[view.window convertRectFromScreen:rect] fromView:nil];
}

static BOOL WordWrapCaretAdvances(NSRect before, NSRect after) {
    CGFloat dy = NSMinY(after)-NSMinY(before);
    return after.size.height > 0 && dy >= -0.02 &&
        (dy > 0.02 || NSMinX(after) >= NSMinX(before)-0.02);
}

static void WordWrapSpaceKey(NSTextView *view, BOOL repeat) {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber
        context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:repeat keyCode:49];
    [NSApp sendEvent:event];
}

static BOOL WordWrapCapture(NSWindow *window, NSString *path) {
    [window display];
    NSView *frame = [window.contentView superview];
    NSBitmapImageRep *bitmap = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:bitmap];
    return [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static CGFloat SeparatorAdvance(NSFont *font) {
    return [font advancementForGlyph:[font glyphWithName:@"x"]].width;
}

static void SeparatorColumns(NSWindow *window, NSTextView *view, NSUInteger columns) {
    [window setContentSize:NSMakeSize(700,610)];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    CGFloat width = columns * SeparatorAdvance(view.font) + 2 * view.textContainer.lineFragmentPadding + 0.25;
    NSSize content = window.contentView.frame.size;
    [window setContentSize:NSMakeSize(content.width + width-view.textContainer.containerSize.width,content.height)];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static NSPoint SeparatorPosition(NSTextView *view, NSUInteger character) {
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    NSUInteger glyph = [view.layoutManager glyphIndexForCharacterAtIndex:character];
    NSPoint location = [view.layoutManager locationForGlyphAtIndex:glyph];
    NSRect line = [view.layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    return NSMakePoint(line.origin.x+location.x,line.origin.y+location.y);
}

static BOOL SeparatorExact(NSTextView *view, NSString *expected) {
    return [[view.string dataUsingEncoding:NSUTF8StringEncoding] isEqual:[expected dataUsingEncoding:NSUTF8StringEncoding]];
}

static BOOL SeparatorStartsAtMargin(NSTextView *view, NSUInteger word) {
    NSPoint start = SeparatorPosition(view,0), next = SeparatorPosition(view,word);
    return next.y > start.y+0.02 && fabs(next.x-start.x)<0.05;
}

static BOOL SeparatorLiteralIndent(NSTextView *view, NSUInteger word, NSUInteger spaces) {
    NSPoint start = SeparatorPosition(view,0), next = SeparatorPosition(view,word);
    return next.y > start.y+0.02 && fabs(next.x-start.x-spaces*SeparatorAdvance(view.font))<0.05;
}
