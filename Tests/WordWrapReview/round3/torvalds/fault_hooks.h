#import <CoreText/CoreText.h>

enum ReviewFault { ReviewNoFault, ReviewTypesetterNull, ReviewFirstLineNull, ReviewExtendedLineNull };
void ReviewSetFault(enum ReviewFault fault);
unsigned long ReviewInjectedFailures(void);
unsigned long ReviewCreatedObjects(void);
unsigned long ReviewReleasedObjects(void);
unsigned long ReviewLiveObjects(void);
CTTypesetterRef ReviewCreateTypesetter(CFAttributedStringRef string);
CTLineRef ReviewCreateLine(CTTypesetterRef typesetter, CFRange range, double offset);
CFIndex ReviewSuggestBreak(CTTypesetterRef typesetter, CFIndex start, double width, double offset);
double ReviewLineBounds(CTLineRef line, CGFloat *ascent, CGFloat *descent, CGFloat *leading);
void ReviewRelease(CFTypeRef object);

#ifdef REVIEW_PRODUCTION_CALLS
#define CTTypesetterCreateWithAttributedString ReviewCreateTypesetter
#define CTTypesetterCreateLineWithOffset ReviewCreateLine
#define CTTypesetterSuggestClusterBreakWithOffset ReviewSuggestBreak
#define CTLineGetTypographicBounds ReviewLineBounds
#define CFRelease ReviewRelease
#endif
