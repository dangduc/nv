#import <Cocoa/Cocoa.h>

// Configuration investigation only. No nvALT code or user notes are loaded.
static NSString *Spaces(NSUInteger count) {
    return [@"" stringByPaddingToLength:count withString:@" " startingAtIndex:0];
}
static NSUInteger Checks;
static void Check(BOOL condition) {
    Checks++;
    if (!condition) { fprintf(stderr,"FAIL at check %lu\n", (unsigned long)Checks); exit(1); }
}

// A separate experiment, beyond configuration: preserve source characters and
// glyph IDs, but remove the layout flag that gives spaces elastic widths.
@interface FixedSpaceDelegate : NSObject <NSLayoutManagerDelegate>
@end
@implementation FixedSpaceDelegate
- (NSUInteger)layoutManager:(NSLayoutManager *)layout shouldGenerateGlyphs:(const CGGlyph *)glyphs
                 properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes
                       font:(NSFont *)font forGlyphRange:(NSRange)range {
    NSGlyphProperty *changed = calloc(range.length, sizeof(NSGlyphProperty));
    if (!changed) return 0;
    NSString *source = layout.textStorage.string;
    for (NSUInteger i=0; i<range.length; i++) {
        changed[i] = properties[i];
        if (indexes[i] < source.length && [source characterAtIndex:indexes[i]] == ' ')
            changed[i] &= ~NSGlyphPropertyElastic;
    }
    [layout setGlyphs:glyphs properties:changed characterIndexes:indexes font:font forGlyphRange:range];
    free(changed);
    return range.length;
}
@end

