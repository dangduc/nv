#import "NVSourceTypesetter.h"
#include <limits.h>
#include <math.h>

@implementation NVSourceTypesetter

- (void)clearParagraphAnalysis {
    if (paragraphMeasure) CFRelease(paragraphMeasure);
    paragraphMeasure = NULL;
    [lineBreaks release];
    lineBreaks = nil;
}

- (void)beginParagraph {
    [self clearParagraphAnalysis];
    limitedLineWidth = NO;
    alignmentShift = 0;
    [super beginParagraph];
    paragraphRange = self.paragraphCharacterRange;
}

- (void)endParagraph {
    [super endParagraph];
    // Empty-note layout does not begin another paragraph. Release completed
    // analysis now so an idle editor does not retain the previous note's data.
    [self clearParagraphAnalysis];
}

- (void)beginLineWithGlyphAtIndex:(NSUInteger)glyphIndex {
    limitedLineWidth = NO;
    alignmentShift = 0;
    [super beginLineWithGlyphAtIndex:glyphIndex];
}

- (void)getLineFragmentRect:(NSRect *)rect usedRect:(NSRect *)used remainingRect:(NSRect *)remaining
    forStartingGlyphAtIndex:(NSUInteger)start proposedRect:(NSRect)proposed lineSpacing:(CGFloat)spacing
    paragraphSpacingBefore:(CGFloat)before paragraphSpacingAfter:(CGFloat)after {
    [super getLineFragmentRect:rect usedRect:used remainingRect:remaining forStartingGlyphAtIndex:start
        proposedRect:proposed lineSpacing:spacing paragraphSpacingBefore:before paragraphSpacingAfter:after];
    fullLineWidth = rect->size.width;
    limitedLineWidth = NO;
    alignmentShift = 0;

    NSTextStorage *storage = self.layoutManager.textStorage;
    NSUInteger charStart = [self characterRangeForGlyphRange:NSMakeRange(start, 0) actualGlyphRange:NULL].location;
    if (paragraphRange.location > storage.length || paragraphRange.length > storage.length - paragraphRange.location ||
        paragraphRange.length > LONG_MAX || charStart < paragraphRange.location || charStart >= NSMaxRange(paragraphRange)) return;

    NSParagraphStyle *style = self.currentParagraphStyle;
    CGFloat head = charStart == paragraphRange.location ? style.firstLineHeadIndent : style.headIndent;
    CGFloat tail = style.tailIndent > 0 ? style.tailIndent : rect->size.width + style.tailIndent;
    CGFloat offset = rect->origin.x + head;
    CGFloat available = tail - head - 2 * self.lineFragmentPadding;
    if (!isfinite(available) || !isfinite(offset) || available <= 0) return;

    if (!paragraphMeasure) {
        NSAttributedString *snapshot = [storage attributedSubstringFromRange:paragraphRange];
        paragraphMeasure = CTTypesetterCreateWithAttributedString((CFAttributedStringRef)snapshot);
    }
    if (!paragraphMeasure) return;
    CFIndex local = charStart - paragraphRange.location;
    CFIndex fit = CTTypesetterSuggestClusterBreakWithOffset(paragraphMeasure, local, available, offset);
    if (fit <= 0 || (NSUInteger)fit >= NSMaxRange(paragraphRange) - charStart) return;
    NSUInteger end = charStart + (NSUInteger)fit;

    // Native character layout keeps spaces advancing at the margin. Moving a
    // preceding word with its trailing spaces would recreate the caret jump.
    NSString *source = storage.string;
    if ([source characterAtIndex:end] == ' ' || [source characterAtIndex:end - 1] == ' ') return;

    if (!lineBreaks) {
        NSString *snapshot = [source substringWithRange:paragraphRange];
        lineBreaks = [[NSMutableData alloc] init];
        CFStringTokenizerRef tokenizer = CFStringTokenizerCreate(NULL, (CFStringRef)snapshot,
            CFRangeMake(0, snapshot.length), kCFStringTokenizerUnitLineBreak, NULL);
        if (tokenizer) {
            // Enumerate once per paragraph. Repeated native word-break searches
            // rescan long words and space runs for every visual line.
            while (CFStringTokenizerAdvanceToNextToken(tokenizer) != kCFStringTokenizerTokenNone) {
                CFRange token = CFStringTokenizerGetCurrentTokenRange(tokenizer);
                if (token.location >= 0 && token.length > 0 && (NSUInteger)token.location <= snapshot.length &&
                    (NSUInteger)token.length <= snapshot.length - (NSUInteger)token.location) {
                    NSUInteger boundary = (NSUInteger)token.location + (NSUInteger)token.length;
                    [lineBreaks appendBytes:&boundary length:sizeof(boundary)];
                }
            }
            CFRelease(tokenizer);
        }
    }

    const NSUInteger *boundaries = lineBreaks.bytes;
    NSUInteger low = 0, high = lineBreaks.length / sizeof(NSUInteger);
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        if (boundaries[middle] <= (NSUInteger)(local + fit)) low = middle + 1;
        else high = middle;
    }
    NSUInteger word = low && boundaries[low - 1] > (NSUInteger)local ? boundaries[low - 1] - (NSUInteger)local : 0;
    if (!word || word >= (NSUInteger)fit) return;

    NSRange next = [source rangeOfComposedCharacterSequenceAtIndex:charStart + word];
    if (next.location != charStart + word || next.length > NSMaxRange(paragraphRange) - next.location) return;
    CTLineRef line = CTTypesetterCreateLineWithOffset(paragraphMeasure, CFRangeMake(local, word), offset);
    if (!line) return;
    double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CFRelease(line);
    CTLineRef extended = CTTypesetterCreateLineWithOffset(paragraphMeasure, CFRangeMake(local, word + next.length), offset);
    if (!extended) return;
    double nextWidth = CTLineGetTypographicBounds(extended, NULL, NULL, NULL);
    CFRelease(extended);
    if (!isfinite(width) || !isfinite(nextWidth) || width < 0 || nextWidth <= width) return;

    // A width between the last fitting word and the next cluster makes native
    // character layout break at that word boundary without replacing glyphs.
    double target = width + (nextWidth - width) * 0.5;
    if (target < available) {
        rect->size.width -= available - target;
        limitedLineWidth = YES;
        if (style.alignment == NSTextAlignmentRight) alignmentShift = fullLineWidth - rect->size.width;
        if (style.alignment == NSTextAlignmentCenter) alignmentShift = (fullLineWidth - rect->size.width) * 0.5;
    }
}

- (void)willSetLineFragmentRect:(NSRect *)rect forGlyphRange:(NSRange)range usedRect:(NSRect *)used baselineOffset:(CGFloat *)baseline {
    if (limitedLineWidth) rect->size.width = fullLineWidth;
    used->origin.x += alignmentShift;
}

- (void)setLocation:(NSPoint)location withAdvancements:(const CGFloat *)advancements forStartOfGlyphRange:(NSRange)range {
    location.x += alignmentShift;
    [super setLocation:location withAdvancements:advancements forStartOfGlyphRange:range];
}

- (void)dealloc {
    [self clearParagraphAnalysis];
    [super dealloc];
}
@end
