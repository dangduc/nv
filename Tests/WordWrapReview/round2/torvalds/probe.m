#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVSourceTypesetter.h"
#include "production-space-delegate.h"

static NSUInteger Checks, Began, Ended, CleanupDuringEnd, NativeEndCalls;
static BOOL InEnd, NativeReturned;
static void (*NativeEndImplementation)(id, SEL);
static void Check(BOOL okay, const char *message) {
    Checks++;
    if (!okay) { fprintf(stderr, "FAIL %lu: %s\n", (unsigned long)Checks, message); exit(1); }
}
static void ObserveNativeEnd(id object, SEL selector) {
    NativeEndCalls++;
    NativeEndImplementation(object, selector);
    NativeReturned=YES;
}

@interface NVSourceTypesetter (ReviewCleanupDeclaration)
- (void)clearParagraphAnalysis;
@end
@interface ObservedTypesetter : NVSourceTypesetter
@end
@implementation ObservedTypesetter
- (void)beginParagraph {
    Began++;
    [super beginParagraph];
    Check(!paragraphMeasure && !lineBreaks, "beginParagraph starts without the previous analysis");
}
- (void)endParagraph {
    Check(!InEnd, "endParagraph does not reenter");
    InEnd=YES;
    NativeReturned=NO;
    [super endParagraph];
    Check(NativeReturned, "production endParagraph calls the native implementation");
    Check(!paragraphMeasure && !lineBreaks, "completed paragraph analysis is empty");
    InEnd=NO;
    Ended++;
}
- (void)clearParagraphAnalysis {
    if (InEnd) {
        Check(NativeReturned, "native endParagraph returns before production cleanup");
        CleanupDuringEnd++;
    }
    [super clearParagraphAnalysis];
    Check(!paragraphMeasure && !lineBreaks, "cleanup clears both cache pointers");
}
@end

