#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import "NVSourceTypesetter.h"
#include "space-delegate.h"
#include <sys/resource.h>
static NSUInteger Checks,Creates,CreateChars,Suggests,Lines,Tokens;
static void Check(BOOL b){Checks++;if(!b){fprintf(stderr,"FAIL %lu\n",Checks);exit(1);}}
CTTypesetterRef CountTypesetter(CFAttributedStringRef s){Creates++;CreateChars+=CFAttributedStringGetLength(s);return CTTypesetterCreateWithAttributedString(s);}
CFIndex CountSuggest(CTTypesetterRef t,CFIndex p,double w,double o){Suggests++;return CTTypesetterSuggestClusterBreakWithOffset(t,p,w,o);}
CTLineRef CountLine(CTTypesetterRef t,CFRange r,double o){Lines++;return CTTypesetterCreateLineWithOffset(t,r,o);}
CFStringTokenizerTokenType CountToken(CFStringTokenizerRef t){Tokens++;return CFStringTokenizerAdvanceToNextToken(t);}
static double Wall(void){return NSProcessInfo.processInfo.systemUptime*1000;}
static double CPU(void){struct rusage r;getrusage(RUSAGE_SELF,&r);return (r.ru_utime.tv_sec+r.ru_stime.tv_sec)*1000.0+(r.ru_utime.tv_usec+r.ru_stime.tv_usec)/1000.0;}
@interface System:NSObject{
@public NSTextStorage*s;NSLayoutManager*l;NSTextContainer*c;SpaceDelegate*d;
}
-(id)init:(NSString*)source refined:(BOOL)refined;
@end
@implementation System
-(id)init:(NSString*)source refined:(BOOL)refined{
 if((self=[super init])){
 s=[[NSTextStorage alloc]init];l=[[NSLayoutManager alloc]init];c=[[NSTextContainer alloc]initWithSize:NSMakeSize(544,10000000)];d=[[SpaceDelegate alloc]init];
 [s addLayoutManager:l];[l addTextContainer:c];l.delegate=d;
 if(refined)l.typesetter=[[[NVSourceTypesetter alloc]init]autorelease];
 NSMutableParagraphStyle*p=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];p.lineBreakMode=NSLineBreakByCharWrapping;
 [s setAttributedString:[[[NSAttributedString alloc]initWithString:source attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular"size:18],NSParagraphStyleAttributeName:p}]autorelease]];
 }return self;
}
-(void)dealloc{l.delegate=nil;[d release];[c release];[l release];[s release];[super dealloc];}
@end
static NSDictionary*Sample(NSString*source,BOOL refined,NSString*op){
 System*x=[[[System alloc]init:source refined:refined]autorelease];
 NSRect viewport=NSMakeRect(0,0,544,600);
 if(![op isEqual:@"initial-visible"])[x->l ensureLayoutForBoundingRect:viewport inTextContainer:x->c];
 if([op isEqual:@"edit-end"])[x->l ensureLayoutForCharacterRange:NSMakeRange(source.length-1,1)];
 Creates=CreateChars=Suggests=Lines=Tokens=0;
 double cpu=CPU(),wall=Wall();NSUInteger edits=0;
 if([op isEqual:@"initial-visible"])[x->l ensureLayoutForBoundingRect:viewport inTextContainer:x->c];
 else if([op isEqual:@"resize-visible"]){
  for(NSUInteger i=0;i<8;i++){CGFloat w=i%2?544:344;x->c.containerSize=NSMakeSize(w,10000000);[x->l ensureLayoutForBoundingRect:NSMakeRect(0,0,w,600)inTextContainer:x->c];}
 }else{
  for(NSUInteger i=0;i<8;i++){
   NSUInteger p=[op isEqual:@"edit-end"]?x->s.length:32+i;
   [x->s replaceCharactersInRange:NSMakeRange(p,0)withString:@"k"];edits++;
   if([op isEqual:@"edit-end"])[x->l ensureLayoutForCharacterRange:NSMakeRange(p,1)];
   else[x->l ensureLayoutForBoundingRect:viewport inTextContainer:x->c];
  }
 }
 wall=Wall()-wall;cpu=CPU()-cpu;
 NSRange visible=[x->l glyphRangeForBoundingRectWithoutAdditionalLayout:viewport inTextContainer:x->c];
 NSUInteger firstUnlaid=x->l.firstUnlaidCharacterIndex;
 __block NSUInteger fragments=0;
 [x->l enumerateLineFragmentsForGlyphRange:NSMakeRange(0,x->l.firstUnlaidGlyphIndex) usingBlock:^(NSRect r,NSRect u,NSTextContainer*t,NSRange g,BOOL*stop){fragments++;}];
 Check(x->s.length==source.length+edits);Check(visible.length>0);Check(NSThread.isMainThread);
 NSMutableString*expected=[[source mutableCopy]autorelease];
 for(NSUInteger i=0;i<edits;i++)[expected insertString:@"k" atIndex:[op isEqual:@"edit-end"]?expected.length:32+i];
 Check([x->s.string isEqual:expected]);
 return @{@"laidLineFragments":@(fragments),@"wallMs":@(wall),@"cpuMs":@(cpu),@"firstUnlaidCharacter":@(firstUnlaid),@"visibleGlyphs":@(visible.length),@"createCalls":@(Creates),@"snapshotCharacters":@(CreateChars),@"suggestCalls":@(Suggests),@"lineCalls":@(Lines),@"tokenAdvanceCalls":@(Tokens)};
}
int main(int argc,char**argv){@autoreleasepool{
 if(argc<3)return 2;[NSApplication sharedApplication];BOOL instrument=!strcmp(argv[2],"instrument");NSMutableArray*records=[NSMutableArray array];
 NSArray*fixtures=@[@"short",@"prose",@"paragraphs"];
 for(NSString*fixture in fixtures){
 NSArray*lengths=[fixture isEqual:@"short"]?@[@128]:([fixture isEqual:@"prose"]?@[@4096,@32768,@131072,@524288]:@[@32768,@131072]);
 NSString*unit=[fixture isEqual:@"url"]?@"https://example.test/abcdefghijklmnopqrstuvwxyz0123456789":([fixture isEqual:@"mixed"]?@"alpha\tbeta e\u0302 👩🏽‍💻 中文 שלום one two three four five six. ":([fixture isEqual:@"paragraphs"]?@"one two three four five six seven eight nine ten.\n":@"one two three four five six seven eight nine ten. "));
 for(NSNumber*n in lengths){NSString*source=[@""stringByPaddingToLength:(n.unsignedIntegerValue/unit.length)*unit.length withString:unit startingAtIndex:0];
 for(NSString*op in @[@"initial-visible",@"edit-start",@"edit-end",@"resize-visible"]){
  if(instrument&&![fixture isEqual:@"prose"]&&![fixture isEqual:@"short"])continue;
  NSUInteger trials=instrument?1:7;
  for(NSUInteger trial=0;trial<trials;trial++)for(NSUInteger j=0;j<2;j++){@autoreleasepool{
   BOOL refined=(trial+j)%2;NSDictionary*sample=Sample(source,refined,op);
   if(trial||instrument){NSMutableDictionary*r=[NSMutableDictionary dictionaryWithDictionary:sample];[r addEntriesFromDictionary:@{@"fixture":fixture,@"characters":@(source.length),@"operation":op,@"mode":refined?@"candidate":@"base",@"trial":@(trial)}];[records addObject:r];}
  }}
  fprintf(stderr,"complete %s %lu %s\n",fixture.UTF8String,source.length,op.UTF8String);
 }
 }
 }
 NSDictionary*result=@{@"checks":@(Checks),@"instrumented":@(instrument),@"warmupsPerCase":@(instrument?0:1),@"trialsPerCase":@(instrument?1:6),@"records":records};NSData*data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];Check([data writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES]);fprintf(stderr,"PASS %lu checks\n",Checks);
 }return 0;}
