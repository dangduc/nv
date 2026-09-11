#import "fault_hooks.h"
#include <stdio.h>
#include <stdlib.h>

static enum ReviewFault ActiveFault;
static unsigned long Injected, Created, Released, LineCalls;
static CFTypeRef Live[32];
static void Require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr,"FAIL instrumentation: %s\n",message); exit(2); }
}
static void Track(CFTypeRef object) {
    if (!object) return;
    for (unsigned long i=0;i<32;i++) if (!Live[i]) { Live[i]=object; Created++; return; }
    Require(NO,"bounded reference table is full");
}
unsigned long ReviewLiveObjects(void) {
    unsigned long count=0;
    for (unsigned long i=0;i<32;i++) if (Live[i]) count++;
    return count;
}
void ReviewSetFault(enum ReviewFault fault) { ActiveFault=fault; LineCalls=0; }
unsigned long ReviewInjectedFailures(void) { return Injected; }
unsigned long ReviewCreatedObjects(void) { return Created; }
unsigned long ReviewReleasedObjects(void) { return Released; }
CTTypesetterRef ReviewCreateTypesetter(CFAttributedStringRef string) {
    Require(string!=NULL,"typesetter creation receives an attributed string");
    if (ActiveFault==ReviewTypesetterNull) { Injected++; return NULL; }
    CTTypesetterRef result=CTTypesetterCreateWithAttributedString(string);
    Track(result);
    return result;
}
CTLineRef ReviewCreateLine(CTTypesetterRef typesetter, CFRange range, double offset) {
    Require(typesetter!=NULL,"line creation does not receive a null typesetter");
    LineCalls++;
    if (ActiveFault==ReviewFirstLineNull || (ActiveFault==ReviewExtendedLineNull && LineCalls%2==0)) {
        Injected++;
        return NULL;
    }
    CTLineRef result=CTTypesetterCreateLineWithOffset(typesetter,range,offset);
    Track(result);
    return result;
}
CFIndex ReviewSuggestBreak(CTTypesetterRef typesetter, CFIndex start, double width, double offset) {
    Require(typesetter!=NULL,"cluster measurement does not receive a null typesetter");
    return CTTypesetterSuggestClusterBreakWithOffset(typesetter,start,width,offset);
}
double ReviewLineBounds(CTLineRef line, CGFloat *ascent, CGFloat *descent, CGFloat *leading) {
    Require(line!=NULL,"typographic bounds do not receive a null line");
    return CTLineGetTypographicBounds(line,ascent,descent,leading);
}
void ReviewRelease(CFTypeRef object) {
    Require(object!=NULL,"production does not release a null Core Foundation reference");
    for (unsigned long i=0;i<32;i++) if (Live[i]==object) { Live[i]=NULL; Released++; break; }
    CFRelease(object);
}
