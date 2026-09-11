#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
CTTypesetterRef OldCreate(CFAttributedStringRef);
CTTypesetterRef NewCreate(CFAttributedStringRef);
void OldRelease(CFTypeRef);
void NewRelease(CFTypeRef);
#if REVIEW_OLD
#define CTTypesetterCreateWithAttributedString OldCreate
#define CFRelease OldRelease
#else
#define CTTypesetterCreateWithAttributedString NewCreate
#define CFRelease NewRelease
#endif
