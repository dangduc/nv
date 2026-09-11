#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <sys/resource.h>
#include "space-delegate.h"
static NSUInteger Checks;
static void Check(BOOL b){Checks++;if(!b){fprintf(stderr,"FAIL %lu\n",Checks);exit(1);}}
typedef struct {NSUInteger creates,releases,chars,live,peak;CFTypeRef refs[32];NSUInteger sizes[32];} Counters;
static Counters Stats[2];
static CTTypesetterRef Create(NSUInteger mode,CFAttributedStringRef s){
 CTTypesetterRef t=CTTypesetterCreateWithAttributedString(s);if(!t)return t;
 Counters*c=&Stats[mode];NSUInteger n=CFAttributedStringGetLength(s);c->creates++;c->chars+=n;c->live+=n;c->peak=MAX(c->peak,c->live);
 for(NSUInteger i=0;i<32;i++)if(!c->refs[i]){c->refs[i]=t;c->sizes[i]=n;return t;}Check(NO);return t;
}
static void Release(NSUInteger mode,CFTypeRef o){Counters*c=&Stats[mode];for(NSUInteger i=0;i<32;i++)if(c->refs[i]==o){c->releases++;c->live-=c->sizes[i];c->refs[i]=NULL;c->sizes[i]=0;break;}CFRelease(o);}
CTTypesetterRef OldCreate(CFAttributedStringRef s){return Create(0,s);} CTTypesetterRef NewCreate(CFAttributedStringRef s){return Create(1,s);}
void OldRelease(CFTypeRef o){Release(0,o);}void NewRelease(CFTypeRef o){Release(1,o);}
static double CPU(void){struct rusage r;getrusage(RUSAGE_SELF,&r);return 1000.0*(r.ru_utime.tv_sec+r.ru_stime.tv_sec)+(r.ru_utime.tv_usec+r.ru_stime.tv_usec)/1000.0;}
static double Wall(void){return NSProcessInfo.processInfo.systemUptime*1000;}
@interface System:NSObject{
@public NSTextStorage*s;NSLayoutManager*l;NSTextContainer*c;SpaceDelegate*d;
}
-(id)initMode:(NSUInteger)mode;
-(void)source:(NSString*)source;
-(void)visible:(CGFloat)y;
-(NSDictionary*)cache;
@end
@implementation System
-(id)initMode:(NSUInteger)mode{if((self=[super init])){s=[[NSTextStorage alloc]init];l=[[NSLayoutManager alloc]init];c=[[NSTextContainer alloc]initWithSize:NSMakeSize(544,10000000)];d=[[SpaceDelegate alloc]init];[s addLayoutManager:l];[l addTextContainer:c];l.delegate=d;l.typesetter=[[[NSClassFromString(mode?@"NVSourceTypesetter":@"NVPreviousTypesetter")alloc]init]autorelease];}return self;}
-(void)source:(NSString*)source{NSMutableParagraphStyle*p=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];p.lineBreakMode=NSLineBreakByCharWrapping;[s setAttributedString:[[[NSAttributedString alloc]initWithString:source attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular"size:18],NSParagraphStyleAttributeName:p}]autorelease]];}
-(void)visible:(CGFloat)y{[l ensureLayoutForBoundingRect:NSMakeRect(0,y,c.containerSize.width,200)inTextContainer:c];}
-(NSDictionary*)cache{
 id t=l.typesetter;Ivar ivar=class_getInstanceVariable([t class],"paragraphMeasure");void*measure=NULL;memcpy(&measure,(char*)t+ivar_getOffset(ivar),sizeof(measure));
 NSMutableData*breaks=object_getIvar(t,class_getInstanceVariable([t class],"lineBreaks"));
 return @{@"measurePresent":@(measure!=NULL),@"breakBytes":@(breaks.length)};
}
-(void)dealloc{l.delegate=nil;[d release];[c release];[l release];[s release];[super dealloc];}
@end
static NSDictionary*State(NSUInteger m,System*x,NSString*label){Counters*c=&Stats[m];NSMutableDictionary*r=[NSMutableDictionary dictionaryWithDictionary:x?[x cache]:@{}];[r addEntriesFromDictionary:@{@"state":label,@"creates":@(c->creates),@"releases":@(c->releases),@"snapshotChars":@(c->chars),@"liveSnapshotChars":@(c->live),@"peakSnapshotChars":@(c->peak)}];return r;}
static NSArray*Lifetime(NSUInteger m){NSMutableArray*r=[NSMutableArray array];NSString*unit=@"one two three four five six seven eight nine ten. ";NSString*source=[@""stringByPaddingToLength:16000 withString:unit startingAtIndex:0];
 @autoreleasepool{
 System*x=[[[System alloc]initMode:m]autorelease];[x source:source];[x visible:0];[r addObject:State(m,x,@"initial")];NSUInteger calls=Stats[m].creates;
 for(NSUInteger i=0;i<20;i++)[x visible:0];Check(calls==Stats[m].creates);[r addObject:State(m,x,@"twenty-cached-queries")];
 // Reuse this layout manager with a different empty storage, as note attachment does.
 [x->s removeLayoutManager:x->l];NSTextStorage*empty=[[[NSTextStorage alloc]init]autorelease];[empty addLayoutManager:x->l];[x visible:0];[r addObject:State(m,x,@"empty-storage-attached")];
 [empty removeLayoutManager:x->l];[x->s addLayoutManager:x->l];[x visible:0];[r addObject:State(m,x,@"source-reattached")];
 NSString*multi=[@""stringByPaddingToLength:4000 withString:@"one two three four five six seven eight nine ten.\n"startingAtIndex:0];[x source:multi];
 for(NSUInteger i=0;i<12;i++)[x visible:80*i];[r addObject:State(m,x,@"twelve-incremental-viewports")];
 [x source:source];[x visible:0];for(NSUInteger i=0;i<8;i++){[x->s replaceCharactersInRange:NSMakeRange(32+i,0)withString:@"k"];[x visible:0];}
 Check(x->s.length==source.length+8);[r addObject:State(m,x,@"eight-edits")];
 Check(NSThread.isMainThread);
 }Check(!Stats[m].live);[r addObject:State(m,nil,@"editor-destroyed")];
 @autoreleasepool{
 NSMutableArray*editors=[NSMutableArray array];for(NSUInteger i=0;i<12;i++){System*x=[[[System alloc]initMode:m]autorelease];[x source:source];[x visible:0];[editors addObject:x];}
 [r addObject:State(m,[editors lastObject],@"twelve-idle-editors")];
 }Check(!Stats[m].live);[r addObject:State(m,nil,@"all-editors-destroyed")];return r;
}
static NSDictionary*Timing(NSUInteger mode){System*x=[[[System alloc]initMode:mode]autorelease];NSString*source=@"one two three four five six seven eight nine ten. one two three four five six seven eight nine ten. ";[x source:source];[x visible:0];
 double cpu=CPU(),wall=Wall();for(NSUInteger i=0;i<96;i++){NSUInteger pos=32+i;[x->s replaceCharactersInRange:NSMakeRange(pos,0)withString:@"k"];[x visible:0];}
 for(NSUInteger i=0;i<96;i++){[x->s replaceCharactersInRange:NSMakeRange(32,1)withString:@""];[x visible:0];}
 wall=Wall()-wall;cpu=CPU()-cpu;Check([x->s.string isEqual:source]);Check(NSThread.isMainThread);return @{@"wallMs":@(wall),@"cpuMs":@(cpu)};
}
int main(int argc,char**argv){@autoreleasepool{if(argc<3)return 2;[NSApplication sharedApplication];BOOL counts=!strcmp(argv[2],"counts");NSMutableDictionary*result=[NSMutableDictionary dictionary];
 if(counts){result[@"old"]=Lifetime(0);result[@"new"]=Lifetime(1);Check(Stats[0].creates==Stats[1].creates);Check(Stats[0].chars==Stats[1].chars);Check(Stats[0].releases==Stats[1].releases);}
 else{NSMutableArray*r=[NSMutableArray array];for(NSUInteger t=0;t<8;t++)for(NSUInteger j=0;j<2;j++){@autoreleasepool{NSUInteger m=(t+j)%2;NSMutableDictionary*s=[NSMutableDictionary dictionaryWithDictionary:Timing(m)];s[@"mode"]=m?@"new":@"old";s[@"trial"]=@(t);if(t)[r addObject:s];}}result[@"samples"]=r;result[@"warmupsPerMode"]=@1;result[@"trialsPerMode"]=@7;result[@"editsPerTrial"]=@192;}
 result[@"checks"]=@(Checks);NSData*data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];Check([data writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES]);fprintf(stderr,"PASS %lu checks\n",Checks);
 }return 0;}
