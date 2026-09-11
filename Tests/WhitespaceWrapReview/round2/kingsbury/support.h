#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "LinkingEditor.h"

static void Check(BOOL result, NSString *description);
static void Pump(void);
static NSUInteger MarkedGlyphCallbacks, GlyphCallbacks;
static IMP OriginalGlyphMethod;
static NSMutableArray *History;

static NSUInteger ObserveGlyphs(id self, SEL selector, NSLayoutManager *manager, const CGGlyph *glyphs,
    const NSGlyphProperty *properties, const NSUInteger *indexes, NSFont *font, NSRange range) {
    GlyphCallbacks++;
    if ([(NSTextView *)self hasMarkedText]) MarkedGlyphCallbacks++;
    return ((NSUInteger (*)(id,SEL,NSLayoutManager *,const CGGlyph *,const NSGlyphProperty *,const NSUInteger *,NSFont *,NSRange))OriginalGlyphMethod)
        (self,selector,manager,glyphs,properties,indexes,font,range);
}
static NSString *Spaces(NSUInteger length) {
    return [@"" stringByPaddingToLength:length withString:@" " startingAtIndex:0];
}
static NSUInteger Lines(NSTextView *view) {
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    __block NSUInteger lines=0;
    [view.layoutManager enumerateLineFragmentsForGlyphRange:NSMakeRange(0,view.layoutManager.numberOfGlyphs)
        usingBlock:^(NSRect rect,NSRect used,NSTextContainer *container,NSRange range,BOOL *stop){lines++;}];
    return lines;
}
static void PureRegeneration(NSArray *editors, NVNoteEditingSession *session) {
    NSAttributedString *snapshot = [[session.textStorage copy] autorelease];
    uint64_t generation = session.sourceGeneration;
    NSString *model = [[[session.note.contentString string] copy] autorelease];
    BOOL undo = session.note.undoManager.canUndo, redo = session.note.undoManager.canRedo;
    NSMutableArray *selections=[NSMutableArray array], *marks=[NSMutableArray array];
    for (NSTextView *view in editors) {
        [selections addObject:[NSValue valueWithRange:view.selectedRange]];
        [marks addObject:[NSValue valueWithRange:view.markedRange]];
    }
    for (NSTextView *view in editors) {
        [view.layoutManager invalidateGlyphsForCharacterRange:NSMakeRange(0,view.string.length)
            changeInLength:0 actualCharacterRange:NULL];
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    }
    Check([session.textStorage isEqualToAttributedString:snapshot],@"glyph regeneration preserves shared source attributes");
    Check(session.sourceGeneration==generation,@"glyph regeneration does not advance the source generation");
    Check([[session.note.contentString string] isEqual:model],@"glyph regeneration leaves the committed model unchanged");
    Check(session.note.undoManager.canUndo==undo && session.note.undoManager.canRedo==redo,@"glyph regeneration preserves Undo availability");
    for (NSUInteger i=0;i<editors.count;i++) {
        NSTextView *view=editors[i];
        Check(NSEqualRanges(view.selectedRange,[selections[i] rangeValue]),@"glyph regeneration preserves each editor selection");
        Check(NSEqualRanges(view.markedRange,[marks[i] rangeValue]),@"glyph regeneration preserves native marked ranges");
    }
}
static void State(NSString *label, NVNoteEditingSession *session, NSArray *editors,
    NSString *live, NSString *model, BOOL composing) {
    Check([session.textStorage.string isEqual:live], [label stringByAppendingString:@": shared live source"]);
    Check([[session.note.contentString string] isEqual:model], [label stringByAppendingString:@": committed source"]);
    BOOL anyMarked=NO;
    NSMutableArray *selections=[NSMutableArray array];
    for (NSTextView *view in editors) {
        Check(view.textStorage==session.textStorage,[label stringByAppendingString:@": shared storage identity"]);
        Check([view.string isEqual:live],[label stringByAppendingString:@": peer source"]);
        Check(NSMaxRange(view.selectedRange)<=view.string.length,[label stringByAppendingString:@": bounded peer selection"]);
        anyMarked|=view.hasMarkedText;
        [selections addObject:NSStringFromRange(view.selectedRange)];
    }
    Check(anyMarked==composing,[label stringByAppendingString:@": composition state"]);
    [History addObject:@{@"label":label,@"live":live,@"model":model,@"composing":@(composing),@"selections":selections}];
}
