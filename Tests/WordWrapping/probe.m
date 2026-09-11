#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "space-delegate.h"

static NSUInteger Checks;
static BOOL NegativeControl;
static void Check(BOOL condition, NSString *message) {
    Checks++;
    if (!condition) {
        fprintf(stderr, "FAIL %lu: %s\n", (unsigned long)Checks, message.UTF8String);
        exit(1);
    }
}
static NSString *Spaces(NSUInteger count) {
    return [@"" stringByPaddingToLength:count withString:@" " startingAtIndex:0];
}
static NSMutableParagraphStyle *ParagraphStyle(NSString *name) {
    NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode = NSLineBreakByCharWrapping;
    if ([name isEqual:@"indent"]) {
        style.firstLineHeadIndent = 32;
        style.headIndent = 16;
        style.tailIndent = -10;
    } else if ([name isEqual:@"tabs"]) {
        style.tabStops = @[];
        style.defaultTabInterval = 40;
    }
    return style;
}

// Own the complete text system; NSLayoutManager does not retain its delegate.
@interface TextSystem : NSObject {
@public
    NSTextStorage *storage;
    NSLayoutManager *layout;
    NSTextContainer *container;
    SpaceDelegate *delegate;
}
- (id)initWithWidth:(CGFloat)width refined:(BOOL)refined;
- (void)setSource:(NSString *)source font:(NSFont *)font style:(NSParagraphStyle *)style;
- (NSDictionary *)snapshot;
@end
@implementation TextSystem
- (id)initWithWidth:(CGFloat)width refined:(BOOL)refined {
    if ((self = [super init])) {
        storage = [[NSTextStorage alloc] init];
        layout = [[NSLayoutManager alloc] init];
        container = [[NSTextContainer alloc] initWithSize:NSMakeSize(width, 10000000)];
        delegate = [[SpaceDelegate alloc] init];
        [storage addLayoutManager:layout];
        [layout addTextContainer:container];
        layout.delegate = delegate;
        if (refined && !NegativeControl) layout.typesetter = [[[NVSourceTypesetter alloc] init] autorelease];
    }
    return self;
}
- (void)setSource:(NSString *)source font:(NSFont *)font style:(NSParagraphStyle *)style {
    NSDictionary *attributes = @{NSFontAttributeName:font, NSParagraphStyleAttributeName:style};
    [storage setAttributedString:[[[NSAttributedString alloc] initWithString:source attributes:attributes] autorelease]];
}
- (NSDictionary *)snapshot {
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *points = [NSMutableArray array], *lines = [NSMutableArray array];
    for (NSUInteger index = 0; index < storage.length; index++) {
        NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:index];
        NSRect line = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
        NSPoint position = [layout locationForGlyphAtIndex:glyph];
        [points addObject:@[@(line.origin.x + position.x), @(line.origin.y)]];
    }
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *textContainer, NSRange glyphs, BOOL *stop) {
            NSRange characters = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
            [lines addObject:@{@"start":@(characters.location), @"length":@(characters.length),
                              @"y":@(rect.origin.y), @"width":@(rect.size.width)}];
        }];
    return @{@"points":points, @"lines":lines};
}
- (void)dealloc {
    layout.delegate = nil;
    [delegate release];
    [container release];
    [layout release];
    [storage release];
    [super dealloc];
}
@end

static NSDictionary *Layout(NSString *source, NSFont *font, CGFloat width, NSParagraphStyle *style) {
    TextSystem *system = [[[TextSystem alloc] initWithWidth:width refined:YES] autorelease];
    [system setSource:source font:font style:style];
    NSDictionary *snapshot = [system snapshot];
    Check([system->storage.string isEqual:source], @"layout preserves the exact source");
    for (NSDictionary *line in snapshot[@"lines"]) {
        NSUInteger start = [line[@"start"] unsignedIntegerValue];
        Check(start == 0 || [source rangeOfComposedCharacterSequenceAtIndex:start].location == start,
              @"line start does not divide a composed character");
    }
    return snapshot;
}

