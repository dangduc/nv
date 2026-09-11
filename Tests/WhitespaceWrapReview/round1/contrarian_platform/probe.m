#import <Cocoa/Cocoa.h>
static NSUInteger Checks;
static NSMutableSet *NativeFonts;
static void Check(BOOL value, NSString *message) {
    Checks++;
    if (!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
@interface ProductionDelegate : NSObject <NSLayoutManagerDelegate>
@end
@implementation ProductionDelegate
// EXTRACTED_PRODUCTION_METHOD
@end
@interface ObservedDelegate : ProductionDelegate
@end
@implementation ObservedDelegate
- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:(const CGGlyph *)glyphs properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes font:(NSFont *)font forGlyphRange:(NSRange)range {
    [NativeFonts addObject:font.fontName];
    return [super layoutManager:manager shouldGenerateGlyphs:glyphs properties:properties characterIndexes:indexes font:font forGlyphRange:range];
}
@end
static NSTextView *MakeView(NSString *text, NSFont *font, NSTextAlignment alignment, NSWritingDirection direction, id delegate) {
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    style.alignment=alignment; style.baseWritingDirection=direction; style.lineBreakMode=NSLineBreakByWordWrapping;
    NSTextStorage *storage=[[[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName:font,NSParagraphStyleAttributeName:style}] autorelease];
    NSLayoutManager *manager=[[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container=[[[NSTextContainer alloc] initWithSize:NSMakeSize(220,100000)] autorelease];
    [storage addLayoutManager:manager]; [manager addTextContainer:container]; manager.delegate=delegate;
    NSTextView *view=[[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,220,400) textContainer:container] autorelease];
    view.richText=NO; view.importsGraphics=NO;
    view.horizontallyResizable=NO; view.verticallyResizable=YES; container.widthTracksTextView=NO;
    view.selectedRange=NSMakeRange(MIN((NSUInteger)3,text.length),MIN((NSUInteger)4,text.length-MIN((NSUInteger)3,text.length)));
    return view;
}
static NSDictionary *Snapshot(NSTextView *view) {
    NSLayoutManager *manager=view.layoutManager;
    [manager ensureGlyphsForCharacterRange:NSMakeRange(0,view.string.length)];
    NSUInteger count=manager.numberOfGlyphs;
    NSMutableData *glyphs=[NSMutableData dataWithLength:count*sizeof(CGGlyph)];
    NSMutableData *props=[NSMutableData dataWithLength:count*sizeof(NSGlyphProperty)];
    NSMutableData *indexes=[NSMutableData dataWithLength:count*sizeof(NSUInteger)];
    NSMutableData *bidi=[NSMutableData dataWithLength:count];
    Check([manager getGlyphsInRange:NSMakeRange(0,count) glyphs:glyphs.mutableBytes properties:props.mutableBytes characterIndexes:indexes.mutableBytes bidiLevels:bidi.mutableBytes]==count,@"complete glyph snapshot");
    [manager ensureLayoutForTextContainer:view.textContainer];
    NSMutableArray *lines=[NSMutableArray array],*positions=[NSMutableArray array];
    [manager enumerateLineFragmentsForGlyphRange:NSMakeRange(0,count) usingBlock:^(NSRect rect,NSRect used,NSTextContainer *container,NSRange range,BOOL *stop) {
        Check(isfinite(used.origin.x)&&isfinite(used.origin.y)&&isfinite(used.size.width)&&isfinite(used.size.height),@"finite line geometry");
        [lines addObject:@[@(range.location),@(range.length),@(used.origin.x),@(used.origin.y),@(used.size.width),@(used.size.height)]];
    }];
    for (NSUInteger k=0;k<count;k++) {
        NSPoint point=[manager locationForGlyphAtIndex:k];
        Check(isfinite(point.x)&&isfinite(point.y),@"finite glyph position");
        [positions addObject:@[@(point.x),@(point.y)]];
    }
    return @{ @"glyphs":glyphs,@"properties":props,@"indexes":indexes,@"bidi":bidi,@"lines":lines,@"positions":positions,@"count":@(count),@"selection":NSStringFromRange(view.selectedRange),@"source":[[view.string copy] autorelease] };
}
static NSDictionary *Geometry(NSDictionary *a, NSDictionary *b) {
    BOOL sameRanges=[a[@"lines"] count]==[b[@"lines"] count];
    double delta=0;
    if (sameRanges) for (NSUInteger i=0;i<[a[@"lines"] count];i++) {
        NSArray *x=a[@"lines"][i],*y=b[@"lines"][i];
        if (![x[0] isEqual:y[0]] || ![x[1] isEqual:y[1]]) sameRanges=NO;
        for (NSUInteger j=2;j<6;j++) delta=MAX(delta,fabs([x[j] doubleValue]-[y[j] doubleValue]));
    }
    for (NSUInteger i=0;i<[a[@"positions"] count];i++) {
        NSArray *x=a[@"positions"][i],*y=b[@"positions"][i];
        for (NSUInteger j=0;j<2;j++) delta=MAX(delta,fabs([x[j] doubleValue]-[y[j] doubleValue]));
    }
    return @{@"sameLineRanges":@(sameRanges),@"maxCoordinateDelta":@(delta),@"sameGeometry":@(sameRanges&&delta<0.000001)};
}
static NSUInteger Compare(NSString *source,NSDictionary *base,NSDictionary *fixed,BOOL protected) {
    Check([base[@"source"] isEqual:source]&&[fixed[@"source"] isEqual:source],@"source preserved during layout");
    Check([base[@"selection"] isEqual:fixed[@"selection"]],@"selection identical across delegates");
    Check([base[@"glyphs"] isEqual:fixed[@"glyphs"]],@"glyph IDs preserved across delegates");
    Check([base[@"indexes"] isEqual:fixed[@"indexes"]],@"UTF16 mapping preserved across delegates");
    Check([base[@"bidi"] isEqual:fixed[@"bidi"]],@"bidi levels preserved across delegates");
    NSUInteger count=[base[@"count"] unsignedIntegerValue],changed=0;
    const NSGlyphProperty *bp=[base[@"properties"] bytes],*fp=[fixed[@"properties"] bytes];
    const NSUInteger *ix=[base[@"indexes"] bytes];
    for (NSUInteger k=0;k<count;k++) if (bp[k]!=fp[k]) {
        changed++;
        Check((bp[k]^fp[k])==NSGlyphPropertyElastic&&!(fp[k]&NSGlyphPropertyElastic),@"only Elastic can change");
        Check(!(bp[k]&NSGlyphPropertyControlCharacter)&&ix[k]<source.length&&[source characterAtIndex:ix[k]]==' ',@"only non-control ASCII space changes");
    }
    if (protected) {
        Check(changed==0,@"protected whitespace has no property changes");
        Check([base[@"lines"] isEqual:fixed[@"lines"]]&&[base[@"positions"] isEqual:fixed[@"positions"]],@"tabs and nonbreaking spaces retain exact native geometry");
    }
    return changed;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        NativeFonts=[NSMutableSet new]; ObservedDelegate *delegate=[ObservedDelegate new];
        NSArray *configs=@[
            @[@"Menlo-Regular",@(NSTextAlignmentLeft),@(NSWritingDirectionLeftToRight),@"mono-left-LTR"],
            @[@"Helvetica",@(NSTextAlignmentLeft),@(NSWritingDirectionLeftToRight),@"proportional-left-LTR"],
            @[@"Times-Roman",@(NSTextAlignmentRight),@(NSWritingDirectionLeftToRight),@"serif-right-LTR"],
            @[@"Helvetica",@(NSTextAlignmentCenter),@(NSWritingDirectionLeftToRight),@"proportional-center-LTR"],
            @[@"Times-Roman",@(NSTextAlignmentJustified),@(NSWritingDirectionLeftToRight),@"serif-justified-LTR"],
            @[@"Helvetica",@(NSTextAlignmentRight),@(NSWritingDirectionRightToLeft),@"proportional-right-RTL"]];
        NSArray *names=@[@"prose",@"tail",@"protected",@"fallback"];
        NSArray *fixtures=@[@"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon omega",[@"alpha " stringByAppendingString:[@"" stringByPaddingToLength:140 withString:@" " startingAtIndex:0]],@"alpha\u00a0beta\tग\u2002中\t👩‍💻\u00a0\u00a0\u2003",@"alpha مرحبا שלום 👩🏽‍💻 中文 क् e\u0301 beta     "];
        NSMutableArray *rows=[NSMutableArray array];
        for (NSArray *config in configs) for (NSUInteger k=0;k<fixtures.count;k++) {
            @autoreleasepool {
                NSString *text=fixtures[k]; NSFont *font=[NSFont fontWithName:config[0] size:14]; Check(font!=nil,@"configured font exists");
                NSTextView *base=MakeView(text,font,[config[1] integerValue],[config[2] integerValue],nil);
                NSTextView *fixed=MakeView(text,font,[config[1] integerValue],[config[2] integerValue],delegate);
                NSRange selection=fixed.selectedRange;
                NSDictionary *a=Snapshot(base),*b=Snapshot(fixed);
                NSUInteger changed=Compare(text,a,b,k==2);
                Check(NSEqualRanges(selection,fixed.selectedRange),@"layout preserves original selection");
                NSDictionary *geometry=Geometry(a,b);
                if (k==1) Check([b[@"lines"] count]>[a[@"lines"] count],@"ordinary trailing spaces occupy additional visual lines");
                NSString *newFontName=[config[0] isEqual:@"Menlo-Regular"]?@"Times-Roman":@"Menlo-Regular";
                NSFont *newFont=[NSFont fontWithName:newFontName size:20];
                NSDictionary *originalParagraphs=[fixed.textStorage attributesAtIndex:0 effectiveRange:NULL];
                [base.textStorage addAttribute:NSFontAttributeName value:newFont range:NSMakeRange(0,text.length)];
                [fixed.textStorage addAttribute:NSFontAttributeName value:newFont range:NSMakeRange(0,text.length)];
                NSDictionary *a2=Snapshot(base),*b2=Snapshot(fixed);
                NSUInteger afterChanged=Compare(text,a2,b2,k==2);
                Check(NSEqualRanges(selection,fixed.selectedRange),@"font-only edit preserves original selection");
                Check([[fixed.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] isEqual:originalParagraphs[NSParagraphStyleAttributeName]],@"font-only edit preserves paragraph attributes");
                if (k==1) Check([b2[@"lines"] count]>[a2[@"lines"] count],@"spaces continue wrapping after font-only change");
                if (k!=2) Check(changed>0&&afterChanged>0,@"ordinary spaces receive adjusted flags before and after font-only change");
                [rows addObject:@{@"configuration":config[3],@"fixture":names[k],@"font":config[0],@"changedFont":newFontName,@"baseLineCount":@([a[@"lines"] count]),@"fixedLineCount":@([b[@"lines"] count]),@"sameGeometry":geometry[@"sameGeometry"],@"geometry":geometry,@"afterFontGeometry":Geometry(a2,b2),@"baseLines":a[@"lines"],@"fixedLines":b[@"lines"],@"changedSpaceGlyphs":@(changed),@"afterFontBaseLineCount":@([a2[@"lines"] count]),@"afterFontFixedLineCount":@([b2[@"lines"] count]),@"afterFontChangedSpaceGlyphs":@(afterChanged)}];
                base.layoutManager.delegate=nil; fixed.layoutManager.delegate=nil;
            }
        }
        Check(NativeFonts.count>3,@"native callbacks include substituted fallback fonts");
        NSDictionary *report=@{@"checks":@(Checks),@"cases":rows,@"nativeFontNames":[[NativeFonts allObjects] sortedArrayUsingSelector:@selector(compare:)],@"passed":@YES};
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        if (![data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES]) { fprintf(stderr,"FAIL: result file save\n"); return 1; }
        fprintf(stderr,"PASS: %lu checks, %lu native cases before and after font-only change, %lu native fonts\n",(unsigned long)Checks,(unsigned long)rows.count,(unsigned long)NativeFonts.count);
        [delegate release]; [NativeFonts release];
    }
    return 0;
}
