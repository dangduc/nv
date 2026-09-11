#import <Cocoa/Cocoa.h>
static NSUInteger Checks,Phases,HitSamples;
static NSMutableDictionary *OldBatches,*NewBatches;
static NSMutableSet *NativeFonts;
static void Check(BOOL p,NSString*s){Checks++;if(!p){fprintf(stderr,"FAIL: %s\n",s.UTF8String);exit(1);}}
static NSDictionary*InstallStyle(NSMutableDictionary*noteBodyAttributes){
// EXTRACTED_STYLE
}
@interface OldProduction:NSObject<NSLayoutManagerDelegate>
@end
@implementation OldProduction
// EXTRACTED_OLD
@end
@interface NewProduction:NSObject<NSLayoutManagerDelegate>
@end
@implementation NewProduction
// EXTRACTED_NEW
@end
static void Record(NSMutableDictionary*d,NSUInteger n,NSFont*f){NSString*k=[@(n)stringValue];d[k]=@([d[k]unsignedIntegerValue]+1);[NativeFonts addObject:f.fontName];}
@interface OldObserved:OldProduction
@end
@implementation OldObserved
- (NSUInteger)layoutManager:(NSLayoutManager*)m shouldGenerateGlyphs:(const CGGlyph*)g properties:(const NSGlyphProperty*)p characterIndexes:(const NSUInteger*)ix font:(NSFont*)f forGlyphRange:(NSRange)r{Record(OldBatches,r.length,f);return[super layoutManager:m shouldGenerateGlyphs:g properties:p characterIndexes:ix font:f forGlyphRange:r];}
@end
@interface NewObserved:NewProduction
@end
@implementation NewObserved
- (NSUInteger)layoutManager:(NSLayoutManager*)m shouldGenerateGlyphs:(const CGGlyph*)g properties:(const NSGlyphProperty*)p characterIndexes:(const NSUInteger*)ix font:(NSFont*)f forGlyphRange:(NSRange)r{Record(NewBatches,r.length,f);return[super layoutManager:m shouldGenerateGlyphs:g properties:p characterIndexes:ix font:f forGlyphRange:r];}
@end
@interface PairState:NSObject{
@public NSTextStorage*storage;NSMutableArray*views;NSMutableDictionary*attributes;
}
- (id)initWithDelegate:(id)delegate;
@end
@implementation PairState
- (id)initWithDelegate:(id)delegate{if((self=[super init])){
    attributes=[[NSMutableDictionary alloc]initWithDictionary:@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18],NSForegroundColorAttributeName:[NSColor textColor],NSLigatureAttributeName:@2,@"NVReviewMarker":@"dynamic"}];InstallStyle(attributes);
    storage=[[NSTextStorage alloc]initWithString:[@"" stringByPaddingToLength:63 withString:@" " startingAtIndex:0]attributes:attributes];views=[NSMutableArray new];
    for(NSNumber*w in @[@62,@180]){NSLayoutManager*m=[[[NSLayoutManager alloc]init]autorelease];NSTextContainer*c=[[[NSTextContainer alloc]initWithSize:NSMakeSize(w.doubleValue,100000)]autorelease];[storage addLayoutManager:m];[m addTextContainer:c];m.delegate=delegate;
        NSTextView*v=[[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,w.doubleValue,1000)textContainer:c]autorelease];v.richText=NO;v.allowsUndo=NO;c.widthTracksTextView=NO;v.typingAttributes=attributes;v.selectedRange=NSMakeRange(storage.length,0);[views addObject:v];}
}return self;}
- (void)dealloc{for(NSTextView*v in views)v.layoutManager.delegate=nil;[views release];[storage release];[attributes release];[super dealloc];}
@end
static NSDictionary*Snapshot(PairState*state,NSUInteger viewIndex){
    NSTextView*v=state->views[viewIndex];NSLayoutManager*m=v.layoutManager;
    [m ensureGlyphsForCharacterRange:NSMakeRange(0,state->storage.length)];NSUInteger n=m.numberOfGlyphs;
    NSMutableData*g=[NSMutableData dataWithLength:n*sizeof(CGGlyph)],*p=[NSMutableData dataWithLength:n*sizeof(NSGlyphProperty)],*ix=[NSMutableData dataWithLength:n*sizeof(NSUInteger)],*b=[NSMutableData dataWithLength:n];
    Check([m getGlyphsInRange:NSMakeRange(0,n)glyphs:g.mutableBytes properties:p.mutableBytes characterIndexes:ix.mutableBytes bidiLevels:b.mutableBytes]==n,@"complete regenerated glyph snapshot");
    [m ensureLayoutForTextContainer:v.textContainer];NSMutableArray*lines=[NSMutableArray array],*positions=[NSMutableArray array],*hits=[NSMutableArray array],*attrs=[NSMutableArray array];
    [m enumerateLineFragmentsForGlyphRange:NSMakeRange(0,n)usingBlock:^(NSRect r,NSRect used,NSTextContainer*c,NSRange range,BOOL*stop){
        NSRange chars=[m characterRangeForGlyphRange:range actualGlyphRange:NULL];
        Check(chars.location==state->storage.length||[state->storage.string rangeOfComposedCharacterSequenceAtIndex:chars.location].location==chars.location,@"dynamic line boundary preserves composed sequence");
        [lines addObject:@[@(range.location),@(range.length),@(r.origin.x),@(r.origin.y),@(used.origin.x),@(used.origin.y),@(used.size.width),@(used.size.height)]];
        for(CGFloat x=0;x<=v.textContainer.size.width;x+=8){NSUInteger index=[v characterIndexForInsertionAtPoint:NSMakePoint(x+v.textContainerOrigin.x,NSMidY(r)+v.textContainerOrigin.y)];Check(index<=state->storage.length,@"dynamic insertion hit stays within source");[hits addObject:@(index)];HitSamples++;}
    }];
    for(NSUInteger i=0;i<n;i++){NSPoint q=[m locationForGlyphAtIndex:i];[positions addObject:@[@(q.x),@(q.y)]];}
    for(NSUInteger i=0;i<state->storage.length;i++){NSDictionary*a=[state->storage attributesAtIndex:i effectiveRange:NULL];Check([a[@"NVReviewMarker"]isEqual:@"dynamic"],@"native edits preserve incoming metadata marker");Check([a[NSParagraphStyleAttributeName]lineBreakMode]==NSLineBreakByCharWrapping,@"native edits retain shared wrapping policy");[attrs addObject:a];}
    Check(NSMaxRange(v.selectedRange)<=state->storage.length,@"view selection remains within edited source");
    return@{@"glyphs":g,@"properties":p,@"indexes":ix,@"bidi":b,@"lines":lines,@"positions":positions,@"hits":hits,@"attributes":attrs,@"selection":NSStringFromRange(v.selectedRange)};
}
static void CompareGeometry(NSArray*a,NSArray*b){Check(a.count==b.count,@"geometry array sizes match");for(NSUInteger i=0;i<a.count;i++){NSArray*x=a[i],*y=b[i];Check(x.count==y.count,@"geometry tuple sizes match");for(NSUInteger j=0;j<x.count;j++)Check(fabs([x[j]doubleValue]-[y[j]doubleValue])<0.000001,@"old/new native geometry remains equal");}}
static void Capture(PairState*old,PairState*current,NSString*expected,NSString*phase,NSMutableArray*rows){
    Check([old->storage.string isEqual:expected]&&[current->storage.string isEqual:expected],@"native edit produces exact expected source in both contexts");
    NSMutableArray*viewRows=[NSMutableArray array];for(NSUInteger v=0;v<2;v++){NSDictionary*a=Snapshot(old,v),*b=Snapshot(current,v);
        for(NSString*k in @[@"glyphs",@"properties",@"indexes",@"bidi",@"hits",@"attributes",@"selection"])Check([a[k]isEqual:b[k]],[@"old/new equivalence: "stringByAppendingString:k]);
        CompareGeometry(a[@"lines"],b[@"lines"]);CompareGeometry(a[@"positions"],b[@"positions"]);
        [viewRows addObject:@{@"width":@([(NSTextView*)current->views[v]textContainer].size.width),@"lines":@([b[@"lines"]count]),@"selection":b[@"selection"],@"hitSamples":@([b[@"hits"]count])}];}
    [rows addObject:@{@"phase":phase,@"length":@(expected.length),@"views":viewRows}];Phases++;
}
static void Replace(PairState*s,NSUInteger view,NSString*text,NSRange range){NSTextView*v=s->views[view];v.typingAttributes=s->attributes;[v insertText:text replacementRange:range];}
static void FontChange(PairState*s,NSString*name,CGFloat size){s->attributes[NSFontAttributeName]=[NSFont fontWithName:name size:size];[s->storage addAttributes:InstallStyle(s->attributes)range:NSMakeRange(0,s->storage.length)];for(NSTextView*v in s->views)v.typingAttributes=s->attributes;}
int main(int argc,const char**argv){@autoreleasepool{
    OldBatches=[NSMutableDictionary new];NewBatches=[NSMutableDictionary new];NativeFonts=[NSMutableSet new];OldObserved*od=[OldObserved new];NewObserved*nd=[NewObserved new];PairState*old=[[PairState alloc]initWithDelegate:od],*current=[[PairState alloc]initWithDelegate:nd];NSMutableArray*rows=[NSMutableArray array];NSMutableString*expected=[old->storage.string mutableCopy];
    Check([(NSTextView*)old->views[0]textStorage]==[(NSTextView*)old->views[1]textStorage]&&[(NSTextView*)current->views[0]textStorage]==[(NSTextView*)current->views[1]textStorage],@"each pair has two native views on one shared storage");
    Capture(old,current,expected,@"initial-63",rows);
    for(NSUInteger cycle=0;cycle<3;cycle++){
        for(NSUInteger add=0;add<2;add++){NSRange range=NSMakeRange(expected.length,0);Replace(old,add,@" ",range);Replace(current,add,@" ",range);[expected appendString:@" "];Capture(old,current,expected,[NSString stringWithFormat:@"cycle%lu-add-%lu",cycle,expected.length],rows);}
        NSString*large=[@"" stringByPaddingToLength:192 withString:@" " startingAtIndex:0];NSRange end=NSMakeRange(expected.length,0);Replace(old,0,large,end);Replace(current,0,large,end);[expected appendString:large];Capture(old,current,expected,@"grow-to-257",rows);
        NSRange remove=NSMakeRange(63,expected.length-63);for(PairState*s in @[old,current]){NSTextView*v=s->views[1];v.selectedRange=remove;[v deleteBackward:nil];}[expected deleteCharactersInRange:remove];Capture(old,current,expected,@"native-delete-to-63",rows);
        NSString*prefix=@"e\u0301 👩🏽‍💻 עברית क्षि\t\u00a0 ";Replace(old,0,prefix,NSMakeRange(0,0));Replace(current,0,prefix,NSMakeRange(0,0));[expected insertString:prefix atIndex:0];Capture(old,current,expected,@"insert-unicode-prefix",rows);
        NSRange emoji=[expected rangeOfString:@"👩🏽‍💻"];for(PairState*s in @[old,current]){NSTextView*v=s->views[1];v.selectedRange=emoji;[v deleteBackward:nil];}[expected deleteCharactersInRange:emoji];Capture(old,current,expected,@"native-delete-emoji-cluster",rows);
        NSString*font=@[@"Helvetica",@"Times-Roman",@"Menlo-Regular"][cycle];CGFloat size=14+cycle*4;FontChange(old,font,size);FontChange(current,font,size);Capture(old,current,expected,@"font-and-fallback-regeneration",rows);
        for(PairState*s in @[old,current]){[(NSTextView*)s->views[0]textContainer].size=NSMakeSize(30+cycle*17,100000);[(NSTextView*)s->views[1]textContainer].size=NSMakeSize(240-cycle*35,100000);}Capture(old,current,expected,@"two-width-regeneration",rows);
        NSString*small=[@"" stringByPaddingToLength:63 withString:@" " startingAtIndex:0];NSRange whole=NSMakeRange(0,expected.length);Replace(old,0,small,whole);Replace(current,0,small,whole);[expected setString:small];Capture(old,current,expected,@"replace-large-unicode-with-small",rows);
    }
    for(NSString*length in @[@"63",@"64",@"65"])Check([NewBatches[length]unsignedIntegerValue]>0,@"native callbacks cross the exact stack boundary sizes");BOOL large=NO;for(NSString*key in NewBatches)if(key.integerValue>64)large=YES;Check(large,@"native callback sequence exercises heap batches");Check(NativeFonts.count>3,@"native font fallback participates in dynamic regeneration");
    NSDictionary*r=@{@"checks":@(Checks),@"phases":rows,@"phaseCount":@(Phases),@"oldBatchLengths":OldBatches,@"newBatchLengths":NewBatches,@"nativeFonts":[[NativeFonts allObjects]sortedArrayUsingSelector:@selector(compare:)],@"hitSamplesAcrossAllVariants":@(HitSamples),@"passed":@YES};NSData*data=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:NULL];if(![data writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES])return 1;
    fprintf(stderr,"PASS %lu checks; %lu dynamic phases; %lu native hit samples; %lu font names\n",(unsigned long)Checks,(unsigned long)Phases,(unsigned long)HitSamples,(unsigned long)NativeFonts.count);[expected release];[old release];[current release];[od release];[nd release];[OldBatches release];[NewBatches release];[NativeFonts release];
}return 0;}
