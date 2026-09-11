#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "delegates.h"
#include <math.h>

static NSUInteger Checks, Cases, BaselineControls;
static NSMutableArray *Failures, *Records;
static void Check(BOOL value, NSString *message) { Checks++; if(!value) [Failures addObject:message]; }
@interface System : NSObject {
@public NSTextStorage *storage; NSLayoutManager *layout; NSTextContainer *container; id delegate;
}
- (id)initWithSource:(NSString *)source mode:(NSUInteger)mode;
- (void)configure:(NSFont *)font padding:(CGFloat)padding first:(CGFloat)first head:(CGFloat)head;
- (NSArray *)at:(NSUInteger)character;
@end
@implementation System
- (id)initWithSource:(NSString *)source mode:(NSUInteger)mode {
    if((self=[super init])) {
        storage=[[NSTextStorage alloc] initWithString:source]; layout=[[NSLayoutManager alloc] init];
        container=[[NSTextContainer alloc] initWithSize:NSMakeSize(200,10000)];
        [storage addLayoutManager:layout]; [layout addTextContainer:container];
        if(mode) {
            delegate=mode==1?(id)[[CurrentDelegate alloc] init]:(id)[[BaseDelegate alloc] init];
            layout.delegate=delegate; layout.typesetter=[[[NVSourceTypesetter alloc] init] autorelease];
        }
    } return self;
}
- (void)configure:(NSFont *)font padding:(CGFloat)padding first:(CGFloat)first head:(CGFloat)head {
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode=delegate?NSLineBreakByCharWrapping:NSLineBreakByWordWrapping;
    style.firstLineHeadIndent=first; style.headIndent=head;
    CGFloat width=[@"abcdefghij" sizeWithAttributes:@{NSFontAttributeName:font}].width+2*padding+first+0.25;
    [storage setAttributes:@{NSFontAttributeName:font,NSParagraphStyleAttributeName:style,@"Fixture":@"retained"}
                    range:NSMakeRange(0,storage.length)];
    container.lineFragmentPadding=padding;
    container.containerSize=NSMakeSize(width,10000);
    NSAttributedString *before=[[storage copy] autorelease];
    [layout ensureLayoutForTextContainer:container];
    Check([storage isEqualToAttributedString:before],@"native layout preserves source and paragraph attributes");
}
- (NSArray *)at:(NSUInteger)character {
    NSUInteger glyph=[layout glyphIndexForCharacterAtIndex:character];
    NSRect line=[layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    NSPoint p=[layout locationForGlyphAtIndex:glyph];
    return @[@(line.origin.x+p.x),@(line.origin.y),@([layout propertyForGlyphAtIndex:glyph])];
}
- (void)dealloc {
    layout.delegate=nil; [delegate release]; [container release]; [layout release]; [storage release]; [super dealloc];
}
@end
static BOOL Near(NSNumber *a, NSNumber *b) { return fabs(a.doubleValue-b.doubleValue)<0.01; }
static NSArray *AllPositions(System *system) {
    NSMutableArray *result=[NSMutableArray array];
    for(NSUInteger index=0;index<system->storage.length;index++) [result addObject:[system at:index]];
    return result;
}
static void Fixture(NSString *source, NSString *name) {
    System *live=[[[System alloc] initWithSource:source mode:1] autorelease];
    // Changes occur on one live layout, including restored original metrics.
    NSArray *settings=@[@[@10,@0,@0,@0],@[@10,@5,@0,@0],@[@22,@9,@0,@0],@[@22,@5,@8,@12],@[@10,@0,@0,@0]];
    for(NSArray *setting in settings) {
        CGFloat size=[setting[0] doubleValue],padding=[setting[1] doubleValue],first=[setting[2] doubleValue],head=[setting[3] doubleValue];
        NSFont *font=[NSFont fontWithName:@"Menlo-Regular" size:size]; Check(font!=nil,@"fixture font exists");
        System *fresh=[[[System alloc] initWithSource:source mode:1] autorelease];
        System *baseline=[[[System alloc] initWithSource:source mode:2] autorelease];
        System *native=[[[System alloc] initWithSource:source mode:0] autorelease];
        for(System *system in @[live,fresh,baseline,native]) [system configure:font padding:padding first:first head:head];
        NSString *label=[NSString stringWithFormat:@"%@ %@",name,setting];
        Check([AllPositions(live) isEqual:AllPositions(fresh)],[label stringByAppendingString:@": changed metrics match fresh production geometry"]);
        Check([live->storage.string isEqual:source],[label stringByAppendingString:@": mixed hard-break code units remain exact"]);
        NSArray *separator=[live at:10],*previous=[live at:9],*word=[live at:11],*nativeWord=[native at:11];
        Check(Near(separator[1],previous[1]) && [word[1] doubleValue]>[separator[1] doubleValue],
              [label stringByAppendingString:@": isolated separator collapses on the preceding line"]);
        Check(fabs([word[0] doubleValue]-(padding+head))<0.01 && Near(word[0],nativeWord[0]),
              [label stringByAppendingString:@": wrapped word begins at the paragraph leading edge"]);
        NSArray *baseWord=[baseline at:11];
        if(!Near(baseWord[0],word[0]) || !Near(baseWord[1],word[1])) BaselineControls++;
        NSMutableArray *indents=[NSMutableArray array];
        for(NSUInteger index=19;index<source.length;index++) if([source characterAtIndex:index]==' ') {
            NSArray *space=[live at:index],*next=[live at:index+1],*baseSpace=[baseline at:index],*baseNext=[baseline at:index+1];
            CGFloat advance=[next[0] doubleValue]-[space[0] doubleValue];
            CGFloat baseAdvance=[baseNext[0] doubleValue]-[baseSpace[0] doubleValue];
            Check(!([space[2] unsignedIntegerValue]&NSGlyphPropertyElastic),[label stringByAppendingString:@": hard-break indentation stays nonelastic"]);
            Check(Near(space[1],next[1]) && advance>0 && fabs(advance-baseAdvance)<0.01,
                  [label stringByAppendingString:@": indentation advances on the same line as its following letter"]);
            Check(Near(space[0],baseSpace[0]),[label stringByAppendingString:@": hard-break indentation retains baseline horizontal origin"]);
            [indents addObject:@{@"sourceIndex":@(index),@"x":space[0],@"advance":@(advance)}];
        }
        Check(indents.count==5,@"each fixture checks CRLF, CR, LF, line separator, and paragraph separator indentation");
        [Records addObject:@{@"fixture":name,@"settings":setting,@"wrappedWordX":word[0],@"nativeWordX":nativeWord[0],@"indents":indents}]; Cases++;
    }
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2) return 2; Failures=[NSMutableArray array]; Records=[NSMutableArray array];
        Fixture(@"abcdefghij nextword\r\n x\r y\n z\u2028 u\u2029 v",@"forward-hardbreaks");
        Fixture(@"abcdefghij nextword\u2029 v\u2028 u\n z\r y\r\n x",@"reverse-hardbreaks");
        Check(BaselineControls>0,@"the old separator policy differs in at least one positive-control layout");
        Check(NSApp==nil,@"the probe creates no GUI application");
        NSDictionary *report=@{@"checks":@(Checks),@"cases":@(Cases),@"baselineControls":@(BaselineControls),@"failures":Failures,@"records":Records};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        printf("%lu checks; %lu cases; %lu baseline controls; %lu failures\n",(unsigned long)Checks,(unsigned long)Cases,(unsigned long)BaselineControls,(unsigned long)Failures.count);
        for(NSString *failure in Failures) fprintf(stderr,"FAIL: %s\n",failure.UTF8String);
        return Failures.count?1:0;
    }
}
