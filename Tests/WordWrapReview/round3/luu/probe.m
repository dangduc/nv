#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import "NVSourceTypesetter.h"
#include <sys/resource.h>
#include "space-delegate.h"
static NSUInteger Checks,Creates,Chars,Suggests,LineCreates,Tokens;
static void Check(BOOL b){Checks++;if(!b){fprintf(stderr,"FAIL %lu\n",Checks);exit(1);}}
CTTypesetterRef CountCreate(CFAttributedStringRef s){Creates++;Chars+=CFAttributedStringGetLength(s);return CTTypesetterCreateWithAttributedString(s);}
CFIndex CountSuggest(CTTypesetterRef t,CFIndex i,double w,double o){Suggests++;return CTTypesetterSuggestClusterBreakWithOffset(t,i,w,o);}
CTLineRef CountLine(CTTypesetterRef t,CFRange r,double o){LineCreates++;return CTTypesetterCreateLineWithOffset(t,r,o);}
CFStringTokenizerTokenType CountToken(CFStringTokenizerRef t){Tokens++;return CFStringTokenizerAdvanceToNextToken(t);}
static double CPU(void){struct rusage r;getrusage(RUSAGE_SELF,&r);return (r.ru_utime.tv_sec+r.ru_stime.tv_sec)*1000.0+(r.ru_utime.tv_usec+r.ru_stime.tv_usec)/1000.0;}
static double Wall(void){return NSProcessInfo.processInfo.systemUptime*1000;}
@interface System:NSObject{
@public NSTextStorage*s;NSLayoutManager*l;NSTextContainer*c;SpaceDelegate*d;NSTextView*v;
}
-(id)initSource:(NSString*)source refined:(BOOL)refined;
-(NSPoint)caret;
@end
@implementation System
-(id)initSource:(NSString*)source refined:(BOOL)refined{if((self=[super init])){
 s=[[NSTextStorage alloc]init];l=[[NSLayoutManager alloc]init];c=[[NSTextContainer alloc]initWithSize:NSMakeSize(544,10000000)];d=[[SpaceDelegate alloc]init];[s addLayoutManager:l];[l addTextContainer:c];l.delegate=d;if(refined)l.typesetter=[[[NVSourceTypesetter alloc]init]autorelease];
 v=[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,544,600)textContainer:c];v.richText=NO;v.allowsUndo=NO;v.verticallyResizable=YES;v.horizontallyResizable=NO;c.widthTracksTextView=NO;
 NSMutableParagraphStyle*p=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];p.lineBreakMode=NSLineBreakByCharWrapping;
 NSDictionary*a=@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular"size:18],NSParagraphStyleAttributeName:p};v.typingAttributes=a;v.defaultParagraphStyle=p;
 [s setAttributedString:[[[NSAttributedString alloc]initWithString:source attributes:a]autorelease]];v.selectedRange=NSMakeRange(source.length,0);[l ensureLayoutForTextContainer:c];
 }return self;}
