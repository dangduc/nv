#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#import "fault_hooks.h"
#include "production-space-delegate.h"

static NSUInteger Checks, CompletedParagraphs;
static void Check(BOOL okay,const char *message) {
    Checks++;
    if (!okay) { fprintf(stderr,"FAIL %lu: %s\n",(unsigned long)Checks,message); exit(1); }
}
@interface ObservedTypesetter : NVSourceTypesetter
@end
@implementation ObservedTypesetter
- (void)endParagraph {
    [super endParagraph];
    Check(!paragraphMeasure && !lineBreaks,"completed failure or recovery clears both analysis caches");
    CompletedParagraphs++;
}
@end

@interface System : NSObject {
@public
    NSTextStorage *storage;
    NSLayoutManager *layout;
    NSTextContainer *container;
    SpaceDelegate *delegate;
}
- (id)initWithSource:(NSString *)source width:(CGFloat)width alignment:(NSTextAlignment)alignment refined:(BOOL)refined;
- (NSDictionary *)snapshot;
@end
@implementation System
- (id)initWithSource:(NSString *)source width:(CGFloat)width alignment:(NSTextAlignment)alignment refined:(BOOL)refined {
    if ((self=[super init])) {
        NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
        style.lineBreakMode=NSLineBreakByCharWrapping;
        style.alignment=alignment;
        storage=[[NSTextStorage alloc] initWithString:source attributes:@{
            NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18],NSParagraphStyleAttributeName:style}];
        layout=[[NSLayoutManager alloc] init];
        container=[[NSTextContainer alloc] initWithSize:NSMakeSize(width,100000)];
        delegate=[[SpaceDelegate alloc] init];
        [storage addLayoutManager:layout];
        [layout addTextContainer:container];
        layout.delegate=delegate;
        if (refined) layout.typesetter=[[[ObservedTypesetter alloc] init] autorelease];
    }
    return self;
}
- (NSDictionary *)snapshot {
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *lines=[NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs)
        usingBlock:^(NSRect rect,NSRect used,NSTextContainer *current,NSRange glyphs,BOOL *stop) {
        NSRange chars=[layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
        Check(NSMaxRange(chars)<=storage.length,"line range stays within the source");
        NSMutableArray *points=[NSMutableArray array];
        for (NSUInteger glyph=glyphs.location;glyph<NSMaxRange(glyphs);glyph++)
            [points addObject:NSStringFromPoint([layout locationForGlyphAtIndex:glyph])];
        [lines addObject:@{@"characters":NSStringFromRange(chars),@"rect":NSStringFromRect(rect),
            @"used":NSStringFromRect(used),@"points":points}];
    }];
    return @{@"source":[[storage.string copy] autorelease],@"lines":lines};
}
- (void)dealloc {
    layout.delegate=nil;
    [delegate release]; [container release]; [layout release]; [storage release];
    [super dealloc];
}
@end

int main(int argc,const char **argv) {
    @autoreleasepool {
        if (argc!=2) return 2;
        [NSApplication sharedApplication];
        NSMutableArray *records=[NSMutableArray array];
        NSArray *sources=@[@"alpha beta gamma delta epsilon zeta eta theta",
            @"alpha beta gamma delta\nשלום עולם hello alpha beta gamma\n",
            @"alpha beta gamma 👩🏽‍💻 e\u0302 中文 delta epsilon zeta eta theta"];
        for (NSNumber *fault in @[@(ReviewTypesetterNull),@(ReviewFirstLineNull),@(ReviewExtendedLineNull)])
        for (NSNumber *width in @[@160,@240])
        for (NSNumber *alignment in @[@(NSTextAlignmentLeft),@(NSTextAlignmentRight)])
        for (NSString *source in sources) {
            @autoreleasepool {
                unsigned long injectedBefore=ReviewInjectedFailures();
                ReviewSetFault(fault.intValue);
                System *candidate=[[[System alloc] initWithSource:source width:width.doubleValue alignment:alignment.integerValue refined:YES] autorelease];
                NSDictionary *actual=[candidate snapshot];
                Check(ReviewInjectedFailures()>injectedBefore,"fixture reaches its injected creation failure");
                Check([candidate->storage.string isEqual:source],"failed measurement preserves exact source");
                Check(ReviewLiveObjects()==0,"every created Core Text object receives a production release");
                System *native=[[[System alloc] initWithSource:source width:width.doubleValue alignment:alignment.integerValue refined:NO] autorelease];
                Check([actual isEqual:[native snapshot]],"null creation falls back to exact native character geometry");

                ReviewSetFault(ReviewNoFault);
                [candidate->layout invalidateLayoutForCharacterRange:NSMakeRange(0,source.length) actualCharacterRange:NULL];
                System *fresh=[[[System alloc] initWithSource:source width:width.doubleValue alignment:alignment.integerValue refined:YES] autorelease];
                Check([[candidate snapshot] isEqual:[fresh snapshot]],"successful retry matches fresh production layout");
                Check(ReviewLiveObjects()==0,"every created Core Text object receives a production release");
                Check([candidate->storage.string isEqual:source],"recovery preserves exact source");
                [records addObject:@{@"fault":fault,@"width":width,@"alignment":alignment,
                    @"sourceLength":@(source.length),@"injectedFailures":@(ReviewInjectedFailures()-injectedBefore)}];
            }
            Check(ReviewLiveObjects()==0,"destruction leaves no outstanding tracked Core Text ownership");
        }
        Check(ReviewCreatedObjects()==ReviewReleasedObjects(),"Core Text create and release counts balance");
        NSDictionary *result=@{@"checks":@(Checks),@"cases":records,@"completedParagraphs":@(CompletedParagraphs),
            @"injectedFailures":@(ReviewInjectedFailures()),@"createdObjects":@(ReviewCreatedObjects()),
            @"releasedObjects":@(ReviewReleasedObjects()),@"outstandingObjects":@(ReviewLiveObjects()),@"status":@"passed"};
        NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        if (![json writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES]) return 2;
        fprintf(stderr,"PASS: %lu checks\n",(unsigned long)Checks);
    }
    return 0;
}
