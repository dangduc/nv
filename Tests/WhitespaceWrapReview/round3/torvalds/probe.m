static NSUInteger Cases, StackStores, HeapStores, SourceReads, NativeStackStores, NativeHeapStores;
static BOOL ActiveProduction;
static const NSGlyphProperty *OriginalNativeProperties;
static volatile unsigned char StackSink;
__attribute__((noinline)) static void ClobberStack(void) {
    volatile unsigned char bytes[8192];
    for(NSUInteger i=0;i<sizeof(bytes);i++)bytes[i]=(unsigned char)(i*37+19);
    StackSink=bytes[StackSink];
}
@interface CountSourceLayout:CaptureLayout
@end
@implementation CountSourceLayout
- (NSTextStorage*)textStorage{SourceReads++;return [super textStorage];}
@end
static void RunCase(ProductionDelegate*d,NSString*source,const NSGlyphProperty*props,const NSUInteger*indexes,const NSGlyphProperty*expected,NSUInteger n,BOOL changed,BOOL fail,BOOL canReadSource){
    CountSourceLayout*m=[CountSourceLayout new];m->source=[[NSTextStorage alloc]initWithString:source];
    CGGlyph glyphs[257];Check(n<=257,@"case bound");for(NSUInteger i=0;i<n;i++)glyphs[i]=(CGGlyph)(i+73);
    void*gm,*pm,*im;const CGGlyph*g=ReadonlyTail(glyphs,n*sizeof(*g),&gm);const NSGlyphProperty*p=ReadonlyTail(props,n*sizeof(*p),&pm);const NSUInteger*ix=ReadonlyTail(indexes,n*sizeof(*ix),&im);
    Allocations=Frees=Bytes=SourceReads=0;FailAllocation=fail;
    BOOL heap=changed&&n>64,stored=changed&&!(heap&&fail);
    NSRange range=NSMakeRange(1009,n);NSFont*token=(NSFont*)source;
    NSUInteger returned=[d layoutManager:m shouldGenerateGlyphs:g properties:p characterIndexes:ix font:token forGlyphRange:range];
    ClobberStack();
    Check(returned==(stored?n:0)&&m->stores==(stored?1:0),@"exact consumed batch and store count");
    Check(Allocations==(heap?1:0)&&Frees==((heap&&!fail)?1:0),@"stack/heap threshold and allocation-failure cleanup");
    Check(SourceReads==(canReadSource?1:0),@"property prescan avoids source access when no property candidate exists");
    Check(!memcmp(g,glyphs,n*sizeof(*g))&&!memcmp(p,props,n*sizeof(*p))&&!memcmp(ix,indexes,n*sizeof(*ix)),@"all guarded caller arrays preserve bytes");
    if(stored){
        Check(NSEqualRanges(m->seenRange,range)&&m->seenFont==token&&m->seenGlyphs==g&&m->seenIndexes==ix&&m->seenProperties!=p,@"range font glyph and character-index identity preserve contract");
        Check(!memcmp(m->storedProperties.bytes,expected,n*sizeof(*p)),@"exact expected properties survive stack reuse");
        if(heap){HeapStores++;Check(Bytes==n*sizeof(*p),@"heap allocation covers full batch");}else StackStores++;
    }
    Check([m->source.string isEqual:source],@"source characters unchanged");
    size_t page=(size_t)getpagesize();munmap(gm,page*2);munmap(pm,page*2);munmap(im,page*2);
    [m release];FailAllocation=NO;Cases++;
}
@interface AuditNativeLayout:NSLayoutManager
@end
@implementation AuditNativeLayout
- (void)setGlyphs:(const CGGlyph*)g properties:(const NSGlyphProperty*)p characterIndexes:(const NSUInteger*)ix font:(NSFont*)f forGlyphRange:(NSRange)range{
    [super setGlyphs:g properties:p characterIndexes:ix font:f forGlyphRange:range];
    if(ActiveProduction){
        Check(p!=OriginalNativeProperties,@"production store uses private scratch properties");
        if(range.length<=64)NativeStackStores++;else NativeHeapStores++;
        // Public setGlyphs has returned. The caller-owned scratch storage is now reusable.
        memset((void*)p,0xCD,range.length*sizeof(*p));
    }
}
@end
@interface AuditDelegate:ProductionDelegate
@end
@implementation AuditDelegate
- (NSUInteger)layoutManager:(NSLayoutManager*)m shouldGenerateGlyphs:(const CGGlyph*)g properties:(const NSGlyphProperty*)p characterIndexes:(const NSUInteger*)ix font:(NSFont*)font forGlyphRange:(NSRange)range{
    NativeBatches++;NSData*before=[NSData dataWithBytes:p length:range.length*sizeof(*p)];
    ActiveProduction=YES;OriginalNativeProperties=p;
    NSUInteger result=[super layoutManager:m shouldGenerateGlyphs:g properties:p characterIndexes:ix font:font forGlyphRange:range];
    ActiveProduction=NO;OriginalNativeProperties=NULL;ClobberStack();
    if(result)ChangedBatches++;
    Check(!memcmp(before.bytes,p,before.length),@"native supplied properties survive scratch poisoning and stack clobber");
    return result;
}
@end
// NATIVE_GLYPH_HELPER
static uint32_t RandomState=0x64c0ffee;
static uint32_t NextRandom(void){RandomState=RandomState*1664525U+1013904223U;return RandomState;}
int main(void){@autoreleasepool{
    ProductionDelegate*d=[ProductionDelegate new];
    NSUInteger(*invoke)(id,SEL,id,const CGGlyph*,const NSGlyphProperty*,const NSUInteger*,id,NSRange)=(void*)[d methodForSelector:@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)];SEL selector=@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:);
    Check(invoke(d,selector,nil,NULL,NULL,NULL,nil,NSMakeRange(NSNotFound,0))==0,@"zero batch needs no buffers or manager");
    Check(invoke(d,selector,nil,NULL,NULL,NULL,nil,NSMakeRange(0,SIZE_MAX/sizeof(NSGlyphProperty)+1))==0,@"overflow guard precedes property prescan");
    NSString*text=@"x e\u0301👩‍💻 \t\u00a0";NSGlyphProperty e=NSGlyphPropertyElastic,c=NSGlyphPropertyControlCharacter,nb=NSGlyphPropertyNonBaseCharacter,z=NSGlyphPropertyNull,other=1L<<24;
    NSGlyphProperty p[257],want[257];NSUInteger ix[257];
    for(NSUInteger pass=0;pass<3;pass++)for(NSNumber*size in @[@63,@64,@65,@257,@64,@1]){
        NSUInteger n=size.unsignedIntegerValue;
        for(NSUInteger kind=0;kind<4;kind++){
            for(NSUInteger i=0;i<n;i++){p[i]=want[i]=other;ix[i]=NSNotFound;}
            if(kind==0){p[n-1]=e|nb;want[n-1]=nb;ix[n-1]=1;}
            if(kind==1){p[0]=want[0]=e;ix[0]=0;if(n>1){p[n-1]=e;want[n-1]=0;ix[n-1]=1;}}
            if(kind==2){for(NSUInteger i=0;i<n;i++){p[i]=want[i]=e|c;ix[i]=1;}}
            if(kind==3){for(NSUInteger i=0;i<n;i++){p[i]=want[i]=e;ix[i]=0;}}
            BOOL changed=kind==0||(kind==1&&n>1);
            RunCase(d,text,p,ix,want,n,changed,NO,kind!=2);
            if(changed)RunCase(d,text,p,ix,want,n,YES,YES,YES);
        }
    }
    NSUInteger lowSurrogate=[text rangeOfString:@"👩"].location+1;
    for(NSUInteger trial=0;trial<256;trial++){
        NSUInteger n=1+NextRandom()%257;BOOL changed=NO,candidate=NO;
        for(NSUInteger i=0;i<n;i++){
            NSUInteger kind=NextRandom()%8;p[i]=e;want[i]=e;ix[i]=0;
            switch(kind){
                case 0:ix[i]=1;want[i]=0;changed=YES;break;
                case 1:ix[i]=0;break;
                case 2:ix[i]=text.length;break;
                case 3:ix[i]=NSNotFound;break;
                case 4:ix[i]=lowSurrogate;p[i]=want[i]=e|nb;break;
                case 5:ix[i]=1;p[i]=want[i]=e|c;break;
                case 6:ix[i]=1;p[i]=e|nb|z|other;want[i]=nb|z|other;changed=YES;break;
                case 7:ix[i]=3;p[i]=want[i]=e|nb;break;
            }
            if(!(p[i]&c))candidate=YES;
        }
        RunCase(d,text,p,ix,want,n,changed,trial%13==0,candidate);
    }
    AuditDelegate*a=[AuditDelegate new];NSUInteger compared=0;
    NSArray*fixtures=@[[@"" stringByPaddingToLength:63 withString:@" " startingAtIndex:0],[@"" stringByPaddingToLength:64 withString:@" " startingAtIndex:0],[@"" stringByPaddingToLength:65 withString:@" " startingAtIndex:0],[@"" stringByPaddingToLength:257 withString:@" " startingAtIndex:0],@"e\u0301 👩🏽‍💻  क्षि \t\u00a0",@"A  B"];
    for(NSUInteger repeat=0;repeat<3;repeat++)for(NSString*s in fixtures){
        NSDictionary*base=NativeGlyphs(s,nil),*current=NativeGlyphs(s,a);
        for(NSString*key in @[@"glyphs",@"indexes",@"bidi"])Check([base[key]isEqual:current[key]],@"native glyph IDs UTF16 indexes and bidi preserve baseline after scratch reuse");
        const NSGlyphProperty*bp=[base[@"properties"]bytes],*cp=[current[@"properties"]bytes];const NSUInteger*indexes=[base[@"indexes"]bytes];
        for(NSUInteger i=0;i<[base[@"count"]unsignedIntegerValue];i++){
            if(bp[i]!=cp[i])Check((bp[i]^cp[i])==e&&!(cp[i]&e)&&!(bp[i]&c)&&indexes[i]<s.length&&[s characterAtIndex:indexes[i]]==' ',@"native readback has only expected space property changes");
            compared++;
        }
    }
    Check(StackStores>0&&HeapStores>0&&NativeStackStores>0&&NativeHeapStores>0,@"synthetic and native cases exercise both scratch storage paths");
    printf("{\"checks\":%lu,\"guarded_cases\":%lu,\"deterministic_fuzz_cases\":256,\"stack_stores\":%lu,\"heap_stores\":%lu,\"native_stack_stores\":%lu,\"native_heap_stores\":%lu,\"native_compared_glyphs\":%lu,\"passed\":true}\n",(unsigned long)Checks,(unsigned long)Cases,(unsigned long)StackStores,(unsigned long)HeapStores,(unsigned long)NativeStackStores,(unsigned long)NativeHeapStores,(unsigned long)compared);
    [a release];[d release];
}return 0;}
