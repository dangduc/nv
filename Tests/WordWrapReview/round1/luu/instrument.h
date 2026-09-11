#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
CTTypesetterRef CountTypesetter(CFAttributedStringRef);
CFIndex CountSuggest(CTTypesetterRef,CFIndex,double,double);
CTLineRef CountLine(CTTypesetterRef,CFRange,double);
CFStringTokenizerTokenType CountToken(CFStringTokenizerRef);
#define CTTypesetterCreateWithAttributedString CountTypesetter
#define CTTypesetterSuggestClusterBreakWithOffset CountSuggest
#define CTTypesetterCreateLineWithOffset CountLine
#define CFStringTokenizerAdvanceToNextToken CountToken
