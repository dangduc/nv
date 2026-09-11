#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include "production.inc"

static NSUInteger Checks, Phases, Cases, NativeElasticTargets;
static NSMutableArray *Rows;
static void Check(BOOL ok,NSString *message) { Checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);} }
@interface TextSystem:NSObject {
@public NSTextStorage *storage;NSLayoutManager *layout;NSTextContainer *container;ProductionDelegate *delegate;
}
- (id)initWithText:(NSAttributedString *)text production:(BOOL)production;
- (NSDictionary *)snapshot;
@end
@implementation TextSystem
- (id)initWithText:(NSAttributedString *)text production:(BOOL)production {
    if((self=[super init])) {
        storage=[[NSTextStorage alloc]initWithAttributedString:text];layout=[NSLayoutManager new];
        container=[[NSTextContainer alloc]initWithSize:NSMakeSize(100,100000)];[storage addLayoutManager:layout];[layout addTextContainer:container];
        if(production){delegate=[ProductionDelegate new];layout.delegate=delegate;}
    }return self;
}
- (NSDictionary *)snapshot {
    [layout ensureGlyphsForCharacterRange:NSMakeRange(0,storage.length)];NSUInteger n=layout.numberOfGlyphs;
    NSMutableData *g=[NSMutableData dataWithLength:n*sizeof(CGGlyph)],*p=[NSMutableData dataWithLength:n*sizeof(NSGlyphProperty)],*ix=[NSMutableData dataWithLength:n*sizeof(NSUInteger)],*b=[NSMutableData dataWithLength:n];
    Check([layout getGlyphsInRange:NSMakeRange(0,n)glyphs:g.mutableBytes properties:p.mutableBytes characterIndexes:ix.mutableBytes bidiLevels:b.mutableBytes]==n,@"complete native glyph snapshot");
    return @{@"glyphs":g,@"properties":p,@"indexes":ix,@"bidi":b,@"count":@(n)};
}
- (void)dealloc {layout.delegate=nil;[delegate release];[container release];[layout release];[storage release];[super dealloc];}
@end
static NSString *Scalar(UTF32Char code) {
    unichar chars[2];NSUInteger length=1;
    if(code<=0xffff)chars[0]=(unichar)code;
    else {code-=0x10000;chars[0]=0xd800+(code>>10);chars[1]=0xdc00+(code&0x3ff);length=2;}
    return [NSString stringWithCharacters:chars length:length];
}
static NSAttributedString *Seed(void) {
    return [[[NSAttributedString alloc]initWithString:@"L R" attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18],@"Marker":@"preserved"}]autorelease];
}
static NSDictionary *Observe(TextSystem *live,NSString *expected,NSUInteger target,NSInteger literal) {
    Check([live->storage.string isEqual:expected],@"neighbor edit preserves exact requested UTF-16 source");
    NSAttributedString *input=[[[NSAttributedString alloc]initWithAttributedString:live->storage]autorelease];
    NSDictionary *actual=[live snapshot];
    TextSystem *fresh=[[[TextSystem alloc]initWithText:input production:YES]autorelease];NSDictionary *reference=[fresh snapshot];
    TextSystem *native=[[[TextSystem alloc]initWithText:input production:NO]autorelease];NSDictionary *raw=[native snapshot];
    for(NSString *key in @[@"glyphs",@"properties",@"indexes",@"bidi",@"count"])
        Check([actual[key]isEqual:reference[key]],@"cached glyph result matches fresh production after neighbor mutation");
    for(NSString *key in @[@"glyphs",@"indexes",@"bidi",@"count"])
        Check([actual[key]isEqual:raw[key]],@"native glyph IDs, UTF-16 indexes, bidi, and count stay unchanged");
    Check([live->storage isEqualToAttributedString:native->storage]&&[live->storage.string isEqual:expected],@"source and attributes match native normalization");
    for(NSUInteger i=0;i<live->storage.length;i++)Check([[live->storage attribute:@"Marker" atIndex:i effectiveRange:NULL]isEqual:@"preserved"],@"source metadata survives each scalar edit");
    const NSGlyphProperty *nativeProperties=[raw[@"properties"]bytes],*actualProperties=[actual[@"properties"]bytes];const NSUInteger *indexes=[actual[@"indexes"]bytes];
    for(NSUInteger glyph=0;glyph<[actual[@"count"]unsignedIntegerValue];glyph++) {
        NSUInteger index=indexes[glyph];Check(index<expected.length,@"native glyph mapping stays inside source");
        Check((actualProperties[glyph]|nativeProperties[glyph])==nativeProperties[glyph]&&((actualProperties[glyph]^nativeProperties[glyph])&~NSGlyphPropertyElastic)==0,@"only removal of native Elastic is permitted");
        BOOL space=[expected characterAtIndex:index]==' ',eligible=space&&(nativeProperties[glyph]&NSGlyphPropertyElastic)&&!(nativeProperties[glyph]&NSGlyphPropertyControlCharacter);
        if(literal>=0) {
            NSGlyphProperty wanted=eligible&&literal?nativeProperties[glyph]&~NSGlyphPropertyElastic:nativeProperties[glyph];
            Check(actualProperties[glyph]==wanted,[NSString stringWithFormat:@"explicit property expectation: source=%@ glyph=%lu index=%lu native=%lu actual=%lu wanted=%lu literal=%ld composed=%@",[expected dataUsingEncoding:NSUTF16LittleEndianStringEncoding],(unsigned long)glyph,(unsigned long)index,(unsigned long)nativeProperties[glyph],(unsigned long)actualProperties[glyph],(unsigned long)wanted,(long)literal,NSStringFromRange([expected rangeOfComposedCharacterSequenceAtIndex:target])]);
        } else if(!eligible)Check(actualProperties[glyph]==nativeProperties[glyph],@"formatting-neighbor observation preserves every ineligible property");
    }
    NSUInteger glyph=[live->layout glyphIndexForCharacterAtIndex:target];
    BOOL nativeElastic=(nativeProperties[glyph]&NSGlyphPropertyElastic)!=0,elastic=(actualProperties[glyph]&NSGlyphPropertyElastic)!=0;
    if(nativeElastic)NativeElasticTargets++;
    Phases++;
    return @{@"spaceComposedRange":NSStringFromRange([expected rangeOfComposedCharacterSequenceAtIndex:target]),@"nativeElastic":@(nativeElastic),@"elastic":@(elastic),@"sourceLength":@(expected.length)};
}
static void Neighbor(TextSystem *live,UTF32Char scalar,BOOL left,NSString *group,NSInteger literal) {
    @autoreleasepool {
        Observe(live,@"L R",1,0);
        NSString *neighbor=Scalar(scalar);
        NSRange change=NSMakeRange(left?0:2,1);
        [live->storage replaceCharactersInRange:change withString:neighbor];
        NSString *expected=left?[neighbor stringByAppendingString:@" R"]:[@"L "stringByAppendingString:neighbor];
        NSUInteger target=left?neighbor.length:1;
        NSMutableDictionary *row=[NSMutableDictionary dictionaryWithDictionary:Observe(live,expected,target,literal)];
        row[@"group"]=group;row[@"scalar"]=[NSString stringWithFormat:@"U+%04X",scalar];row[@"side"]=left?@"left":@"right";
        row[@"expectedLiteral"]=literal<0?(id)[NSNull null]:(id)@(literal);
        row[@"foundationWhitespace"]=@([[NSCharacterSet whitespaceAndNewlineCharacterSet]longCharacterIsMember:scalar]);
        [Rows addObject:row];
        [live->storage replaceCharactersInRange:NSMakeRange(left?0:2,neighbor.length)withString:left?@"L":@"R"];
        Observe(live,@"L R",1,0);Cases++;
    }
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=2)return 2;Rows=[NSMutableArray new];TextSystem *live=[[[TextSystem alloc]initWithText:Seed()production:YES]autorelease];
    NSCharacterSet *whitespace=[NSCharacterSet whitespaceAndNewlineCharacterSet];NSMutableArray *members=[NSMutableArray array];
    for(UTF32Char scalar=0;scalar<=0x10ffff;scalar++) {
        if(scalar>=0xd800&&scalar<=0xdfff)continue;
        if([whitespace longCharacterIsMember:scalar]) {
            [members addObject:[NSString stringWithFormat:@"U+%04X",scalar]];
            Neighbor(live,scalar,YES,@"Foundation whitespace",1);Neighbor(live,scalar,NO,@"Foundation whitespace",1);
        }
    }
    Check(members.count>0,@"Foundation whitespace set has enumerated scalar members");
    UTF32Char controls[]={0x200b,0x200c,0x2060,0xfeff,0x200e,0x200f,0x061c,0x2066,0x2067,0x2068,0x2069,0x0600};
    for(NSUInteger i=0;i<sizeof(controls)/sizeof(*controls);i++) {
        // Record these platform classifications without assuming visual spacing.
        Neighbor(live,controls[i],YES,@"formatting observation",-1);Neighbor(live,controls[i],NO,@"formatting observation",-1);
    }
    UTF32Char attached[]={0x0301,0xfe0f,0x200d,0xe0100};
    for(NSUInteger i=0;i<sizeof(attached)/sizeof(*attached);i++) {
        Neighbor(live,attached[i],YES,@"preceding mark",0);
        Neighbor(live,attached[i],NO,@"space with attached mark",1);
    }
    Neighbor(live,0x1f600,YES,@"surrogate-pair neighbor",0);Neighbor(live,0x1f600,NO,@"surrogate-pair neighbor",0);
    Check(NativeElasticTargets>Cases,@"native eligible spaces participate across the edit sequence");
    NSDictionary *result=@{@"checks":@(Checks+1),@"cases":@(Cases),@"phases":@(Phases),@"nativeElasticTargetPhases":@(NativeElasticTargets),@"whitespaceMembers":members,@"observations":Rows,@"passed":@YES};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];Check([data writeToFile:@(argv[1])atomically:YES],@"write bounded review JSON");
    printf("PASS %lu checks, %lu scalar-neighbor cases, %lu phases, %lu whitespace scalars\n",(unsigned long)Checks,(unsigned long)Cases,(unsigned long)Phases,(unsigned long)members.count);
}return 0; }
