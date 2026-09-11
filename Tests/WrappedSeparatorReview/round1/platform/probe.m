#import <Cocoa/Cocoa.h>
#import "NVSourceTypesetter.h"
#include "delegates.h"
#include <math.h>

static NSUInteger Checks, Comparisons, BaselineDifferences;
static NSMutableArray *Failures, *Observations;
static void Check(BOOL result, NSString *label) {
    Checks++;
    if (!result) [Failures addObject:label];
}
@interface FixtureCell : NSTextAttachmentCell
@end
@implementation FixtureCell
- (NSSize)cellSize { return NSMakeSize(14, 14); }
@end

static NSDictionary *Snapshot(NSAttributedString *text, CGFloat width, NSUInteger mode) {
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithAttributedString:text] autorelease];
    NSLayoutManager *layout = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithSize:NSMakeSize(width, 10000)] autorelease];
    id delegate = mode == 0 ? nil : mode == 1 ? (id)[[[CurrentDelegate alloc] init] autorelease] : (id)[[[BaseDelegate alloc] init] autorelease];
    [storage addLayoutManager:layout]; [layout addTextContainer:container];
    layout.delegate = delegate;
    if (mode) layout.typesetter = [[[NVSourceTypesetter alloc] init] autorelease];
    if (!mode) {
        NSMutableParagraphStyle *style = [[[storage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] mutableCopy] autorelease];
        style.lineBreakMode = NSLineBreakByWordWrapping;
        [storage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0,storage.length)];
    }
    NSAttributedString *before = [[storage copy] autorelease];
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *rows = [NSMutableArray array], *points = [NSMutableArray array], *indexes = [NSMutableArray array];
    NSMutableArray *controls = [NSMutableArray array], *attachments = [NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *unused, NSRange glyphs, BOOL *stop) {
        NSRange chars = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
        [rows addObject:@[@(chars.location), @(chars.length), @(rect.origin.x), @(rect.origin.y),
            @(rect.size.height), @(used.origin.x), @(used.size.width), @(used.size.height)]];
    }];
    for (NSUInteger index = 0; index < layout.numberOfGlyphs; index++) {
        NSPoint location = [layout locationForGlyphAtIndex:index];
        NSRect line = [layout lineFragmentRectForGlyphAtIndex:index effectiveRange:NULL];
        [points addObject:@[@(line.origin.x+location.x), @(line.origin.y+location.y)]];
        [indexes addObject:@([layout characterIndexForGlyphAtIndex:index])];
        NSGlyphProperty property=[layout propertyForGlyphAtIndex:index];
        if(property & NSGlyphPropertyControlCharacter) [controls addObject:@[@(index),@(property)]];
        NSUInteger character=[layout characterIndexForGlyphAtIndex:index];
        if([storage attribute:NSAttachmentAttributeName atIndex:character effectiveRange:NULL]) {
            NSSize size=[layout attachmentSizeForGlyphAtIndex:index];
            [attachments addObject:@[@(character),@(size.width),@(size.height)]];
        }
        Check(isfinite(location.x) && isfinite(location.y), @"glyph positions stay finite");
    }
    Check([storage isEqualToAttributedString:before], @"layout retains all source characters and attributes");
    layout.delegate = nil;
    return @{@"rows":rows, @"points":points, @"indexes":indexes, @"controls":controls, @"attachments":attachments};
}
static BOOL Close(id a, id b) {
    if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
        if ([a count] != [b count]) return NO;
        for (NSUInteger i=0; i<[a count]; i++) if (!Close(a[i], b[i])) return NO;
        return YES;
    }
    return fabs([a doubleValue]-[b doubleValue]) < 0.01;
}
static void Case(NSString *fixture, CGFloat size, NSUInteger styleIndex) {
    NSString *plain = [fixture isEqual:@"attachment"] ? @"abcdefghij \uFFFC nextword tail" :
        [fixture isEqual:@"tab"] ? @"abcdefghij \tword tail" : @"abcdefghij nextword tail";
    NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:size];
    Check(font != nil, @"the fixture font exists");
    NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.lineBreakMode = NSLineBreakByCharWrapping;
    if (styleIndex == 1) {
        style.firstLineHeadIndent=8; style.headIndent=16; style.tailIndent=-5;
        style.paragraphSpacingBefore=3; style.paragraphSpacing=9; style.lineSpacing=4;
    } else if (styleIndex == 2) {
        style.alignment=NSTextAlignmentRight; style.lineHeightMultiple=1.3;
    }
    style.tabStops=@[]; style.defaultTabInterval=4*size;
    NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:plain
        attributes:@{NSFontAttributeName:font, NSParagraphStyleAttributeName:style, @"ProbeMarker":@"unchanged"}] autorelease];
    if ([fixture isEqual:@"attachment"]) {
        NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
        attachment.attachmentCell=[[[FixtureCell alloc] initTextCell:@""] autorelease];
        [text addAttribute:NSAttachmentAttributeName value:attachment range:[plain rangeOfString:@"\uFFFC"]];
    }
    CGFloat width=[@"abcdefghij" sizeWithAttributes:@{NSFontAttributeName:font}].width+10.25;
    NSDictionary *current=Snapshot(text,width,1), *baseline=Snapshot(text,width,2), *native=Snapshot(text,width,0);
    NSString *label=[NSString stringWithFormat:@"%@ %.0fpt paragraph %lu",fixture,size,(unsigned long)styleIndex];
    BOOL nativeRows=Close(current[@"rows"],native[@"rows"]), nativePoints=Close(current[@"points"],native[@"points"]);
    BOOL baselineRows=Close(current[@"rows"],baseline[@"rows"]);
    Check([current[@"indexes"] isEqual:baseline[@"indexes"]] && [current[@"indexes"] isEqual:native[@"indexes"]],
          [label stringByAppendingString:@": UTF-16 mappings agree across baseline, current, and native"]);
    Check([current[@"controls"] isEqual:baseline[@"controls"]],
          [label stringByAppendingString:@": native control glyph properties retain their baseline values"]);
    // Tab-adjacent spaces are intentionally literal. Compare their unchanged policy with baseline.
    if ([fixture isEqual:@"tab"]) {
        Check(baselineRows && Close(current[@"points"],baseline[@"points"]),
              [label stringByAppendingString:@": tab-adjacent geometry retains the baseline policy"]);
    } else if ([fixture isEqual:@"prose"]) {
        Check(nativeRows && nativePoints, [label stringByAppendingString:@": isolated separators match native paragraph geometry"]);
        if (!baselineRows) BaselineDifferences++;
    } else {
        // The app disables rich text and graphic imports. Keep this synthetic
        // attachment check about mapping and size, with geometry as observations.
        Check([current[@"attachments"] isEqual:baseline[@"attachments"]] &&
              [current[@"attachments"] isEqual:native[@"attachments"]],
              [label stringByAppendingString:@": attachment dimensions match baseline and native"]);
    }
    [Observations addObject:@{@"case":label, @"current":current, @"baseline":baseline, @"native":native,
        @"currentMatchesNativeRows":@(nativeRows), @"currentMatchesNativePoints":@(nativePoints), @"currentMatchesBaselineRows":@(baselineRows),
        @"baselineMatchesNativeRows":@(Close(baseline[@"rows"],native[@"rows"])),
        @"baselineMatchesNativePoints":@(Close(baseline[@"points"],native[@"points"]))}];
    Comparisons++;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if(argc!=2) return 2;
        Failures=[NSMutableArray array]; Observations=[NSMutableArray array];
        for(NSString *fixture in @[@"prose",@"attachment",@"tab"])
            for(NSNumber *size in @[@9,@27]) for(NSUInteger style=0;style<3;style++) Case(fixture,size.doubleValue,style);
        Check(BaselineDifferences>0,@"the baseline control detects separator layout differences");
        Check(NSApp==nil,@"the probe creates no NSApplication or GUI session");
        NSDictionary *report=@{@"checks":@(Checks),@"comparisons":@(Comparisons),@"baselineDifferences":@(BaselineDifferences),
                              @"failures":Failures,@"observations":Observations};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        printf("%lu checks; %lu paragraph/size/adjacency cases; %lu baseline differences; %lu failures\n",
            (unsigned long)Checks,(unsigned long)Comparisons,(unsigned long)BaselineDifferences,(unsigned long)Failures.count);
        for(NSString *failure in Failures) fprintf(stderr,"FAIL: %s\n",failure.UTF8String);
        return Failures.count?1:0;
    }
}