static NSDictionary *Measure(NSTextView *view) {
    NSMutableArray *lines = [NSMutableArray array];
    if (view.textLayoutManager) {
        NSTextLayoutManager *layout = view.textLayoutManager;
        [layout ensureLayoutForRange:layout.textContentManager.documentRange];
        [layout enumerateTextLayoutFragmentsFromLocation:layout.textContentManager.documentRange.location
            options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout usingBlock:^BOOL(NSTextLayoutFragment *fragment) {
            for (NSTextLineFragment *line in fragment.textLineFragments)
                [lines addObject:@{@"range":NSStringFromRange(line.characterRange),
                    @"y":@(fragment.layoutFragmentFrame.origin.y + line.typographicBounds.origin.y),
                    @"usedWidth":@(line.typographicBounds.size.width)}];
            return YES;
        }];
    } else {
        NSLayoutManager *layout = view.layoutManager;
        [layout ensureLayoutForTextContainer:view.textContainer];
        [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *container, NSRange glyphs, BOOL *stop) {
        [lines addObject:@{@"range": NSStringFromRange(glyphs), @"y": @(rect.origin.y), @"usedWidth": @(used.size.width)}];
        }];
    }
    if (view.horizontallyResizable) [view sizeToFit];
    [view scrollRangeToVisible:view.selectedRange];
    NSRect caret = [view firstRectForCharacterRange:NSMakeRange(view.string.length, 0) actualRange:NULL];
    // Insertion rectangles can have zero width and still provide valid geometry.
    BOOL validCaret = caret.size.height > 0;
    caret = [view convertRect:[view.window convertRectFromScreen:caret] fromView:nil];
    return @{@"lines": lines, @"caretX": validCaret ? @(caret.origin.x) : (id)[NSNull null],
        @"caretY": validCaret ? @(caret.origin.y) : (id)[NSNull null], @"validCaretRect":@(validCaret),
        @"length": @(view.string.length), @"selection": NSStringFromRange(view.selectedRange),
        @"containerWidth": @(view.textContainer.size.width), @"textKit2":@(view.textLayoutManager != nil),
        @"visibleX":@(view.visibleRect.origin.x), @"viewWidth":@(view.frame.size.width)};
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,480,400)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        NSArray *modes = @[@"default", @"paragraph-character", @"container-character", @"both-character",
            @"standard-strategy", @"latest-typesetter", @"original-typesetter", @"show-invisibles", @"no-wrap",
            @"textkit2-default", @"textkit2-character", @"fixed-space-glyphs", @"fixed-space-glyphs-character"];
        NSMutableArray *results = [NSMutableArray array];
        for (NSString *mode in modes) {
            for (NSNumber *fontSize in @[@12, @22]) {
                @autoreleasepool {
                    BOOL textKit2 = [mode hasPrefix:@"textkit2"];
                    NSTextView *view;
                    if (textKit2) {
                        view = [[[NSTextView alloc] initUsingTextLayoutManager:YES] autorelease];
                        view.frame = NSMakeRect(0,0,480,400);
                    } else {
                        NSTextStorage *storage = [[[NSTextStorage alloc] init] autorelease];
                        NSLayoutManager *layout = [[[NSLayoutManager alloc] init] autorelease];
                        NSTextContainer *container = [[[NSTextContainer alloc] initWithSize:NSMakeSize(464, 10000000)] autorelease];
                        [storage addLayoutManager:layout]; [layout addTextContainer:container];
                        view = [[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,480,400) textContainer:container] autorelease];
                    }
                    NSTextStorage *storage = view.textStorage;
                    NSLayoutManager *layout = textKit2 ? nil : view.layoutManager;
                    FixedSpaceDelegate *fixedSpaces = [[[FixedSpaceDelegate alloc] init] autorelease];
                    if ([mode hasPrefix:@"fixed-space-glyphs"]) layout.delegate = fixedSpaces;
                    NSTextContainer *container = view.textContainer;
                    view.richText = NO;
                    view.horizontallyResizable = NO; view.verticallyResizable = YES;
                    view.textContainerInset = NSMakeSize(8,8);
                    container.widthTracksTextView = YES;
                    NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:fontSize.doubleValue];
                    view.font = font;
                    NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
                    if ([mode isEqual:@"paragraph-character"] || [mode isEqual:@"both-character"] ||
                        [mode isEqual:@"textkit2-character"] || [mode isEqual:@"fixed-space-glyphs-character"])
                        style.lineBreakMode = NSLineBreakByCharWrapping;
                    if ([mode isEqual:@"container-character"] || [mode isEqual:@"both-character"])
                        container.lineBreakMode = NSLineBreakByCharWrapping;
                    if ([mode isEqual:@"standard-strategy"]) style.lineBreakStrategy = NSLineBreakStrategyStandard;
                    if ([mode isEqual:@"latest-typesetter"]) layout.typesetterBehavior = NSTypesetterLatestBehavior;
                    if ([mode isEqual:@"original-typesetter"]) layout.typesetterBehavior = NSTypesetterOriginalBehavior;
                    if ([mode isEqual:@"show-invisibles"]) layout.showsInvisibleCharacters = YES;
                    if ([mode isEqual:@"no-wrap"]) {
                        view.horizontallyResizable = YES;
                        view.maxSize = NSMakeSize(10000000,10000000);
                        container.widthTracksTextView = NO; container.size = NSMakeSize(10000000,10000000);
                    }
                    view.defaultParagraphStyle = style;
                    NSDictionary *attributes = @{NSFontAttributeName:font, NSParagraphStyleAttributeName:style};
                    view.typingAttributes = attributes;
                    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,400)] autorelease];
                    scroll.hasVerticalScroller = YES;
                    scroll.hasHorizontalScroller = [mode isEqual:@"no-wrap"];
                    scroll.documentView = view;
                    window.contentView = scroll;
                    [window makeKeyAndOrderFront:nil]; [window makeFirstResponder:view];
                    for (NSString *fixture in @[@"spaces", @"prefix-spaces", @"prose", @"spaces-newline",
                        @"tabs", @"unicode", @"unicode-spaces"]) {
                        NSString *text = [fixture isEqual:@"spaces"] ? Spaces(200) :
                            [fixture isEqual:@"prefix-spaces"] ? [@"hello " stringByAppendingString:Spaces(200)] :
                            [fixture isEqual:@"spaces-newline"] ? [Spaces(200) stringByAppendingString:@"\n"] :
                            [fixture isEqual:@"tabs"] ? @"\talpha\tbeta\n\tgamma\t" :
                            [fixture isEqual:@"unicode"] ? @"êôâuieơăưe\u0302👩🏽‍💻中文\u00a0\u00a0\u00a0" :
                            [fixture isEqual:@"unicode-spaces"] ? [@"êôâuieơăưe\u0302👩🏽‍💻中文" stringByAppendingString:Spaces(200)] :
                            @"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega";
                        [storage setAttributedString:[[[NSAttributedString alloc] initWithString:text attributes:attributes] autorelease]];
                        view.selectedRange = NSMakeRange(text.length,0);
                        NSDictionary *before = Measure(view);
                        [view insertText:@" " replacementRange:view.selectedRange];
                        Check([view.string isEqual:[text stringByAppendingString:@" "]]);
                        Check(NSEqualRanges(view.selectedRange,NSMakeRange(text.length+1,0)));
                        NSDictionary *afterSpace = Measure(view);
                        [view insertText:@"X" replacementRange:view.selectedRange];
                        Check([view.string isEqual:[text stringByAppendingString:@" X"]]);
                        Check(NSEqualRanges(view.selectedRange,NSMakeRange(text.length+2,0)));
                        NSDictionary *afterPrintable = Measure(view);
                        [results addObject:@{@"mode":mode, @"fontSize":fontSize, @"fixture":fixture,
                            @"typesetter":@(layout.typesetterBehavior), @"before":before,
                            @"afterSpace":afterSpace, @"afterPrintable":afterPrintable}];
                    }
                    // Start empty and deliver actual repeated Space key events. Geometry
                    // queries run only after the sequence, not between key events.
                    [storage setAttributedString:[[[NSAttributedString alloc] initWithString:@"" attributes:attributes] autorelease]];
                    view.typingAttributes = attributes;
                    view.selectedRange = NSMakeRange(0,0);
                    for (NSUInteger i=0; i<201; i++) {
                        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                            modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                            context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:i>0 keyCode:49];
                        [NSApp sendEvent:event];
                        Check(view.string.length == i+1);
                        Check(NSEqualRanges(view.selectedRange,NSMakeRange(i+1,0)));
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
                    }
                    Check([view.string isEqual:Spaces(201)]);
                    NSDictionary *repeated = Measure(view);
                    [view deleteBackward:nil];
                    Check([view.string isEqual:Spaces(200)]);
                    Check(NSEqualRanges(view.selectedRange,NSMakeRange(200,0)));
                    [results addObject:@{@"mode":mode, @"fontSize":fontSize, @"fixture":@"repeated-key-events",
                        @"afterSpace":repeated, @"afterBackspace":Measure(view)}];
                    layout.delegate = nil;
                }
            }
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
        if (argc > 1) [data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        else fwrite(data.bytes,1,data.length,stdout);
        fprintf(stderr,"PASS: %lu source/selection checks; %lu configuration results\n",
            (unsigned long)Checks, (unsigned long)results.count);
        [window orderOut:nil]; [window release];
    }
    return 0;
}
