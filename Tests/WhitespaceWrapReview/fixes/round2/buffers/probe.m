#import <Cocoa/Cocoa.h>
#import <sys/mman.h>
#import <unistd.h>
static NSUInteger Checks,Allocations,Frees,MaxAllocation;
static BOOL FailAllocation;
static void Check(BOOL condition,NSString*message){Checks++;if(!condition){fprintf(stderr,"FAIL %s\n",message.UTF8String);exit(1);}}
static void*TrackedMalloc(size_t size){Allocations++;MaxAllocation=MAX(MaxAllocation,size);return FailAllocation?NULL:malloc(size);}
static void TrackedFree(void*memory){Frees++;free(memory);}
@interface OldDelegate:NSObject<NSLayoutManagerDelegate>@end
@implementation OldDelegate
#define malloc TrackedMalloc
#define free TrackedFree
/*OLD*/
#undef malloc
#undef free
@end
@interface NewDelegate:NSObject<NSLayoutManagerDelegate>@end
@implementation NewDelegate
#define malloc TrackedMalloc
#define free TrackedFree
/*NEW*/
#undef malloc
#undef free
@end
@interface CaptureStorage:NSObject { @public NSString*source; NSUInteger reads; }
- (NSString*)string;
@end
@implementation CaptureStorage
- (NSString*)string{reads++;return source;}
@end
@interface CaptureManager:NSObject { @public CaptureStorage*storage;NSUInteger reads,sets;NSDictionary*publication; }
- (NSTextStorage*)textStorage;
- (void)setGlyphs:(const CGGlyph*)glyphs properties:(const NSGlyphProperty*)properties characterIndexes:(const NSUInteger*)indexes font:(NSFont*)font forGlyphRange:(NSRange)range;
@end
@implementation CaptureManager
- (NSTextStorage*)textStorage{reads++;return (NSTextStorage*)storage;}
- (void)setGlyphs:(const CGGlyph*)glyphs properties:(const NSGlyphProperty*)properties characterIndexes:(const NSUInteger*)indexes font:(NSFont*)font forGlyphRange:(NSRange)range{
 sets++;publication=@{@"glyphs":[NSData dataWithBytes:glyphs length:range.length*sizeof(*glyphs)],
 @"properties":[NSData dataWithBytes:properties length:range.length*sizeof(*properties)],
 @"indexes":[NSData dataWithBytes:indexes length:range.length*sizeof(*indexes)],@"font":font,@"range":[NSValue valueWithRange:range]};
}
@end
typedef struct{void*base;size_t mapped;void*bytes;size_t length;}Guarded;
static Guarded Buffer(size_t length){size_t page=getpagesize(),body=((MAX(length,(size_t)1)+page-1)/page)*page;void*base=mmap(NULL,body+2*page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);Check(base!=MAP_FAILED,@"guarded allocation");mprotect(base,page,PROT_NONE);mprotect((char*)base+page+body,page,PROT_NONE);Guarded b={base,body+2*page,(char*)base+page+body-length,length};return b;}
static void Drop(Guarded b){munmap(b.base,b.mapped);}
static NSDictionary*Invoke(id delegate,NSString*source,const CGGlyph*g,const NSGlyphProperty*p,const NSUInteger*i,NSRange range,BOOL fail){
 CaptureStorage*s=[[[CaptureStorage alloc]init]autorelease];s->source=source;
 CaptureManager*m=[[[CaptureManager alloc]init]autorelease];m->storage=s;
 Allocations=Frees=MaxAllocation=0;FailAllocation=fail;
 NSUInteger result=[delegate layoutManager:(NSLayoutManager*)m shouldGenerateGlyphs:g properties:p characterIndexes:i font:(NSFont*)@"font-identity" forGlyphRange:range];
 return @{@"returned":@(result),@"sets":@(m->sets),@"publication":m->publication?:@{},@"allocations":@(Allocations),@"frees":@(Frees),@"maxAllocation":@(MaxAllocation),@"storageReads":@(m->reads),@"stringReads":@(s->reads)};
}
static NSDictionary*Units(void){
 id old=[[[OldDelegate alloc]init]autorelease];
 id next=[[[NewDelegate alloc]init]autorelease];
 NSUInteger comparisons=0,oldAllocations=0,newAllocations=0,fastReturns=0;
 NSArray*lengths=@[@0,@1,@2,@63,@64,@65,@127,@268,@1024];
 for(NSNumber*length in lengths){NSUInteger n=length.unsignedIntegerValue;
  for(NSUInteger pattern=0;pattern<6;pattern++){
   Guarded gb=Buffer(n*sizeof(CGGlyph)),pb=Buffer(n*sizeof(NSGlyphProperty)),ib=Buffer(n*sizeof(NSUInteger));
   CGGlyph*g=gb.bytes;NSGlyphProperty*p=pb.bytes;NSUInteger*i=ib.bytes;
   NSString*source=pattern==4?@"x\t\u00a0\n\u2003":@" \tx\u00a0\n ê ";
   for(NSUInteger j=0;j<n;j++){
    g[j]=(CGGlyph)(30+j%32000);i[j]=pattern==0?0:j%source.length;
    p[j]=pattern==1?0:pattern==2?(NSGlyphPropertyElastic|NSGlyphPropertyControlCharacter):NSGlyphPropertyElastic;
    if(pattern==3){p[j]|=j%2?NSGlyphPropertyNonBaseCharacter:0;if(j%5==0)p[j]|=NSGlyphPropertyControlCharacter;if(j%7==0)i[j]=NSNotFound;if(j%11==0)i[j]=source.length;}
    if(pattern==5){p[j]=j+1==n?NSGlyphPropertyElastic:0;i[j]=0;}
   }
   NSData*originalG=[NSData dataWithBytes:g length:gb.length],*originalP=[NSData dataWithBytes:p length:pb.length],*originalI=[NSData dataWithBytes:i length:ib.length];
   NSDictionary*a=Invoke(old,source,g,p,i,NSMakeRange(17,n),NO),*b=Invoke(next,source,g,p,i,NSMakeRange(17,n),NO);
   Check([a[@"returned"]isEqual:b[@"returned"]]&&[a[@"publication"]isEqual:b[@"publication"]],@"old/new publication equivalence");
   Check([a[@"sets"]isEqual:b[@"sets"]],@"one unchanged publication count");
   Check([originalG isEqual:[NSData dataWithBytes:g length:gb.length]]&&[originalP isEqual:[NSData dataWithBytes:p length:pb.length]]&&[originalI isEqual:[NSData dataWithBytes:i length:ib.length]],@"input arrays remain unchanged");
   Check([b[@"allocations"]unsignedIntegerValue]==(n>64&&[b[@"sets"]boolValue]?1:0),@"only changed large batches allocate");
   Check([b[@"frees"]isEqual:b[@"allocations"]],@"heap buffer released exactly once");
   oldAllocations+=[a[@"allocations"]unsignedIntegerValue];newAllocations+=[b[@"allocations"]unsignedIntegerValue];comparisons++;
   if(!n||pattern==1||pattern==2){Check([b[@"storageReads"]unsignedIntegerValue]==0&&[b[@"stringReads"]unsignedIntegerValue]==0,@"ineligible property batch skips storage and string");fastReturns++;}
   if(n>64&&pattern==0){a=Invoke(old,source,g,p,i,NSMakeRange(17,n),YES);b=Invoke(next,source,g,p,i,NSMakeRange(17,n),YES);Check([a[@"returned"]unsignedIntegerValue]==0&&[b[@"returned"]unsignedIntegerValue]==0&&[b[@"sets"]unsignedIntegerValue]==0&&[b[@"frees"]unsignedIntegerValue]==0,@"failed heap allocation leaves native fallback untouched");}
   if(n&&n<=64&&pattern==0){b=Invoke(next,source,g,p,i,NSMakeRange(17,n),YES);Check([b[@"returned"]unsignedIntegerValue]==n&&[b[@"allocations"]unsignedIntegerValue]==0,@"small stack batch works without heap allocation");}
   Drop(gb);Drop(pb);Drop(ib);
  }
 }
 for(NSNumber*n in @[@0,@(SIZE_MAX/sizeof(NSGlyphProperty)+1)]){
  NSDictionary*a=Invoke(old,@" ",NULL,NULL,NULL,NSMakeRange(0,n.unsignedIntegerValue),NO),*b=Invoke(next,@" ",NULL,NULL,NULL,NSMakeRange(0,n.unsignedIntegerValue),NO);
  Check([a[@"returned"]unsignedIntegerValue]==0&&[b[@"returned"]unsignedIntegerValue]==0&&[b[@"storageReads"]unsignedIntegerValue]==0,@"empty/overflow guard precedes all buffer and source reads");
 }
 return @{@"checks":@(Checks),@"equivalenceCases":@(comparisons),@"oldAllocations":@(oldAllocations),@"newAllocations":@(newAllocations),@"fastReturnCases":@(fastReturns)};
}
static NSDictionary*NativeLayout(id delegate,NSString*source,NSString*fontName,NSUInteger width){
 NSTextStorage*s=[[[NSTextStorage alloc]init]autorelease];NSLayoutManager*l=[[[NSLayoutManager alloc]init]autorelease];
 NSTextContainer*c=[[[NSTextContainer alloc]initWithSize:NSMakeSize(width,1000000)]autorelease];[s addLayoutManager:l];[l addTextContainer:c];l.delegate=delegate;
 NSMutableParagraphStyle*style=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];style.lineBreakMode=NSLineBreakByCharWrapping;
 Allocations=Frees=MaxAllocation=0;FailAllocation=NO;
 [s setAttributedString:[[[NSAttributedString alloc]initWithString:source attributes:@{NSFontAttributeName:[NSFont fontWithName:fontName size:18],NSParagraphStyleAttributeName:style}]autorelease]];
 [l ensureLayoutForTextContainer:c];
 NSMutableArray*lines=[NSMutableArray array];
 [l enumerateLineFragmentsForGlyphRange:NSMakeRange(0,l.numberOfGlyphs)usingBlock:^(NSRect rect,NSRect used,NSTextContainer*container,NSRange range,BOOL*stop){[lines addObject:@{ @"range":NSStringFromRange(range),@"rect":NSStringFromRect(rect),@"used":NSStringFromRect(used)}];}];
 NSMutableArray*glyphs=[NSMutableArray array];
 for(NSUInteger i=0;i<l.numberOfGlyphs;i++)[glyphs addObject:@{ @"id":@([l CGGlyphAtIndex:i]),@"properties":@([l propertyForGlyphAtIndex:i]),@"character":@([l characterIndexForGlyphAtIndex:i]),@"position":NSStringFromPoint([l locationForGlyphAtIndex:i])}];
 Check([source isEqual:s.string],@"native layout preserves source");
 return @{@"lines":lines,@"glyphs":glyphs,@"allocations":@(Allocations),@"frees":@(Frees),@"maxAllocation":@(MaxAllocation)};
}
static NSDictionary*Native(void){
 [NSApplication sharedApplication];id old=[[[OldDelegate alloc]init]autorelease],next=[[[NewDelegate alloc]init]autorelease];
 NSUInteger cases=0,oldAllocations=0,newAllocations=0,max=0;
 NSArray*fixtures=@[@"alpha beta                                        ",@"\talpha\tbeta  Việt e\u0302 👩🏽‍💻 中文  \nsecond line",@"אבגדה alpha beta     ",[@""stringByPaddingToLength:64 withString:@" "startingAtIndex:0],[@""stringByPaddingToLength:65 withString:@" "startingAtIndex:0],[@""stringByPaddingToLength:2048 withString:@"abc   "startingAtIndex:0]];
 for(NSString*source in fixtures)for(NSString*font in @[@"Menlo-Regular",@"Helvetica",@"Times-Roman"])for(NSNumber*width in @[@160,@544,@700]){@autoreleasepool{
  NSDictionary*a=NativeLayout(old,source,font,width.unsignedIntegerValue),*b=NativeLayout(next,source,font,width.unsignedIntegerValue);
  Check([a[@"lines"]isEqual:b[@"lines"]]&&[a[@"glyphs"]isEqual:b[@"glyphs"]],@"native geometry and glyph records remain identical");
  Check([b[@"allocations"]unsignedIntegerValue]<=[a[@"allocations"]unsignedIntegerValue],@"native heap allocations do not increase");
  Check([b[@"allocations"]isEqual:b[@"frees"]],@"native heap allocation/free balance");
  oldAllocations+=[a[@"allocations"]unsignedIntegerValue];newAllocations+=[b[@"allocations"]unsignedIntegerValue];max=MAX(max,[b[@"maxAllocation"]unsignedIntegerValue]);cases++;
 }}
 return @{@"checks":@(Checks),@"cases":@(cases),@"oldAllocations":@(oldAllocations),@"newAllocations":@(newAllocations),@"maxHeapAllocation":@(max)};
}
int main(int argc,const char**argv){@autoreleasepool{NSDictionary*result=strcmp(argv[1],"units")==0?Units():Native();NSData*data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];Check([data writeToFile:[NSString stringWithUTF8String:argv[2]]atomically:YES],@"evidence saved");printf("%s PASS %lu checks\n",argv[1],(unsigned long)Checks);}return 0;}
