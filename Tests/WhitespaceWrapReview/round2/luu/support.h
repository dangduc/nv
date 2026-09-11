#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <malloc/malloc.h>
#import <objc/runtime.h>
#import "GlobalPrefs.h"
static IMP OriginalAttributes;
static NSUInteger StyleCalls,StyleOffMainCalls;
static NSMutableSet*StyleIdentities;
static size_t StyleBytes;
static id ObserveAttributes(id self,SEL selector){
    id result=((id(*)(id,SEL))OriginalAttributes)(self,selector);
    @synchronized(StyleIdentities){
        StyleCalls++;
        if(!NSThread.isMainThread)StyleOffMainCalls++;
        id style=result[NSParagraphStyleAttributeName];
        if(style){NSValue*identity=[NSValue valueWithPointer:style];if(![StyleIdentities containsObject:identity]){[StyleIdentities addObject:identity];StyleBytes+=malloc_size(style);}}
    }
    return result;
}
static double Ms(uint64_t ticks){mach_timebase_info_data_t t;mach_timebase_info(&t);return(double)ticks*t.numer/t.denom/1e6;}
static double CPU(void){thread_basic_info_data_t info;mach_msg_type_number_t count=THREAD_BASIC_INFO_COUNT;mach_port_t thread=mach_thread_self();kern_return_t result=thread_info(thread,THREAD_BASIC_INFO,(thread_info_t)&info,&count);mach_port_deallocate(mach_task_self(),thread);return result==KERN_SUCCESS?1000.0*(info.user_time.seconds+info.system_time.seconds)+(info.user_time.microseconds+info.system_time.microseconds)/1000.0:-1;}
