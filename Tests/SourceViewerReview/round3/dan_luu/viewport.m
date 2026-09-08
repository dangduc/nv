#import <Cocoa/Cocoa.h>
#include <time.h>

static NSUInteger Checks;
static void Check(BOOL result, const char *message) {
    Checks++;
    if (!result) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static double Clock(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1000000.0;
}
@interface CountingLayout : NSLayoutManager <NSLayoutManagerDelegate> {
@public NSUInteger ensureCalls, fragmentCalls, fragmentCharacters, generatedGlyphs;
@public NSRect requested;
}
@end
@implementation CountingLayout
- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:(const CGGlyph *)glyphs properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes font:(NSFont *)font forGlyphRange:(NSRange)range {
    generatedGlyphs += range.length;
    return 0; // Use the unmodified AppKit generation path.
}
- (void)ensureLayoutForBoundingRect:(NSRect)rect inTextContainer:(NSTextContainer *)container {
    ensureCalls++; requested = rect;
    [super ensureLayoutForBoundingRect:rect inTextContainer:container];
}
- (void)setLineFragmentRect:(NSRect)fragment forGlyphRange:(NSRange)range usedRect:(NSRect)used {
    fragmentCalls++; fragmentCharacters += range.length;
    [super setLineFragmentRect:fragment forGlyphRange:range usedRect:used];
}
@end

// The method under review uses only these geometry and scroll messages.
// Real TextKit objects perform layout. No window, painting, or user notes are used.
@interface ProbeText : NSObject {
@public CountingLayout *manager; NSTextContainer *container; NSPoint scrolled;
}
- (id)layoutManager; - (id)textContainer; - (NSRect)bounds; - (void)scrollPoint:(NSPoint)point;
@end
@implementation ProbeText
- (id)layoutManager { return manager; }
- (id)textContainer { return container; }
- (NSRect)bounds { return NSMakeRect(0,0,780,480); }
- (void)scrollPoint:(NSPoint)point { scrolled = point; }
@end
@interface ProbeClip : NSObject
- (NSRect)bounds;
@end
@implementation ProbeClip
- (NSRect)bounds { return NSMakeRect(0,0,780,480); }
@end
@interface ProbeScroll : NSObject {
@public ProbeClip *clip;
}
- (id)contentView;
@end
@implementation ProbeScroll
- (id)contentView { return clip; }
@end
static NSString *NotePresentationKey(id note) { return @"test-note"; }
@interface ProbeHost : NSObject {
@public id currentNote; NSMutableDictionary *noteBodyStates;
@public BOOL viewingNote; ProbeText *textView; ProbeScroll *textScrollView;
}
- (void)restoreSourceScroll;
@end
@implementation ProbeHost
// run.py inserts the exact current production method here.
#include "restore_method.inc"
@end

static NSDictionary *RunCase(NSUInteger lines, CGFloat y, BOOL hidden, BOOL fullControl) {
    NSMutableString *source = [NSMutableString string];
    for (NSUInteger i=0; i<lines; i++)
        [source appendFormat:@"%06lu: source restoration measurement row.\n", i];
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source attributes:@{NSFontAttributeName:[NSFont userFixedPitchFontOfSize:12]}];
    CountingLayout *layout = [[CountingLayout alloc] init]; [layout setDelegate:layout];
    NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(780, CGFLOAT_MAX)];
    [layout addTextContainer:container]; [storage addLayoutManager:layout];
    ProbeText *text = [[ProbeText alloc] init]; text->manager = layout; text->container = container;
    ProbeClip *clip = [[ProbeClip alloc] init];
    ProbeScroll *scroll = [[ProbeScroll alloc] init]; scroll->clip = clip;
    ProbeHost *host = [[ProbeHost alloc] init];
    host->currentNote = @"note"; host->textView = text; host->textScrollView = scroll; host->viewingNote = hidden;
    host->noteBodyStates = [@{@"test-note":@{@"sourceScroll":NSStringFromPoint(NSMakePoint(0,y))}} mutableCopy];
    Check([layout firstUnlaidCharacterIndex] == 0, "fixture starts with no laid-out characters");
    double start = Clock();
    if (fullControl) [layout ensureLayoutForTextContainer:container];
    else [host restoreSourceScroll];
    double elapsed = Clock() - start;
    NSUInteger laid = [layout firstUnlaidCharacterIndex], fragments = layout->fragmentCalls;
    printf("%s,%lu,%.0f,%d,%lu,%lu,%lu,%lu,%lu,%.3f\n",fullControl?"full":"viewport",lines,y,hidden,layout->ensureCalls,laid,fragments,layout->fragmentCharacters,layout->generatedGlyphs,elapsed);
    if (!fullControl) {
        Check(text->scrolled.y == y, "production method sends saved point after layout");
        if (!hidden && y>0) {
            Check(laid > 0 && fragments > 0, "real TextKit work occurred");
            Check(laid < [source length]/2, "near-top restoration avoids most document layout");
            Check(NSEqualRects(layout->requested,NSMakeRect(0,0,780,y+480)), "production request reaches saved viewport bottom");
        } else {
            Check(laid == 0 && fragments == 0 && layout->generatedGlyphs == 0, "hidden or zero position does no synchronous layout");
        }
        Check(layout->ensureCalls == ((!hidden && y>0)?1:0), "only nonzero Source position requests layout");
    } else Check(laid == [source length] && fragments >= lines, "full control lays out the complete source");
    NSDictionary *result = @{ @"laid":@(laid), @"fragments":@(fragments), @"generated":@(layout->generatedGlyphs), @"ms":@(elapsed) };
    [host->noteBodyStates release]; [host release]; [scroll release]; [clip release]; [text release];
    [storage removeLayoutManager:layout]; [layout release]; [container release]; [storage release];
    return result;
}
int main(void) {
    @autoreleasepool {
        printf("mode,lines,saved_y,hidden,ensure_calls,laid_characters,line_fragments,glyphs_laid_out,glyphs_generated,elapsed_ms\n");
        RunCase(2000,0,NO,NO); RunCase(2000,700,YES,NO);
        NSDictionary *shortNear = RunCase(2000,700,NO,NO);
        NSDictionary *longNear = RunCase(12000,700,NO,NO);
        NSDictionary *shortDeep = RunCase(2000,6000,NO,NO);
        NSDictionary *longDeep = RunCase(12000,6000,NO,NO);
        Check([shortNear[@"laid"] isEqual:longNear[@"laid"]], "same shallow viewport has document-length independent character work");
        Check([shortDeep[@"laid"] isEqual:longDeep[@"laid"]], "same deeper viewport has document-length independent character work");
        Check([shortNear[@"generated"] isEqual:longNear[@"generated"]], "same shallow viewport has document-length independent glyph generation");
        Check([shortDeep[@"generated"] isEqual:longDeep[@"generated"]], "same deeper viewport has document-length independent glyph generation");
        Check([shortDeep[@"laid"] unsignedIntegerValue] > [shortNear[@"laid"] unsignedIntegerValue], "deeper viewport increases actual layout work");
        RunCase(2000,0,NO,YES); RunCase(12000,0,NO,YES);
        printf("PASS: %lu assertions\n",Checks);
    }
    return 0;
}
