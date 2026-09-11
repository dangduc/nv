#import <Cocoa/Cocoa.h>
#include <stdint.h>

static NSUInteger Checks, SyntheticCases, HeapAttempts, HeapFrees, AllocationBytes;
static BOOL FailAllocation;
static void Check(BOOL ok,NSString *message) { Checks++; if(!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1); } }
static void *ReviewMalloc(size_t size) { HeapAttempts++;AllocationBytes=size;return FailAllocation?NULL:malloc(size); }
static void ReviewFree(void *pointer) { HeapFrees++;free(pointer); }
#include "production-hooks.inc"

@interface Sink:NSObject {
@public NSTextStorage *storage; NSUInteger reads,writes; NSData *glyphs,*properties,*indexes; NSFont *font; NSRange range;
}
- (id)initWithSource:(NSString *)source;
- (NSTextStorage *)textStorage;
- (void)setGlyphs:(const CGGlyph *)g properties:(const NSGlyphProperty *)p characterIndexes:(const NSUInteger *)i font:(NSFont *)f forGlyphRange:(NSRange)r;
@end
@implementation Sink
- (id)initWithSource:(NSString *)source { if((self=[super init]))storage=[[NSTextStorage alloc]initWithString:source attributes:@{@"Marker":@"unchanged"}];return self; }
- (NSTextStorage *)textStorage { reads++;return storage; }
- (void)setGlyphs:(const CGGlyph *)g properties:(const NSGlyphProperty *)p characterIndexes:(const NSUInteger *)i font:(NSFont *)f forGlyphRange:(NSRange)r {
    writes++;glyphs=[[NSData alloc]initWithBytes:g length:r.length*sizeof(*g)];properties=[[NSData alloc]initWithBytes:p length:r.length*sizeof(*p)];indexes=[[NSData alloc]initWithBytes:i length:r.length*sizeof(*i)];font=f;range=r;
}
- (void)dealloc { [glyphs release];[properties release];[indexes release];[storage release];[super dealloc]; }
@end
static BOOL HasIndex(NSArray *indexes,NSUInteger index) { return [indexes containsObject:@(index)]; }
static void Synthetic(NSString *source,NSArray *literal,NSUInteger length,NSUInteger rotation,BOOL fail) {
    @autoreleasepool {
        Sink *sink=[[[Sink alloc]initWithSource:source]autorelease]; CurrentDelegate *delegate=[[[CurrentDelegate alloc]init]autorelease];
        NSFont *font=[NSFont fontWithName:@"Menlo-Regular" size:18];
        CGGlyph *glyphs=calloc(MAX(length,1),sizeof(CGGlyph));NSGlyphProperty *properties=calloc(MAX(length,1),sizeof(NSGlyphProperty)),*expected=calloc(MAX(length,1),sizeof(NSGlyphProperty));NSUInteger *indexes=calloc(MAX(length,1),sizeof(NSUInteger));
        Check(glyphs&&properties&&expected&&indexes,@"bounded fixture buffers allocate");
        BOOL changed=NO,eligible=NO;
        for(NSUInteger i=0;i<length;i++) {
            NSUInteger mapped=(i+rotation)%(source.length+2);indexes[i]=mapped==source.length+1?NSNotFound:mapped;
            glyphs[i]=(CGGlyph)(100+i);properties[i]=(NSGlyphProperty)((i+rotation)%16);expected[i]=properties[i];
            BOOL candidate=(properties[i]&NSGlyphPropertyElastic)&&!(properties[i]&NSGlyphPropertyControlCharacter);
            if(candidate)eligible=YES;
            if(candidate&&HasIndex(literal,indexes[i])) { expected[i]&=~NSGlyphPropertyElastic;changed=YES; }
        }
        NSData *inputGlyphs=[NSData dataWithBytes:glyphs length:length*sizeof(*glyphs)],*inputProperties=[NSData dataWithBytes:properties length:length*sizeof(*properties)],*inputIndexes=[NSData dataWithBytes:indexes length:length*sizeof(*indexes)];
        HeapAttempts=HeapFrees=AllocationBytes=0;FailAllocation=fail;
        NSUInteger result=[delegate layoutManager:(NSLayoutManager *)sink shouldGenerateGlyphs:glyphs properties:properties characterIndexes:indexes font:font forGlyphRange:NSMakeRange(103,length)];
        BOOL allocationFails=changed&&length>64&&fail,installed=changed&&!allocationFails;
        Check(result==(installed?length:0),[NSString stringWithFormat:@"callback result for source %@, length %lu, rotation %lu, expected %lu, actual %lu",source,(unsigned long)length,(unsigned long)rotation,(unsigned long)(installed?length:0),(unsigned long)result]);
        Check(sink->reads==(eligible?1:0),@"candidate fast path reads source only when required");
        Check(sink->writes==(installed?1:0),@"callback installs the complete batch exactly once when changed");
        Check([inputGlyphs isEqual:[NSData dataWithBytes:glyphs length:length*sizeof(*glyphs)]]&&[inputProperties isEqual:[NSData dataWithBytes:properties length:length*sizeof(*properties)]]&&[inputIndexes isEqual:[NSData dataWithBytes:indexes length:length*sizeof(*indexes)]],@"callback preserves every caller-owned input byte");
        Check([sink->storage.string isEqual:source],@"callback preserves exact source");
        if(installed) {
            Check([sink->glyphs isEqual:inputGlyphs]&&[sink->indexes isEqual:inputIndexes]&&sink->font==font&&NSEqualRanges(sink->range,NSMakeRange(103,length)),@"installation preserves glyph IDs, UTF-16 mapping, font identity, and nonzero glyph range");
            Check([sink->properties isEqual:[NSData dataWithBytes:expected length:length*sizeof(*expected)]],@"explicit fixture expectation matches every property bit");
        }
        BOOL heap=changed&&length>64;
        Check(HeapAttempts==(heap?1:0)&&HeapFrees==(heap&&!fail?1:0),@"property allocation and release follow one bounded ownership path");
        if(heap)Check(AllocationBytes==length*sizeof(NSGlyphProperty),@"heap buffer has exactly one property per glyph");
        free(glyphs);free(properties);free(expected);free(indexes);FailAllocation=NO;SyntheticCases++;
    }
}
static NSDictionary *CallbackContract(void) {
    // Literal positions are fixture expectations, not a copy of the new classifier.
    NSArray *cases=@[@[@"",@[]],@[@" ",@[@0]],@[@"a b",@[]],@[@" a ",@[@0,@2]],@[@"a  b",@[@1,@2]],
        @[@"a\t b",@[@2]],@[@"a \u00a0b",@[@1]],@[@"a\u2028 b",@[@2]],@[@"e\u0301 x",@[]],
        @[@"😀 x",@[]],@[@"x 😀",@[]],@[@"x \u0301y",@[@1]],@[@"x \ufe0fy",@[@1]],@[@"x \u200dy",@[@1]],@[@"\u0600 a",@[]]];
    for(NSArray *fixture in cases)for(NSNumber *length in @[@0,@1,@2,@63,@64,@65,@127,@257])for(NSUInteger rotation=0;rotation<16;rotation++)
        Synthetic(fixture[0],fixture[1],length.unsignedIntegerValue,rotation,NO);
    for(NSUInteger rotation=0;rotation<16;rotation++)Synthetic(@" a  b ",@[@0,@2,@3,@5],257,rotation,YES);
    Sink *sink=[[[Sink alloc]initWithSource:@"unused"]autorelease];CurrentDelegate *delegate=[[[CurrentDelegate alloc]init]autorelease];
    CGGlyph glyph=1;NSGlyphProperty p=NSGlyphPropertyElastic;NSUInteger index=1;
    NSFont *font=[NSFont fontWithName:@"Menlo-Regular" size:18];
    Check([delegate layoutManager:(NSLayoutManager *)sink shouldGenerateGlyphs:&glyph properties:&p characterIndexes:&index font:font forGlyphRange:NSMakeRange(0,SIZE_MAX/sizeof(NSGlyphProperty)+1)]==0&&sink->reads==0&&sink->writes==0,@"oversized batch returns before dereferencing buffers or source");
    Sink *old=[[[Sink alloc]initWithSource:@"a b"]autorelease],*now=[[[Sink alloc]initWithSource:@"a b"]autorelease];
    NSUInteger oldResult=[[[[PreviousDelegate alloc]init]autorelease]layoutManager:(NSLayoutManager *)old shouldGenerateGlyphs:&glyph properties:&p characterIndexes:&index font:font forGlyphRange:NSMakeRange(99,1)];
    NSUInteger newResult=[delegate layoutManager:(NSLayoutManager *)now shouldGenerateGlyphs:&glyph properties:&p characterIndexes:&index font:font forGlyphRange:NSMakeRange(99,1)];
    Check(oldResult==1&&old->writes==1&&newResult==0&&now->writes==0,@"baseline control proves isolated batch separator now preserves native elasticity");
    NSMutableArray *composed=[NSMutableArray array];
    for(NSString *source in @[@"x \u0301y",@"x \ufe0fy",@"x \u200dy",@"\u0600 a"])
        [composed addObject:@{@"source":source,@"nativeSpaceComposedRange":NSStringFromRange([source rangeOfComposedCharacterSequenceAtIndex:1])}];
    return @{@"fixtureStrings":@(cases.count),@"cases":@(SyntheticCases),@"allocationFailureCases":@16,@"nativeComposedRanges":composed};
}
static NSMutableSet *Fonts;
static NSMutableDictionary *Batches;
static NSUInteger NativeHeapBatches;
@interface ObservedCurrent:CurrentDelegate
@end
@implementation ObservedCurrent
- (NSUInteger)layoutManager:(NSLayoutManager *)m shouldGenerateGlyphs:(const CGGlyph *)g properties:(const NSGlyphProperty *)p characterIndexes:(const NSUInteger *)ix font:(NSFont *)f forGlyphRange:(NSRange)r {
    [Fonts addObject:f.fontName];NSString *key=[@(r.length)stringValue];Batches[key]=@([Batches[key]unsignedIntegerValue]+1);
    NSUInteger before=HeapAttempts;
    NSUInteger result=[super layoutManager:m shouldGenerateGlyphs:g properties:p characterIndexes:ix font:f forGlyphRange:r];
    if(HeapAttempts>before)NativeHeapBatches++;
    return result;
}
@end
static NSDictionary *NativeSnapshot(NSString *source,NSFont *font,NSUInteger mode) {
    NSTextStorage *storage=[[[NSTextStorage alloc]initWithString:source attributes:@{NSFontAttributeName:font,@"Marker":@"unchanged"}]autorelease];
    NSLayoutManager *layout=[[[NSLayoutManager alloc]init]autorelease];NSTextContainer *container=[[[NSTextContainer alloc]initWithSize:NSMakeSize(150,100000)]autorelease];
    [storage addLayoutManager:layout];[layout addTextContainer:container];
    id delegate=mode==2?[[[ObservedCurrent alloc]init]autorelease]:(mode==1?[[[PreviousDelegate alloc]init]autorelease]:nil);layout.delegate=delegate;
    [layout ensureGlyphsForCharacterRange:NSMakeRange(0,source.length)];NSUInteger count=layout.numberOfGlyphs;
    NSMutableData *g=[NSMutableData dataWithLength:count*sizeof(CGGlyph)],*p=[NSMutableData dataWithLength:count*sizeof(NSGlyphProperty)],*ix=[NSMutableData dataWithLength:count*sizeof(NSUInteger)],*b=[NSMutableData dataWithLength:count];
    Check([layout getGlyphsInRange:NSMakeRange(0,count)glyphs:g.mutableBytes properties:p.mutableBytes characterIndexes:ix.mutableBytes bidiLevels:b.mutableBytes]==count,@"complete native glyph snapshot");
    Check([storage.string isEqual:source],@"native generation preserves source");
    NSAttributedString *attributes=[[[NSAttributedString alloc]initWithAttributedString:storage]autorelease];layout.delegate=nil;
    return @{@"glyphs":g,@"properties":p,@"indexes":ix,@"bidi":b,@"attributes":attributes,@"glyphCount":@(count)};
}
static NSDictionary *NativeFallback(void) {
    Fonts=[NSMutableSet new];Batches=[NSMutableDictionary new];NSUInteger cases=0,propertyDifferences=0;
    NSString *longText=[[@""stringByPaddingToLength:255 withString:@"a b " startingAtIndex:0]stringByAppendingString:@"  "];
    NSArray *sources=@[@"a e\u0301 👩🏽‍💻 中文 नमस्ते b",@"  a\tb\u00a0c d  e \u0301f ",longText];
    for(NSString *name in @[@"Menlo-Regular",@"Helvetica"])for(NSUInteger fixture=0;fixture<sources.count;fixture++) {
        NSString *source=sources[fixture];NSFont *font=[NSFont fontWithName:name size:18];Check(font!=nil,@"native fixture font exists");
        NSDictionary *native=NativeSnapshot(source,font,0),*old=NativeSnapshot(source,font,1),*now=NativeSnapshot(source,font,2);
        for(NSString *key in @[@"glyphs",@"indexes",@"bidi",@"attributes"])Check([native[key]isEqual:old[key]]&&[native[key]isEqual:now[key]],@"native and both production hooks preserve glyphs, mapping, bidi, and font normalization");
        const NSGlyphProperty *original=[native[@"properties"]bytes],*before=[old[@"properties"]bytes],*after=[now[@"properties"]bytes];const NSUInteger *indexes=[native[@"indexes"]bytes];
        for(NSUInteger g=0;g<[native[@"glyphCount"]unsignedIntegerValue];g++) {
            NSUInteger index=indexes[g];BOOL space=index<source.length&&[source characterAtIndex:index]==' ';
            BOOL eligible=(original[g]&NSGlyphPropertyElastic)&&!(original[g]&NSGlyphPropertyControlCharacter)&&space;
            BOOL literal=fixture==1&&index!=[source rangeOfString:@"c d"].location+1;
            if(fixture==2)literal=index>=source.length-2;
            NSGlyphProperty expected=eligible&&literal?original[g]&~NSGlyphPropertyElastic:original[g];
            Check(after[g]==expected,@"native callback matches explicit fixture policy with all other bits preserved");
            if(before[g]!=after[g]) { propertyDifferences++;Check(eligible&&!literal&&(before[g]^after[g])==NSGlyphPropertyElastic,@"only intended separator elasticity differs from baseline"); }
        }
        cases++;
    }
    Check(Fonts.count>2,@"native fallback fonts participated");Check(NativeHeapBatches>0,@"current native callback allocates a mixed large-batch property buffer");
    return @{@"cases":@(cases),@"baselinePropertyDifferences":@(propertyDifferences),@"fonts":[[Fonts allObjects]sortedArrayUsingSelector:@selector(compare:)],@"batchLengths":Batches,@"currentHeapBatches":@(NativeHeapBatches)};
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=2)return 2;NSDictionary *synthetic=CallbackContract(),*native=NativeFallback();
    NSDictionary *result=@{@"checks":@(Checks+1),@"callbackContract":synthetic,@"nativeFallback":native,@"passed":@YES};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];Check([data writeToFile:@(argv[1])atomically:YES],@"write bounded JSON evidence");
    printf("PASS %lu checks; %lu synthetic calls; %lu native comparisons\n",(unsigned long)Checks,(unsigned long)SyntheticCases,(unsigned long)[native[@"cases"]unsignedIntegerValue]);
}return 0; }
