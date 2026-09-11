#import <Cocoa/Cocoa.h>
static NSUInteger Checks;
static NSMutableSet *Fonts;
static void Check(BOOL pass,NSString *label){Checks++;if(!pass){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
static NSDictionary *InstallReviewedStyle(NSMutableDictionary *noteBodyAttributes) {
// EXTRACTED_STYLE_BLOCK
}
@interface ProductionDelegate:NSObject<NSLayoutManagerDelegate>
@end
@implementation ProductionDelegate
// EXTRACTED_GLYPH_METHOD
@end
@interface FontObserver:ProductionDelegate
@end
@implementation FontObserver
- (NSUInteger)layoutManager:(NSLayoutManager*)m shouldGenerateGlyphs:(const CGGlyph*)g properties:(const NSGlyphProperty*)p characterIndexes:(const NSUInteger*)ix font:(NSFont*)font forGlyphRange:(NSRange)range {
    [Fonts addObject:font.fontName];
    return [super layoutManager:m shouldGenerateGlyphs:g properties:p characterIndexes:ix font:font forGlyphRange:range];
}
@end
static BOOL Boundary(NSString*s,NSUInteger i){return i==s.length||(i<s.length&&[s rangeOfComposedCharacterSequenceAtIndex:i].location==i);}
static NSDictionary *Measure(NSString *text,NSString*fixture,NSFont*font,CGFloat width,NSUInteger mode,id delegate){
    NSMutableDictionary *attrs=[NSMutableDictionary dictionaryWithDictionary:@{NSFontAttributeName:font,NSForegroundColorAttributeName:[NSColor textColor],NSLigatureAttributeName:@2,@"NVReviewMarker":@"keep"}];
    if(mode)InstallReviewedStyle(attrs);else[attrs setObject:[NSParagraphStyle defaultParagraphStyle]forKey:NSParagraphStyleAttributeName];
    if([fixture isEqual:@"bidi"])[attrs setObject:@[@(NSWritingDirectionRightToLeft)]forKey:NSWritingDirectionAttributeName];
    NSTextStorage *storage=[[[NSTextStorage alloc]initWithString:text attributes:attrs]autorelease];
    NSLayoutManager *layout=[[[NSLayoutManager alloc]init]autorelease];NSTextContainer *container=[[[NSTextContainer alloc]initWithSize:NSMakeSize(width,100000)]autorelease];
    [storage addLayoutManager:layout];[layout addTextContainer:container];if(mode==2)layout.delegate=delegate;
    NSTextView *view=[[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,width,1000)textContainer:container]autorelease];view.richText=NO;container.widthTracksTextView=NO;
    NSRange selection=NSMakeRange(text.length,0);view.selectedRange=selection;
    [layout ensureGlyphsForCharacterRange:NSMakeRange(0,text.length)];NSUInteger n=layout.numberOfGlyphs;
    NSMutableData*g=[NSMutableData dataWithLength:n*sizeof(CGGlyph)],*p=[NSMutableData dataWithLength:n*sizeof(NSGlyphProperty)],*ix=[NSMutableData dataWithLength:n*sizeof(NSUInteger)],*b=[NSMutableData dataWithLength:n];
    Check([layout getGlyphsInRange:NSMakeRange(0,n)glyphs:g.mutableBytes properties:p.mutableBytes characterIndexes:ix.mutableBytes bidiLevels:b.mutableBytes]==n,@"complete native glyph snapshot");
    [layout ensureLayoutForTextContainer:container];NSMutableArray *lines=[NSMutableArray array],*splitOffsets=[NSMutableArray array],*interiorHits=[NSMutableArray array];
    __block NSUInteger hits=0;
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,n)usingBlock:^(NSRect rect,NSRect used,NSTextContainer*c,NSRange range,BOOL*stop){
        NSRange chars=[layout characterRangeForGlyphRange:range actualGlyphRange:NULL];
        [lines addObject:@[@(chars.location),@(chars.length),@(used.origin.x),@(used.origin.y),@(used.size.width),@(used.size.height)]];
        if(!Boundary(text,chars.location))[splitOffsets addObject:@(chars.location)];
        // Use the native view's public insertion hit test across each rendered line.
        for(CGFloat x=0;x<=width;x+=4){
            NSPoint point=NSMakePoint(x+view.textContainerOrigin.x,NSMidY(rect)+view.textContainerOrigin.y);
            NSUInteger index=[view characterIndexForInsertionAtPoint:point];hits++;
            Check(index<=text.length,@"native hit test returns an in-bounds source position");
            if(!Boundary(text,index)&&![interiorHits containsObject:@(index)])[interiorHits addObject:@(index)];
        }
    }];
    Check([storage.string isEqual:text],@"layout preserves complete Unicode source");
    Check(NSEqualRanges(selection,view.selectedRange),@"layout and hit testing preserve original selection");
    NSMutableArray *sourceFonts=[NSMutableArray array];
    for(NSUInteger i=0;i<text.length;i++){
        Check([[storage attribute:@"NVReviewMarker" atIndex:i effectiveRange:NULL]isEqual:@"keep"],@"source metadata survives native layout");
        NSFont *actualFont=[storage attribute:NSFontAttributeName atIndex:i effectiveRange:NULL];
        Check(actualFont!=nil,@"native font attribute remains present");
        [sourceFonts addObject:@[actualFont.fontName,@(actualFont.pointSize)]];
    }
    // Set only grapheme-boundary selections and require the native view to preserve them.
    for(NSUInteger i=0;i<=text.length;i++)if(Boundary(text,i)){
        view.selectedRange=NSMakeRange(i,0);Check(NSEqualRanges(view.selectedRange,NSMakeRange(i,0)),@"native selection preserves each grapheme boundary");
    }
    layout.delegate=nil;
    return @{@"sourceFonts":sourceFonts,@"glyphs":g,@"props":p,@"indexes":ix,@"bidi":b,@"lineRecords":lines,@"splitOffsets":splitOffsets,@"interiorHitOffsets":interiorHits,@"hitCount":@(hits),@"glyphCount":@(n)};
}
int main(int argc,const char**argv){@autoreleasepool{
    Fonts=[NSMutableSet new];FontObserver *delegate=[FontObserver new];NSMutableArray*rows=[NSMutableArray array];
    NSArray*names=@[@"combining",@"emoji",@"indic",@"bidi",@"protected",@"ligatures"];
    NSArray*texts=@[@"A e\u0301 a\u0308 o\u0302 B    ",@"A 👩🏽‍💻 👨‍👩‍👧‍👦 🇻🇳 1\ufe0f\u20e3 B   ",@"A क्‍षि क्षि नमस्ते B  ",@"אבג مرحبا A12 שלום 👩‍💻   ",@"A\tB\u00a0C\u2002D\u2003E\tF",@"office affine fi fl ffi ffl   "];
    NSUInteger candidateSplits=0,candidateInteriorHits=0,totalHits=0,protectedChecks=0;
    for(NSString*fontName in @[@"Helvetica",@"Times-Roman"])for(NSNumber*w in @[@18,@35,@62,@120])for(NSUInteger k=0;k<names.count;k++){@autoreleasepool{
        NSString*text=texts[k];NSFont*font=[NSFont fontWithName:fontName size:18];Check(font!=nil,@"requested native font exists");
        NSDictionary*word=Measure(text,names[k],font,w.doubleValue,0,nil);
        NSDictionary*chars=Measure(text,names[k],font,w.doubleValue,1,nil);
        NSDictionary*current=Measure(text,names[k],font,w.doubleValue,2,delegate);
        for(NSString*key in @[@"glyphs",@"indexes",@"bidi",@"sourceFonts"]){Check([word[key]isEqual:chars[key]],@"native character-wrap policy preserves glyph/mapping/bidi data");Check([chars[key]isEqual:current[key]],@"production glyph adjustment preserves glyph/mapping/bidi data");}
        const NSGlyphProperty*bp=[chars[@"props"]bytes],*cp=[current[@"props"]bytes];const NSUInteger*ix=[chars[@"indexes"]bytes];NSUInteger changed=0;
        for(NSUInteger g=0;g<[current[@"glyphCount"]unsignedIntegerValue];g++)if(bp[g]!=cp[g]){changed++;Check((bp[g]^cp[g])==NSGlyphPropertyElastic&&!(cp[g]&NSGlyphPropertyElastic)&&!(bp[g]&NSGlyphPropertyControlCharacter)&&ix[g]<text.length&&[text characterAtIndex:ix[g]]==' ',@"only eligible U0020 Elastic flags differ");}
        if(k==4){protectedChecks++;Check(changed==0&&[chars[@"lineRecords"]isEqual:current[@"lineRecords"]],@"protected whitespace glyphs and geometry match native character wrapping");}
        for(NSNumber *offset in current[@"interiorHitOffsets"])Check([chars[@"interiorHitOffsets"]containsObject:offset]||[word[@"interiorHitOffsets"]containsObject:offset],@"current interior caret offsets also occur in native controls");
        candidateSplits+=[current[@"splitOffsets"]count];candidateInteriorHits+=[current[@"interiorHitOffsets"]count];totalHits+=[current[@"hitCount"]unsignedIntegerValue];
        [rows addObject:@{@"font":fontName,@"width":w,@"fixture":names[k],@"source":text,@"wordLineCount":@([word[@"lineRecords"]count]),@"charLineCount":@([chars[@"lineRecords"]count]),@"currentLineCount":@([current[@"lineRecords"]count]),@"wordSplitOffsets":word[@"splitOffsets"],@"charSplitOffsets":chars[@"splitOffsets"],@"currentSplitOffsets":current[@"splitOffsets"],@"wordInteriorHits":word[@"interiorHitOffsets"],@"charInteriorHits":chars[@"interiorHitOffsets"],@"currentInteriorHits":current[@"interiorHitOffsets"],@"currentHitCount":current[@"hitCount"],@"changedSpaceGlyphs":@(changed)}];
    }}
    Check(candidateSplits==0,@"current line boundaries never split a composed-character sequence");
    NSDictionary*report=@{@"checks":@(Checks),@"cases":rows,@"candidateSplitCount":@(candidateSplits),@"candidateInteriorHitRecords":@(candidateInteriorHits),@"candidateHitCount":@(totalHits),@"protectedComparisons":@(protectedChecks),@"nativeFonts":[[Fonts allObjects]sortedArrayUsingSelector:@selector(compare:)],@"passed":@YES};
    NSData*data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];if(![data writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES])return 1;
    fprintf(stderr,"PASS %lu checks; %lu matrices; current cluster splits %lu; interior hit records %lu; native hit samples %lu\n",(unsigned long)Checks,(unsigned long)rows.count,(unsigned long)candidateSplits,(unsigned long)candidateInteriorHits,(unsigned long)totalHits);[delegate release];[Fonts release];
}return 0;}