static NSDictionary *Matrix(void) {
    NSArray *prefixes = @[@"alpha beta", @"one two three four alpha beta", @"\talpha\tbeta",
        @"êôâuieơăư e\u0302 👩🏽‍💻 中文", @"hello שלום עולם", @"שלום עולם hello", @"alpha\u00a0beta gamma"];
    NSString *prose = @"dark mode / light mode separate note body color styles; including differing syntax color styles\n"
        "support more syntax formats; not necessarily all we need to support previews\n";
    NSRegularExpression *words = [NSRegularExpression regularExpressionWithPattern:@"[a-zA-Z]+" options:0 error:NULL];
    NSUInteger configurations = 0;
    for (NSString *fontName in @[@"Menlo-Regular", @"Helvetica", @"TimesNewRomanPSMT"])
    for (NSNumber *size in @[@12, @18, @22])
    for (NSNumber *width in @[@80, @160, @320, @544])
    for (NSString *styleName in @[@"plain", @"indent", @"tabs"]) {
        @autoreleasepool {
            NSFont *font = [NSFont fontWithName:fontName size:size.doubleValue];
            Check(font != nil, @"fixture font is available");
            NSParagraphStyle *style = ParagraphStyle(styleName);
            NSDictionary *flow = Layout(prose, font, width.doubleValue, style);
            CGFloat available = width.doubleValue - 10 - ([styleName isEqual:@"indent"] ? 42 : 0);
            for (NSTextCheckingResult *word in [words matchesInString:prose options:0 range:NSMakeRange(0, prose.length)]) {
                CGFloat measured = [[prose substringWithRange:word.range] sizeWithAttributes:@{NSFontAttributeName:font}].width;
                if (measured <= available) {
                    Check([flow[@"points"][word.range.location][1] isEqual:flow[@"points"][NSMaxRange(word.range)-1][1]],
                          [NSString stringWithFormat:@"fitting word stays on one line (%@ %@ %@ %@)", fontName, size, width, styleName]);
                }
            }
            for (NSString *prefix in prefixes) {
                NSDictionary *before = Layout(prefix, font, width.doubleValue, style);
                for (NSNumber *count in @[@1, @40, @100]) {
                    NSDictionary *after = Layout([prefix stringByAppendingString:Spaces(count.unsignedIntegerValue)], font, width.doubleValue, style);
                    for (NSUInteger index = 0; index < prefix.length; index++) {
                        unichar character = [prefix characterAtIndex:index];
                        if (character != ' ' && character != '\t')
                            Check([before[@"points"][index][1] isEqual:after[@"points"][index][1]],
                                  @"appended spaces do not move existing words to another line");
                    }
                }
            }
            configurations++;
        }
    }
    // Oversize words are allowed to split, but must continue within the container.
    NSDictionary *longWord = Layout([@"" stringByPaddingToLength:300 withString:@"k" startingAtIndex:0],
        [NSFont fontWithName:@"Menlo-Regular" size:18], 160, ParagraphStyle(@"plain"));
    Check([longWord[@"lines"] count] > 10, @"an oversize word continues on following lines");
    return @{@"configurations":@(configurations)};
}

static NSDictionary *Geometry(void) {
    NSUInteger compared = 0, differentLines = 0;
    for (NSNumber *width in @[@320, @544])
    for (NSNumber *alignment in @[@(NSTextAlignmentNatural), @(NSTextAlignmentLeft), @(NSTextAlignmentRight), @(NSTextAlignmentCenter)])
    for (NSString *phrase in @[@"dark mode / light mode separate note body color styles; including differing syntax color styles ",
                              @"שלום עולם שלום עולם hello שלום עולם "]) {
        @autoreleasepool {
            NSString *source = [@"" stringByPaddingToLength:phrase.length*4 withString:phrase startingAtIndex:0];
            NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:18];
            NSMutableParagraphStyle *style = ParagraphStyle(@"plain");
            style.alignment = alignment.integerValue;
            NSDictionary *candidate = Layout(source, font, width.doubleValue, style);
            TextSystem *native = [[[TextSystem alloc] initWithWidth:width.doubleValue refined:NO] autorelease];
            style.lineBreakMode = NSLineBreakByWordWrapping;
            [native setSource:source font:font style:style];
            NSDictionary *reference = [native snapshot];
            for (NSUInteger index = 0; index < source.length; index++) {
                if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[source characterAtIndex:index]]) continue;
                NSArray *actual = candidate[@"points"][index], *expected = reference[@"points"][index];
                if (![actual[1] isEqual:expected[1]]) {
                    // The two wrapping modes can choose different line boundaries.
                    differentLines++;
                    continue;
                }
                NSDictionary *candidateLine = nil, *nativeLine = nil;
                for (NSDictionary *line in candidate[@"lines"])
                    if ([line[@"y"] isEqual:actual[1]]) { candidateLine = line; break; }
                for (NSDictionary *line in reference[@"lines"])
                    if ([line[@"y"] isEqual:expected[1]]) { nativeLine = line; break; }
                if (![candidateLine isEqual:nativeLine]) {
                    differentLines++;
                    continue;
                }
                Check(fabs([actual[0] doubleValue]-[expected[0] doubleValue]) < 0.1,
                      [NSString stringWithFormat:@"word positions preserve native paragraph alignment on identical lines (width %@ alignment %@ index %lu: %@ vs %@)",
                       width, alignment, (unsigned long)index, actual, expected]);
                compared++;
            }
        }
    }
    Check(compared > 500, @"alignment comparison covers enough matching glyph positions");
    return @{@"matchingRowComparisons":@(compared), @"differentRowPositions":@(differentLines)};
}

