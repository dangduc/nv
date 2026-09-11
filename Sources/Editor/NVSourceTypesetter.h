#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>

// One instance belongs to each source editor's layout manager. The paragraph
// uses character wrapping; this typesetter preserves word boundaries while
// retaining native advancement for the editor's nonelastic ordinary spaces.
@interface NVSourceTypesetter : NSATSTypesetter {
    CTTypesetterRef paragraphMeasure;
    NSRange paragraphRange;
    NSMutableData *lineBreaks;
    CGFloat fullLineWidth;
    CGFloat alignmentShift;
    BOOL limitedLineWidth;
}
@end