-(NSPoint)caret{
 Check(NSEqualRanges(v.selectedRange,NSMakeRange(s.length,0)));
 [l ensureLayoutForCharacterRange:NSMakeRange(s.length-1,1)];NSUInteger glyph=[l glyphIndexForCharacterAtIndex:s.length-1];NSRect rect=[l lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
 NSUInteger n=[l getLineFragmentInsertionPointsForCharacterAtIndex:s.length-1 alternatePositions:NO inDisplayOrder:NO positions:NULL characterIndexes:NULL];Check(n<256);
 CGFloat positions[256];NSUInteger indexes[256];[l getLineFragmentInsertionPointsForCharacterAtIndex:s.length-1 alternatePositions:NO inDisplayOrder:NO positions:positions characterIndexes:indexes];
 for(NSUInteger i=0;i<n;i++)if(indexes[i]==s.length){NSPoint p=NSMakePoint(rect.origin.x+positions[i],rect.origin.y);Check(isfinite(p.x)&&isfinite(p.y));return p;}
 Check(NO);return NSZeroPoint;
}
-(void)dealloc{l.delegate=nil;[v release];[d release];[c release];[l release];[s release];[super dealloc];}
@end
static NSDictionary*Sample(NSString*source,BOOL refined,NSString*op){System*x=[[[System alloc]initSource:source refined:refined]autorelease];NSMutableArray*carets=[NSMutableArray array];
 [x caret];Creates=Chars=Suggests=LineCreates=Tokens=0;double cpu=CPU(),wall=Wall();
 if([op isEqual:@"resize"]){for(NSUInteger i=0;i<8;i++){x->c.containerSize=NSMakeSize(i%2?544:344,10000000);NSPoint p=[x caret];[carets addObject:@[@(p.x),@(p.y)]];}}
 else if([op isEqual:@"end-edits"]){
  NSString*one=[source substringToIndex:1];for(NSUInteger i=0;i<32;i++){[x->v insertText:one replacementRange:x->v.selectedRange];NSPoint p=[x caret];[carets addObject:@[@(p.x),@(p.y)]];}
  for(NSUInteger i=0;i<32;i++){[x->v deleteBackward:nil];NSPoint p=[x caret];[carets addObject:@[@(p.x),@(p.y)]];}
 }else{for(NSUInteger i=0;i<256;i++){[x->l ensureLayoutForBoundingRect:NSMakeRect(0,0,544,600)inTextContainer:x->c];[x caret];}}
 wall=Wall()-wall;cpu=CPU()-cpu;Check([x->s.string isEqual:source]);Check(NSEqualRanges(x->v.selectedRange,NSMakeRange(source.length,0)));Check(NSThread.isMainThread);
 NSPoint final=[x caret];__block NSUInteger lines=0;[x->l enumerateLineFragmentsForGlyphRange:NSMakeRange(0,x->l.numberOfGlyphs)usingBlock:^(NSRect r,NSRect u,NSTextContainer*t,NSRange g,BOOL*stop){lines++;}];
 return @{@"wallMs":@(wall),@"cpuMs":@(cpu),@"carets":carets,@"finalCaret":@[@(final.x),@(final.y)],@"lineFragments":@(lines),@"creates":@(Creates),@"snapshotChars":@(Chars),@"suggests":@(Suggests),@"lineCreates":@(LineCreates),@"tokenAdvances":@(Tokens)};
}
int main(int argc,char**argv){@autoreleasepool{if(argc<3)return 2;[NSApplication sharedApplication];BOOL counts=!strcmp(argv[2],"counts");NSMutableArray*records=[NSMutableArray array];
 for(NSString*token in @[@" ",@"k"]){NSString*source=[@""stringByPaddingToLength:32768 withString:token startingAtIndex:0];for(NSString*op in @[@"resize",@"end-edits",@"cached-queries"]){
  for(NSUInteger trial=0;trial<(counts?1:7);trial++){@autoreleasepool{NSDictionary*pair[2];for(NSUInteger j=0;j<2;j++){NSUInteger m=(trial+j)%2;pair[m]=Sample(source,m,op);if(trial||counts){NSMutableDictionary*r=[NSMutableDictionary dictionaryWithDictionary:pair[m]];[r addEntriesFromDictionary:@{@"fixture":[token isEqual:@" "]?@"spaces":@"long-token",@"operation":op,@"mode":m?@"candidate":@"base",@"trial":@(trial)}];[records addObject:r];}}
   Check([pair[0][@"carets"]isEqual:pair[1][@"carets"]]);Check([pair[0][@"finalCaret"]isEqual:pair[1][@"finalCaret"]]);Check([pair[0][@"lineFragments"]isEqual:pair[1][@"lineFragments"]]);
  }}fprintf(stderr,"complete %s %s\n",token.UTF8String,op.UTF8String);
 }}
 NSDictionary*result=@{@"records":records,@"checks":@(Checks),@"warmupsPerMode":@(counts?0:1),@"trialsPerMode":@(counts?1:6),@"instrumented":@(counts)};NSData*d=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];Check([d writeToFile:[NSString stringWithUTF8String:argv[1]]atomically:YES]);fprintf(stderr,"PASS %lu checks\n",Checks);
 }return 0;}