static void CheckFreshLayout(TextSystem *system) {
    NSDictionary *incremental = [system snapshot];
    TextSystem *fresh = [[[TextSystem alloc] initWithWidth:system->container.size.width refined:YES] autorelease];
    fresh->container.lineFragmentPadding = system->container.lineFragmentPadding;
    [fresh->storage setAttributedString:system->storage];
    NSDictionary *expected = [fresh snapshot];
    Check([incremental[@"lines"] isEqual:expected[@"lines"]], @"incremental edit produces the same line boundaries as a fresh layout");
    for (NSUInteger index = 0; index < system->storage.length; index++) {
        NSArray *actual = incremental[@"points"][index], *point = expected[@"points"][index];
        Check(fabs([actual[0] doubleValue]-[point[0] doubleValue]) < 0.1 && [actual[1] isEqual:point[1]],
              @"incremental edit produces the same glyph positions as a fresh layout");
    }
}

static NSPoint Caret(NSTextView *view) {
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    NSRect rect = [view firstRectForCharacterRange:view.selectedRange actualRange:NULL];
    Check(rect.size.height > 0, @"native caret geometry exists");
    return [view convertPoint:[view.window convertPointFromScreen:rect.origin] fromView:nil];
}
static NSDictionary *Editing(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 560, 600)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSMutableArray *records = [NSMutableArray array];
    for (NSString *fontName in @[@"Menlo-Regular", @"Helvetica"])
    for (NSNumber *width in @[@320, @560])
    for (NSString *prefix in @[@"", @"alpha beta", @"êôâuieơăư 👩🏽‍💻 中文"]) {
        @autoreleasepool {
            TextSystem *system = [[[TextSystem alloc] initWithWidth:width.doubleValue-16 refined:YES] autorelease];
            NSTextView *view = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, width.doubleValue, 600)
                textContainer:system->container] autorelease];
            view.richText = NO;
            view.horizontallyResizable = NO;
            view.verticallyResizable = YES;
            view.textContainerInset = NSMakeSize(8, 8);
            system->container.widthTracksTextView = YES;
            NSFont *font = [NSFont fontWithName:fontName size:18];
            NSParagraphStyle *style = ParagraphStyle(@"plain");
            view.defaultParagraphStyle = style;
            view.typingAttributes = @{NSFontAttributeName:font, NSParagraphStyleAttributeName:style};
            [window setContentSize:NSMakeSize(width.doubleValue, 600)];
            window.contentView = view;
            [window makeKeyAndOrderFront:nil];
            [window makeFirstResponder:view];
            [system setSource:prefix font:font style:style];
            view.selectedRange = NSMakeRange(prefix.length, 0);
            NSDictionary *before = [system snapshot];
            NSPoint previous = Caret(view);
            for (NSUInteger count = 1; count <= 201; count++) {
                NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
                    characters:@" " charactersIgnoringModifiers:@" " isARepeat:count>1 keyCode:49];
                [NSApp sendEvent:event];
                Check([view.string isEqual:[prefix stringByAppendingString:Spaces(count)]], @"native Space preserves exact source");
                Check(NSEqualRanges(view.selectedRange, NSMakeRange(prefix.length+count, 0)), @"native Space advances logical selection");
                NSPoint caret = Caret(view);
                Check(caret.y >= previous.y-0.1 && (fabs(caret.y-previous.y)>0.1 || caret.x >= previous.x-0.1),
                      @"caret advances while appending spaces");
                previous = caret;
                if (prefix.length) {
                    NSUInteger glyph = [system->layout glyphIndexForCharacterAtIndex:prefix.length-1];
                    Check([system->layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL].origin.y ==
                          [before[@"points"][prefix.length-1][1] doubleValue], @"typing spaces keeps the prefix on its original line");
                }
            }
            Check([[system snapshot][@"lines"] count] > 1, @"typed spaces occupy multiple lines");
            for (NSUInteger count = 201; count > 0; count--) {
                [view deleteBackward:nil];
                Check([view.string isEqual:[prefix stringByAppendingString:Spaces(count-1)]], @"Backspace preserves remaining source");
                Check(NSEqualRanges(view.selectedRange, NSMakeRange(prefix.length+count-1, 0)), @"Backspace retreats logical selection");
            }
            [view setMarkedText:@"e" selectedRange:NSMakeRange(1, 0) replacementRange:view.selectedRange];
            [view setMarkedText:@"ê" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
            [view unmarkText];
            Check([view.string isEqual:[prefix stringByAppendingString:@"ê"]], @"native composition commits exact Unicode");
            Check(NSEqualRanges(view.selectedRange, NSMakeRange(prefix.length+1, 0)), @"composition keeps selection at the end");
            for (NSNumber *position in @[@0, @(view.string.length/2), @(view.string.length)]) {
                view.selectedRange = NSMakeRange(position.unsignedIntegerValue, 0);
                [view insertText:@"alpha beta " replacementRange:view.selectedRange];
                CheckFreshLayout(system);
                [view deleteBackward:nil];
                CheckFreshLayout(system);
            }
            [view setFrameSize:NSMakeSize(width.doubleValue-75, 600)];
            CheckFreshLayout(system);
            [view setFrameSize:NSMakeSize(width.doubleValue, 600)];
            CheckFreshLayout(system);
            [records addObject:@{@"font":fontName, @"width":width, @"prefix":prefix, @"endCaret":NSStringFromPoint(previous)}];
        }
    }
    [window orderOut:nil];
    [window release];
    return @{@"cases":records};
}