@interface System : NSObject {
@public
    NSTextStorage *storage;
    NSLayoutManager *layout;
    NSMutableArray *containers;
    SpaceDelegate *delegate;
}
- (id)initWithWidths:(NSArray *)widths height:(CGFloat)height;
- (void)replaceSource:(NSString *)source size:(CGFloat)size;
- (NSDictionary *)snapshot;
@end
@implementation System
- (id)initWithWidths:(NSArray *)widths height:(CGFloat)height {
    if ((self=[super init])) {
        storage=[[NSTextStorage alloc] init];
        layout=[[NSLayoutManager alloc] init];
        containers=[[NSMutableArray alloc] init];
        delegate=[[SpaceDelegate alloc] init];
        [storage addLayoutManager:layout];
        layout.delegate=delegate;
        layout.typesetter=[[[ObservedTypesetter alloc] init] autorelease];
        for (NSNumber *width in widths) {
            NSTextContainer *container=[[[NSTextContainer alloc] initWithSize:NSMakeSize(width.doubleValue,height)] autorelease];
            [layout addTextContainer:container];
            [containers addObject:container];
        }
    }
    return self;
}
- (void)replaceSource:(NSString *)source size:(CGFloat)size {
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode=NSLineBreakByCharWrapping;
    NSMutableDictionary *attrs=[NSMutableDictionary dictionaryWithDictionary:@{
        NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:size],
        NSParagraphStyleAttributeName:style}];
    [storage setAttributedString:[[[NSAttributedString alloc] initWithString:source attributes:attrs] autorelease]];
}
- (NSDictionary *)snapshot {
    for (NSTextContainer *container in containers) [layout ensureLayoutForTextContainer:container];
    NSMutableArray *lines=[NSMutableArray array];
    for (NSTextContainer *container in containers) {
        NSRange glyphRange=[layout glyphRangeForTextContainer:container];
        [layout enumerateLineFragmentsForGlyphRange:glyphRange usingBlock:^(NSRect rect, NSRect used, NSTextContainer *current, NSRange glyphs, BOOL *stop) {
            NSRange chars=[layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
            Check(NSMaxRange(chars)<=storage.length, "native line range stays inside source");
            NSMutableArray *points=[NSMutableArray array];
            for (NSUInteger glyph=glyphs.location;glyph<NSMaxRange(glyphs);glyph++) {
                NSPoint point=[layout locationForGlyphAtIndex:glyph];
                [points addObject:NSStringFromPoint(point)];
            }
            [lines addObject:@{@"characters":NSStringFromRange(chars), @"rect":NSStringFromRect(rect),
                @"used":NSStringFromRect(used), @"points":points, @"container":@([containers indexOfObjectIdenticalTo:current])}];
        }];
    }
    return @{@"source":storage.string, @"lines":lines};
}
- (void)dealloc {
    layout.delegate=nil;
    [delegate release];
    [containers release];
    [layout release];
    [storage release];
    [super dealloc];
}
@end

static void CompareFresh(System *system) {
    NSMutableArray *widths=[NSMutableArray array];
    for (NSTextContainer *container in system->containers) [widths addObject:@(container.size.width)];
    System *fresh=[[[System alloc] initWithWidths:widths height:((NSTextContainer *)system->containers[0]).size.height] autorelease];
    [fresh->storage setAttributedString:system->storage];
    Check([[system snapshot] isEqual:[fresh snapshot]], "incremental geometry equals a fresh production text system");
}

int main(int argc,const char **argv) {
    @autoreleasepool {
        if (argc!=2) return 2;
        [NSApplication sharedApplication];
        Class nativeClass=[NSATSTypesetter class];
        SEL selector=@selector(endParagraph);
        Method method=class_getInstanceMethod(nativeClass,selector);
        Check(method!=NULL, "native endParagraph implementation exists");
        NativeEndImplementation=(void (*)(id,SEL))method_getImplementation(method);
        class_replaceMethod(nativeClass,selector,(IMP)ObserveNativeEnd,method_getTypeEncoding(method));

        NSString *phrase=@"alpha beta gamma delta epsilon zeta eta theta ";
        NSString *longSource=[@"" stringByPaddingToLength:4096 withString:phrase startingAtIndex:0];
        NSUInteger sequences=0;
        for (NSNumber *size in @[@12,@18])
        for (NSArray *widths in @[@[@160],@[@240,@160,@320]])
        for (NSNumber *height in @[@44,@100000]) {
            @autoreleasepool {
                System *system=[[[System alloc] initWithWidths:widths height:height.doubleValue] autorelease];
                for (NSString *source in @[longSource, @"", @"\n", @"alpha beta\n\nשלום עולם\r\nemoji 👩🏽‍💻 e\u0302 alpha beta\u2028tail", phrase]) {
                    [system replaceSource:source size:size.doubleValue];
                    CompareFresh(system);
                    if (system->storage.length) {
                        [system->storage addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Helvetica" size:16] range:NSMakeRange(0,system->storage.length)];
                        CompareFresh(system);
                    }
                    for (NSTextContainer *container in system->containers) container.size=NSMakeSize(container.size.width+23,container.size.height);
                    CompareFresh(system);
                    sequences++;
                }
            }
        }
        Check(Began==Ended, "native paragraph callbacks balance after complete layout requests");
        Check(Ended==CleanupDuringEnd && Ended==NativeEndCalls, "each native paragraph exit has one completed cleanup");
        for (NSUInteger i=0;i<40;i++) {
            @autoreleasepool {
                System *system=[[[System alloc] initWithWidths:@[@160] height:44] autorelease];
                [system replaceSource:longSource size:18];
                [system snapshot];
                [(NVSourceTypesetter *)system->layout.typesetter clearParagraphAnalysis];
                [(NVSourceTypesetter *)system->layout.typesetter clearParagraphAnalysis];
                [system replaceSource:@"" size:18];
                [system snapshot];
            }
        }
        class_replaceMethod(nativeClass,selector,(IMP)NativeEndImplementation,method_getTypeEncoding(method));
        NSDictionary *results=@{@"checks":@(Checks), @"sequences":@(sequences), @"paragraphBegins":@(Began),
            @"paragraphEnds":@(Ended), @"nativeEnds":@(NativeEndCalls), @"cleanupDuringEnd":@(CleanupDuringEnd),
            @"repeatedCleanupCycles":@40, @"status":@"passed"};
        NSData *json=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
        Check([json writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES], "write evidence");
        fprintf(stderr,"PASS: %lu checks\n",(unsigned long)Checks);
    }
    return 0;
}
