#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
static __thread NSUInteger GlyphDepth;
static NSUInteger Mallocs,Frees,GlyphCalls,ChangedSmall,ChangedLarge,MaximumBatch;
static uint64_t MallocBytes;
/*INTERPOSE*/
typedef NSUInteger(*GlyphFunction)(id,SEL,NSLayoutManager*,const CGGlyph*,const NSGlyphProperty*,const NSUInteger*,NSFont*,NSRange);
static GlyphFunction OriginalGlyphs;
static NSUInteger ObserveGlyphs(id self,SEL sel,NSLayoutManager*l,const CGGlyph*g,const NSGlyphProperty*p,const NSUInteger*i,NSFont*f,NSRange r){
 GlyphCalls++;MaximumBatch=MAX(MaximumBatch,r.length);GlyphDepth++;
 NSUInteger result=OriginalGlyphs(self,sel,l,g,p,i,f,r);
 GlyphDepth--;if(result){if(r.length<=64)ChangedSmall++;else ChangedLarge++;}return result;
}
static double Ms(uint64_t ticks){mach_timebase_info_data_t t;mach_timebase_info(&t);return(double)ticks*t.numer/t.denom/1e6;}
static double CPU(void){thread_basic_info_data_t info;mach_msg_type_number_t n=THREAD_BASIC_INFO_COUNT;mach_port_t thread=mach_thread_self();kern_return_t r=thread_info(thread,THREAD_BASIC_INFO,(thread_info_t)&info,&n);mach_port_deallocate(mach_task_self(),thread);return r==KERN_SUCCESS?1000.0*(info.user_time.seconds+info.system_time.seconds)+(info.user_time.microseconds+info.system_time.microseconds)/1000.0:-1;}