static NSDictionary *Performance(void) {
    NSMutableArray *records = [NSMutableArray array];
    for (NSString *fixture in @[@"spaces", @"letters", @"prose"])
    for (NSNumber *count in @[@4096, @8192, @16384, @32768])
    for (NSNumber *refined in @[@NO, @YES]) {
        NSMutableArray *times = [NSMutableArray array];
        NSString *token = [fixture isEqual:@"spaces"] ? @" " : ([fixture isEqual:@"letters"] ? @"k" : @"one two three four five six seven eight nine ten. ");
        NSString *source = [@"" stringByPaddingToLength:count.unsignedIntegerValue withString:token startingAtIndex:0];
        for (NSUInteger iteration = 0; iteration < 7; iteration++) {
            @autoreleasepool {
                TextSystem *system = [[[TextSystem alloc] initWithWidth:544 refined:refined.boolValue] autorelease];
                [system setSource:source font:[NSFont fontWithName:@"Menlo-Regular" size:18] style:ParagraphStyle(@"plain")];
                NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
                [system->layout ensureLayoutForTextContainer:system->container];
                double elapsed = (NSProcessInfo.processInfo.systemUptime-start)*1000;
                Check(system->layout.numberOfGlyphs > 0 && [system->storage.string isEqual:source], @"timed layout completes with unchanged source");
                if (iteration) [times addObject:@(elapsed)];
            }
        }
        NSArray *sorted = [times sortedArrayUsingSelector:@selector(compare:)];
        double median = ([sorted[2] doubleValue] + [sorted[3] doubleValue])/2;
        [records addObject:@{@"fixture":fixture, @"characters":count, @"mode":refined.boolValue ? @"word" : @"previous-character",
                            @"medianMs":@(median), @"samplesMs":times}];
        fprintf(stderr, "%s %lu %s: %.3f ms\n", fixture.UTF8String, count.unsignedLongValue,
                refined.boolValue ? "word" : "character", median);
    }
    // Timings are evidence, not machine-dependent pass/fail thresholds.
    return @{@"measurements":records};
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3) return 2;
        [NSApplication sharedApplication];
        NegativeControl = argc > 3;
        NSString *suite = [NSString stringWithUTF8String:argv[1]];
        NSDictionary *evidence = nil;
        if ([suite isEqual:@"matrix"]) evidence = Matrix();
        else if ([suite isEqual:@"geometry"]) evidence = Geometry();
        else if ([suite isEqual:@"editing"]) evidence = Editing();
        else if ([suite isEqual:@"performance"]) evidence = Performance();
        else return 2;
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:evidence];
        result[@"checks"] = @(Checks);
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        Check([json writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES], @"write evidence JSON");
        fprintf(stderr, "PASS %s: %lu checks\n", suite.UTF8String, (unsigned long)Checks-1);
    }
    return 0;
}
