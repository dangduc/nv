#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
static double Milliseconds(uint64_t ticks){mach_timebase_info_data_t t;mach_timebase_info(&t);return (double)ticks*t.numer/t.denom/1e6;}
static double MainCPU(void){thread_basic_info_data_t info;mach_msg_type_number_t count=THREAD_BASIC_INFO_COUNT;mach_port_t thread=mach_thread_self();kern_return_t result=thread_info(thread,THREAD_BASIC_INFO,(thread_info_t)&info,&count);mach_port_deallocate(mach_task_self(),thread);if(result!=KERN_SUCCESS)return -1;return 1000.0*(info.user_time.seconds+info.system_time.seconds)+(info.user_time.microseconds+info.system_time.microseconds)/1000.0;}
static NSString*Spaces(NSUInteger n){return [@"" stringByPaddingToLength:n withString:@" " startingAtIndex:0];}
static NSUInteger Lines(NSTextView*v){[v.layoutManager ensureLayoutForTextContainer:v.textContainer];__block NSUInteger n=0;[v.layoutManager enumerateLineFragmentsForGlyphRange:NSMakeRange(0,v.layoutManager.numberOfGlyphs)usingBlock:^(NSRect a,NSRect b,NSTextContainer*c,NSRange r,BOOL*stop){n++;}];return n;}
